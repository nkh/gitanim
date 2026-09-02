/* ad_layer_overwrite_v2.c — Clone of overwrite using shared position-walk.
 *
 * Same algorithm as ad_layer_overwrite.c, but uses
 * ad_layer_recompute_positions() instead of its own position walk.
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static int layer_overwrite_v2(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int out_count = 0;
    int i = 0;

    while (i < n_ops) {
        int can_merge = 0;
        if (i + 1 < n_ops
            && strcmp(ops[i].type, "delete") == 0 && ops[i].code != AD_LAYER_CHAR_NEWLINE
            && strcmp(ops[i+1].type, "insert") == 0 && ops[i+1].code != AD_LAYER_CHAR_NEWLINE
            && ops[i].line == ops[i+1].line
            && ops[i].col == ops[i+1].col) {

            int prev_is_delete_same_pos = 0;
            if (i > 0
                && strcmp(ops[i-1].type, "delete") == 0 && ops[i-1].code != AD_LAYER_CHAR_NEWLINE
                && ops[i-1].line == ops[i].line
                && ops[i-1].col == ops[i].col) {
                prev_is_delete_same_pos = 1;
            }
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

    /* Use shared position-walk instead of the broken one */
    ad_layer_recompute_positions(out, out_count);
    return out_count;
}

int main(void) {
    return ad_layer_run(layer_overwrite_v2);
}
