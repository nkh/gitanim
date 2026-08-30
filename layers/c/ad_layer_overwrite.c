/* ad_layer_overwrite.c — merge delete+insert pairs into overwrite_insert.
 *
 * Detects adjacent delete+insert at the same (line, col) and merges them
 * into overwrite_insert. Prevents merge if the previous op was a delete at
 * the same position (prev_is_delete_same_pos) or the next-next op is an
 * insert at the same line (next_is_insert_same_line).
 */
#include "ad_layer_common.h"

/* layer_overwrite: Detects adjacent delete+insert pairs at the same
 * (line, col) and merges them into a single overwrite_insert op. This
 * prevents the visual "delete then insert" flicker for in-place edits.
 * The merge is suppressed if (a) the previous op was a delete at the same
 * position (would lose information) or (b) the next-next op is an insert
 * on the same line (would interrupt a multi-char insert run).
 *
 * Inputs:  ops[0..n_ops-1]   — ops for one hunk (positions already set).
 * Outputs: out[0..out_cap-1] — merged ops with positions re-walked.
 *          *line_offset       — not modified.
 * Returns: number of output ops written. */
static int layer_overwrite(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;  /* overwrite doesn't use line_offset */
    int out_count = 0;
    int i = 0;

    while (i < n_ops) {
        int can_merge = 0;
        if (i + 1 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && ops[i].code != AD_LAYER_CHAR_NEWLINE
            && strcmp(ops[i+1].type, "insert") == 0 && ops[i+1].code != AD_LAYER_CHAR_NEWLINE
            && ops[i].line == ops[i+1].line
            && ops[i].col == ops[i+1].col) {
            /* Check prev_is_delete_same_pos (previous op was a delete at the same position) */
            int prev_is_delete_same_pos = 0;
            if (i > 0
                && strcmp(ops[i-1].type, "delete") == 0 && ops[i-1].code != AD_LAYER_CHAR_NEWLINE
                && ops[i-1].line == ops[i].line
                && ops[i-1].col == ops[i].col) {
                prev_is_delete_same_pos = 1;
            }
            /* Check next_is_insert_same_line (next-next op is an insert at the same line) */
            int next_is_insert_same_line = 0;
            if (i + 2 < n_ops
                && strcmp(ops[i+2].type, "insert") == 0 && ops[i+2].code != AD_LAYER_CHAR_NEWLINE
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

    /* Set positions on the output. */
    int cl = (out_count > 0) ? out[0].line : 1;
    int cc = 1;
    for (int i = 0; i < out_count; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;
        out[i].line = cl;
        out[i].col = cc;
        if (strcmp(out[i].type, "keep") == 0 ||
            strcmp(out[i].type, "insert") == 0 ||
            strcmp(out[i].type, "overwrite_insert") == 0) {
            if (out[i].code == AD_LAYER_CHAR_NEWLINE) { cl++; cc = 1; }
            else cc++;
        }
    }

    return out_count;
}

int main(void) {
    return ad_layer_run(layer_overwrite);
}
