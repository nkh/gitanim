/*
 * pp_layer3_cursor.c — Layer 3: Cursor Recomputation
 *
 * Purpose:
 *   Assign correct (line, col) to every op based on cursor simulation.
 *   Simple loop — no look-ahead, no special cases, no ghost-line fix.
 *
 * Algorithm:
 *   cur_line = target_line + line_offset
 *   cur_col = 1
 *
 *   for each op (skip debug ops):
 *       op.line = cur_line
 *       op.col = cur_col
 *
 *       if keep:
 *           if code == 10: cur_line++; cur_col = 1
 *           else:           cur_col++
 *       elif delete:
 *           if code == 10: (cur_line stays, cur_col stays — join)
 *           else:           (cur_col stays — content removed at cursor)
 *       elif insert or overwrite_insert:
 *           if code == 10: cur_line++; cur_col = 1
 *           else:           cur_col++
 *
 *   line_offset += (newline_inserts - newline_deletes)
 *
 * Input:  V2 TSV on stdin (ops with raw line/col from compute)
 * Output: V2 TSV on stdout (ops with recomputed line/col)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_layer3 animator/c/pp_layer3_cursor.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=path  →  dumps to $path/L3_cursor_recomp_input.txt
 *                                and $path/L3_cursor_recomp_output.txt
 *   DV_OLD_FILE=path           →  old file path (available to layer function)
 */

#include "pp_common.h"

/*
 * Layer 3: Cursor Recomputation
 *
 * Simple cursor tracking. No look-ahead. No ghost-line fix. No special cases.
 * Just walk the ops and assign (line, col) based on what the cursor would
 * do as each op is applied.
 *
 * Parameters:
 *   in        — input Op array
 *   in_count  — number of input ops
 *   out       — output Op array (pre-allocated)
 *   out_cap   — capacity of out array
 *   old_file  — path to old file (unused by this layer, but available)
 *
 * Returns: number of output ops (always = input count for this layer)
 */
int layer3_cursor(Op *in, int in_count, Op *out, int out_cap,
                  const char *old_file) {
    (void)old_file;  /* not used by this layer */

    int count = in_count;
    if (count > out_cap) count = out_cap;

    /* Simple cursor tracking. No look-ahead. No special cases. */
    int cur_line = 0;  /* will be set from HUNK target in runner */
    int cur_col = 1;
    int newl_ins = 0, newl_del = 0;

    /* The runner calls us per-hunk, but we don't know the target line here.
     * The runner writes the HUNK header before calling us. We need the
     * target line to initialize cur_line.
     *
     * Solution: the first op's line is the target line (from compute).
     * We use that as our starting cur_line. Then we recompute everything.
     */
    if (count > 0) {
        cur_line = in[0].line;
    }

    for (int i = 0; i < count; i++) {
        /* Copy the op */
        out[i] = in[i];

        /* Skip debug ops — don't update cursor */
        if (pp_is_debug_op(&in[i])) {
            continue;
        }

        /* Set the op's position to the current cursor (BEFORE applying) */
        out[i].line = cur_line;
        out[i].col = cur_col;

        /* Update cursor based on what this op does */
        if (strcmp(in[i].type, "keep") == 0) {
            if (in[i].code == 10) {
                cur_line++;
                cur_col = 1;
            } else {
                cur_col++;
            }
        } else if (strcmp(in[i].type, "delete") == 0) {
            if (in[i].code == 10) {
                /* \n delete — join current line with next.
                 * cur_line stays (content from next line joins onto current).
                 * cur_col stays at the join point. */
                newl_del++;
            } else {
                /* Content delete — cur_col stays (content removed at cursor) */
            }
        } else if (strcmp(in[i].type, "insert") == 0 ||
                   strcmp(in[i].type, "overwrite_insert") == 0) {
            if (in[i].code == 10) {
                /* \n insert — split line */
                cur_line++;
                cur_col = 1;
                newl_ins++;
            } else {
                cur_col++;
            }
        }
    }

    pp_logf("Cursor recomp: %d ops, %d newl_ins, %d newl_del, "
            "final line=%d col=%d",
            count, newl_ins, newl_del, cur_line, cur_col);

    return count;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L3", "Cursor Recomputation");
    return pp_run_layer(layer3_cursor);
}
#endif
