/* ad_layer_line_delete_in_place.c — Delete content BEFORE joining lines.
 *
 * When the diff engine deletes multiple consecutive lines, it produces:
 *
 *   delete(line1 chars)  → join_lines → delete(line2 chars) → join_lines → ...
 *
 * The join_lines pulls line2's content UP to line1 before it's deleted.
 * Visually, the user sees content jumping up before disappearing.
 *
 * This layer detects: join_lines(L) + delete(content at L) + join_lines(L)
 * and reorders to: delete(content at L+1) + join_lines(L+1)
 * The first join_lines(L) stays in place for re-iteration.
 *
 * After the reorder, content is deleted in place (at its own line number)
 * before the join removes the now-empty line.
 *
 * Build: make layers
 * Usage:  ad_postprocess --ad-layer=ad_layer_line_delete_in_place < ops.tsv
 */
#include "ad_layer_common.h"

static int layer_line_delete_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;

    Op *work = (Op *)malloc(n_ops * sizeof(Op));
    if (!work && n_ops > 0) { fprintf(stderr, "out of memory\n"); return 0; }
    if (n_ops > 0) memcpy(work, ops, n_ops * sizeof(Op));
    int n_work = n_ops;

    int n_out = 0;
    int i = 0;

    while (i < n_work) {
        /* Pattern: join_lines(L) + delete(content) + join_lines(L)
         *
         * The content between two join_lines belongs to the line that
         * was joined IN (line L+1). Moving it to line L+1 and placing
         * it BEFORE the join means the content is deleted in place. */

        if (i + 2 < n_work
            && strcmp(work[i].type, "join_lines") == 0) {

            /* Scan forward for content deletes (all type="delete", not line ops) */
            int ce = i + 1;
            while (ce < n_work
                   && strcmp(work[ce].type, "delete") == 0
                   && !ad_layer_is_line_op(&work[ce]))
                ce++;

            /* Check: is there a trailing join_lines? */
            if (ce > i + 1  /* at least one content delete */
                && ce < n_work
                && strcmp(work[ce].type, "join_lines") == 0) {

                /* Only reorder if the content deletes start at col 1.
                 * Col 1 means a full line deletion (starting from the
                 * beginning of the line). Deletes at col > 1 are partial
                 * content from the middle of a joined line — moving
                 * them would corrupt positions. */
                int content_col = work[i + 1].col;
                if (content_col != 1) {
                    /* Partial content — don't reorder, emit as-is */
                    if (n_out < out_cap)
                        out[n_out++] = work[i];
                    i++;
                    continue;
                }

                int joiner_line = work[i].line;

                /* Emit content deletes at line+1 (before the join,
                 * the content is on its own line) */
                for (int k = i + 1; k < ce && n_out < out_cap; k++) {
                    Op tmp = work[k];
                    tmp.line = joiner_line + 1;
                    out[n_out++] = tmp;
                }
                /* Emit the second join_lines at line+1 */
                if (n_out < out_cap) {
                    Op tmp = work[ce];
                    tmp.line = joiner_line + 1;
                    out[n_out++] = tmp;
                }

                /* Remove content + second join_lines from work[].
                 * Keep the first join_lines at position i for re-iteration. */
                int removed = (ce - (i + 1)) + 1;  /* content + 2nd join */
                int src = ce + 1;
                int dst = i + 1;
                int to_move = n_work - src;
                if (to_move > 0)
                    memmove(&work[dst], &work[src], to_move * sizeof(Op));
                n_work -= removed;

                /* DON'T advance i — re-iterate at the joiner.
                 * It may match another pattern (cascading joins). */
                continue;
            }
        }

        /* No match — emit op unchanged */
        if (n_out < out_cap)
            out[n_out++] = work[i];
        i++;
    }

    free(work);
    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_line_delete_in_place);
}
