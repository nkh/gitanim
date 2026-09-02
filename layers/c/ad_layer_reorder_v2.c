/* ad_layer_reorder_v2.c — Clone of reorder using shared position-walk.
 *
 * Same 4-sweep as ad_layer_reorder.c, but uses
 * ad_layer_recompute_positions() instead of its own position walk.
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static int layer_reorder_v2(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    int out_count = 0, segment_start = 0;

    /* Pass 1: 4-sweep within segments */
    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i]))
            if (strcmp(ops[i].type, "keep") == 0 || ops[i].code == AD_LAYER_CHAR_NEWLINE)
                is_boundary = 1;

        if (is_boundary) {
            /* Sweep 1: non-\n deletes */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 2: non-\n inserts/overwrite_inserts */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 ||
                     strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 3: debug ops (original order) */
            for (int j = segment_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Emit boundary (keep or \n) in place */
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* Use shared position-walk instead of the inline one */
    ad_layer_recompute_positions(out, out_count);

    /* Update line_offset: cumulative \n_ins - \n_del from output ops. */
    int ni = 0, nd = 0;
    for (int j = 0; j < out_count; j++) {
        if (strcmp(out[j].type, "insert") == 0 && out[j].code == AD_LAYER_CHAR_NEWLINE) ni++;
        if (strcmp(out[j].type, "delete") == 0 && out[j].code == AD_LAYER_CHAR_NEWLINE) nd++;
    }
    *line_offset += ni - nd;

    return out_count;
}

int main(void) {
    return ad_layer_run(layer_reorder_v2);
}
