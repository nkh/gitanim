/* ad_layer_reorder.c — Reorder character ops within each line.
 *
 * SEGMENT-BASED 4-SWEEP (within lines):
 *   Segments are delimited by keep ops and \n ops (boundaries).
 *   Within each segment (the non-keep, non-\n ops between boundaries),
 *   emit in this order:
 *     1. non-\n deletes
 *     2. non-\n inserts/overwrite_inserts
 *     3. debug ops
 *   Boundaries (keeps, \n ops) are emitted in their original positions.
 *
 * This layer NEVER touches a 'delete \n' op:
 *   - It does NOT reorder \n ops (they stay where they were in the stream).
 *   - It does NOT recompute \n ops' positions (original position kept).
 *
 * Position handling:
 *   - For non-\n ops: recompute (current_line, current_col) based on
 *     keeps/inserts advancing the cursor.
 *   - For \n ops: KEEP original position. Don't touch.
 */
#include "ad_layer_common.h"

static int layer_reorder(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    int out_count = 0, segment_start = 0;

    /* ── Pass 1: 4-sweep within segments ──
     * Segments are bounded by keeps and line ops (keep_line, join_lines,
     * split_line). Within a segment, emit deletes first, then inserts,
     * then debug ops. Boundaries are emitted in place. */
    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i]))
            if (strcmp(ops[i].type, "keep") == 0 || ad_layer_is_line_op(&ops[i]))
                is_boundary = 1;

        if (is_boundary) {
            /* Sweep 1: deletes */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 &&
                    !ad_layer_is_line_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 2: inserts/overwrite_inserts */
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 ||
                     strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    !ad_layer_is_line_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Sweep 3: debug ops (in original order) */
            for (int j = segment_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Emit the boundary op itself (keep or line op) in place. */
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* Update line_offset: net split_line - join_lines from output ops. */
    int ni = 0, nd = 0;
    for (int j = 0; j < out_count; j++) {
        if (strcmp(out[j].type, "split_line") == 0) ni++;
        if (strcmp(out[j].type, "join_lines") == 0) nd++;
    }
    *line_offset += ni - nd;

    return out_count;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_reorder);
}

