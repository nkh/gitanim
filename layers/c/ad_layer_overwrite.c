/* ad_layer_overwrite.c — merge delete+insert pairs into overwrite_insert.
 *
 * Detects adjacent delete+insert at the same (line, col) and merges them
 * into overwrite_insert. Operates ONLY on non-\n ops — never touches
 * 'delete \n' or 'insert \n' ops.
 *
 * Position handling:
 *   - For non-\n ops: recompute (current_line, current_col) based on
 *     keeps/inserts/overwrite_inserts advancing the cursor.
 *   - For \n ops: KEEP original position. Never touch.
 */
#include "ad_layer_common.h"

static int layer_overwrite(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int out_count = 0;
    int i = 0;

    while (i < n_ops) {
        int can_merge = 0;
        /* Only merge non-\n delete + non-\n insert at the same (line, col). */
        if (i + 1 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && !ad_layer_is_line_op(&ops[i])
            && strcmp(ops[i+1].type, "insert") == 0 && !ad_layer_is_line_op(&ops[i+1])
            && ops[i].line == ops[i+1].line
            && ops[i].col == ops[i+1].col) {
            /* Check prev_is_delete_same_pos (previous op was a delete at the same position) */
            int prev_is_delete_same_pos = 0;
            if (i > 0
                && strcmp(ops[i-1].type, "delete") == 0 && !ad_layer_is_line_op(&ops[i-1])
                && ops[i-1].line == ops[i].line
                && ops[i-1].col == ops[i].col) {
                prev_is_delete_same_pos = 1;
            }
            /* Check next_is_insert_same_line (next-next op is an insert at the same line) */
            int next_is_insert_same_line = 0;
            if (i + 2 < n_ops
                && strcmp(ops[i+2].type, "insert") == 0 && !ad_layer_is_line_op(&ops[i+2])
                && ops[i+2].line == ops[i+1].line) {
                next_is_insert_same_line = 1;
            }
            if (!prev_is_delete_same_pos && !next_is_insert_same_line) can_merge = 1;
        }

        if (can_merge && out_count < out_cap) {
            strncpy(out[out_count].type, "overwrite_insert", AD_LAYER_TYPE_LEN - 1);
            out[out_count].type[AD_LAYER_TYPE_LEN - 1] = 0;
            out[out_count].code = ops[i+1].code;
            out[out_count].line = ops[i+1].line;
            out[out_count].col = ops[i+1].col;
            out_count++;
            i += 2;
        } else {
            if (out_count < out_cap) out[out_count++] = ops[i];
            i++;
        }
    }

    /* Position recomputation pass REMOVED — the diff engine produces
     * correct positions. The overwrite layer should only merge ops,
     * not recompute positions. */

    return out_count;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_overwrite);
}
