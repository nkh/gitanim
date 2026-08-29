/* ad_layer_overwrite.c — merge delete+insert pairs into overwrite_insert.
 *
 * Detects adjacent delete+insert at the same (line, col) and merges them
 * into overwrite_insert. Prevents merge if the previous op was a delete at
 * the same position (pd) or the next-next op is an insert at the same line (ni).
 */
#include "ad_layer_common.h"

static int layer_overwrite(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;  /* overwrite doesn't use line_offset */
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        int can_merge = 0;
        if (i + 1 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && ops[i].code != 10
            && strcmp(ops[i+1].type, "insert") == 0 && ops[i+1].code != 10
            && ops[i].line == ops[i+1].line
            && ops[i].col == ops[i+1].col) {
            /* Check pd (previous op was a delete at the same position) */
            int pd = 0;
            if (i > 0
                && strcmp(ops[i-1].type, "delete") == 0 && ops[i-1].code != 10
                && ops[i-1].line == ops[i].line
                && ops[i-1].col == ops[i].col) {
                pd = 1;
            }
            /* Check ni (next-next op is an insert at the same line) */
            int ni = 0;
            if (i + 2 < n_ops
                && strcmp(ops[i+2].type, "insert") == 0 && ops[i+2].code != 10
                && ops[i+2].line == ops[i+1].line) {
                ni = 1;
            }
            if (!pd && !ni) can_merge = 1;
        }

        if (can_merge && n_out < out_cap) {
            strcpy(out[n_out].type, "overwrite_insert");
            out[n_out].code = ops[i+1].code;
            out[n_out].line = ops[i+1].line;
            out[n_out].col = ops[i+1].col;
            n_out++;
            i += 2;
        } else {
            if (n_out < out_cap) out[n_out++] = ops[i];
            i++;
        }
    }

    /* Set positions on the output. */
    int cl = (n_out > 0) ? out[0].line : 1;
    int cc = 1;
    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;
        out[i].line = cl;
        out[i].col = cc;
        if (strcmp(out[i].type, "keep") == 0 ||
            strcmp(out[i].type, "insert") == 0 ||
            strcmp(out[i].type, "overwrite_insert") == 0) {
            if (out[i].code == 10) { cl++; cc = 1; }
            else cc++;
        }
    }

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_overwrite);
}
