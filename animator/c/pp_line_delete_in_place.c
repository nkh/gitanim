/*
 * pp_layer_line_delete_in_place.c — Transform Layer: Line-Delete-In-Place
 *
 * Purpose:
 *   When a line is fully deleted (all content + \n), ensure its content
 *   is deleted on its OWN line, not after a join with the previous line.
 *
 *   This prevents the "join then delete" visual where line B's content
 *   briefly appears on line A before being deleted.
 *
 *   ALWAYS RUNS (not optional).
 *
 * Algorithm:
 *
 *   1. PRE-PASS: Scan all ops to identify which lines are FULLY DELETED.
 *      A line is fully deleted if ALL its ops are deletes (no keeps,
 *      no inserts, no overwrite_inserts).
 *
 *   2. MAIN PASS: Walk ops. When we find a \n delete on line N that is
 *      a JOIN (line N has content ops before the \n delete) AND line N+1
 *      is fully deleted:
 *        - Move line N+1's content deletes BEFORE the \n delete on line N
 *        - Move line N+1's \n delete BEFORE the \n delete on line N
 *        - Keep the join \n delete (line N) AFTER them
 *
 *   This handles any number of consecutive fully-deleted lines.
 *
 * Example:
 *
 *   Old:          New:
 *   A             AC
 *   B
 *   C
 *
 *   Raw ops:
 *     keep (1,1) 'A'
 *     delete (1,2) \n      ← join A+B
 *     delete (2,1) 'B'     ← B content
 *     delete (2,1) \n      ← B's \n
 *     keep (3,1) 'C'
 *
 *   Pre-pass: line 2 is fully deleted (only deletes).
 *
 *   After this layer:
 *     keep (1,1) 'A'
 *     delete (2,1) 'B'     ← B content FIRST (on line 2)
 *     delete (2,1) \n      ← B's \n (empty line removed)
 *     delete (1,2) \n      ← join A+C (A's \n deleted, C moves up)
 *     keep (2,1) 'C'
 */

#include "pp_common.h"

/* Check if a line is fully deleted: all ops are deletes, no keeps/inserts.
 * Returns 1 if fully deleted, 0 otherwise. */
static int is_line_fully_deleted(Op *ops, int n_ops, int line) {
    int has_delete = 0;
    int has_content = 0;  /* keep/insert/overwrite_insert */

    for (int i = 0; i < n_ops; i++) {
        if (ops[i].line != line) continue;
        if (pp_is_debug_op(&ops[i])) continue;

        if (strcmp(ops[i].type, "delete") == 0) {
            has_delete = 1;
        } else {
            has_content = 1;
        }
    }

    /* Fully deleted: has at least one delete and no content ops */
    return has_delete && !has_content;
}

int layer_line_delete_in_place(Op *in, int in_count, Op *out, int out_cap,
                                const char *old_file) {
    (void)old_file;

    int n_out = 0;

    pp_logf("line-delete-in-place: %d input ops", in_count);

    /* PRE-PASS: Find the max line number to know how many lines exist */
    int max_line = 0;
    for (int i = 0; i < in_count; i++) {
        if (in[i].line > max_line) max_line = in[i].line;
    }

    /* PRE-PASS: Mark which lines are fully deleted */
    /* Use a dynamically allocated array */
    int *fully_deleted = (int *)calloc(max_line + 2, sizeof(int));
    if (!fully_deleted) {
        /* Fallback: copy as-is */
        int n = in_count < out_cap ? in_count : out_cap;
        memcpy(out, in, n * sizeof(Op));
        return n;
    }

    for (int line = 1; line <= max_line; line++) {
        fully_deleted[line] = is_line_fully_deleted(in, in_count, line);
    }

    /* MAIN PASS: Walk ops and reorder */
    int i = 0;
    while (i < in_count) {
        /* Look for pattern: \n delete on line N (join) followed by
         * content on line N+1 which is fully deleted. */
        if (i + 1 < in_count &&
            strcmp(in[i].type, "delete") == 0 && in[i].code == 10 &&
            in[i + 1].line == in[i].line + 1 &&
            fully_deleted[in[i + 1].line]) {

            int join_line = in[i].line;
            int deleted_line = join_line + 1;

            /* Check if the \n delete on line N is a JOIN:
             * look backwards for content ops on the same line. */
            int is_join = 0;
            for (int k = i - 1; k >= 0; k--) {
                if (in[k].line != join_line) break;
                if (pp_is_debug_op(&in[k])) continue;
                if (strcmp(in[k].type, "keep") == 0 ||
                    strcmp(in[k].type, "insert") == 0 ||
                    strcmp(in[k].type, "overwrite_insert") == 0) {
                    is_join = 1;
                    break;
                }
                if (in[k].code == 10) break;
            }

            if (is_join) {
                /* Find all ops on the deleted line */
                int del_start = i + 1;
                int del_end = del_start;
                while (del_end < in_count && in[del_end].line == deleted_line) {
                    del_end++;
                }

                /* Emit the deleted line's ops FIRST (content + \n) */
                for (int k = del_start; k < del_end; k++) {
                    if (n_out < out_cap) {
                        out[n_out++] = in[k];
                    }
                }

                /* Emit the join \n delete LAST */
                if (n_out < out_cap) {
                    out[n_out++] = in[i];
                }

                pp_logf("line-delete-in-place: moved line %d ops before "
                        "join on line %d", deleted_line, join_line);

                i = del_end;
                continue;
            }
        }

        /* No pattern matched — pass through */
        if (n_out < out_cap) {
            out[n_out++] = in[i];
        }
        i++;
    }

    free(fully_deleted);
    pp_logf("line-delete-in-place: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L_line_delete_in_place", "Line-Delete-In-Place");
    return pp_run_layer(layer_line_delete_in_place);
}
#endif
