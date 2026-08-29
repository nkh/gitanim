/* ad_layer_reorder.c — 4-sweep reorder + cross-hunk position adjust.
 *
 * Within each change region (consecutive non-keep, non-\n ops between
 * boundaries), emit all DELETEs first, then all INSERTs. Keeps and \n
 * ops stay in place as anchors/line boundaries.
 *
 * This avoids the visual problem of interleaved delete+insert.
 */
#include "ad_layer_common.h"

/* Layer function: reorder ops in 4 sweeps, set positions, update line_offset. */
static int layer_reorder(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    int n_out = 0, buf_start = 0;

    /* 4-sweep reorder within each segment.
     * A segment is delimited by keep ops, \n ops, or end of array. */
    for (int i = 0; i <= n_ops; i++) {
        int is_flush = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i]))
            if (strcmp(ops[i].type, "keep") == 0 || ops[i].code == 10)
                is_flush = 1;

        if (is_flush) {
            /* Sweep 1: non-newline deletes */
            for (int j = buf_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 && ops[j].code != 10 && n_out < out_cap)
                    out[n_out++] = ops[j];
            /* Sweep 2: non-newline inserts/overwrite_inserts */
            for (int j = buf_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 || strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code != 10 && n_out < out_cap)
                    out[n_out++] = ops[j];
            /* Sweep 3: newline deletes */
            for (int j = buf_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 && ops[j].code == 10 && n_out < out_cap)
                    out[n_out++] = ops[j];
            /* Sweep 4: newline inserts */
            for (int j = buf_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 || strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code == 10 && n_out < out_cap)
                    out[n_out++] = ops[j];
            /* Sweep 5: debug ops (in original order) */
            for (int j = buf_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && n_out < out_cap)
                    out[n_out++] = ops[j];
            /* Emit the boundary op itself (keep or \n) */
            if (i < n_ops && n_out < out_cap)
                out[n_out++] = ops[i];
            buf_start = i + 1;
        }
    }

    /* Set positions on the output by walking forward. */
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

    /* Update line_offset: cumulative \n_ins - \n_del from output ops. */
    int ni = 0, nd = 0;
    for (int j = 0; j < n_out; j++) {
        if (strcmp(out[j].type, "insert") == 0 && out[j].code == 10) ni++;
        if (strcmp(out[j].type, "delete") == 0 && out[j].code == 10) nd++;
    }
    *line_offset += ni - nd;

    return n_out;
}

int main(void) {
    return ad_layer_run(layer_reorder);
}
