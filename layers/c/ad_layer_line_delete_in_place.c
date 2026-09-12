/* ad_layer_line_delete_in_place.c — Delete content BEFORE joining lines.
 *
 * When the diff engine deletes multiple consecutive lines, it produces:
 *
 *   delete(line1 chars) → join_lines → delete(line2 chars) → join_lines → ...
 *
 * The join_lines pulls line2's content UP to line1 before it's deleted.
 * Visually, the user sees content jumping up before disappearing.
 *
 * Two algorithms are available, switchable via --mode:
 *
 * --mode batch (default):
 *   Delete ALL content first, THEN join all empty lines.
 *   delete(line1) → delete(line2 at L+1) → join → join → ...
 *   Advantage: fewer visual jumps — all deletions happen in place.
 *
 * --mode interleaved:
 *   Delete each line's content, then immediately join the empty line.
 *   delete(line1) → join → delete(line2 at L+1) → join → ...
 *   Advantage: more incremental — each line disappears completely
 *   before the next is touched.
 *
 * Only matches when content deletes are at col 1 (full line deletion).
 * Partial content at col > 1 is left unchanged.
 *
 * Build: make layers
 * Usage:  ad_layer_line_delete_in_place [--mode batch|interleaved] < ops.tsv
 */
#include "ad_layer_common.h"

static int ldi_mode = 0;  /* 0=batch, 1=interleaved */

static int layer_line_delete_in_place(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;

    Op *work = (Op *)malloc(n_ops * sizeof(Op));
    if (!work && n_ops > 0) { fprintf(stderr, "out of memory\n"); return 0; }
    if (n_ops > 0) memcpy(work, ops, n_ops * sizeof(Op));
    int n_work = n_ops;

    int n_out = 0;
    int i = 0;

    while (i < n_work) {
        /* Pattern 1 (original): join_lines(L) + delete@col1+ + join_lines(L)
         * Pattern 2 (NEW): DELETE(L, col)+ + JOIN_LINES(L) + DELETE(L, col)+
         *   The deletes AFTER the join are on joined content (from line L+1).
         *   Move them to BEFORE the join, with line changed to L+1.
         *   Rule: line MUST NOT BE JOINED to delete the joined part. */

        /* Check Pattern 2: any JOIN_LINES followed by DELETE ops */
        if (strcmp(work[i].type, "join_lines") == 0
            && i + 1 < n_work
            && strcmp(work[i + 1].type, "delete") == 0
            && !ad_layer_is_line_op(&work[i + 1])) {

            int join_line = work[i].line;

            /* Scan forward for all DELETE ops after the join */
            int de = i + 1;
            while (de < n_work
                   && strcmp(work[de].type, "delete") == 0
                   && !ad_layer_is_line_op(&work[de]))
                de++;
            int del_count = de - (i + 1);

            if (del_count > 0 && ldi_mode == 0) {
                /* The col of post-join deletes is relative to the JOINED
                 * line (line L content + line L+1 content). On the original
                 * line L+1, the col is: joined_col - (join_point - 1).
                 * Where join_point = col of first post-join op (the col
                 * where joined content starts). */
                int join_point = work[i + 1].col;
                /* Emit the DELETE ops with line = join_line + 1, col adjusted */
                for (int k = i + 1; k < de && n_out < out_cap; k++) {
                    Op tmp = work[k];
                    tmp.line = join_line + 1;
                    tmp.col = tmp.col - (join_point - 1);
                    if (tmp.col < 1) tmp.col = 1;
                    out[n_out++] = tmp;
                }
                /* Emit the JOIN_LINES (after the deletes) */
                if (n_out < out_cap)
                    out[n_out++] = work[i];

                i = de;  /* skip past the moved deletes */
                continue;
            }
            /* Interleaved mode or no deletes after join — fall through */
        }

        /* Check Pattern 1: join_lines(L) + delete@col1+ + join_lines(L) */
        if (i + 2 < n_work
            && strcmp(work[i].type, "join_lines") == 0) {

            /* Scan forward for content deletes */
            int ce = i + 1;
            while (ce < n_work
                   && strcmp(work[ce].type, "delete") == 0
                   && !ad_layer_is_line_op(&work[ce]))
                ce++;

            /* Check: trailing join_lines? */
            if (ce > i + 1  /* at least one content delete */
                && ce < n_work
                && strcmp(work[ce].type, "join_lines") == 0) {

                /* Only reorder if content deletes start at col 1 */
                int content_col = work[i + 1].col;
                if (content_col != 1) {
                    /* Partial content — don't reorder */
                    if (n_out < out_cap)
                        out[n_out++] = work[i];
                    i++;
                    continue;
                }

                int joiner_line = work[i].line;
                int content_count = ce - (i + 1);

                if (ldi_mode == 0) {
                    /* ── Batch mode ──
                     * Emit content deletes at line+1, then join at line+1.
                     * The joiner stays for re-iteration (may match again).
                     * Result: all content deleted first, then all joins. */
                    for (int k = i + 1; k < ce && n_out < out_cap; k++) {
                        Op tmp = work[k];
                        tmp.line = joiner_line + 1;
                        out[n_out++] = tmp;
                    }
                    if (n_out < out_cap) {
                        Op tmp = work[ce];
                        tmp.line = joiner_line + 1;
                        out[n_out++] = tmp;
                    }

                    /* Remove content + 2nd join from work, keep joiner */
                    int removed = content_count + 1;
                    int src = ce + 1;
                    int dst = i + 1;
                    int to_move = n_work - src;
                    if (to_move > 0)
                        memmove(&work[dst], &work[src], to_move * sizeof(Op));
                    n_work -= removed;

                    continue;  /* re-iterate at joiner */

                } else {
                    /* ── Interleaved mode ──
                     * Don't reorder — emit as-is. This is algorithm B:
                     * delete content → join → delete next content → join.
                     * The join happens after each line's content is deleted,
                     * so the join only moves an empty line. The next line's
                     * content is then at the current line and gets deleted
                     * there. This is what the diff engine already produces. */
                    if (n_out < out_cap)
                        out[n_out++] = work[i];
                    i++;
                    continue;
                }
            }
        }

        /* No match — emit unchanged */
        if (n_out < out_cap)
            out[n_out++] = work[i];
        i++;
    }

    free(work);
    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            i++;
            if (strcmp(argv[i], "interleaved") == 0)
                ldi_mode = 1;
            else
                ldi_mode = 0;  /* batch (default) */
        } else if (strncmp(argv[i], "--mode=", 7) == 0) {
            if (strcmp(argv[i] + 7, "interleaved") == 0)
                ldi_mode = 1;
            else
                ldi_mode = 0;
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_line_delete_in_place — delete content before joining lines\n\n"
                "Usage: ad_layer_line_delete_in_place [--mode batch|interleaved] < ops.tsv\n\n"
                "Options:\n"
                "  --mode batch        Delete all content first, then join all (default)\n"
                "  --mode interleaved  Delete each line then immediately join\n"
                "  --help, -h          Show this help\n\n"
                "Pattern: join_lines(L) + delete(content at col 1) + join_lines(L)\n"
                "Only matches full-line deletions (col 1). Partial content at col > 1\n"
                "is left unchanged.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_line_delete_in_place);
}
