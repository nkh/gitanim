/* ad_layer_reorder_v3.c — Reorder with merged \n delete remapping.
 *
 * Combines reorder's 4-sweep with v7's line/col remapping.
 * After the 4-sweep, instead of a simple position walk, uses
 * buf_line[] and col_shift[] to correctly remap positions for
 * BOTH \n deletes (join) and \n inserts (split).
 *
 * NOT added to git — experimental clone for testing.
 */
#include "ad_layer_common.h"

static int layer_reorder_v3(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    int out_count = 0, segment_start = 0;

    /* Pass 1: 4-sweep within segments */
    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i]))
            if (strcmp(ops[i].type, "keep") == 0 || ops[i].code == AD_LAYER_CHAR_NEWLINE)
                is_boundary = 1;

        if (is_boundary) {
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "delete") == 0 &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            for (int j = segment_start; j < i; j++)
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    (strcmp(ops[j].type, "insert") == 0 ||
                     strcmp(ops[j].type, "overwrite_insert") == 0) &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE && out_count < out_cap)
                    out[out_count++] = ops[j];
            for (int j = segment_start; j < i; j++)
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* Pass 2: position remap using buf_line and col_shift */
    if (out_count > 0) {
        int max_line = 0;
        for (int i = 0; i < out_count; i++)
            if (out[i].line > max_line) max_line = out[i].line;
        int sz = max_line + 2;

        int *buf_line  = (int *)malloc(sz * sizeof(int));
        int *col_shift = (int *)calloc(sz, sizeof(int));
        if (!buf_line || !col_shift) {
            free(buf_line); free(col_shift);
            /* Fallback: simple walk */
            int cl = out[0].line, cc = 1;
            for (int i = 0; i < out_count; i++) {
                if (ad_layer_is_debug_op(&out[i])) continue;
                int is_nl = (out[i].code == AD_LAYER_CHAR_NEWLINE);
                if (!is_nl) {
                    out[i].line = cl; out[i].col = cc;
                    if (strcmp(out[i].type, "keep") == 0
                        || strcmp(out[i].type, "insert") == 0
                        || strcmp(out[i].type, "overwrite_insert") == 0) cc++;
                } else {
                    out[i].line = cl; out[i].col = cc;
                    if (strcmp(out[i].type, "delete") != 0) { cl++; cc = 1; }
                }
            }
        } else {
            for (int i = 0; i < sz; i++) buf_line[i] = i;

            for (int i = 0; i < out_count; i++) {
                if (ad_layer_is_debug_op(&out[i])) continue;

                int orig_line = out[i].line;
                int orig_col  = out[i].col;
                if (orig_line < 1) orig_line = 1;
                if (orig_line >= sz) orig_line = sz - 1;

                /* Compute new position */
                out[i].line = buf_line[orig_line];
                out[i].col  = orig_col + col_shift[orig_line];

                /* Update state on \n delete (join) */
                if (strcmp(out[i].type, "delete") == 0
                    && out[i].code == AD_LAYER_CHAR_NEWLINE) {
                    int join_point = orig_col + col_shift[orig_line];
                    int target_buf = buf_line[orig_line];
                    int next = orig_line + 1;
                    if (next < sz) {
                        int absorbed_buf = buf_line[next];
                        for (int j = 1; j < sz; j++) {
                            if (buf_line[j] == absorbed_buf) {
                                buf_line[j] = target_buf;
                                col_shift[j] += (join_point - 1);
                            }
                        }
                    }
                }

                /* Update state on \n insert (split) */
                if ((strcmp(out[i].type, "insert") == 0
                     || strcmp(out[i].type, "overwrite_insert") == 0)
                    && out[i].code == AD_LAYER_CHAR_NEWLINE) {
                    int split_buf = buf_line[orig_line];
                    for (int j = 1; j < sz; j++) {
                        if (buf_line[j] > split_buf) buf_line[j]++;
                    }
                }
            }

            free(buf_line);
            free(col_shift);
        }
    }

    /* Update line_offset */
    int ni = 0, nd = 0;
    for (int j = 0; j < out_count; j++) {
        if (strcmp(out[j].type, "insert") == 0 && out[j].code == AD_LAYER_CHAR_NEWLINE) ni++;
        if (strcmp(out[j].type, "delete") == 0 && out[j].code == AD_LAYER_CHAR_NEWLINE) nd++;
    }
    *line_offset += ni - nd;

    return out_count;
}

int main(void) {
    return ad_layer_run(layer_reorder_v3);
}
