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
     * Segments are bounded by keeps and \n ops. Within a segment, emit
     * non-\n deletes first, then non-\n inserts, then debug ops.
     * Boundaries (keeps and \n ops) are emitted in place, in their
     * original positions in the stream. */
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
            /* Sweep 3: debug ops (in original order) */
            for (int j = segment_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            /* Emit the boundary op itself (keep or \n) in place. */
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* ── Pass 2: position walk ──
     * Walk forward, assigning (line, col) to each op based on the
     * execution order. Track a "line_shift" that adjusts for \n
     * deletes (join reduces line count) and \n inserts (split
     * increases line count).
     *
     *   - \n keep/insert: advance to next line (content moves down)
     *   - \n delete: DON'T advance (join brings next line's content HERE).
     *     Decrement line_shift so subsequent ops' lines are adjusted.
     *   - \n insert: advance to next line.
     *     Increment line_shift so subsequent ops' lines are adjusted. */
    if (out_count > 0) {
        int current_line = out[0].line;
        int current_col = 1;
        int line_shift = 0;  /* cumulative shift from \n deletes (-) and inserts (+) */
        for (int i = 0; i < out_count; i++) {
            if (ad_layer_is_debug_op(&out[i])) continue;

            int is_newline_op = (out[i].code == AD_LAYER_CHAR_NEWLINE);

            if (!is_newline_op) {
                /* Apply line_shift to the op's line */
                out[i].line = current_line;
                out[i].col = current_col;
                if (strcmp(out[i].type, "keep") == 0
                    || strcmp(out[i].type, "insert") == 0
                    || strcmp(out[i].type, "overwrite_insert") == 0) {
                    current_col++;
                }
            } else {
                /* \n op */
                out[i].line = current_line;  /* assign current line */
                out[i].col = current_col;    /* assign current col */
                if (strcmp(out[i].type, "delete") == 0) {
                    /* \n delete: join — DON'T advance. Next content
                     * stays on SAME line. */
                    line_shift--;
                } else {
                    /* \n keep or insert: advance to next line */
                    current_line++;
                    current_col = 1;
                    if (strcmp(out[i].type, "insert") == 0
                        || strcmp(out[i].type, "overwrite_insert") == 0) {
                        line_shift++;
                    }
                }
            }
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

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_reorder);
}

