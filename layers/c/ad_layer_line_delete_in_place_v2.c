/* ad_layer_line_delete_in_place_v2.c — Clone using shared position-walk.
 *
 * Same algorithm as ad_layer_line_delete_in_place.c, but uses
 * ad_layer_recompute_positions() instead of the broken decrement heuristic.
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static int layer_line_delete_in_place_v2(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
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

                    /* Shift: remove emitted ops from work[].
                     * op[i] (joiner \n) stays. */
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

    /* Use shared position-walk to fix all positions */
    ad_layer_recompute_positions(out, n_out);
    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place_v2);
}
