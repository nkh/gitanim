/* ad_layer_reorder.c — 4-sweep reorder + cross-hunk position adjust.
 *
 * Within each change region (consecutive non-keep, non-\n ops between
 * boundaries), emit all DELETEs first, then all INSERTs. Keeps and \n
 * ops stay in place as anchors/line boundaries.
 *
 * This avoids the visual problem of interleaved delete+insert.
 */
#include "ad_layer_common.h"

/* layer_reorder: Reorders ops within each change region using a 5-sweep
 * algorithm (non-\n deletes, non-\n inserts, \n deletes, \n inserts,
 * debug ops). Each segment is delimited by keep ops, \n ops, or the end
 * of the input array. Sets (line, col) positions on output by walking
 * forward through the emitted ops. Updates *line_offset with the
 * cumulative (\n_ins - \n_del) delta for cross-hunk position tracking.
 *
 * Inputs:  ops[0..n_ops-1]  — ops for one hunk (already shifted by
 *                             line_offset from prior hunks).
 * Outputs: out[0..out_cap-1] — reordered ops with positions set.
 *          *line_offset      — updated by (\n_ins - \n_del) delta.
 * Returns: number of output ops written. */
static int layer_reorder(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    int out_count = 0, segment_start = 0;

    /* 5-sweep reorder within each segment.
     * A segment is delimited by keep ops, \n ops, or end of array. */
    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i]))
            if (strcmp(ops[i].type, "keep") == 0 || ops[i].code == AD_LAYER_CHAR_NEWLINE)
                is_boundary = 1;

        if (is_boundary) {
            /* Sweep 1: non-newline deletes */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 && ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 2: non-newline inserts/overwrite_inserts */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 || strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 3: newline deletes */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 && ops[j].code == AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 4: newline inserts */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 || strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code == AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 5: debug ops (in original order) */
            for (int j = segment_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Emit the boundary op itself (keep or \n) */
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* Set positions on the output by walking forward. */
    int current_line = (out_count > 0) ? out[0].line : 1;
    int current_col = 1;
    for (int i = 0; i < out_count; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;
        out[i].line = current_line;
        out[i].col = current_col;
        if (strcmp(out[i].type, "keep") == 0 ||
            strcmp(out[i].type, "insert") == 0 ||
            strcmp(out[i].type, "overwrite_insert") == 0) {
            if (out[i].code == AD_LAYER_CHAR_NEWLINE) { current_line++; current_col = 1; }
            else current_col++;
        }
    }

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
    return ad_layer_run(layer_reorder);
}
