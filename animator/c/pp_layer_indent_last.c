/*
 * pp_layer_indent_last.c — Transform Layer: Delete-Indent-Last
 *
 * Purpose:
 *   On each line, if there are DELETE ops for leading whitespace
 *   (indentation), move those deletes to the END of the line's ops:
 *     - If the line has a \n delete: move indent deletes just before
 *       the \n delete.
 *     - If the line has no \n delete: move indent deletes to the end
 *       of the line's ops.
 *
 *   This only applies to DELETION of indent. Adding indent is a normal
 *   operation and is NOT affected.
 *
 *   This layer does NOT touch line/col positions. It only reorders ops.
 *   Line/col adjustment is a SEPARATE concern (handled in postprocess.c
 *   via adjust_positions).
 *
 * Trigger:
 *   --indent-last  (env: DV_INDENT_LAST=1)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_indent_last animator/c/pp_layer_indent_last.c
 */

#include "pp_common.h"

int layer_indent_last(Op *in, int in_count, Op *out, int out_cap,
                      const char *old_file) {
    (void)old_file;

    int n_out = 0;
    int seg_start = 0;

    pp_logf("Delete-indent-last: %d input ops", in_count);

    for (int i = 0; i <= in_count; i++) {
        int is_boundary = (i == in_count);

        if (i < in_count && i > seg_start) {
            if (in[i].code == 10 && !pp_is_debug_op(&in[i])) {
                is_boundary = 1;
            }
            if (!pp_is_debug_op(&in[i]) && !pp_is_debug_op(&in[i-1])) {
                if (in[i].line != in[i-1].line) {
                    is_boundary = 1;
                }
            }
        }

        if (is_boundary) {
            int seg_len = i - seg_start;

            if (seg_len > 0 && n_out + seg_len <= out_cap) {
                /* Find leading indent deletes — consecutive space/tab
                 * DELETE ops at the start of the segment. */
                int indent_end = seg_start;
                for (int j = seg_start; j < i; j++) {
                    if (pp_is_debug_op(&in[j])) continue;
                    if (strcmp(in[j].type, "delete") == 0 &&
                        (in[j].code == 32 || in[j].code == 9)) {
                        indent_end = j + 1;
                    } else {
                        break;
                    }
                }

                int n_indent = indent_end - seg_start;

                if (n_indent == 0) {
                    /* No leading indent deletes — copy segment as-is */
                    for (int j = seg_start; j < i; j++) {
                        out[n_out++] = in[j];
                    }
                } else {
                    /* Find the \n op position (if any) */
                    int nl_pos = -1;
                    for (int j = i - 1; j >= indent_end; j--) {
                        if (!pp_is_debug_op(&in[j]) && in[j].code == 10) {
                            nl_pos = j;
                            break;
                        }
                    }

                    /* Emit: content ops (indent_end..content_end),
                     *       then indent deletes (seg_start..indent_end),
                     *       then \n op (if present). */
                    int content_end = (nl_pos >= 0) ? nl_pos : i;
                    for (int j = indent_end; j < content_end; j++) {
                        out[n_out++] = in[j];
                    }
                    for (int j = seg_start; j < indent_end; j++) {
                        out[n_out++] = in[j];
                    }
                    if (nl_pos >= 0) {
                        out[n_out++] = in[nl_pos];
                    }
                }
            }

            seg_start = i;
        }
    }

    pp_logf("Delete-indent-last: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L_indent_last", "Delete-Indent-Last");
    return pp_run_layer(layer_indent_last);
}
#endif
