/* ad_layer_line_delete_in_place_v6.c — LDI with buffer simulation.
 *
 * KEY INSIGHT: The layer can compute initial line lengths from the ops
 * (max col per line), then simulate the buffer as ops are applied.
 * For each op, compute the correct (line, col) based on current buffer
 * state.
 *
 * This is the fix that belongs in the LAYER, not the animator.
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

/* Simulate the buffer to recompute positions.
 *
 * 1. Compute initial line lengths from ops (max col per line,
 *    including \n as +1 to the line's length).
 * 2. Track line_map[L] = current buffer line of original line L.
 * 3. Track line_len[buf_line] = current char count on that buffer line.
 * 4. For each op, compute (buf_line, buf_col) from the simulation.
 * 5. Update simulation state after each op.
 */
static void recompute_positions_v6(Op *out, int n_out) {
    if (n_out <= 0) return;

    /* Find max line number */
    int max_line = 0;
    for (int i = 0; i < n_out; i++) {
        if (out[i].line > max_line) max_line = out[i].line;
    }
    if (max_line <= 0) return;

    int sz = max_line + 2;

    /* Compute initial line lengths from ops.
     * For each original line L, the initial length = max col seen
     * for that line across all ops. If a \n op exists at (L, C),
     * the line length is C (the \n is at col C, so the line has
     * C chars including the \n). Otherwise, it's the max col of
     * non-\n ops on that line.
     *
     * Actually, simpler: the initial length of line L is the max col
     * of any op on line L (including \n ops). Because col is 1-indexed
     * and represents the position of the char, the max col = number
     * of chars on that line.
     *
     * But wait — \n is at the END of the line. If we have:
     *   keep A(1,1)  delete \n(1,2)
     * Then line 1 has 2 chars: A and \n. Max col = 2. Correct.
     *
     * If we have:
     *   delete B(2,1)  delete \n(2,1)
     * Then line 2 has 1 char: B (at col 1), and \n (also at col 1?).
     *
     * Hmm, the \n is at col 1 too. That means max col = 1, but the
     * line actually has 2 chars (B and \n). This is wrong.
     *
     * The issue: after deleting B, the \n is still at col 1 (the
     * cursor doesn't move on delete). But the \n's ORIGINAL col was
     * 2 (after B). Compute puts it at col 1 because after B is deleted,
     * the \n shifts to col 1.
     *
     * So the ops' cols reflect the state AFTER prior ops on the same
     * line have been applied, not the initial state.
     *
     * To get initial lengths, we need to count keeps + non-\n deletes
     * + non-\n inserts + (1 if there's a \n keep/delete) per line.
     * That gives us the initial char count.
     */

    /* Count initial chars per line */
    int *init_len = (int *)calloc(sz, sizeof(int));
    int *has_nl = (int *)calloc(sz, sizeof(int));  /* line has a \n op */
    if (!init_len || !has_nl) { free(init_len); free(has_nl); return; }

    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;
        int L = out[i].line;
        if (L < 1 || L >= sz) continue;

        if (out[i].code == AD_LAYER_CHAR_NEWLINE) {
            has_nl[L] = 1;
        } else {
            /* Non-\n char: counts toward initial length */
            if (strcmp(out[i].type, "keep") == 0
                || strcmp(out[i].type, "delete") == 0) {
                init_len[L]++;
            }
            /* Inserts don't count toward INITIAL length */
        }
    }
    /* Add \n to length if present */
    for (int i = 1; i < sz; i++) {
        if (has_nl[i]) init_len[i]++;
    }

    /* Initialize simulation state */
    int *line_map = (int *)calloc(sz, sizeof(int));
    int *line_len = (int *)calloc(sz, sizeof(int));  /* indexed by BUFFER line */
    int *join_col = (int *)calloc(sz, sizeof(int));  /* indexed by original line */
    if (!line_map || !line_len || !join_col) {
        free(init_len); free(has_nl); free(line_map); free(line_len); free(join_col);
        return;
    }

    for (int i = 1; i < sz; i++) {
        line_map[i] = i;       /* original line L → buffer line L */
        line_len[i] = init_len[i];  /* current length = initial length */
        join_col[i] = 0;       /* no join offset yet */
    }

    /* Process ops, computing new positions */
    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;

        int orig_line = out[i].line;
        int orig_col = out[i].col;
        int code = out[i].code;
        int is_newline = (code == AD_LAYER_CHAR_NEWLINE);

        if (orig_line < 1) orig_line = 1;
        if (orig_line >= sz) orig_line = sz - 1;

        /* Current buffer line for this original line */
        int buf_line = line_map[orig_line];

        /* Current col = original col + join offset for this line */
        int buf_col = orig_col + join_col[orig_line];

        /* Assign new position */
        out[i].line = buf_line;
        out[i].col = buf_col;

        /* Update simulation state — ALWAYS index line_len by buf_line */
        if (strcmp(out[i].type, "keep") == 0) {
            /* keep: no length change */
        } else if (strcmp(out[i].type, "delete") == 0) {
            if (is_newline) {
                /* \n delete: join orig_line with orig_line+1 */
                int next = orig_line + 1;
                if (next < sz) {
                    int join_point = line_len[buf_line] - 1;
                    if (join_point < 0) join_point = 0;

                    /* Update col_offset for ALL lines already joined
                     * into 'next' — they need the additional offset. */
                    int next_buf = line_map[next];
                    for (int j = 1; j < sz; j++) {
                        if (line_map[j] == next_buf && j != orig_line) {
                            join_col[j] += join_point;
                        }
                    }
                    join_col[next] += join_point;

                    /* Merge lengths on the BUFFER line */
                    line_len[buf_line] = join_point + line_len[next_buf];
                    /* next line now maps to current line's buffer line */
                    line_map[next] = buf_line;
                    /* Shift lines > next down by 1 */
                    for (int j = next + 1; j < sz; j++) {
                        if (line_map[j] > buf_line) {
                            line_map[j]--;
                        }
                    }
                }
            } else {
                /* delete char: line shrinks (on the BUFFER line) */
                line_len[buf_line]--;
                if (line_len[buf_line] < 0) line_len[buf_line] = 0;
            }
        } else if (strcmp(out[i].type, "insert") == 0
                   || strcmp(out[i].type, "overwrite_insert") == 0) {
            if (is_newline) {
                /* \n insert: split at current col */
                int new_buf = buf_line + 1;
                if (new_buf < sz) {
                    int remaining = line_len[buf_line] - buf_col;
                    if (remaining < 0) remaining = 0;
                    /* Shift buffer lines up */
                    for (int j = sz - 1; j > new_buf; j--) {
                        line_len[j] = line_len[j-1];
                    }
                    /* Shift original line mappings */
                    for (int j = 1; j < sz; j++) {
                        if (line_map[j] >= new_buf) line_map[j]++;
                    }
                    line_len[new_buf] = remaining;
                    line_len[buf_line] = buf_col;
                    if (line_len[buf_line] < 0) line_len[buf_line] = 0;
                }
            } else {
                /* insert char: line grows (on the BUFFER line) */
                line_len[buf_line]++;
            }
        }
    }

    free(init_len); free(has_nl);
    free(line_map); free(line_len); free(join_col);
}

/* LDI transform (same as v5 — just reorder, then recompute) */
static int layer_line_delete_in_place_v6(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
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

                    /* Emit content deletes (original positions) */
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

    /* Recompute positions using buffer simulation */
    recompute_positions_v6(out, n_out);

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place_v6);
}
