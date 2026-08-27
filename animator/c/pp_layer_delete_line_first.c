/*
 * pp_layer_delete_line_first.c — Transform Layer: Delete-Line-Content-First
 *
 * Purpose:
 *   When a line is fully deleted (content + \n) and the PREVIOUS line's
 *   \n is also deleted (to join), reorder so the deleted line's content
 *   is removed BEFORE the join happens.
 *
 *   This prevents the "join then delete" visual where line B's content
 *   briefly appears on line A before being deleted.
 *
 *   ALWAYS RUNS (not optional).
 *
 * Example:
 *
 *   Old:          New:
 *   A             AC
 *   B
 *   C
 *
 *   Raw ops (from compute):
 *     keep (1,1) 'A'
 *     delete (1,2) \n      ← join A+B (A's \n deleted)
 *     delete (2,1) 'B'     ← delete B content (now on line 1!)
 *     delete (2,1) \n      ← delete B's \n
 *     keep (3,1) 'C'
 *
 *   After this layer:
 *     keep (1,1) 'A'
 *     delete (2,1) 'B'     ← delete B content FIRST (on line 2)
 *     delete (2,1) \n      ← delete B's \n (empty line removed)
 *     delete (1,2) \n      ← join A with C (A's \n deleted, C moves up)
 *     keep (2,1) 'C'
 *
 *   Now the animation shows: B's content vanishes on line 2, then
 *   line 2 is removed, then A and C join. No "B appears on line A".
 *
 * Algorithm:
 *
 *   Walk ops. Look for pattern:
 *     1. \n delete on line N (the join)
 *     2. Content deletes on line N+1 (the deleted line's content)
 *     3. \n delete on line N+1 (the deleted line's \n)
 *
 *   When found:
 *     - Move the content deletes (step 2) BEFORE the join \n delete (step 1)
 *     - Move the \n delete on line N+1 (step 3) BEFORE the join \n delete
 *     - Keep the join \n delete (step 1) after them
 *
 *   This works for any number of consecutive line deletions.
 */

#include "pp_common.h"

int layer_delete_line_first(Op *in, int in_count, Op *out, int out_cap,
                             const char *old_file) {
    (void)old_file;

    int n_out = 0;

    pp_logf("delete-line-content-first: %d input ops", in_count);

    int i = 0;
    while (i < in_count) {
        /* Look for pattern: \n delete on line N, followed by content
         * deletes on line N+1, followed by \n delete on line N+1.
         *
         * BUT: only match if the \n delete on line N is a JOIN — meaning
         * there are content ops (keeps/inserts) on line N BEFORE the \n
         * delete. If line N only has deletes (content + \n), it's a full
         * line deletion, not a join — don't reorder. */
        if (i + 2 < in_count &&
            strcmp(in[i].type, "delete") == 0 && in[i].code == 10 &&
            strcmp(in[i+1].type, "delete") == 0 && in[i+1].code != 10 &&
            in[i+1].line == in[i].line + 1) {

            int join_line = in[i].line;
            int deleted_line = join_line + 1;

            /* Check if the \n delete on line N is a JOIN:
             * look backwards for content ops (keep/insert) on the same line.
             * If found, it's a join. If only deletes, it's a full deletion. */
            int is_join = 0;
            for (int k = i - 1; k >= 0; k--) {
                if (in[k].line != join_line) break;
                if (strcmp(in[k].type, "keep") == 0 ||
                    strcmp(in[k].type, "insert") == 0 ||
                    strcmp(in[k].type, "overwrite_insert") == 0) {
                    is_join = 1;
                    break;
                }
                /* If we hit a \n op, we've gone past the line start */
                if (in[k].code == 10) break;
            }

            if (!is_join) {
                /* Not a join — pass through unchanged */
                if (n_out < out_cap) {
                    out[n_out++] = in[i];
                }
                i++;
                continue;
            }

            /* Find the end of content deletes on the deleted line */
            int content_start = i + 1;
            int content_end = i + 1;  /* exclusive */
            while (content_end < in_count &&
                   strcmp(in[content_end].type, "delete") == 0 &&
                   in[content_end].code != 10 &&
                   in[content_end].line == deleted_line) {
                content_end++;
            }

            /* Check if there's a \n delete on the deleted line after content */
            if (content_end < in_count &&
                strcmp(in[content_end].type, "delete") == 0 &&
                in[content_end].code == 10 &&
                in[content_end].line == deleted_line) {

                /* Pattern matched! Reorder:
                 *   Emit content deletes (line N+1) FIRST
                 *   Emit \n delete on line N+1 (the deleted line's \n)
                 *   Then emit the join \n delete (line N)
                 */
                int nl_delete_idx = content_end;

                /* Emit content deletes first */
                for (int k = content_start; k < content_end; k++) {
                    if (n_out < out_cap) {
                        out[n_out++] = in[k];
                    }
                }
                /* Emit the \n delete on the deleted line */
                if (n_out < out_cap) {
                    out[n_out++] = in[nl_delete_idx];
                }
                /* Emit the join \n delete LAST */
                if (n_out < out_cap) {
                    out[n_out++] = in[i];
                }

                pp_logf("delete-line-content-first: reordered line %d delete "
                        "before join on line %d (%d content + \\n)",
                        deleted_line, join_line,
                        content_end - content_start);

                /* Skip past the entire pattern */
                i = nl_delete_idx + 1;
                continue;
            }
        }

        /* No pattern matched — pass through */
        if (n_out < out_cap) {
            out[n_out++] = in[i];
        }
        i++;
    }

    pp_logf("delete-line-content-first: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L_delete_line_first", "Delete-Line-Content-First");
    return pp_run_layer(layer_delete_line_first);
}
#endif
