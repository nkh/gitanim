/* ad_layer_line_delete_in_place.c — reorder ops so lines are created
 * before content fills them, and content is deleted before lines are
 * joined.
 *
 * Two patterns are handled:
 *
 * 1. DELETE pattern (join then delete → delete in place):
 *
 *    delete(\n)            ← joiner \n (joins two lines)
 *    delete(content)...    ← content on the joined line
 *    delete(\n)            ← content's own \n
 *    →
 *    delete(content)...    ← content deleted first (on its own line)
 *    delete(\n)            ← content's \n (removes empty line)
 *    [joiner \n stays, re-iterate]
 *    [decrement line of later ops by 1]
 *
 * 2. INSERT pattern (content typed on existing line → line created first):
 *
 *    insert(content)...    ← new content typed on existing line
 *    insert(\n)            ← \n that creates the new line
 *    →
 *    insert(\n)            ← \n FIRST (creates empty line, pushes old content down)
 *    insert(content)...    ← content fills the new empty line
 *    [drop the \n at end — already created by the front \n]
 *
 * Both patterns work purely by op code, not by line number. This makes
 * the layer work on any input (raw compute, post-reorder, etc.).
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

        /* ── Pattern 1: DELETE (joiner \n, content, content's \n) ── */
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

                    /* Emit content deletes. Their positions were recomputed
                     * by reorder to be on the JOINED line (same as joiner).
                     * But we're moving them BEFORE the joiner \n, so at
                     * execution time the join hasn't happened — the content
                     * is still on the NEXT line. Increment line by 1. */
                    for (int k = i + 1; k < ce && n_out < out_cap; k++) {
                        Op tmp = work[k];
                        tmp.line = work[i].line + 1;  /* content is on line after joiner */
                        out[n_out++] = tmp;
                    }
                    /* Emit content's \n (also on the next line) */
                    if (n_out < out_cap) {
                        Op tmp = work[ce];
                        tmp.line = work[i].line + 1;
                        out[n_out++] = tmp;
                    }

                    for (int k = ce + 1; k < n_work; k++)
                        work[k].line--;

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

        /* ── Pattern 2: INSERT (content..., then \n) ──
         * Move the \n INSERT to the FRONT so the new line is created
         * before content fills it. Drop the \n at the end (already
         * created by the front \n). */
        if (i + 1 < n_work
            && (strcmp(work[i].type, "insert") == 0
                || strcmp(work[i].type, "overwrite_insert") == 0)
            && work[i].code != AD_LAYER_CHAR_NEWLINE) {

            /* Collect content inserts on the same line */
            int ce = i;
            int line = work[i].line;
            while (ce < n_work
                   && (strcmp(work[ce].type, "insert") == 0
                       || strcmp(work[ce].type, "overwrite_insert") == 0)
                   && work[ce].code != AD_LAYER_CHAR_NEWLINE
                   && work[ce].line == line)
                ce++;

            /* Check: op[ce] is INSERT \n on the same line */
            if (ce < n_work
                && (strcmp(work[ce].type, "insert") == 0
                    || strcmp(work[ce].type, "overwrite_insert") == 0)
                && work[ce].code == AD_LAYER_CHAR_NEWLINE
                && work[ce].line == line) {

                /* Pattern matched: move \n to front, drop \n at end */
                Op nl_op = work[ce];
                nl_op.col = work[i].col;  /* \n goes at the start col */
                if (n_out < out_cap)
                    out[n_out++] = nl_op;

                /* Emit content inserts (same positions) */
                for (int k = i; k < ce && n_out < out_cap; k++)
                    out[n_out++] = work[k];

                /* Skip the \n insert at ce (already emitted at front) */
                i = ce + 1;
                continue;
            }
        }

        /* No match — emit op[i] unchanged.
         * If this is a \n delete, the animator will join two lines
         * (buffer loses a line) → decrement later ops by 1, but ONLY
         * for ops that are BELOW this \n's line (ops on the same line
         * or above are not affected by the join). */
        if (n_out < out_cap)
            out[n_out++] = work[i];
        if (strcmp(work[i].type, "delete") == 0
            && work[i].code == AD_LAYER_CHAR_NEWLINE) {
            int join_line = work[i].line;
            for (int k = i + 1; k < n_work; k++)
                if (work[k].line > join_line)
                    work[k].line--;
        }
        i++;
    }

    free(work);
    return n_out;
}

int main(void) {
    return ad_layer_run(layer_line_delete_in_place);
}
