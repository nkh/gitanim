/*
 * pp_layer1_reorder.c — Layer 1: Reorder (4-sweep, per line group)
 *
 * Purpose:
 *   Reorder ops within each line group. A "line group" is the
 *   sequence of ops between two \n ops (or between a keep and a \n).
 *
 *   Within each line group, the 4-sweep order is:
 *     1. Content deletes (code != 10)
 *     2. Content inserts (code != 10)
 *     3. \n deletes (code == 10) — at the end of the group
 *     4. \n inserts (code == 10) — at the end of the group
 *
 *   Keeps stay in their original position (they anchor the groups).
 *
 *   This ordering ensures that \n deletes happen AFTER all content
 *   is settled, preventing content from appearing on the wrong line.
 */

#include "pp_common.h"

int layer1_reorder(Op *in, int in_count, Op *out, int out_cap,
                   const char *old_file) {
    (void)old_file;
    int n_out = 0;
    int buf_start = 0;

    for (int i = 0; i <= in_count; i++) {
        /* Flush at: end of array, keep op, or \n op (code == 10) */
        int is_flush_point = (i == in_count);
        if (i < in_count && !pp_is_debug_op(&in[i])) {
            if (strcmp(in[i].type, "keep") == 0 || in[i].code == 10)
                is_flush_point = 1;
            /* Don't flush at \n — \n is part of the current line group.
             * Flush AFTER the \n (i.e., the \n is the last op in the group). */
        }

        if (is_flush_point) {
            /* Flush buffer in 4 sweeps.
             * overwrite_insert is treated like insert (it advances col). */
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
            /* Pass through debug ops */
            for (int j = buf_start; j < i; j++)
                if (pp_is_debug_op(&in[j]) && n_out < out_cap)
                    out[n_out++] = in[j];
            /* Emit the keep (if not at end) */
            if (i < in_count && n_out < out_cap)
                out[n_out++] = in[i];
            buf_start = i + 1;
        }
    }
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L1", "Reorder");
    return pp_run_layer(layer1_reorder);
}
#endif
