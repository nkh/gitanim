/* diffvim-compute.c — External diff computer for diffvim.
 *
 * Reads two files, computes line-level + char-level LCS diff, and writes
 * the result in a format that `diffvim --precomputed FILE` can consume.
 *
 * This is the same algorithm as diffvim's embedded vimscript engine, but
 * compiled to native code for speed (10-100x faster than vimscript LCS).
 *
 * Build: make c
 * Usage: diffvim-compute <oldfile> <newfile> <outputfile>
 *
 * Timing is printed to stderr:
 *   compute: <ms> ms (total)
 *   startup: <ms> ms (process start to first byte read)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>

/* --- Timing --- */
static double now_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double)tv.tv_sec * 1000.0 + (double)tv.tv_usec / 1000.0;
}

/* --- Dynamic array of strings (for file lines) --- */
typedef struct {
    char **data;
    int count;
    int capacity;
} StrArr;

static void sa_init(StrArr *a) { a->data = NULL; a->count = 0; a->capacity = 0; }
static void sa_push(StrArr *a, char *s) {
    if (a->count >= a->capacity) {
        a->capacity = a->capacity ? a->capacity * 2 : 16;
        a->data = realloc(a->data, a->capacity * sizeof(char*));
    }
    a->data[a->count++] = s;
}
static void sa_free(StrArr *a) {
    for (int i = 0; i < a->count; i++) free(a->data[i]);
    free(a->data);
}

/* Read file into StrArr of lines (without trailing newlines).
 * Returns empty array on error. */
static StrArr read_lines(const char *path) {
    StrArr lines;
    sa_init(&lines);
    FILE *f = fopen(path, "rb");
    if (!f) return lines;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1);
    fread(buf, 1, sz, f);
    buf[sz] = '\0';
    fclose(f);

    char *p = buf;
    char *line_start = buf;
    for (long i = 0; i <= sz; i++) {
        if (i == sz || buf[i] == '\n') {
            long len = &buf[i] - line_start;
            /* If we're at the end of the buffer and the last char was a
             * newline, don't emit a trailing empty line — this matches
             * vim's readfile() behavior. */
            if (i == sz && len == 0 && lines.count > 0) break;
            char *line = malloc(len + 1);
            memcpy(line, line_start, len);
            line[len] = '\0';
            sa_push(&lines, line);
            line_start = &buf[i + 1];
        }
    }
    (void)p;  /* p was used during line splitting; silence unused warning */
    free(buf);
    return lines;
}

/* Read an entire file (or stdin if path is "-") into a malloc'd buffer.
 * The buffer is NUL-terminated. Sets *out_size to the byte length (excluding
 * the NUL). Caller must free the buffer. Returns NULL on error. */
static char *read_file_or_stdin(const char *path, long *out_size) {
    if (strcmp(path, "-") == 0) {
        size_t cap = 65536, len = 0;
        char *buf = malloc(cap + 1);
        size_t n;
        while ((n = fread(buf + len, 1, cap - len, stdin)) > 0) {
            len += n;
            if (len == cap) {
                cap *= 2;
                buf = realloc(buf, cap + 1);
            }
        }
        buf[len] = '\0';
        *out_size = (long)len;
        return buf;
    }
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long sz = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *buf = malloc(sz + 1);
    if (sz > 0) fread(buf, 1, sz, f);
    buf[sz] = '\0';
    fclose(f);
    *out_size = sz;
    return buf;
}

/* Parse a unified diff (patch file) into old_lines and new_lines.
 *
 * Reads from `path` (or stdin if "-"). Fills *old_lines and *new_lines
 * (which the caller must sa_free).
 *
 * Unified diff rules:
 *   - `---` prefix  → old file header, ignore.
 *   - `+++` prefix  → new file header, ignore.
 *   - `@@`  prefix  → hunk header, ignore (we recompute our own hunks).
 *   - `\`   prefix  → diff metadata (e.g. "\ No newline at end of file"), ignore.
 *   - `-`   prefix  (not `---`) → old file line; strip leading `-`.
 *   - `+`   prefix  (not `+++`) → new file line; strip leading `+`.
 *   - ` `   prefix  → context line; strip leading ` `; appears in BOTH.
 *   - empty line    → treated as a space-prefixed empty context line.
 *   - anything else → unrecognized (e.g. "diff --git" from git diff); skip.
 *
 * Multiple hunks are concatenated to reconstruct the full old/new content.
 * Returns 0 on success, -1 if the diff file can't be read. */
static int parse_unified_diff(const char *path, StrArr *old_lines, StrArr *new_lines) {
    long sz;
    char *buf = read_file_or_stdin(path, &sz);
    if (!buf) return -1;

    sa_init(old_lines);
    sa_init(new_lines);

    char *line_start = buf;
    for (long i = 0; i <= sz; i++) {
        if (i == sz || buf[i] == '\n') {
            long len = &buf[i] - line_start;
            /* Skip a trailing empty line (matches vim's readfile()). */
            if (i == sz && len == 0) break;

            if (len == 0) {
                /* Empty line in the diff = empty context line in both files. */
                char *e1 = malloc(1); e1[0] = '\0';
                char *e2 = malloc(1); e2[0] = '\0';
                sa_push(old_lines, e1);
                sa_push(new_lines, e2);
            } else if (len >= 3 && memcmp(line_start, "---", 3) == 0) {
                /* old file header — ignore */
            } else if (len >= 3 && memcmp(line_start, "+++", 3) == 0) {
                /* new file header — ignore */
            } else if (len >= 2 && memcmp(line_start, "@@", 2) == 0) {
                /* hunk header — ignore (we recompute our own) */
            } else if (line_start[0] == '\\') {
                /* metadata (e.g. "\ No newline at end of file") — ignore */
            } else if (line_start[0] == '-') {
                /* delete line — strip leading '-' */
                char *s = malloc(len);  /* (len-1) chars + NUL */
                memcpy(s, line_start + 1, len - 1);
                s[len - 1] = '\0';
                sa_push(old_lines, s);
            } else if (line_start[0] == '+') {
                /* insert line — strip leading '+' */
                char *s = malloc(len);
                memcpy(s, line_start + 1, len - 1);
                s[len - 1] = '\0';
                sa_push(new_lines, s);
            } else if (line_start[0] == ' ') {
                /* context line — strip leading ' ', present in both */
                char *s1 = malloc(len);
                char *s2 = malloc(len);
                memcpy(s1, line_start + 1, len - 1);
                s1[len - 1] = '\0';
                memcpy(s2, line_start + 1, len - 1);
                s2[len - 1] = '\0';
                sa_push(old_lines, s1);
                sa_push(new_lines, s2);
            }
            /* else: unrecognized line (e.g. "diff --git", "index ...") — skip */

            line_start = &buf[i + 1];
        }
    }

    free(buf);
    return 0;
}

/* --- Line-level LCS diff --- */
typedef enum { OP_KEEP, OP_DELETE, OP_INSERT } OpType;

typedef struct {
    OpType type;
    int a_idx;  /* old line index (for keep, delete) */
    int b_idx;  /* new line index (for keep, insert) */
} LineOp;

static LineOp *line_diff(StrArr *a, StrArr *b, int *out_count) {
    int na = a->count, nb = b->count;
    /* dp[i][j] = LCS length of a[0..i) b[0..j) */
    int *dp = calloc((na + 1) * (nb + 1), sizeof(int));
    #define DP(i,j) dp[(i)*(nb+1)+(j)]

    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++) {
            if (strcmp(a->data[i-1], b->data[j-1]) == 0)
                DP(i,j) = DP(i-1,j-1) + 1;
            else
                DP(i,j) = DP(i-1,j) > DP(i,j-1) ? DP(i-1,j) : DP(i,j-1);
        }

    /* Backtrack */
    int max_ops = na + nb;
    LineOp *ops = malloc(max_ops * sizeof(LineOp));
    int count = 0;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && strcmp(a->data[i-1], b->data[j-1]) == 0) {
            ops[count].type = OP_KEEP; ops[count].a_idx = i-1; ops[count].b_idx = j-1;
            count++; i--; j--;
        } else if (j > 0 && (i == 0 || DP(i,j-1) >= DP(i-1,j))) {
            ops[count].type = OP_INSERT; ops[count].a_idx = -1; ops[count].b_idx = j-1;
            count++; j--;
        } else {
            ops[count].type = OP_DELETE; ops[count].a_idx = i-1; ops[count].b_idx = -1;
            count++; i--;
        }
    }
    /* Reverse */
    for (int k = 0; k < count/2; k++) {
        LineOp tmp = ops[k]; ops[k] = ops[count-1-k]; ops[count-1-k] = tmp;
    }
    free(dp);
    *out_count = count;
    return ops;
}

/* --- Myers diff algorithm (O(ND)) --- */
/* Faster than LCS for small diffs. Falls back to LCS for very large N+M. */
static LineOp *myers_diff(StrArr *a, StrArr *b, int *out_count) {
    int na = a->count, nb = b->count;
    /* For very large inputs, Myers can use excessive memory; fall back to LCS. */
    if (na + nb > 200000) {
        return line_diff(a, b, out_count);
    }
    int max = na + nb;
    int *v = calloc(2 * max + 1, sizeof(int));
    #define V(k) v[(k) + max]
    /* Trace stores the v array at each d for backtracking. */
    typedef int *IntPtr;
    IntPtr *trace = malloc((max + 1) * sizeof(IntPtr));

    int found = 0;
    for (int d = 0; d <= max; d++) {
        trace[d] = malloc((2 * max + 1) * sizeof(int));
        memcpy(trace[d], v, (2 * max + 1) * sizeof(int));
        for (int k = -d; k <= d; k += 2) {
            int x;
            if (k == -d || (k != d && V(k-1) < V(k+1)))
                x = V(k+1);
            else
                x = V(k-1) + 1;
            int y = x - k;
            while (x < na && y < nb && strcmp(a->data[x], b->data[y]) == 0) {
                x++; y++;
            }
            V(k) = x;
            if (x >= na && y >= nb) {
                found = 1;
                /* Backtrack from (x, y) at depth d. */
                LineOp *ops = malloc((d + na + nb) * sizeof(LineOp));
                int count = 0;
                int cx = na, cy = nb;
                for (int dd = d; dd > 0; dd--) {
                    int *vp = trace[dd];
                    #define TV(k) vp[(k) + max]
                    int k = cx - cy;
                    int prev_x, prev_y;
                    int from_below;  /* 1 = came from k+1 (insert), 0 = came from k-1 (delete) */
                    if (k == -dd) {
                        from_below = 1;
                    } else if (k == dd) {
                        from_below = 0;
                    } else {
                        from_below = (TV(k-1) < TV(k+1)) ? 1 : 0;
                    }
                    if (from_below) {
                        prev_x = TV(k+1);
                        prev_y = prev_x - (k + 1);
                    } else {
                        prev_x = TV(k-1) + 1;
                        prev_y = prev_x - (k - 1);
                    }
                    /* Emit diagonal keeps from (cx,cy) back to (prev_x, prev_y) */
                    while (cx > prev_x && cy > prev_y) {
                        ops[count].type = OP_KEEP;
                        ops[count].a_idx = cx - 1;
                        ops[count].b_idx = cy - 1;
                        count++; cx--; cy--;
                    }
                    /* The single non-diagonal step */
                    if (from_below) {
                        ops[count].type = OP_INSERT;
                        ops[count].a_idx = -1;
                        ops[count].b_idx = cy - 1;
                        count++; cy--;
                    } else {
                        ops[count].type = OP_DELETE;
                        ops[count].a_idx = cx - 1;
                        ops[count].b_idx = -1;
                        count++; cx--;
                    }
                    #undef TV
                }
                /* Handle any diagonal keeps at the very start (depth 0) */
                while (cx > 0 && cy > 0) {
                    ops[count].type = OP_KEEP;
                    ops[count].a_idx = cx - 1;
                    ops[count].b_idx = cy - 1;
                    count++; cx--; cy--;
                }
                /* Reverse */
                for (int i = 0; i < count/2; i++) {
                    LineOp tmp = ops[i]; ops[i] = ops[count-1-i]; ops[count-1-i] = tmp;
                }
                for (int i = 0; i <= d; i++) free(trace[i]);
                free(trace);
                free(v);
                *out_count = count;
                return ops;
            }
        }
        if (found) break;
    }
    /* Fallback */
    for (int i = 0; i <= max; i++) if (trace[i]) free(trace[i]);
    free(trace);
    free(v);
    return line_diff(a, b, out_count);
    #undef V
}

/* --- Patience diff algorithm --- */
/* Anchors on unique common lines, then recurses on the gaps. */
static LineOp *patience_diff(StrArr *a, StrArr *b, int *out_count);

/* Find unique common lines between a[a_start..a_end) and b[b_start..b_end).
 * Returns arrays of matching (a_idx, b_idx) pairs in increasing order. */
static int find_patience_anchors(StrArr *a, int a_start, int a_end,
                                  StrArr *b, int b_start, int b_end,
                                  int *out_a_idx, int *out_b_idx) {
    /* Count occurrences of each line in both a and b. We use a simple
     * hash map (linear probe) keyed by string. For simplicity and
     * correctness, we use a naive O(N*M) approach for small ranges. */
    int count = 0;
    for (int i = a_start; i < a_end; i++) {
        /* Check if a[i] appears exactly once in a[a_start..a_end) */
        int a_count = 0;
        for (int k = a_start; k < a_end; k++) {
            if (strcmp(a->data[i], a->data[k]) == 0) a_count++;
        }
        if (a_count != 1) continue;
        /* Find the unique match in b[b_start..b_end) */
        int b_match = -1;
        int b_count = 0;
        for (int k = b_start; k < b_end; k++) {
            if (strcmp(a->data[i], b->data[k]) == 0) {
                b_match = k;
                b_count++;
            }
        }
        if (b_count == 1) {
            out_a_idx[count] = i;
            out_b_idx[count] = b_match;
            count++;
        }
    }
    /* The anchors are already in increasing a_idx order. We need them in
     * increasing b_idx order too (for the LIS). Since we iterated a in
     * order, we need to find the LIS of b_idx values. */
    /* Simple LIS via patience sorting. */
    if (count <= 1) return count;
    /* Build LIS of (a_idx, b_idx) pairs sorted by a_idx, maximizing b_idx
     * increasing subsequence. */
    int *lis_prev = malloc(count * sizeof(int));
    int *lis_tail = malloc(count * sizeof(int));
    int *lis_tail_idx = malloc(count * sizeof(int));
    int lis_len = 0;
    for (int i = 0; i < count; i++) {
        /* Binary search for position in lis_tail (by b_idx) */
        int lo = 0, hi = lis_len;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (out_b_idx[lis_tail_idx[mid]] < out_b_idx[i])
                lo = mid + 1;
            else
                hi = mid;
        }
        lis_prev[i] = (lo > 0) ? lis_tail_idx[lo - 1] : -1;
        if (lo == lis_len) {
            lis_tail_idx[lis_len] = i;
            lis_len++;
        } else {
            lis_tail_idx[lo] = i;
        }
    }
    /* Reconstruct LIS */
    int *keep_a = malloc(lis_len * sizeof(int));
    int *keep_b = malloc(lis_len * sizeof(int));
    int idx = lis_tail_idx[lis_len - 1];
    for (int i = lis_len - 1; i >= 0; i--) {
        keep_a[i] = out_a_idx[idx];
        keep_b[i] = out_b_idx[idx];
        idx = lis_prev[idx];
    }
    /* Copy back */
    for (int i = 0; i < lis_len; i++) {
        out_a_idx[i] = keep_a[i];
        out_b_idx[i] = keep_b[i];
    }
    free(lis_prev); free(lis_tail); free(lis_tail_idx);
    free(keep_a); free(keep_b);
    return lis_len;
}

static LineOp *patience_diff_range(StrArr *a, int a_start, int a_end,
                                    StrArr *b, int b_start, int b_end,
                                    int *out_count) {
    int na = a_end - a_start;
    int nb = b_end - b_start;
    LineOp *ops = NULL;
    int count = 0;

    if (na == 0 && nb == 0) {
        *out_count = 0;
        return NULL;
    }
    if (na == 0) {
        ops = malloc(nb * sizeof(LineOp));
        for (int j = 0; j < nb; j++) {
            ops[j].type = OP_INSERT;
            ops[j].a_idx = -1;
            ops[j].b_idx = b_start + j;
        }
        *out_count = nb;
        return ops;
    }
    if (nb == 0) {
        ops = malloc(na * sizeof(LineOp));
        for (int i = 0; i < na; i++) {
            ops[i].type = OP_DELETE;
            ops[i].a_idx = a_start + i;
            ops[i].b_idx = -1;
        }
        *out_count = na;
        return ops;
    }

    /* Find patience anchors */
    int max_anchors = na < nb ? na : nb;
    int *anchor_a = malloc(max_anchors * sizeof(int));
    int *anchor_b = malloc(max_anchors * sizeof(int));
    int n_anchors = find_patience_anchors(a, a_start, a_end, b, b_start, b_end,
                                           anchor_a, anchor_b);

    if (n_anchors == 0) {
        /* No unique common lines — fall back to LCS for this range. */
        StrArr sub_a, sub_b;
        sub_a.data = a->data + a_start; sub_a.count = na; sub_a.capacity = na;
        sub_b.data = b->data + b_start; sub_b.count = nb; sub_b.capacity = nb;
        free(anchor_a); free(anchor_b);
        ops = line_diff(&sub_a, &sub_b, &count);
        /* Fix indices to be absolute */
        for (int i = 0; i < count; i++) {
            if (ops[i].type == OP_KEEP || ops[i].type == OP_DELETE)
                ops[i].a_idx += a_start;
            if (ops[i].type == OP_KEEP || ops[i].type == OP_INSERT)
                ops[i].b_idx += b_start;
        }
        *out_count = count;
        return ops;
    }

    /* Diff the gaps between anchors. */
    int prev_a = a_start, prev_b = b_start;
    for (int k = 0; k <= n_anchors; k++) {
        int cur_a = (k < n_anchors) ? anchor_a[k] : a_end;
        int cur_b = (k < n_anchors) ? anchor_b[k] : b_end;
        if (cur_a > prev_a || cur_b > prev_b) {
            int sub_count;
            LineOp *sub_ops = patience_diff_range(a, prev_a, cur_a, b, prev_b, cur_b, &sub_count);
            if (sub_count > 0) {
                ops = realloc(ops, (count + sub_count) * sizeof(LineOp));
                memcpy(ops + count, sub_ops, sub_count * sizeof(LineOp));
                count += sub_count;
                free(sub_ops);
            }
        }
        if (k < n_anchors) {
            ops = realloc(ops, (count + 1) * sizeof(LineOp));
            ops[count].type = OP_KEEP;
            ops[count].a_idx = anchor_a[k];
            ops[count].b_idx = anchor_b[k];
            count++;
            prev_a = anchor_a[k] + 1;
            prev_b = anchor_b[k] + 1;
        }
    }
    free(anchor_a); free(anchor_b);
    *out_count = count;
    return ops;
}

static LineOp *patience_diff(StrArr *a, StrArr *b, int *out_count) {
    return patience_diff_range(a, 0, a->count, b, 0, b->count, out_count);
}

/* --- Diff dispatcher --- */
static LineOp *compute_line_diff(StrArr *a, StrArr *b, int *out_count, const char *algorithm) {
    if (strcmp(algorithm, "myers") == 0)
        return myers_diff(a, b, out_count);
    if (strcmp(algorithm, "patience") == 0)
        return patience_diff(a, b, out_count);
    return line_diff(a, b, out_count);  /* default: lcs */
}

/* --- Char-level LCS diff between two strings --- */
/* Uses Unicode code points (not bytes) to match vim's split(str, '\zs'). */

typedef struct {
    OpType type;
    int code;  /* Unicode code point */
} CharOp;

/* Decode one UTF-8 sequence from s starting at *pos.
 * Updates *pos to point past the decoded character.
 * Returns the Unicode code point, or -1 on error. */
static int utf8_decode(const char *s, int len, int *pos) {
    if (*pos >= len) return -1;
    unsigned char c = (unsigned char)s[*pos];
    if (c < 0x80) {
        (*pos)++;
        return c;
    }
    int cp, extra;
    if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; extra = 1; }
    else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; extra = 2; }
    else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; extra = 3; }
    else { (*pos)++; return c; }  /* invalid, treat as single byte */
    if (*pos + extra >= len) { (*pos)++; return c; }  /* truncated */
    for (int k = 1; k <= extra; k++) {
        unsigned char b = (unsigned char)s[*pos + k];
        if ((b & 0xC0) != 0x80) { (*pos)++; return c; }  /* invalid */
        cp = (cp << 6) | (b & 0x3F);
    }
    *pos += 1 + extra;
    return cp;
}

static CharOp *char_diff(const char *a, const char *b, int *out_count) {
    int alen = strlen(a), blen = strlen(b);
    /* Decode into arrays of code points */
    int *ac = malloc((alen + 1) * sizeof(int));
    int *bc = malloc((blen + 1) * sizeof(int));
    int na = 0, nb = 0;
    int pos = 0;
    while (pos < alen) {
        int cp = utf8_decode(a, alen, &pos);
        if (cp < 0) break;
        ac[na++] = cp;
    }
    pos = 0;
    while (pos < blen) {
        int cp = utf8_decode(b, blen, &pos);
        if (cp < 0) break;
        bc[nb++] = cp;
    }

    int *dp = calloc((na + 1) * (nb + 1), sizeof(int));
    #define CDP(i,j) dp[(i)*(nb+1)+(j)]

    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++) {
            if (ac[i-1] == bc[j-1])
                CDP(i,j) = CDP(i-1,j-1) + 1;
            else
                CDP(i,j) = CDP(i-1,j) > CDP(i,j-1) ? CDP(i-1,j) : CDP(i,j-1);
        }

    int max_ops = na + nb;
    CharOp *ops = malloc(max_ops * sizeof(CharOp));
    int count = 0;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && ac[i-1] == bc[j-1]) {
            ops[count].type = OP_KEEP; ops[count].code = ac[i-1];
            count++; i--; j--;
        } else if (j > 0 && (i == 0 || CDP(i,j-1) >= CDP(i-1,j))) {
            ops[count].type = OP_INSERT; ops[count].code = bc[j-1];
            count++; j--;
        } else {
            ops[count].type = OP_DELETE; ops[count].code = ac[i-1];
            count++; i--;
        }
    }
    for (int k = 0; k < count/2; k++) {
        CharOp tmp = ops[k]; ops[k] = ops[count-1-k]; ops[count-1-k] = tmp;
    }
    free(dp);
    free(ac);
    free(bc);
    *out_count = count;
    return ops;
}

/* --- Word-level diff --- */
/* Splits text into tokens (maximal runs of non-whitespace + maximal runs of
 * whitespace), runs LCS at the token level, then expands each token to
 * individual char ops. Produces more natural typing patterns than char-level
 * LCS because consecutive chars within a word are grouped.
 *
 * Matches vimscript s:WordDiff + s:SplitWords. */

typedef struct {
    int start;  /* byte offset into the source text */
    int len;    /* byte length */
} Token;

static int is_ws_byte(unsigned char c) {
    /* Vim's \s matches [ \t\n\r\f\v] */
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

/* Split text into tokens: maximal runs of whitespace OR maximal runs of
 * non-whitespace. E.g. "hello world" -> ["hello", " ", "world"].
 * Returns malloc'd array; *out_count is the count. */
static Token *split_words(const char *text, int *out_count) {
    int len = (int)strlen(text);
    int cap = 16, count = 0;
    Token *toks = malloc(cap * sizeof(Token));
    int i = 0;
    while (i < len) {
        if (count >= cap) {
            cap *= 2;
            toks = realloc(toks, cap * sizeof(Token));
        }
        int start = i;
        if (is_ws_byte((unsigned char)text[i])) {
            while (i < len && is_ws_byte((unsigned char)text[i])) i++;
        } else {
            while (i < len && !is_ws_byte((unsigned char)text[i])) i++;
        }
        toks[count].start = start;
        toks[count].len = i - start;
        count++;
    }
    *out_count = count;
    return toks;
}

static int token_eq(const char *a, Token *ta, const char *b, Token *tb) {
    return ta->len == tb->len && memcmp(a + ta->start, b + tb->start, ta->len) == 0;
}

static CharOp *word_diff(const char *a, const char *b, int *out_count) {
    int na, nb;
    Token *ta = split_words(a, &na);
    Token *tb = split_words(b, &nb);

    int *dp = calloc((na + 1) * (nb + 1), sizeof(int));
    #define WDP(i,j) dp[(i)*(nb+1)+(j)]
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++) {
            if (token_eq(a, &ta[i-1], b, &tb[j-1]))
                WDP(i,j) = WDP(i-1,j-1) + 1;
            else
                WDP(i,j) = WDP(i-1,j) > WDP(i,j-1) ? WDP(i-1,j) : WDP(i,j-1);
        }

    /* Backtrack at token level, collecting (type, is_a, tok_idx) in reverse. */
    typedef struct { OpType type; int is_a; int tok_idx; } TokenOp;
    int max_tops = na + nb;
    if (max_tops == 0) max_tops = 1;
    TokenOp *tops = malloc(max_tops * sizeof(TokenOp));
    int tops_count = 0;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && token_eq(a, &ta[i-1], b, &tb[j-1])) {
            tops[tops_count].type = OP_KEEP;
            tops[tops_count].is_a = 1;
            tops[tops_count].tok_idx = i - 1;
            tops_count++; i--; j--;
        } else if (j > 0 && (i == 0 || WDP(i,j-1) >= WDP(i-1,j))) {
            tops[tops_count].type = OP_INSERT;
            tops[tops_count].is_a = 0;
            tops[tops_count].tok_idx = j - 1;
            tops_count++; j--;
        } else {
            tops[tops_count].type = OP_DELETE;
            tops[tops_count].is_a = 1;
            tops[tops_count].tok_idx = i - 1;
            tops_count++; i--;
        }
    }
    /* Reverse token ops so chars within each token are in forward order. */
    for (int k = 0; k < tops_count / 2; k++) {
        TokenOp tmp = tops[k];
        tops[k] = tops[tops_count-1-k];
        tops[tops_count-1-k] = tmp;
    }

    /* Expand each token to char ops (UTF-8 code points). */
    int max_ops = (int)strlen(a) + (int)strlen(b);
    if (max_ops == 0) max_ops = 1;
    CharOp *ops = malloc(max_ops * sizeof(CharOp));
    int count = 0;
    for (int k = 0; k < tops_count; k++) {
        TokenOp *top = &tops[k];
        const char *text = top->is_a ? a : b;
        Token *tok = top->is_a ? &ta[top->tok_idx] : &tb[top->tok_idx];
        int pos = tok->start;
        int end = tok->start + tok->len;
        while (pos < end) {
            int cp = utf8_decode(text, end, &pos);
            if (cp < 0) break;
            ops[count].type = top->type;
            ops[count].code = cp;
            count++;
        }
    }

    free(dp);
    free(tops);
    free(ta);
    free(tb);
    *out_count = count;
    return ops;
    #undef WDP
}

/* Strip leading whitespace (spaces and tabs) from a line.
 * Used by --indent-aware so lines that differ only in indentation are
 * treated as "keep" at the line level. */
static char *normalize_indent(const char *line) {
    int start = 0;
    while (line[start] == ' ' || line[start] == '\t') start++;
    int len = (int)strlen(line + start);
    char *result = malloc(len + 1);
    memcpy(result, line + start, len + 1);
    return result;
}

/* --- Hunk building --- */
typedef struct {
    int target_line;     /* 1-indexed in old file */
    int deleted_count;
    int inserted_count;
    int is_end_insert;
    int is_end_delete;
    CharOp *char_ops;
    int char_op_count;
} Hunk;

/* --- Semantic cleanup: merge adjacent delete+insert pairs that cancel --- */
static CharOp *semantic_cleanup(CharOp *ops, int *count) {
    if (*count < 2) return ops;
    CharOp *out = malloc(*count * sizeof(CharOp));
    int out_count = 0;
    int i = 0;
    while (i < *count) {
        if (i + 1 < *count) {
            /* delete X followed by insert X → keep X */
            if (ops[i].type == OP_DELETE && ops[i+1].type == OP_INSERT && ops[i].code == ops[i+1].code) {
                out[out_count].type = OP_KEEP;
                out[out_count].code = ops[i].code;
                out_count++;
                i += 2;
                continue;
            }
            /* insert X followed by delete X → keep X */
            if (ops[i].type == OP_INSERT && ops[i+1].type == OP_DELETE && ops[i].code == ops[i+1].code) {
                out[out_count].type = OP_KEEP;
                out[out_count].code = ops[i].code;
                out_count++;
                i += 2;
                continue;
            }
        }
        out[out_count++] = ops[i];
        i++;
    }
    free(ops);
    *count = out_count;
    return out;
}

/* --- Op-sequence optimization: consolidate interleaved del/ins --- */
static CharOp *optimize_sequence(CharOp *ops, int *count) {
    if (*count < 4) return ops;
    CharOp *out = malloc(*count * sizeof(CharOp));
    int out_count = 0;
    int i = 0;
    while (i < *count) {
        if (ops[i].type != OP_KEEP && ops[i].code != 10) {
            while (i < *count) {
                if (ops[i].type == OP_KEEP) break;
                if (ops[i].code == 10) break;
                out[out_count++] = ops[i];
                i++;
            }
        } else {
            out[out_count++] = ops[i];
            i++;
        }
    }
    free(ops);
    *count = out_count;
    return out;
}

/* --- Left-to-right: sort ops within each line by type --- */
static CharOp *left_to_right(CharOp *ops, int *count) {
    if (*count < 2) return ops;
    CharOp *out = malloc(*count * sizeof(CharOp));
    int out_count = 0;
    int i = 0;
    while (i < *count) {
        int line_start = i;
        while (i < *count && ops[i].code != 10) i++;
        int line_end = i;
        for (int k = line_start; k < line_end; k++)
            if (ops[k].type == OP_KEEP) out[out_count++] = ops[k];
        for (int k = line_start; k < line_end; k++)
            if (ops[k].type == OP_DELETE) out[out_count++] = ops[k];
        for (int k = line_start; k < line_end; k++)
            if (ops[k].type == OP_INSERT) out[out_count++] = ops[k];
        if (i < *count) { out[out_count++] = ops[i]; i++; }
    }
    free(ops);
    *count = out_count;
    return out;
}

int main(int argc, char **argv) {
    double t_start = now_ms();

    const char *algorithm = getenv("DIFFVIM_ALGORITHM");
    if (!algorithm || !*algorithm) algorithm = "lcs";
    int do_semantic = getenv("DIFFVIM_SEMANTIC_CLEANUP") && getenv("DIFFVIM_SEMANTIC_CLEANUP")[0] == '1';
    int do_word_diff = getenv("DIFFVIM_WORD_DIFF") && getenv("DIFFVIM_WORD_DIFF")[0] == '1';
    int do_indent_aware = getenv("DIFFVIM_INDENT_AWARE") && getenv("DIFFVIM_INDENT_AWARE")[0] == '1';
    int do_optimize = !getenv("DIFFVIM_OPTIMIZE_SEQUENCE") || getenv("DIFFVIM_OPTIMIZE_SEQUENCE")[0] != '0';  /* default on */
    int do_l2r = getenv("DIFFVIM_LEFT_TO_RIGHT") && getenv("DIFFVIM_LEFT_TO_RIGHT")[0] == '1';

    /* Parse args:
     *   Two-file mode: <oldfile> <newfile> <outputfile> [options]
     *   Diff mode:     --diff <patchfile> <outputfile> [options]
     * Options: --algorithm lcs|myers|patience, --semantic-cleanup,
     *          --word-diff, --indent-aware. May appear in any position.
     * --diff may also appear in any position; positional args are then
     * interpreted as (patchfile, outputfile) instead of (old, new, output). */
    int diff_mode = 0;
    const char *positionals[3] = {NULL, NULL, NULL};
    int n_positionals = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            printf(
"diffvim-compute-c — External diff computer for diffvim (C reference).\n"
"\n"
"USAGE\n"
"    diffvim-compute-c <oldfile> <newfile> <outputfile> [options]\n"
"    diffvim-compute-c --diff <patchfile> <outputfile> [options]\n"
"    diffvim-compute-c --diff - <outputfile> [options]   (read diff from stdin)\n"
"    diffvim-compute-c -h | --help\n"
"\n"
"Reads two files (or a unified diff), computes a line-level + char-level\n"
"LCS diff, and writes the result in the format that `diffvim --precomputed\n"
"FILE` consumes. Compiled to native code for speed (10-100x faster than\n"
"vimscript LCS).\n"
"\n"
"OPTIONS\n"
"    --algorithm lcs|myers|patience   Diff algorithm (default: lcs).\n"
"    --semantic-cleanup               Merge adjacent delete/insert pairs.\n"
"    --word-diff                      Batch word runs in char ops.\n"
"    --indent-aware                   Treat indent-only changes specially.\n"
"    --optimize-sequence              Reorder ops within a line (default on).\n"
"    --no-optimize-sequence           Disable op reordering.\n"
"    --left-to-right                  Emit keeps, then deletes, then inserts.\n"
"    --diff                           Read a unified diff instead of two files.\n"
"    -h, --help                       Show this help and exit.\n"
"\n"
"ENVIRONMENT\n"
"    DIFFVIM_ALGORITHM          Same as --algorithm.\n"
"    DIFFVIM_SEMANTIC_CLEANUP   Set to 1 to enable by default.\n"
"    DIFFVIM_WORD_DIFF          Set to 1 to enable by default.\n"
"    DIFFVIM_INDENT_AWARE       Set to 1 to enable by default.\n"
"    DIFFVIM_OPTIMIZE_SEQUENCE  Default 1; set to 0 to disable.\n"
"    DIFFVIM_LEFT_TO_RIGHT      Set to 1 to enable by default.\n"
"\n"
"OUTPUT FORMAT (written to <outputfile>)\n"
"    # algorithm <name>\n"
"    # semantic_cleanup <0|1>\n"
"    # word_diff <0|1>\n"
"    # indent_aware <0|1>\n"
"    # optimize_sequence <0|1>\n"
"    # left_to_right <0|1>\n"
"    # hunk_count <N>\n"
"    HUNK <line>\n"
"    keep|delete|insert <code>\n"
"    ...\n"
"\n"
"Timing is printed to stderr:\n"
"    compute: <ms> ms (total)\n"
"    startup: <ms> ms (process start to first byte read)\n"
"\n"
"EXAMPLES\n"
"    diffvim-compute-c old.py new.py /tmp/diff.txt\n"
"    diffvim-compute-c --algorithm patience --semantic-cleanup old.py new.py out.txt\n"
"    diffvim-compute-c --diff patch.diff out.txt\n"
"    diffvim-precomputed --tool c old.py new.py\n"
"\n"
"SEE ALSO\n"
"    diffvim(1), diffvim-precomputed(1), diffvim-compare(1)\n"
"    Full docs: docs/PARALLEL_COMPUTE.md, docs/src/architecture.md\n");
            return 0;
        } else if (strcmp(argv[i], "--algorithm") == 0 && i + 1 < argc) {
            algorithm = argv[++i];
        } else if (strcmp(argv[i], "--semantic-cleanup") == 0) {
            do_semantic = 1;
        } else if (strcmp(argv[i], "--word-diff") == 0) {
            do_word_diff = 1;
        } else if (strcmp(argv[i], "--indent-aware") == 0) {
            do_indent_aware = 1;
        } else if (strcmp(argv[i], "--optimize-sequence") == 0) {
            do_optimize = 1;
        } else if (strcmp(argv[i], "--no-optimize-sequence") == 0) {
            do_optimize = 0;
        } else if (strcmp(argv[i], "--left-to-right") == 0) {
            do_l2r = 1;
        } else if (strcmp(argv[i], "--diff") == 0) {
            diff_mode = 1;
        } else if (n_positionals < 3) {
            positionals[n_positionals++] = argv[i];
        }
    }

    const char *oldfile = NULL, *newfile = NULL, *outfile = NULL, *diff_file = NULL;
    if (diff_mode) {
        if (n_positionals < 2) {
            fprintf(stderr, "Usage: %s --diff <patchfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", argv[0]);
            fprintf(stderr, "   or: %s --diff - <outputfile> [options]   (read diff from stdin)\n", argv[0]);
            return 1;
        }
        diff_file = positionals[0];
        outfile = positionals[1];
    } else {
        if (n_positionals < 3) {
            fprintf(stderr, "Usage: %s <oldfile> <newfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", argv[0]);
            fprintf(stderr, "   or: %s --diff <patchfile> <outputfile> [options]\n", argv[0]);
            return 1;
        }
        oldfile = positionals[0];
        newfile = positionals[1];
        outfile = positionals[2];
    }

    double t_read_start = now_ms();
    StrArr old_lines, new_lines;
    if (diff_mode) {
        if (parse_unified_diff(diff_file, &old_lines, &new_lines) != 0) {
            fprintf(stderr, "Error: cannot read diff file %s\n", diff_file);
            return 1;
        }
    } else {
        old_lines = read_lines(oldfile);
        new_lines = read_lines(newfile);
    }
    double t_read_end = now_ms();

    if (old_lines.count == 0 && new_lines.count == 0) {
        fprintf(stderr, "Error: both files empty or unreadable\n");
        return 1;
    }

    /* If indent_aware, build normalized copies of the lines for the line-level
     * diff. The indices returned by compute_line_diff are the same (since
     * normalization doesn't change line count), so we can use them to access
     * the ORIGINAL (non-normalized) lines when building hunk text. */
    StrArr old_norm, new_norm;
    sa_init(&old_norm);
    sa_init(&new_norm);
    if (do_indent_aware) {
        for (int i = 0; i < old_lines.count; i++)
            sa_push(&old_norm, normalize_indent(old_lines.data[i]));
        for (int i = 0; i < new_lines.count; i++)
            sa_push(&new_norm, normalize_indent(new_lines.data[i]));
    }
    StrArr *line_a = do_indent_aware ? &old_norm : &old_lines;
    StrArr *line_b = do_indent_aware ? &new_norm : &new_lines;

    double t_diff_start = now_ms();
    int line_op_count;
    LineOp *lops = compute_line_diff(line_a, line_b, &line_op_count, algorithm);

    /* Group line ops into hunks */
    Hunk *hunks = malloc((line_op_count + 1) * sizeof(Hunk));
    int hunk_count = 0;
    int cur_target = 1;
    int old_pos = 1;

    for (int i = 0; i < line_op_count; i++) {
        if (lops[i].type == OP_KEEP) {
            old_pos = lops[i].a_idx + 2;
        } else {
            /* Start or continue a hunk */
            if (hunk_count == 0 || lops[i-1].type == OP_KEEP) {
                cur_target = old_pos;
            }
            /* Collect all non-keep ops until next keep or end */
            int start = i;
            while (i < line_op_count && lops[i].type != OP_KEEP) i++;
            int end = i;
            i--; /* will be incremented by for loop */

            Hunk *h = &hunks[hunk_count];
            h->target_line = cur_target;
            h->deleted_count = 0;
            h->inserted_count = 0;

            /* Build old_text and new_text */
            char *old_text = malloc(1); old_text[0] = '\0';
            char *new_text = malloc(1); new_text[0] = '\0';
            int old_text_len = 0, new_text_len = 0;

            for (int k = start; k < end; k++) {
                if (lops[k].type == OP_DELETE) {
                    char *line = old_lines.data[lops[k].a_idx];
                    int len = strlen(line);
                    old_text = realloc(old_text, old_text_len + len + 2);
                    if (h->deleted_count > 0) {
                        old_text[old_text_len++] = '\n';
                        old_text[old_text_len] = '\0';
                    }
                    strcat(old_text, line);
                    old_text_len += len;
                    h->deleted_count++;
                    old_pos = lops[k].a_idx + 2;
                } else if (lops[k].type == OP_INSERT) {
                    char *line = new_lines.data[lops[k].b_idx];
                    int len = strlen(line);
                    new_text = realloc(new_text, new_text_len + len + 2);
                    if (h->inserted_count > 0) {
                        new_text[new_text_len++] = '\n';
                        new_text[new_text_len] = '\0';
                    }
                    strcat(new_text, line);
                    new_text_len += len;
                    h->inserted_count++;
                }
            }

            /* Handle pure insert / pure delete newline padding */
            h->is_end_insert = 0;
            h->is_end_delete = 0;
            if (h->deleted_count == 0) {
                free(old_text); old_text = malloc(1); old_text[0] = '\0';
                if (old_lines.count == 0) {
                    /* empty old file */
                } else if (h->target_line > old_lines.count) {
                    char *tmp = malloc(strlen(new_text) + 2);
                    tmp[0] = '\n'; strcpy(tmp + 1, new_text);
                    free(new_text); new_text = tmp;
                    h->is_end_insert = 1;
                } else {
                    char *tmp = malloc(strlen(new_text) + 2);
                    strcpy(tmp, new_text); strcat(tmp, "\n");
                    free(new_text); new_text = tmp;
                }
            } else if (h->inserted_count == 0) {
                free(new_text); new_text = malloc(1); new_text[0] = '\0';
                if (h->target_line + h->deleted_count - 1 >= old_lines.count) {
                    char *tmp = malloc(strlen(old_text) + 2);
                    tmp[0] = '\n'; strcpy(tmp + 1, old_text);
                    free(old_text); old_text = tmp;
                    h->is_end_delete = 1;
                } else {
                    char *tmp = malloc(strlen(old_text) + 2);
                    strcpy(tmp, old_text); strcat(tmp, "\n");
                    free(old_text); old_text = tmp;
                }
            }

            h->char_ops = do_word_diff ? word_diff(old_text, new_text, &h->char_op_count)
                                       : char_diff(old_text, new_text, &h->char_op_count);
            if (do_semantic) {
                h->char_ops = semantic_cleanup(h->char_ops, &h->char_op_count);
            }
            if (do_optimize) {
                h->char_ops = optimize_sequence(h->char_ops, &h->char_op_count);
            }
            if (do_l2r) {
                h->char_ops = left_to_right(h->char_ops, &h->char_op_count);
            }
            free(old_text);
            free(new_text);
            hunk_count++;
        }
    }

    double t_diff_end = now_ms();

    /* Write output */
    double t_write_start = now_ms();
    FILE *out = fopen(outfile, "wb");
    if (!out) { fprintf(stderr, "Cannot write %s\n", outfile); return 1; }

    fprintf(out, "# diffvim precomputed diff v1\n");
    fprintf(out, "# algorithm %s\n", algorithm);
    fprintf(out, "# semantic_cleanup %d\n", do_semantic ? 1 : 0);
    fprintf(out, "# word_diff %d\n", do_word_diff ? 1 : 0);
    fprintf(out, "# indent_aware %d\n", do_indent_aware ? 1 : 0);
    fprintf(out, "# optimize_sequence %d\n", do_optimize ? 1 : 0);
    fprintf(out, "# left_to_right %d\n", do_l2r ? 1 : 0);
    fprintf(out, "# hunk_count %d\n", hunk_count);
    for (int h = 0; h < hunk_count; h++) {
        Hunk *hk = &hunks[h];
        fprintf(out, "HUNK %d %d %d %d %d\n",
                hk->target_line, hk->deleted_count, hk->inserted_count,
                hk->is_end_insert, hk->is_end_delete);
        for (int k = 0; k < hk->char_op_count; k++) {
            const char *type = hk->char_ops[k].type == OP_KEEP ? "keep" :
                                hk->char_ops[k].type == OP_DELETE ? "delete" : "insert";
            fprintf(out, "%s %d\n", type, hk->char_ops[k].code);
        }
    }
    fclose(out);
    double t_write_end = now_ms();

    /* Timing to stderr */
    fprintf(stderr, "compute: %.2f ms (read %.2f + diff %.2f + write %.2f)\n",
            t_write_end - t_start,
            t_read_end - t_read_start,
            t_diff_end - t_diff_start,
            t_write_end - t_write_start);
    fprintf(stderr, "startup: %.2f ms (process start to first read)\n",
            t_read_start - t_start);
    fprintf(stderr, "hunks: %d, lines: %d -> %d\n",
            hunk_count, old_lines.count, new_lines.count);

    /* Cleanup */
    for (int h = 0; h < hunk_count; h++) free(hunks[h].char_ops);
    free(hunks);
    free(lops);
    sa_free(&old_lines);
    sa_free(&new_lines);
    sa_free(&old_norm);
    sa_free(&new_norm);

    return 0;
}
