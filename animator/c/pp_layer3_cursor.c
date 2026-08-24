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
 * Algorithm:
 *
 *   Read old file into a buffer (list of lines, each a list of chars).
 *
 *   cur_line = target_line + line_offset
 *   cur_col = 1
 *
 *   for each op:
 *       if keep:
 *           op.line = cur_line
 *           op.col = cur_col
 *           if code == 10: cur_line++; cur_col = 1
 *           else: cur_col++
 *       elif delete:
 *           if code == 10:
 *               # \n delete — join current line with next
 *               op.line = cur_line
 *               op.col = cur_col
 *               # Remove the \n (join lines in buffer)
 *               if cur_line < n_buf_lines - 1:
 *                   buf[cur_line] += buf[cur_line + 1]
 *                   remove buf[cur_line + 1]
 *               # cur_line stays, cur_col stays
 *           else:
 *               # Content delete — find the char in the buffer
 *               line = buf[cur_line]
 *               # Find the first occurrence of code in the line
 *               # starting from cur_col - 1 (0-indexed)
 *               found = find_char(line, code, cur_col - 1)
 *               if found >= 0:
 *                   op.col = found + 1  # 1-indexed
 *                   # Remove the char from the buffer
 *                   remove char at found from line
 *                   # cur_col stays at the deletion point
 *                   cur_col = found + 1
 *               else:
#                   # Char not found — use cursor position
 *                   op.col = cur_col
 *               op.line = cur_line
 *       elif insert:
 *           op.line = cur_line
 *           op.col = cur_col
 *           if code == 10: cur_line++; cur_col = 1
 *           else: cur_col++
 *
 *   The buffer simulation ensures that each delete targets the correct
 *   char, regardless of op order.
 *
 *   If the old file is not available (DV_OLD_FILE not set), falls back
 *   to cursor-only tracking (no buffer lookup).
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

    /* Load old file for buffer simulation */
    Buf buf;
    buf_load_file(&buf, old_file);
    int has_buf = (buf.n_lines > 0) && env_flag("DV_USE_BUFFER");

    /* The buffer is 0-indexed. cur_line is 1-indexed.
     * Buffer line index = cur_line - 1 + line_offset (already applied to cur_line) */
    int buf_line_idx = cur_line - 1;

    for (int i = 0; i < count; i++) {
        out[i] = in[i];

        if (pp_is_debug_op(&in[i])) continue;

        /* Set the op's position to the current cursor */
        out[i].line = cur_line;
        out[i].col = cur_col;

        if (strcmp(in[i].type, "keep") == 0) {
            if (in[i].code == 10) {
                cur_line++;
                cur_col = 1;
                buf_line_idx++;
            } else {
                cur_col++;
            }
        } else if (strcmp(in[i].type, "delete") == 0) {
            if (in[i].code == 10) {
                /* \n delete — join lines in buffer */
                newl_del++;
                if (has_buf) {
                    buf_join_lines(&buf, buf_line_idx);
                }
                /* cur_line stays, cur_col stays */
            } else {
                /* Content delete — find char in buffer */
                if (has_buf) {
                    BufLine *bl = buf_get_line(&buf, buf_line_idx);
                    if (bl) {
                        /* Find the char starting from cursor position */
                        int pos = buf_find_char(bl, in[i].code, cur_col - 1);
                        if (pos >= 0) {
                            /* Found — assign actual position */
                            out[i].col = pos + 1;  /* 1-indexed */
                            /* Remove from buffer */
                            buf_remove_char(bl, pos);
                            /* Cursor stays at the deletion point */
                            // cur_col NOT updated — keep cursor position
                        }
                        /* If not found, keep cursor position */
                    }
                }
                /* Without buffer: cur_col stays (content removed at cursor) */
            }
        } else if (strcmp(in[i].type, "insert") == 0 ||
                   strcmp(in[i].type, "overwrite_insert") == 0) {
            if (in[i].code == 10) {
                cur_line++;
                cur_col = 1;
                buf_line_idx++;
                newl_ins++;
            } else {
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
