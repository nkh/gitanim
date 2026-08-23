/*
 * pp_layer3_cursor.c — Layer 3: Cursor Recomputation (no-op for now)
 *
 * Purpose (future):
 *   Assign correct (line, col) to every op based on cursor simulation.
 *   Simple tracking — no look-ahead, no special cases.
 *   The cursor follows the ops as the animator would apply them.
 *
 * Current state: NO-OP (passthrough). Returns input unchanged.
 *
 * Input:  V2 TSV on stdin (from Layer 2)
 * Output: V2 TSV on stdout (with recomputed line/col — future)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -o animator/bin/pp_layer3 animator/c/pp_layer3_cursor.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=1  → writes log and op dumps
 */

#include "pp_common.h"

/*
 * Layer 3: Cursor Recomputation
 *
 * Future implementation:
 *   cur_line = target_line + line_offset
 *   cur_col = 1
 *   for each op:
 *       op.line = cur_line
 *       op.col = cur_col
 *       if keep (code != 10): cur_col++
 *       if keep (code == 10): cur_line++; cur_col = 1
 *       if delete (code != 10): (cur_col stays)
 *       if delete (code == 10): (cur_line stays, join)
 *       if insert (code != 10): cur_col++
 *       if insert (code == 10): cur_line++; cur_col = 1
 *
 * Currently: passthrough (no-op). Copies input to output unchanged.
 *
 * Parameters:
 *   in       — input Op array
 *   in_count — number of input ops
 *   out      — output Op array (pre-allocated)
 *   out_cap  — capacity of out array
 *
 * Returns: number of output ops
 */
int layer3_cursor(Op *in, int in_count, Op *out, int out_cap) {
    pp_log("Layer 3: Cursor Recomputation (no-op, passthrough)");

    /* Copy input to output unchanged */
    int count = in_count;
    if (count > out_cap) count = out_cap;
    memcpy(out, in, count * sizeof(Op));

    pp_logf("Passthrough: %d ops → %d ops (no change)", in_count, count);
    return count;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("Layer 3: Cursor Recomputation");
    return pp_run_layer(layer3_cursor);
}
#endif
