/* ad_layer_split_in_place.c — Insert content AFTER splitting lines.
 *
 * Symmetric of ad_layer_line_delete_in_place.
 *
 * When the diff engine expands one old line into N new lines, it may
 * produce the pattern:
 *
 *   insert(line L, col 1, chars) → split_line(L, col K)
 *
 * where K = number of inserted chars + 1. Visually, the inserted text
 * and the old line's content are momentarily concatenated on line L
 * before the split separates them. The user sees the old content
 * briefly "joined" to the new content, then "moved" to line L+1.
 *
 * This layer reorders the pattern to:
 *
 *   split_line(L, col 1) → insert(line L, col 1, chars)
 *
 * so the split happens FIRST (creating an empty line L, with the old
 * content moving to line L+1), then the inserts fill the empty line L.
 * No concatenation.
 *
 * The layer also handles chained patterns: when N new lines are inserted
 * between two old lines, the diff engine produces
 *
 *   insert(L, col 1, chars) → split_line(L, K)
 *   → split_line(L+1, K')        ← already in good order
 *   → insert(L+2, col 1, chars)  ← already in good order
 *   → ...
 *
 * The first (insert + split) pair is reordered; the rest are already
 * in good order (split first, then insert on the new empty line).
 *
 * Only matches when inserts start at col 1 (full-line insertions).
 * Partial content at col > 1 is left unchanged.
 *
 * Build: make layers
 * Usage:  ad_layer_split_in_place < ops.tsv
 */
#include "ad_layer_common.h"

static int layer_split_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;

    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Pattern: insert(line L, col 1, chars)+ + split_line(L, K)
         * where K = (number of inserts) + 1.
         *
         * The split col K = (count of inserts at col 1 on line L) + 1
         * because each insert at col c advances the next col to c+1,
         * so after N inserts starting at col 1, the cursor is at col N+1,
         * and the split happens there.
         *
         * We only reorder if the inserts START at col 1 (full-line
         * insertion). The col 1 check is on the FIRST insert in the run.
         */
        if (i + 1 < n_ops
            && strcmp(ops[i].type, "insert") == 0
            && ops[i].col == 1) {

            /* Scan forward for consecutive inserts on the same line */
            int ie = i;
            int insert_line = ops[i].line;
            while (ie < n_ops
                   && strcmp(ops[ie].type, "insert") == 0
                   && ops[ie].line == insert_line
                   && ops[ie].col == (ie - i) + 1) {
                ie++;
            }
            int insert_count = ie - i;

            /* Check: trailing split_line on the same line? */
            if (insert_count > 0
                && ie < n_ops
                && strcmp(ops[ie].type, "split_line") == 0
                && ops[ie].line == insert_line
                && ops[ie].col == insert_count + 1) {

                /* Only reorder if there IS old content on the line that
                 * would get concatenated with the inserts. We detect this
                 * by checking if the op AFTER the split_line is a `keep`
                 * on line L+1 (the pushed old content). If the next op is
                 * an `insert` or `split_line` (at col 1), the line was
                 * empty — no old content, no concatenation, skip. */
                int has_old_content = 0;
                if (ie + 1 < n_ops) {
                    Op *next = &ops[ie + 1];
                    if (strcmp(next->type, "keep") == 0 && next->line == insert_line + 1)
                        has_old_content = 1;
                    else if (strcmp(next->type, "keep_line") == 0 && next->line == insert_line + 1)
                        has_old_content = 1;
                }

                if (has_old_content) {
                    /* Reorder: emit split_line FIRST (at col 1), then the
                     * inserts (at col 1 on the now-empty line). */
                    Op split_first = ops[ie];
                    split_first.col = 1;
                    if (n_out < out_cap)
                        out[n_out++] = split_first;

                    for (int k = i; k < ie && n_out < out_cap; k++) {
                        out[n_out++] = ops[k];
                    }

                    i = ie + 1;  /* skip the original split_line */
                    continue;
                }
                /* Fall through: no old content, emit unchanged */
            }
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
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_split_in_place — insert content after splitting lines\n\n"
                "Usage: ad_layer_split_in_place < ops.tsv\n\n"
                "Reorders the pattern:\n"
                "  insert(L, col 1, chars)+ + split_line(L, K)\n"
                "to:\n"
                "  split_line(L, col 1) + insert(L, col 1, chars)+\n\n"
                "so the split happens FIRST (creating an empty line L, with\n"
                "the old content moving to line L+1), then the inserts fill\n"
                "the empty line L. Without this reorder, the inserted text and\n"
                "the old content are momentarily concatenated on line L before\n"
                "the split separates them — a visual \"join then move\" artifact.\n\n"
                "Only matches full-line insertions (col 1). Partial content at\n"
                "col > 1 is left unchanged.\n\n"
                "Symmetric of ad_layer_line_delete_in_place.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_split_in_place);
}
