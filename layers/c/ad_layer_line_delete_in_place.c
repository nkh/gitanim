/* ad_layer_line_delete_in_place.c — delete lines on their own line.
 *
 * When a \n delete joins two lines and the next line is fully deleted,
 * reorder so content is deleted FIRST (on its own line), then the \n
 * delete joins. Prevents "join then delete" visual.
 *
 * Pattern matched:
 *   delete \n (line N)      delete content (line N+1)
 *   delete content (line N+1)  →  delete \n (line N+1)
 *   delete \n (line N+1)      delete \n (line N)
 */
#include "ad_layer_common.h"

/* layer_line_delete_in_place: When a \n delete joins two lines and the
 * next line is being fully deleted (content deletes + \n delete on
 * line N+1), reorder so that the content of line N+1 is deleted FIRST
 * (on its own line), then the \n delete joining N→N+1 happens. This
 * prevents the awkward visual of "join, then delete the joined content".
 *
 * Pattern matched (and rewritten):
 *   delete \n (line N)        delete content (line N+1)
 *   delete content (line N+1) →  delete \n (line N+1)
 *   delete \n (line N+1)        delete \n (line N)
 *
 * Inputs:  ops[0..n_ops-1]   — ops for one hunk (positions already set).
 * Outputs: out[0..out_cap-1] — reordered ops (positions are NOT re-walked;
 *                              callers should not need to re-track).
 *          *line_offset       — not modified.
 * Returns: number of output ops written. */
static int layer_line_delete_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Check for pattern: \n delete + content deletes + \n delete */
        if (i + 2 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && ops[i].code == AD_LAYER_CHAR_NEWLINE
            && strcmp(ops[i+1].type, "delete") == 0 && ops[i+1].code != AD_LAYER_CHAR_NEWLINE
            && ops[i+1].line == ops[i].line + 1) {

            int dl = ops[i].line + 1;
            int cs = i + 1;   /* content start */
            int ce = cs;       /* content end */

            /* Collect consecutive content deletes on line N+1. */
            while (ce < n_ops
                   && strcmp(ops[ce].type, "delete") == 0
                   && ops[ce].code != AD_LAYER_CHAR_NEWLINE
                   && ops[ce].line == dl)
                ce++;

            /* Check if followed by \n delete on line N+1. */
            if (ce < n_ops
                && strcmp(ops[ce].type, "delete") == 0
                && ops[ce].code == AD_LAYER_CHAR_NEWLINE
                && ops[ce].line == dl) {
                /* Pattern matched: emit content first, then \n on N+1, then \n on N. */
                for (int k = cs; k < ce && n_out < out_cap; k++)
                    out[n_out++] = ops[k];
                if (n_out < out_cap) out[n_out++] = ops[ce];   /* \n on N+1 */
                if (n_out < out_cap) out[n_out++] = ops[i];    /* \n on N (join) */
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
