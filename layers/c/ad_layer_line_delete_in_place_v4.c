/* ad_layer_line_delete_in_place_v4.c — Clone using line-only adjustment.
 *
 * Same LDI algorithm, but position recompute ONLY adjusts line numbers
 * based on \n deletes/inserts. Columns are left untouched — the
 * animator's clamping (col > line_length → clamp to end) handles
 * column correctness.
 *
 * Line adjustment rule:
 *   For each op at (orig_line, orig_col):
 *     count \n deletes at lines < orig_line processed so far → shift_down
 *     count \n inserts at lines < orig_line processed so far → shift_up
 *     new_line = orig_line - shift_down + shift_up
 *     new_col = orig_col (unchanged)
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static void recompute_positions_v4(Op *out, int n_out) {
    if (n_out <= 0) return;

    /* Save original lines (we modify in place) */
    int *orig_lines = (int *)malloc(n_out * sizeof(int));
    if (!orig_lines) return;
    for (int i = 0; i < n_out; i++)
        orig_lines[i] = out[i].line;

    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;

        int my_orig_line = orig_lines[i];
        int shift = 0;

        /* Count \n deletes/inserts at lines < my_orig_line, processed before this op */
        for (int j = 0; j < i; j++) {
            int is_nl_delete = (strcmp(out[j].type, "delete") == 0
                                && out[j].code == AD_LAYER_CHAR_NEWLINE);
            int is_nl_insert = ((strcmp(out[j].type, "insert") == 0
                                 || strcmp(out[j].type, "overwrite_insert") == 0)
                                && out[j].code == AD_LAYER_CHAR_NEWLINE);

            if (orig_lines[j] < my_orig_line) {
                if (is_nl_delete) shift--;
                if (is_nl_insert) shift++;
            }
        }

        out[i].line = my_orig_line + shift;
        /* Don't touch col — animator clamping handles it */
    }

    free(orig_lines);
}

static int layer_line_delete_in_place_v4(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
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

    /* Use line-only position adjustment */
    recompute_positions_v4(out, n_out);

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place_v4);
}
