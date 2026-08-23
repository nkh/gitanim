/*
 * pp_layer1_reorder.c — Layer 1: Reorder (4-sweep, no-op for now)
 *
 * Purpose (future):
 *   Reorder ops within each line group (between \n ops) to prevent
 *   content from appearing on the wrong line during animation.
 *   4-sweep order: content deletes → content inserts → \n deletes → \n inserts.
 *
 * Current state: NO-OP (passthrough). Returns input unchanged.
 *
 * Input:  V2 TSV on stdin (from Layer 0)
 * Output: V2 TSV on stdout (unchanged — ready for Layer 2)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -o animator/bin/pp_layer1 animator/c/pp_layer1_reorder.c
 *
 * Build into postprocess:
 *   #include "pp_layer1_reorder.c"  (or link the object file)
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=1  → writes log to /tmp/dv_debug/postprocess.log
 *                            and op dumps to /tmp/dv_debug/layer_input.txt
 *                            and /tmp/dv_debug/layer_output.txt
 */

#include "pp_common.h"

/*
 * Layer 1: Reorder
 *
 * Future implementation will do the 4-sweep reorder:
 *   1. Content deletes (code != 10)
 *   2. Content inserts (code != 10)
 *   3. \n deletes (code == 10)
 *   4. \n inserts (code == 10)
 *
 * Currently: passthrough (no-op). Copies input to output unchanged.
 *
 * Parameters:
 *   in       — input Op array
 *   in_count — number of input ops
 *   out      — output Op array (pre-allocated, capacity = out_cap)
 *   out_cap  — capacity of out array
 *
 * Returns: number of output ops
 */
int layer1_reorder(Op *in, int in_count, Op *out, int out_cap) {
    pp_log("Layer 1: Reorder (no-op, passthrough)");

    /* Copy input to output unchanged */
    int count = in_count;
    if (count > out_cap) count = out_cap;
    memcpy(out, in, count * sizeof(Op));

    pp_logf("Passthrough: %d ops → %d ops (no change)", in_count, count);
    return count;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("Layer 1: Reorder");
    return pp_run_layer(layer1_reorder);
}
#endif
