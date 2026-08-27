/*
 * pp_reorder.c — Reorder Layer
 *
 * Always runs. Does ONE thing:
 *   4-sweep reorder within each line group:
 *   content deletes → content inserts → \n deletes → \n inserts
 *
 * Does NOT adjust positions. Position adjustment is handled by
 * pp_adjust which runs as a separate final step in the pipeline.
 * This allows pp_reorder to be composed with other layers in any
 * order without position conflicts.
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_reorder animator/c/pp_reorder.c
 */

#include "pp_common.h"

int layer_reorder(Op *in, int in_count, Op *out, int out_cap,
                   const char *old_file) {
    (void)old_file;
    int n_out = 0;
    int buf_start = 0;

    pp_logf("Reorder: %d input ops", in_count);

    for (int i = 0; i <= in_count; i++) {
        int is_flush_point = (i == in_count);
        if (i < in_count && !pp_is_debug_op(&in[i])) {
            if (strcmp(in[i].type, "keep") == 0 || in[i].code == 10)
                is_flush_point = 1;
        }

        if (is_flush_point) {
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code != 10 && n_out < out_cap)
                    out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if ((strcmp(in[j].type, "insert") == 0 ||
                     strcmp(in[j].type, "overwrite_insert") == 0) &&
                    in[j].code != 10 && n_out < out_cap)
                    out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code == 10 && n_out < out_cap)
                    out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if ((strcmp(in[j].type, "insert") == 0 ||
                     strcmp(in[j].type, "overwrite_insert") == 0) &&
                    in[j].code == 10 && n_out < out_cap)
                    out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (pp_is_debug_op(&in[j]) && n_out < out_cap)
                    out[n_out++] = in[j];
            if (i < in_count && n_out < out_cap)
                out[n_out++] = in[i];
            buf_start = i + 1;
        }
    }

    pp_logf("Reorder: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("reorder", "Reorder");
    return pp_run_layer(layer_reorder);
}
#endif
