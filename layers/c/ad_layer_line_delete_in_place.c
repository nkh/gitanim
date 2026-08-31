/* ad_layer_line_delete_in_place.c — delete lines on their own line.
 *
 * When a \n delete joins two lines and the next line is fully deleted,
 * reorder so content is deleted FIRST (on its own line), then the \n
 * delete joins. Prevents "join then delete" visual.
 *
 * Pattern matched (regardless of line numbers — positions may have been
 * recomputed by ad_layer_reorder):
 *   delete \n        →   delete content
 *   delete content   →   delete \n (the content's own \n)
 *   delete \n        →   delete \n (the joiner)
 *
 * The layer detects: a \n delete followed by non-\n deletes followed by
 * another \n delete. It reorders so the content deletes come first,
 * then the content's \n delete, then the joining \n delete.
 */
#include "ad_layer_common.h"

/* layer_line_delete_in_place: Reorder delete sequences so that when
 * a line is being fully deleted (via \n join + content delete + \n delete),
 * the content is deleted first on its own line, then the \n that joins
 * the lines is deleted last.
 *
 * Pattern (by op CODE, not line number — positions may have been
 * recomputed by a previous layer):
 *   delete(code=10)    ← \n delete (joiner)
 *   delete(code!=10)   ← content delete(s)
 *   ...
 *   delete(code!=10)   ← more content
 *   delete(code=10)    ← \n delete (content's own newline)
 *
 * Rewritten as:
 *   delete(content)    ← content deletes first
 *   ...
 *   delete(content)
 *   delete(\n)         ← content's \n
 *   delete(\n)         ← joiner \n last
 *
 * Inputs:  ops[0..n_ops-1] — ops for one hunk.
 * Outputs: out[0..out_cap-1] — reordered ops.
 * Returns: number of output ops. */
static int layer_line_delete_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Check for pattern: \n delete, then content delete(s), then \n delete.
         * We match purely by code, not by line number, because a previous
         * layer (reorder) may have recomputed positions. */
        if (i + 2 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && ops[i].code == AD_LAYER_CHAR_NEWLINE
            && strcmp(ops[i+1].type, "delete") == 0 && ops[i+1].code != AD_LAYER_CHAR_NEWLINE) {

            /* Collect consecutive non-\n deletes after the first \n delete. */
            int cs = i + 1;   /* content start */
            int ce = cs;       /* content end (exclusive) */

            while (ce < n_ops
                   && strcmp(ops[ce].type, "delete") == 0
                   && ops[ce].code != AD_LAYER_CHAR_NEWLINE)
                ce++;

            /* Check if followed by another \n delete. */
            if (ce < n_ops
                && strcmp(ops[ce].type, "delete") == 0
                && ops[ce].code == AD_LAYER_CHAR_NEWLINE) {
                /* Pattern matched: emit content first, then content's \n,
                 * then the joining \n. */
                for (int k = cs; k < ce && n_out < out_cap; k++)
                    out[n_out++] = ops[k];
                if (n_out < out_cap) out[n_out++] = ops[ce];   /* \n (content's own) */
                if (n_out < out_cap) out[n_out++] = ops[i];     /* \n (joiner) */
                i = ce + 1;
                continue;
            }
        }
        if (n_out < out_cap) out[n_out++] = ops[i];
        i++;
    }

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place);
}
