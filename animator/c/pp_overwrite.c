/*
 * pp_overwrite.c — Transform Layer: Overwrite
 *
 * Merges delete+insert pairs at the same position into overwrite_insert.
 * Does NOT adjust positions — pp_adjust handles that at the end.
 */

#include "pp_common.h"

int layer_overwrite(Op *in, int in_count, Op *out, int out_cap,
                    const char *old_file) {
    (void)old_file;
    int n_out = 0;

    pp_logf("Overwrite: %d input ops", in_count);

    int i = 0;
    int merges = 0;
    while (i < in_count) {
        int prev_is_same_del = (i > 0 &&
            strcmp(in[i-1].type, "delete") == 0 && in[i-1].code != 10 &&
            in[i-1].line == in[i].line && in[i-1].col == in[i].col);
        int next_is_same_ins = (i + 2 < in_count &&
            strcmp(in[i+2].type, "insert") == 0 && in[i+2].code != 10 &&
            in[i+2].line == in[i+1].line);

        if (i + 1 < in_count &&
            strcmp(in[i].type, "delete") == 0 && in[i].code != 10 &&
            strcmp(in[i+1].type, "insert") == 0 && in[i+1].code != 10 &&
            in[i].line == in[i+1].line && in[i].col == in[i+1].col &&
            !prev_is_same_del && !next_is_same_ins) {

            if (n_out < out_cap) {
                strcpy(out[n_out].type, "overwrite_insert");
                out[n_out].code = in[i+1].code;
                out[n_out].line = in[i+1].line;
                out[n_out].col = in[i+1].col;
                n_out++;
            }
            merges++;
            i += 2;
        } else {
            if (n_out < out_cap) {
                out[n_out] = in[i];
                n_out++;
            }
            i++;
        }
    }

    pp_logf("Overwrite: %d ops -> %d ops (%d merges)", in_count, n_out, merges);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("overwrite", "Overwrite");
    return pp_run_layer(layer_overwrite);
}
#endif
