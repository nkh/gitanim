/*
 * pp_layer_reorder.c — Reorder + Position Adjustment
 *
 * Always runs. Does two things:
 *   1. 4-sweep reorder within each line group:
 *      content deletes → content inserts → \n deletes → \n inserts
 *   2. Position adjustment: walks ops and fixes (line, col) based on
 *      \n deletes (lines shift after joins).
 *
 * The position adjustment is part of THIS layer because the reorder
 * is what changes when \n deletes happen relative to content ops.
 * After reordering, the layer knows the final op order and can
 * compute correct positions.
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_reorder animator/c/pp_layer_reorder.c \
 *      animator/c/pp_adjust.c
 */

#include "pp_common.h"

/* From pp_adjust.c */
extern void adjust_positions(Op *ops, int n_ops, int current_characters_in,
                              int deleted_lines_in,
                              int *deleted_lines_out, int *ops_consumed_out);
extern int run_adjust_positions(Op *ops, int n_ops);

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
            /* 4-sweep reorder */
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

    /* Position adjustment: fix (line, col) based on \n deletes.
     * This runs HERE because the reorder changes when \n deletes
     * happen relative to content ops, which affects line numbers.
     * Layers that run AFTER this (indent_last, overwrite) do their
     * own position adjustment on top of these corrected positions. */
    run_adjust_positions(out, n_out);

    pp_logf("Reorder+adjust: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("reorder", "Reorder");
    return pp_run_layer(layer_reorder);
}
#endif
