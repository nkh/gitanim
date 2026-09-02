/* ad_layer_line_delete_in_place_v7.c — LDI with line/col remapping.
 *
 * NO buffer simulation. Just track which buffer line each original line
 * maps to, and what col offset to apply. All information comes from
 * the ops' (line, col) values.
 *
 * Algorithm:
 *   buf_line[L]   = current buffer line of original line L
 *   col_shift[L]  = col offset for original line L
 *
 *   for each op (orig_line, orig_col):
 *     new_line = buf_line[orig_line]
 *     new_col  = orig_col + col_shift[orig_line]
 *
 *     if delete \n(orig_line, orig_col):
 *       join_point = orig_col + col_shift[orig_line]
 *       target_buf = buf_line[orig_line]
 *       absorbed_buf = buf_line[orig_line + 1]
 *       for each line J where buf_line[J] == absorbed_buf:
 *         buf_line[J] = target_buf
 *         col_shift[J] += (join_point - 1)
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static void recompute_positions_v7(Op *out, int n_out) {
    if (n_out <= 0) return;

    int max_line = 0;
    for (int i = 0; i < n_out; i++)
        if (out[i].line > max_line) max_line = out[i].line;
    if (max_line <= 0) return;

    int sz = max_line + 2;
    int *buf_line  = (int *)malloc(sz * sizeof(int));
    int *col_shift = (int *)calloc(sz, sizeof(int));
    if (!buf_line || !col_shift) { free(buf_line); free(col_shift); return; }

    for (int i = 0; i < sz; i++) buf_line[i] = i;

    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;

        int orig_line = out[i].line;
        int orig_col  = out[i].col;
        if (orig_line < 1) orig_line = 1;
        if (orig_line >= sz) orig_line = sz - 1;

        /* Compute new position */
        out[i].line = buf_line[orig_line];
        out[i].col  = orig_col + col_shift[orig_line];

        /* Update state on \n delete (join) */
        if (strcmp(out[i].type, "delete") == 0
            && out[i].code == AD_LAYER_CHAR_NEWLINE) {
            int join_point = orig_col + col_shift[orig_line];
            int target_buf = buf_line[orig_line];
            int next = orig_line + 1;
            if (next < sz) {
                int absorbed_buf = buf_line[next];
                for (int j = 1; j < sz; j++) {
                    if (buf_line[j] == absorbed_buf) {
                        buf_line[j] = target_buf;
                        col_shift[j] += (join_point - 1);
                    }
                }
            }
        }

        /* \n inserts: NO remapping needed. The animator handles \n inserts
         * via set_cursor which respects the op's position. After a split,
         * subsequent ops have correct positions because compute already
         * accounts for the new line. */
    }

    free(buf_line);
    free(col_shift);
}

/* LDI transform — same reordering as v5 */
static int layer_line_delete_in_place_v7(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    Op *work = (Op *)malloc(n_ops * sizeof(Op));
    if (!work && n_ops > 0) { fprintf(stderr, "out of memory\n"); return 0; }
    if (n_ops > 0) memcpy(work, ops, n_ops * sizeof(Op));
    int n_work = n_ops;
    int n_out = 0;
    int i = 0;

    while (i < n_work) {
        if (i + 2 < n_work
            && strcmp(work[i].type, "delete") == 0
            && work[i].code == AD_LAYER_CHAR_NEWLINE
            && strcmp(work[i+1].type, "delete") == 0
            && work[i+1].code != AD_LAYER_CHAR_NEWLINE) {

            int ce = i + 1;
            while (ce < n_work
                   && strcmp(work[ce].type, "delete") == 0
                   && work[ce].code != AD_LAYER_CHAR_NEWLINE) ce++;

            if (ce < n_work
                && strcmp(work[ce].type, "delete") == 0
                && work[ce].code == AD_LAYER_CHAR_NEWLINE) {

                int content_count = ce - (i + 1);
                for (int k = i + 1; k < ce && n_out < out_cap; k++)
                    out[n_out++] = work[k];
                if (n_out < out_cap) out[n_out++] = work[ce];

                int removed = content_count + 1;
                int src = ce + 1, dst = i + 1;
                int to_move = n_work - src;
                if (to_move > 0) memmove(&work[dst], &work[src], to_move * sizeof(Op));
                n_work -= removed;
                continue;
            }
        }
        if (n_out < out_cap) out[n_out++] = work[i];
        i++;
    }

    free(work);
    recompute_positions_v7(out, n_out);
    return n_out;
}

int main(void) { return ad_layer_run(layer_line_delete_in_place_v7); }
