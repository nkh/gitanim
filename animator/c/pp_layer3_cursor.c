/*
 * pp_layer3_cursor.c — Layer 3: Cursor Recomputation
 *
 * Purpose:
 *   Assign correct (line, col) to every op.
 *
 *   For KEEP and INSERT ops: track the cursor position (simple).
 *   For DELETE ops: find the actual position of the char in the
 *   current buffer state (requires old file content).
 *
 *   This handles reordered deletes correctly. If indent-last moves
 *   a delete from the beginning to the end of the op sequence, the
 *   cursor recomp still finds the correct position because it
 *   simulates the buffer.
 *
 *   For ops with pos_set=1 (set by a previous layer, e.g., indent-last
 *   on deferred leading-whitespace deletes), respect the op's col and
 *   only update the cursor accordingly.
 *
 * Algorithm:
 *
 *   Read old file into a buffer (list of lines, each a list of chars).
 *
 *   cur_line = first op's line (adjusted by line_offset, already applied)
 *   cur_col = 1
 *
 *   for each op:
 *       if pos_set:
 *           cur_col = op.col      // jump cursor to op's col
 *           op.line = cur_line
 *           op.col  = cur_col
 *           // update buffer to reflect the op
 *           if delete (non-\n): remove char at cur_col-1 from buffer
 *           if delete (\n): join lines in buffer
 *           if insert (non-\n): insert char at cur_col-1 in buffer
 *           if insert (\n): split line in buffer at cur_col-1
 *       else:
 *           op.line = cur_line
 *           op.col  = cur_col
 *           if keep:
 *               if code == 10: cur_line++; cur_col = 1; buf_line_idx++
 *               else: cur_col++
 *           elif delete:
 *               if code == 10:
 *                   // \n delete — join lines in buffer
 *                   if has_buf: buf_join_lines(buf, buf_line_idx)
 *                   // cur_line stays, cur_col stays
 *               else:
 *                   // Content delete — find char in buffer
 *                   if has_buf:
 *                       pos = find_char(buf[cur_line], code, cur_col-1)
 *                       if pos >= 0:
 *                           op.col = pos + 1     // actual position
 *                           cur_col = pos + 1    // IMPORTANT: update cursor
 *                           remove char at pos from buffer
 *                       // else: char not found, keep cursor position
 *                   // Without buffer: cur_col stays
 *           elif insert:
 *               if code == 10: cur_line++; cur_col = 1; buf_line_idx++
 *               else: cur_col++
 *
 *   The buffer simulation ensures that each delete targets the correct
 *   char, regardless of op order. The cur_col update after a found
 *   char is critical: without it, subsequent searches start from the
 *   original cursor position and may find the wrong char (e.g., a
 *   leading space instead of an intended content space).
 *
 *   If the old file is not available (DV_OLD_FILE not set), falls back
 *   to cursor-only tracking (no buffer lookup). In this mode, all
 *   content deletes get the current cursor col (which stays at 1 for
 *   consecutive deletes, matching the animator's delete-at-cursor
 *   behavior).
 *
 * Input:  V2 TSV on stdin (from previous layers)
 * Output: V2 TSV on stdout (with recomputed line/col)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_layer3 animator/c/pp_layer3_cursor.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=path  →  dumps to $path/L3_cursor_*.txt
 *   DV_OLD_FILE=path           →  old file for buffer simulation
 *   DV_NO_BUFFER=1             →  disable buffer simulation even if
 *                                 old file is available (fallback mode)
 */

#include "pp_common.h"

/* ── Buffer simulation ──────────────────────────────────────────────── */

typedef struct {
    char *data;     /* line content (null-terminated) */
    int len;        /* length (not counting null) */
    int cap;        /* allocated capacity */
} BufLine;

typedef struct {
    BufLine *lines;
    int n_lines;
    int cap;
} Buf;

static void buf_init(Buf *buf) {
    buf->lines = NULL;
    buf->n_lines = 0;
    buf->cap = 0;
}

static void buf_free(Buf *buf) {
    for (int i = 0; i < buf->n_lines; i++)
        free(buf->lines[i].data);
    free(buf->lines);
}

static BufLine *buf_get_line(Buf *buf, int line_idx /* 0-indexed */) {
    if (line_idx < 0 || line_idx >= buf->n_lines) return NULL;
    return &buf->lines[line_idx];
}

static void buf_ensure_cap(Buf *buf, int needed) {
    if (buf->cap >= needed) return;
    int new_cap = buf->cap ? buf->cap * 2 : 256;
    while (new_cap < needed) new_cap *= 2;
    buf->lines = (BufLine *)realloc(buf->lines, new_cap * sizeof(BufLine));
    buf->cap = new_cap;
}

static void buf_load_file(Buf *buf, const char *path) {
    buf_init(buf);
    if (!path || path[0] == 0) return;
    FILE *f = fopen(path, "r");
    if (!f) return;
    char line[PP_MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n\r")] = 0;
        buf_ensure_cap(buf, buf->n_lines + 1);
        int len = strlen(line);
        int cap = len + 1;
        buf->lines[buf->n_lines].data = (char *)malloc(cap);
        memcpy(buf->lines[buf->n_lines].data, line, len + 1);
        buf->lines[buf->n_lines].len = len;
        buf->lines[buf->n_lines].cap = cap;
        buf->n_lines++;
    }
    fclose(f);
    pp_logf("Buffer: loaded %d lines from %s", buf->n_lines, path);
}

/* Find the first occurrence of char `code` in the line, starting
 * from position `start` (0-indexed). Returns the position or -1. */
static int buf_find_char(BufLine *bl, int code, int start) {
    if (!bl) return -1;
    if (start < 0) start = 0;
    for (int i = start; i < bl->len; i++) {
        if ((unsigned char)bl->data[i] == code) return i;
    }
    return -1;
}

/* Remove the char at position `pos` (0-indexed) from the line. */
static void buf_remove_char(BufLine *bl, int pos) {
    if (!bl || pos < 0 || pos >= bl->len) return;
    memmove(bl->data + pos, bl->data + pos + 1, bl->len - pos);
    bl->len--;
}

/* Insert char `code` at position `pos` (0-indexed) in the line.
 * If pos >= len, appends to end. */
static void buf_insert_char(BufLine *bl, int pos, int code) {
    if (!bl) return;
    if (pos < 0) pos = 0;
    if (pos > bl->len) pos = bl->len;
    if (bl->cap < bl->len + 2) {
        bl->cap = bl->len + 2;
        bl->data = (char *)realloc(bl->data, bl->cap);
    }
    memmove(bl->data + pos + 1, bl->data + pos, bl->len - pos + 1);
    bl->data[pos] = (char)code;
    bl->len++;
}

/* Join line `idx` with line `idx+1` (remove \n between them). */
static void buf_join_lines(Buf *buf, int idx) {
    if (idx < 0 || idx >= buf->n_lines - 1) return;
    BufLine *cur = &buf->lines[idx];
    BufLine *next = &buf->lines[idx + 1];
    int new_len = cur->len + next->len;
    if (cur->cap < new_len + 1) {
        cur->cap = new_len + 1;
        cur->data = (char *)realloc(cur->data, cur->cap);
    }
    memcpy(cur->data + cur->len, next->data, next->len + 1);
    cur->len = new_len;
    /* Shift remaining lines down */
    free(next->data);
    for (int i = idx + 1; i < buf->n_lines - 1; i++)
        buf->lines[i] = buf->lines[i + 1];
    buf->n_lines--;
}

/* Split line `idx` into two lines at position `pos` (0-indexed).
 * Chars [0, pos) stay on line idx; chars [pos, end) move to a new
 * line idx+1 (existing lines shift down). */
static void buf_split_line(Buf *buf, int idx, int pos) {
    if (idx < 0 || idx >= buf->n_lines) return;
    BufLine *cur = &buf->lines[idx];
    if (pos < 0) pos = 0;
    if (pos > cur->len) pos = cur->len;
    int tail_len = cur->len - pos;
    /* Make room for a new line */
    buf_ensure_cap(buf, buf->n_lines + 1);
    /* Shift lines after idx down by 1 */
    for (int i = buf->n_lines; i > idx + 1; i--)
        buf->lines[i] = buf->lines[i - 1];
    /* Set up the new line (idx+1) with the tail */
    buf->lines[idx + 1].data = (char *)malloc(tail_len + 1);
    memcpy(buf->lines[idx + 1].data, cur->data + pos, tail_len + 1);
    buf->lines[idx + 1].len = tail_len;
    buf->lines[idx + 1].cap = tail_len + 1;
    /* Truncate the original line */
    cur->len = pos;
    cur->data[pos] = 0;
    buf->n_lines++;
}

/* ── Layer 3 main function ────────────────────────────────────────── */

static int env_flag(const char *name) {
    const char *v = getenv(name);
    return v && v[0] == '1';
}

int layer3_cursor(Op *in, int in_count, Op *out, int out_cap,
                  const char *old_file) {
    int count = in_count;
    if (count > out_cap) count = out_cap;

    int cur_line = 0;
    int cur_col = 1;
    int newl_ins = 0, newl_del = 0;

    if (count > 0) {
        cur_line = in[0].line;
    }

    /* Load old file for buffer simulation.
     *
     * Buffer sim is enabled when:
     *   - DV_OLD_FILE is set and points to a readable file, AND
     *   - DV_NO_BUFFER is not set, AND
     *   - At least one op has pos_set=1 (set by indent-last layer),
     *     OR DV_USE_BUFFER=1 (explicit override).
     *
     * This conditional activation preserves the existing behavior for
     * the standard pipeline (no indent-last), where buffer sim could
     * interfere with the "delete last line" pattern. Buffer sim is
     * only needed for the indent-last case (to find actual char
     * positions for content deletes and to handle deferred indent
     * deletes). */
    Buf buf;
    buf_load_file(&buf, old_file);

    /* Check if any op has pos_set=1 */
    int has_pos_set = 0;
    for (int i = 0; i < count; i++) {
        if (in[i].pos_set) { has_pos_set = 1; break; }
    }

    int has_buf = (buf.n_lines > 0) && !env_flag("DV_NO_BUFFER") &&
                  (has_pos_set || env_flag("DV_USE_BUFFER"));

    pp_logf("Buffer sim: %s (has_pos_set=%d, old_file=%s, n_lines=%d)",
            has_buf ? "enabled" : "disabled",
            has_pos_set, old_file ? old_file : "(null)", buf.n_lines);

    /* The buffer is 0-indexed. cur_line is 1-indexed.
     * Buffer line index = cur_line - 1 + line_offset (already applied to cur_line) */
    int buf_line_idx = cur_line - 1;

    for (int i = 0; i < count; i++) {
        out[i] = in[i];

        if (pp_is_debug_op(&in[i])) continue;

        /* ── pos_set ops: use op's col, but compute line from cursor ── */
        if (in[i].pos_set) {
            /* Jump cursor to op's col (line stays as current cursor line).
             * For deletes, the op's col is just a search hint — the actual
             * position may differ if previous ops (inserts, keeps) shifted
             * the leading whitespace. We use buffer sim to find the char. */
            cur_col = in[i].col;
            out[i].line = cur_line;
            out[i].col = cur_col;

            /* Update buffer to reflect the op (so subsequent buffer sim
             * searches see the correct state). */
            if (strcmp(in[i].type, "delete") == 0) {
                if (in[i].code == 10) {
                    newl_del++;
                    if (has_buf) {
                        BufLine *bl = buf_get_line(&buf, buf_line_idx);
                        if (bl) {
                            out[i].col = bl->len + 1;
                            cur_col = out[i].col;
                        }
                        buf_join_lines(&buf, buf_line_idx);
                    }
                    /* cur_line stays, cur_col stays */
                } else {
                    /* Content delete — search buffer for the char.
                     * Start from op's col (which is 1 for deferred indent
                     * deletes — meaning search from the start of the line).
                     * This handles cases where the leading whitespace has
                     * been shifted by prior inserts/keeps. */
                    if (has_buf) {
                        BufLine *bl = buf_get_line(&buf, buf_line_idx);
                        if (bl) {
                            int pos = buf_find_char(bl, in[i].code, cur_col - 1);
                            if (pos >= 0) {
                                out[i].col = pos + 1;
                                cur_col = pos + 1;
                                buf_remove_char(bl, pos);
                            } else {
                                /* Not found — try from start of line */
                                pos = buf_find_char(bl, in[i].code, 0);
                                if (pos >= 0) {
                                    out[i].col = pos + 1;
                                    cur_col = pos + 1;
                                    buf_remove_char(bl, pos);
                                }
                                /* else: keep cursor position */
                            }
                        }
                    }
                    /* cur_col stays (chars shift left) */
                }
            } else if (strcmp(in[i].type, "insert") == 0 ||
                       strcmp(in[i].type, "overwrite_insert") == 0) {
                if (in[i].code == 10) {
                    if (has_buf) buf_split_line(&buf, buf_line_idx, cur_col - 1);
                    cur_line++;
                    cur_col = 1;
                    buf_line_idx++;
                    newl_ins++;
                } else {
                    if (has_buf) {
                        BufLine *bl = buf_get_line(&buf, buf_line_idx);
                        if (bl) buf_insert_char(bl, cur_col - 1, in[i].code);
                    }
                    cur_col++;
                }
            } else if (strcmp(in[i].type, "keep") == 0) {
                if (in[i].code == 10) {
                    cur_line++;
                    cur_col = 1;
                    buf_line_idx++;
                } else {
                    cur_col++;
                }
            }
            continue;
        }

        /* ── Non-pos_set ops: compute position from cursor ── */

        /* Set the op's position to the current cursor */
        out[i].line = cur_line;
        out[i].col = cur_col;

        if (strcmp(in[i].type, "keep") == 0) {
            if (in[i].code == 10) {
                cur_line++;
                cur_col = 1;
                buf_line_idx++;
            } else {
                /* Buffer sim: find the kept char in the buffer to
                 * determine its actual position. This is needed when
                 * previous ops (e.g., deferred indent deletes via
                 * indent-last) haven't yet removed the leading
                 * whitespace, so the kept char's position differs
                 * from the simple cursor-tracking model. */
                if (has_buf) {
                    BufLine *bl = buf_get_line(&buf, buf_line_idx);
                    if (bl) {
                        int pos = buf_find_char(bl, in[i].code, cur_col - 1);
                        if (pos >= 0) {
                            out[i].col = pos + 1;
                            cur_col = pos + 2;  /* advance past the kept char */
                        } else {
                            cur_col++;
                        }
                    } else {
                        cur_col++;
                    }
                } else {
                    cur_col++;
                }
            }
        } else if (strcmp(in[i].type, "delete") == 0) {
            if (in[i].code == 10) {
                /* \n delete — join lines in buffer.
                 *
                 * The \n is at the END of the current line. If the cursor
                 * was reset by previous pos_set ops (e.g., deferred
                 * indent deletes that set col=1), we can't use cur_col
                 * directly — we need the actual end-of-line position.
                 *
                 * With buffer sim, look up the line length. Without buffer
                 * sim, fall back to cur_col (the simple cursor tracking
                 * model, which works for the standard reorder without
                 * indent-last). */
                newl_del++;
                if (has_buf) {
                    BufLine *bl = buf_get_line(&buf, buf_line_idx);
                    if (bl) {
                        out[i].col = bl->len + 1;  /* 1-indexed: past last char */
                        cur_col = out[i].col;
                    }
                    buf_join_lines(&buf, buf_line_idx);
                }
                /* cur_line stays (the join brings next line up to cur_line),
                 * cur_col stays at the \n position (so subsequent ops
                 * continue from there). */
            } else {
                /* Content delete — find char in buffer */
                if (has_buf) {
                    BufLine *bl = buf_get_line(&buf, buf_line_idx);
                    if (bl) {
                        /* Find the char starting from cursor position */
                        int pos = buf_find_char(bl, in[i].code, cur_col - 1);
                        if (pos >= 0) {
                            /* Found — assign actual position */
                            out[i].col = pos + 1;     /* 1-indexed */
                            /* Remove from buffer */
                            buf_remove_char(bl, pos);
                            /* IMPORTANT: update cursor to the deletion point.
                             * Without this, subsequent searches start from
                             * the old cursor position and may find the wrong
                             * char (e.g., a leading space instead of an
                             * intended content space). */
                            cur_col = pos + 1;
                        }
                        /* If not found, keep cursor position */
                    }
                }
                /* Without buffer: cur_col stays (content removed at cursor) */
            }
        } else if (strcmp(in[i].type, "insert") == 0 ||
                   strcmp(in[i].type, "overwrite_insert") == 0) {
            if (in[i].code == 10) {
                if (has_buf) buf_split_line(&buf, buf_line_idx, cur_col - 1);
                cur_line++;
                cur_col = 1;
                buf_line_idx++;
                newl_ins++;
            } else {
                if (has_buf) {
                    BufLine *bl = buf_get_line(&buf, buf_line_idx);
                    if (bl) buf_insert_char(bl, cur_col - 1, in[i].code);
                }
                cur_col++;
            }
        }
    }

    if (has_buf) buf_free(&buf);

    pp_logf("Cursor recomp: %d ops, %d newl_ins, %d newl_del, "
            "final line=%d col=%d, buf=%s",
            count, newl_ins, newl_del, cur_line, cur_col,
            has_buf ? "yes" : "no");
    return count;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L3", "Cursor Recomputation");
    return pp_run_layer(layer3_cursor);
}
#endif
