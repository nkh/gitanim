/* ad_layer_indent_last.c — move leading whitespace deletes to end of line.
 *
 * For each line segment, if it starts with whitespace deletes, move them
 * AFTER the content deletes. Adjust content ops' col by +n_indent (the
 * indent is still in the buffer when content runs first). Indent deletes
 * are placed at col 1.
 */
#include "ad_layer_common.h"

static int layer_indent_last(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0, seg_start = 0;

    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (!is_boundary && i > seg_start) {
            if (ops[i].code == 10 && !ad_layer_is_debug_op(&ops[i]))
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
                        (ops[j].code == 32 || ops[j].code == 9))
                        indent_end = j + 1;
                    else break;
                }
                int n_indent = indent_end - seg_start;

                if (n_indent == 0) {
                    /* No indent deletes — pass segment through. */
                    for (int j = seg_start; j < i && n_out < out_cap; j++)
                        out[n_out++] = ops[j];
                } else {
                    /* Find \n op at the tail of the segment. */
                    int nl = -1;
                    for (int j = i - 1; j >= indent_end; j--) {
                        if (!ad_layer_is_debug_op(&ops[j]) && ops[j].code == 10) {
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
                    /* \n op: keep as-is. */
                    if (nl >= 0 && n_out < out_cap)
                        out[n_out++] = ops[nl];
                }
            }
            seg_start = i;
        }
    }

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_indent_last);
}
