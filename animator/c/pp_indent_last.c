/*
 * pp_indent_last.c — Transform Layer: Delete-Indent-Last
 *
 * Moves leading whitespace DELETE ops to end of line.
 * Does NOT adjust positions — pp_adjust handles that at the end.
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_indent_last animator/c/pp_indent_last.c
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
                    for (int j = seg_start; j < i; j++) {
                        out[n_out++] = in[j];
                    }
                } else {
                    int nl_pos = -1;
                    for (int j = i - 1; j >= indent_end; j--) {
                        if (!pp_is_debug_op(&in[j]) && in[j].code == 10) {
                            nl_pos = j;
                            break;
                        }
                    }

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
    pp_debug_init("indent_last", "Delete-Indent-Last");
    return pp_run_layer(layer_indent_last);
}
#endif
