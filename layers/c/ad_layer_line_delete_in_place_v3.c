/* ad_layer_line_delete_in_place_v3.c — Clone using buffer-simulation position walk.
 *
 * Same LDI algorithm as v1, but uses a new position-recompute function
 * that simulates the buffer to correctly track line shifts and column
 * offsets after joins.
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

/* ── Buffer-simulation position recompute ──────────────────────────
 *
 * Tracks per-original-line state:
 *   line_map[L]    = current buffer line of original line L
 *   line_len[L]    = current char count on original line L
 *   join_offset[L] = col offset for content joined from line L
 *                    (the length of the absorbing line at join time)
 *
 * For each op:
 *   1. Look up current buffer line: buf_line = line_map[orig_line]
 *   2. Compute current col: buf_col = orig_col + join_offset[orig_line]
 *   3. Assign (buf_line, buf_col)
 *   4. Update state based on op type
 *
 * Key insight: if content ops on a line are processed BEFORE the \n
 * delete that joins it, the join_offset is 0 (line is empty at join
 * time). If content ops are processed AFTER the join, the join_offset
 * is the absorbing line's length at join time.
 */
static void recompute_positions_v3(Op *out, int n_out, int max_line) {
    if (n_out <= 0 || max_line <= 0) return;

    /* Allocate state arrays (1-indexed, +2 for safety) */
    int sz = max_line + 2;
    int *line_map    = (int *)calloc(sz, sizeof(int));
    int *line_len    = (int *)calloc(sz, sizeof(int));
    int *join_offset = (int *)calloc(sz, sizeof(int));
    if (!line_map || !line_len || !join_offset) {
        free(line_map); free(line_len); free(join_offset);
        return;
    }

    /* Initialize: line L is at buffer line L, length 0 */
    for (int i = 1; i < sz; i++) {
        line_map[i] = i;
        line_len[i] = 0;
        join_offset[i] = 0;
    }

    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;

        int orig_line = out[i].line;
        int orig_col  = out[i].col;
        int code      = out[i].code;
        int is_newline = (code == AD_LAYER_CHAR_NEWLINE);

        /* Clamp orig_line to valid range */
        if (orig_line < 1) orig_line = 1;
        if (orig_line >= sz) orig_line = sz - 1;

        /* Look up current buffer line and col */
        int buf_line = line_map[orig_line];
        int buf_col  = orig_col + join_offset[orig_line];

        /* Assign new position */
        out[i].line = buf_line;
        out[i].col  = buf_col;

        /* Update state based on op type */
        if (strcmp(out[i].type, "keep") == 0) {
            if (!is_newline) {
                /* keep char: line grows (char is still in buffer) */
                line_len[orig_line]++;
            }
            /* keep \n: no state change (cursor moves, buffer unchanged) */
        } else if (strcmp(out[i].type, "delete") == 0) {
            if (is_newline) {
                /* delete \n: join orig_line with orig_line+1 */
                int next = orig_line + 1;
                if (next < sz) {
                    /* Content from next line starts after current line's length */
                    join_offset[next] = line_len[orig_line];
                    /* Merge lengths */
                    line_len[orig_line] += line_len[next];
                    /* next line now maps to orig_line's buffer line */
                    line_map[next] = line_map[orig_line];
                    /* Shift all lines > next down by 1 */
                    for (int j = next + 1; j < sz; j++) {
                        if (line_map[j] > line_map[orig_line]) {
                            line_map[j]--;
                        }
                    }
                }
            } else {
                /* delete char: line shrinks */
                line_len[orig_line]--;
                if (line_len[orig_line] < 0) line_len[orig_line] = 0;
            }
        } else if (strcmp(out[i].type, "insert") == 0
                   || strcmp(out[i].type, "overwrite_insert") == 0) {
            if (is_newline) {
                /* insert \n: split orig_line at orig_col */
                /* Content from orig_col onwards moves to a new line */
                int new_line = orig_line + 1;
                if (new_line < sz) {
                    /* New line gets content from orig_col onwards */
                    int remaining = line_len[orig_line] - (orig_col - 1);
                    if (remaining < 0) remaining = 0;
                    /* Shift all lines > orig_line up by 1 */
                    for (int j = sz - 1; j > new_line; j--) {
                        line_map[j] = line_map[j-1];
                        line_len[j] = line_len[j-1];
                        join_offset[j] = join_offset[j-1];
                    }
                    /* New line starts with the remaining content */
                    line_map[new_line] = line_map[orig_line] + 1;
                    line_len[new_line] = remaining;
                    join_offset[new_line] = 0;
                    /* Original line keeps content before orig_col */
                    line_len[orig_line] = orig_col - 1;
                    if (line_len[orig_line] < 0) line_len[orig_line] = 0;
                }
            } else {
                /* insert char: line grows */
                line_len[orig_line]++;
            }
        }
    }

    free(line_map);
    free(line_len);
    free(join_offset);
}

/* ── LDI transform (same as v1) ──────────────────────────────────── */
static int layer_line_delete_in_place_v3(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;

    Op *work = (Op *)malloc(n_ops * sizeof(Op));
    if (!work && n_ops > 0) { fprintf(stderr, "out of memory\n"); return 0; }
    if (n_ops > 0) memcpy(work, ops, n_ops * sizeof(Op));
    int n_work = n_ops;

    int n_out = 0;
    int i = 0;

    while (i < n_work) {
        /* Pattern: delete(\n), delete(content)..., delete(\n) */
        if (i + 2 < n_work
            && strcmp(work[i].type, "delete") == 0
            && work[i].code == AD_LAYER_CHAR_NEWLINE) {

            if (strcmp(work[i+1].type, "delete") == 0
                && work[i+1].code != AD_LAYER_CHAR_NEWLINE) {

                int ce = i + 1;
                while (ce < n_work
                       && strcmp(work[ce].type, "delete") == 0
                       && work[ce].code != AD_LAYER_CHAR_NEWLINE)
                    ce++;

                if (ce < n_work
                    && strcmp(work[ce].type, "delete") == 0
                    && work[ce].code == AD_LAYER_CHAR_NEWLINE) {

                    int content_count = ce - (i + 1);

                    /* Emit content deletes (keep original positions) */
                    for (int k = i + 1; k < ce && n_out < out_cap; k++)
                        out[n_out++] = work[k];
                    /* Emit content's \n */
                    if (n_out < out_cap)
                        out[n_out++] = work[ce];

                    /* Shift: remove emitted ops from work[] */
                    int removed = content_count + 1;
                    int src = ce + 1;
                    int dst = i + 1;
                    int to_move = n_work - src;
                    if (to_move > 0)
                        memmove(&work[dst], &work[src], to_move * sizeof(Op));
                    n_work -= removed;

                    continue;
                }
            }
        }

        /* No match — emit op[i] unchanged */
        if (n_out < out_cap)
            out[n_out++] = work[i];
        i++;
    }

    free(work);

    /* Find max line number for state arrays */
    int max_line = 0;
    for (int i = 0; i < n_out; i++) {
        if (out[i].line > max_line) max_line = out[i].line;
    }

    /* Use buffer-simulation position walk */
    recompute_positions_v3(out, n_out, max_line);

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place_v3);
}
