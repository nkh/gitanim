/*
 * pp_layer_overwrite.c — Transform Layer: Overwrite
 *
 * Purpose:
 *   When a delete (code != 10) is immediately followed by an insert
 *   (code != 10) at the same position, replace the pair with a single
 *   overwrite_insert op. The animator applies the insert in-place
 *   (replacing the deleted char) instead of delete-then-insert.
 *
 *   "Same position" means: same line AND same col. After the delete,
 *   the col doesn't advance (the char is removed at the cursor). So
 *   if the next insert is at the same (line, col), it replaces the
 *   deleted char.
 *
 *   Codes need NOT match — this is position-based, not value-based.
 *   Example: delete 'a' at (1,5) followed by insert 'B' at (1,5)
 *   → overwrite_insert 'B' at (1,5). The animator deletes 'a' and
 *   inserts 'B' in one step (no gap, no flicker).
 *
 * Trigger:
 *   --overwrite  (env: DIFFVIM_OVERWRITE=1)
 *
 * Debug:
 *   If --op-debug is set, inserts debug ops into the stream showing
 *   what was merged:
 *     debug\toverwrite\tmerged delete(X) + insert(Y) → overwrite_insert(Y) at line=L col=C
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_overwrite animator/c/pp_layer_overwrite.c
 *
 * Include in postprocess:
 *   #include "pp_layer_overwrite.c"
 *   Then call: layer_overwrite(in, count, out, cap, old_file);
 *
 * Input:  V2 TSV on stdin
 * Output: V2 TSV on stdout (with overwrite_insert ops)
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=path  →  dumps to $path/L_overwrite_input.txt etc.
 *   DV_OP_DEBUG=1              →  inserts debug ops into the stream
 *   DV_OLD_FILE=path           →  old file path (unused, but available)
 */

#include "pp_common.h"

/* Check if env var is set to "1" */
static int env_flag(const char *name) {
    const char *v = getenv(name);
    return v && v[0] == '1';
}

/*
 * Layer: Overwrite
 *
 * Linear scan over ops. When delete (code != 10) is immediately
 * followed by insert (code != 10) at the same (line, col):
 *   - Replace the delete with nothing (skip it)
 *   - Replace the insert type with "overwrite_insert"
 *   - The op's code becomes the insert's code (the new char)
 *   - The op's line/col stays (same position)
 *
 * If --op-debug is set, insert a debug op before the overwrite_insert
 * explaining what was merged.
 *
 * Parameters:
 *   in        — input Op array
 *   in_count  — number of input ops
 *   out       — output Op array (pre-allocated)
 *   out_cap   — capacity of out array
 *   old_file  — old file path (unused)
 *
 * Returns: number of output ops (can be < in_count because pairs merge)
 */
int layer_overwrite(Op *in, int in_count, Op *out, int out_cap,
                    const char *old_file) {
    (void)old_file;

    int op_debug = env_flag("DV_OP_DEBUG");
    int n_out = 0;

    pp_logf("Overwrite layer: %d input ops, op_debug=%s",
            in_count, op_debug ? "on" : "off");

    int i = 0;
    int merges = 0;
    while (i < in_count) {
        /* Check: is this a delete (code != 10) followed by insert (code != 10)
         * at the same position? */
        if (i + 1 < in_count &&
            strcmp(in[i].type, "delete") == 0 && in[i].code != 10 &&
            strcmp(in[i+1].type, "insert") == 0 && in[i+1].code != 10 &&
            in[i].line == in[i+1].line && in[i].col == in[i+1].col) {

            /* Merge: skip the delete, convert insert to overwrite_insert */
            if (op_debug && n_out + 2 <= out_cap) {
                /* Insert debug op before the overwrite */
                char msg[256];
                snprintf(msg, sizeof(msg),
                         "merged delete(%d) + insert(%d) → overwrite_insert(%d) at line=%d col=%d",
                         in[i].code, in[i+1].code, in[i+1].code,
                         in[i].line, in[i].col);
                strcpy(out[n_out].type, "debug");
                out[n_out].code = 0;
                out[n_out].line = in[i].line;
                out[n_out].col = in[i].col;
                n_out++;
            }

            /* Emit the overwrite_insert */
            if (n_out < out_cap) {
                strcpy(out[n_out].type, "overwrite_insert");
                out[n_out].code = in[i+1].code;  /* the new char */
                out[n_out].line = in[i+1].line;
                out[n_out].col = in[i+1].col;
                n_out++;
            }
            merges++;
            i += 2;  /* consumed both delete and insert */
        } else {
            /* Pass through unchanged */
            if (n_out < out_cap) {
                out[n_out] = in[i];
                n_out++;
            }
            i++;
        }
    }

    pp_logf("Overwrite: %d ops → %d ops (%d merges)",
            in_count, n_out, merges);

    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L_overwrite", "Overwrite");
    return pp_run_layer(layer_overwrite);
}
#endif
