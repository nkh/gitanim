/*
 * pp_layer2_transforms.c — Layer 2: Transforms (no-op for now)
 *
 * Purpose (future):
 *   Apply optional transforms: indent-last, semantic-cleanup, overwrite.
 *   Each transform is a separate sub-layer that can be enabled/disabled.
 *
 * Current state: NO-OP (passthrough). Returns input unchanged.
 *
 * Input:  V2 TSV on stdin (from Layer 1)
 * Output: V2 TSV on stdout (unchanged — ready for Layer 3)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -o animator/bin/pp_layer2 animator/c/pp_layer2_transforms.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=1  → writes log and op dumps
 */

#include "pp_common.h"

/*
 * Layer 2: Transforms
 *
 * Future implementation will apply:
 *   2a. semantic_cleanup  (option: --semantic-cleanup)
 *   2b. indent_last       (option: --indent-last)
 *   2c. overwrite         (option: --overwrite)
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
int layer2_transforms(Op *in, int in_count, Op *out, int out_cap) {
    pp_log("Layer 2: Transforms (no-op, passthrough)");

    /* Copy input to output unchanged */
    int count = in_count;
    if (count > out_cap) count = out_cap;
    memcpy(out, in, count * sizeof(Op));

    pp_logf("Passthrough: %d ops → %d ops (no change)", in_count, count);
    return count;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("Layer 2: Transforms");
    return pp_run_layer(layer2_transforms);
}
#endif
