/* ad_layer_indent_last.c — move leading whitespace deletes to end of line.
 *
 * For each line segment, if it starts with whitespace deletes (space OR
 * tab), move them to AFTER the content deletes. The trailing \n char op
 * (if any) is moved to the very end (after the indent deletes) so the
 * join doesn't pull the next line up at the now-deleted indentation
 * level. Content op cols are bumped by +n_indent (the indent is still
 * in the buffer when the content runs first). Indent deletes are placed
 * at col 1.
 *
 * Output order per segment: content (col +n_indent) → indent (col 1)
 * → \n op (original position). This is "Option C-correct" per
 * docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md §4.3 (Phase 2 fix).
 */
#include "ad_layer_common.h"

/* layer_indent_last: For each line segment, if it begins with a run of
 * leading-whitespace deletes (spaces/tabs), moves them to AFTER the
 * content deletes. The content deletes are still in the buffer when
 * they run, so their col is bumped by +n_indent; the indent deletes
 * are then re-emitted at col 1. A trailing \n char op (if present) is
 * moved to the very end of the segment (after the indent deletes) so
 * the join doesn't pull the next line up at the now-deleted indent
 * level.
 *
 * Rationale: deleting indent before content makes the line shift left
 * before its content disappears, which looks visually wrong. Deleting
 * content first, then indent, then the \n gives a cleaner
 * shrink-to-empty-then-join effect — and crucially, applying the \n
 * delete LAST means the next line is not pulled up at the (now-deleted)
 * indentation level, which would otherwise cause it to appear
 * incorrectly indented during the animation.
 *
 * Inputs:  ops[0..n_ops-1]   — ops for one hunk (positions already set).
 * Outputs: out[0..out_cap-1] — reordered ops (no position re-walk;
 *                              only content cols are bumped).
 *          *line_offset       — not modified.
 * Returns: number of output ops written. */
static int layer_indent_last(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0, seg_start = 0;

    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (!is_boundary && i > seg_start) {
            if (ad_layer_is_line_op(&ops[i]) && !ad_layer_is_debug_op(&ops[i]))
                is_boundary = 1;
            if (!is_boundary && !ad_layer_is_debug_op(&ops[i]) && !ad_layer_is_debug_op(&ops[i-1]))
                if (ops[i].line != ops[i-1].line)
                    is_boundary = 1;
        }

        if (is_boundary) {
            int seg_len = i - seg_start;
            if (seg_len > 0 && n_out < out_cap) {
                /* Find leading run of indent deletes (space/tab). */
                int indent_end = seg_start;
                for (int j = seg_start; j < i; j++) {
                    if (ad_layer_is_debug_op(&ops[j])) continue;
                    if (strcmp(ops[j].type, "delete") == 0 &&
                        (ops[j].code == AD_LAYER_CHAR_SPACE || ops[j].code == AD_LAYER_CHAR_TAB))
                        indent_end = j + 1;
                    else break;
                }
                int n_indent = indent_end - seg_start;

                if (n_indent == 0) {
                    /* No indent deletes — pass segment through. */
                    for (int j = seg_start; j < i && n_out < out_cap; j++)
                        out[n_out++] = ops[j];
                } else {
                    /* Find the trailing \n char op (code == 10) at the tail
                     * of the segment. We match on code, not on op type,
                     * because a `delete \n` op has type "delete" (not a
                     * line_op type like "delete_line") — ad_layer_is_line_op
                     * would miss it. The \n op must be moved to AFTER the
                     * indent deletes, otherwise the next line would inherit
                     * the deleted indentation when the \n delete is applied
                     * before the indent deletes (the \n join pulls the next
                     * line up at the current cursor's indentation level). */
                    int nl = -1;
                    for (int j = i - 1; j >= indent_end; j--) {
                        if (!ad_layer_is_debug_op(&ops[j])
                            && ops[j].code == AD_LAYER_CHAR_NEWLINE) {
                            nl = j; break;
                        }
                    }
                    int content_end = (nl >= 0) ? nl : i;

                    /* Content ops: bump col by +n_indent. */
                    for (int j = indent_end; j < content_end && n_out < out_cap; j++) {
                        out[n_out] = ops[j];
                        out[n_out].col = ops[j].col + n_indent;
                        n_out++;
                    }
                    /* Indent deletes: keep at col 1. */
                    for (int j = seg_start; j < indent_end && n_out < out_cap; j++) {
                        out[n_out] = ops[j];
                        out[n_out].col = 1;
                        n_out++;
                    }
                    /* \n op: emit LAST, keep as-is. The \n delete joins
                     * the line with the next; doing it after the indent
                     * deletes ensures the next line is not pulled up at
                     * the (now-deleted) indentation level. */
                    if (nl >= 0 && n_out < out_cap)
                        out[n_out++] = ops[nl];
                }
            }
            seg_start = i;
        }
    }

    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_indent_last);
}
