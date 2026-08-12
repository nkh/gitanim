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

int main(int argc, char **argv) {
    double t_start = now_ms();

    if (argc != 4) {
        fprintf(stderr, "Usage: %s <oldfile> <newfile> <outputfile>\n", argv[0]);
        return 1;
    }

    double t_read_start = now_ms();
    StrArr old_lines = read_lines(argv[1]);
    StrArr new_lines = read_lines(argv[2]);
    double t_read_end = now_ms();

    if (old_lines.count == 0 && new_lines.count == 0) {
        fprintf(stderr, "Error: both files empty or unreadable\n");
        return 1;
    }

    double t_diff_start = now_ms();
    int line_op_count;
    LineOp *lops = line_diff(&old_lines, &new_lines, &line_op_count);

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

            h->char_ops = char_diff(old_text, new_text, &h->char_op_count);
            free(old_text);
            free(new_text);
            hunk_count++;
        }
    }

    double t_diff_end = now_ms();

    /* Write output */
    double t_write_start = now_ms();
    FILE *out = fopen(argv[3], "wb");
    if (!out) { fprintf(stderr, "Cannot write %s\n", argv[3]); return 1; }

    fprintf(out, "# diffvim precomputed diff v1\n");
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

    return 0;
}
