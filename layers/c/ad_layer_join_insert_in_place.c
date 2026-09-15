/* ad_layer_join_insert_in_place.c — Move inserts AFTER a join.
 *
 * Handles the pattern:
 *   join_lines(L) + insert(L, col 1, chars)+ + [keep(L, ...) | delete(L, ...)]*
 *
 * The join pulls old content up to line L. Then inserts are typed at
 * col 1 — in front of the old content. The user sees the new text
 * concatenated with the old text ("@dataclass DataProcessor:").
 *
 * This layer reorders to:
 *   insert(L+1, col 1, chars)+ + [keep(L+1, ...) | delete(L+1, ...)]* + join_lines(L)
 *
 * The inserts and deletes now happen on line L+1 (where the content
 * originally was, before the join). The join happens AFTER — it joins
 * the (empty) line L with the (modified) line L+1. No concatenation.
 *
 * Only matches when there are inserts at col 1 after the join. If the
 * ops after the join are only keeps and deletes (no inserts), the join
 * is needed to bring the content to the right position — don't reorder.
 *
 * Build: make layers
 * Usage:  ad_layer_join_insert_in_place < ops.tsv
 */
#include "ad_layer_common.h"

static int layer_join_insert_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Pattern: join_lines(L) + insert(L, col 1, ...) + ... */
        if (strcmp(ops[i].type, "join_lines") == 0
            && i + 1 < n_ops
            && strcmp(ops[i + 1].type, "insert") == 0
            && ops[i + 1].col == 1
            && ops[i + 1].line == ops[i].line) {

            int join_line = ops[i].line;

            /* Scan forward for all ops on the same line until a
             * line boundary (join_lines, keep_line, split_line,
             * delete_line, batch_insert) or end of ops. */
            int end = i + 1;
            while (end < n_ops
                   && ops[end].line == join_line
                   && !ad_layer_is_line_op(&ops[end])) {
                end++;
            }

            /* Check: are there inserts at col 1 in this range? */
            int has_inserts_at_col1 = 0;
            for (int k = i + 1; k < end; k++) {
                if (strcmp(ops[k].type, "insert") == 0 && ops[k].col == 1) {
                    has_inserts_at_col1 = 1;
                    break;
                }
            }

            if (has_inserts_at_col1) {
                debug_log("Pattern: join_lines(%d) + inserts at col 1, %d ops to move\n",
                          join_line, end - (i + 1));

                /* Emit all ops (inserts, keeps, deletes) with line changed
                 * from join_line to join_line + 1. Col stays the same. */
                for (int k = i + 1; k < end; k++) {
                    Op tmp = ops[k];
                    tmp.line = join_line + 1;
                    if (n_out < out_cap)
                        out[n_out++] = tmp;
                }

                /* Emit the join_lines AFTER the ops */
                if (n_out < out_cap)
                    out[n_out++] = ops[i];  /* join_lines(L) — line stays L */

                debug_log("Reorder: moved %d ops to line %d, join after\n",
                          end - (i + 1), join_line + 1);

                i = end;  /* skip past the moved ops */
                continue;
            }
            /* No inserts at col 1 — don't reorder, emit as-is */
        }

        /* No match — emit unchanged */
        if (n_out < out_cap)
            out[n_out++] = ops[i];
        i++;
    }

    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--debug") == 0) {
            ad_layer_debug = 1;
            continue;
        }
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_join_insert_in_place — move inserts after a join\n\n"
                "Usage: ad_layer_join_insert_in_place < ops.tsv\n\n"
                "Reorders: join_lines(L) + insert(L,col1)+ + [keep|delete](L,...)\n"
                "      to: insert(L+1,col1)+ + [keep|delete](L+1,...) + join_lines(L)\n\n"
                "The join pulls old content up to line L, then inserts are typed\n"
                "at col 1 — in front of the old content (concatenation). This\n"
                "layer moves the join to AFTER the inserts, so inserts happen on\n"
                "the original line (L+1), then the join joins the empty line L\n"
                "with the modified line L+1. No concatenation.\n\n"
                "Only matches when there are inserts at col 1 after the join.\n"
                "  --debug   Log pattern matches to stderr.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_join_insert_in_place);
}
