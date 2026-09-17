/* ad_layer_line_delete_in_place.c — Delete content BEFORE joining lines.
 *
 * When the diff engine deletes multiple consecutive lines, it produces:
 *
 *   delete(line1 chars) -> join_lines -> delete(line2 chars) -> join_lines -> ...
 *
 * The join_lines pulls line2's content UP to line1 before it's deleted.
 * Visually, the user sees content jumping up before disappearing.
 *
 * Two algorithms are available, switchable via --mode:
 *
 * --mode batch (default):
 *   Delete ALL content first, THEN join all empty lines.
 *   delete(line1) -> delete(line2 at L+1) -> delete(line3 at L+2) ->
 *   ... -> join -> join -> ...
 *   The content deletes for line N are emitted at line L+N-1 (their
 *   original pre-join position). All joins are deferred to the end
 *   of the block so the user sees content shrink-to-empty in place
 *   first, then lines collapse upward.
 *
 * --mode interleaved:
 *   Delete each line's content, then immediately join the empty line.
 *   delete(line1) -> join -> delete(line2 at L+1) -> join -> ...
 *   Advantage: more incremental — each line disappears completely
 *   before the next is touched.
 *
 * Sliding-window algorithm (Phase 2 fix, handles arbitrary N lines):
 *   Walk the ops. When a `join_lines(L)` is followed by content
 *   deletes at col 1, start a block. Within the block, a 2-line
 *   window [join + delete@col1+] is matched repeatedly. Each match:
 *     - Emits the content deletes at L + 1 + offset (offset = number
 *       of content batches already emitted in this block).
 *     - Defers the join to a pending list.
 *     - Advances offset by 1.
 *   When the block ends (no more join+delete pattern, or a trailing
 *   join with no content), all pending joins are emitted at the end.
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
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Check: is work[i] a join_lines followed by content deletes?
         * This is the start of a potential multi-line block. */
        if (strcmp(ops[i].type, "join_lines") == 0
            && i + 1 < n_ops
            && strcmp(ops[i + 1].type, "delete") == 0
            && !ad_layer_is_line_op(&ops[i + 1])
            && ops[i + 1].col == 1) {

            /* ── Sliding-window block ──
             * Collect content deletes and joins. Emit content first,
             * defer joins to the end of the block. */
            int line_off = 0;  /* number of content batches emitted so far */

            /* Collect joins in a local array (max reasonable block size). */
            Op pending_joins[4096];
            int n_pending = 0;

            int j = i;
            while (j < n_ops && strcmp(ops[j].type, "join_lines") == 0) {
                int join_line = ops[j].line;

                    /* Scan content deletes after this join. The FIRST delete
                 * must be at col 1 (full-line deletion, not partial).
                 * Subsequent deletes can be at any col (they're the rest
                 * of the line's content). */
                int ce = j + 1;
                if (ce < n_ops
                    && strcmp(ops[ce].type, "delete") == 0
                    && !ad_layer_is_line_op(&ops[ce])
                    && ops[ce].col == 1) {
                    ce++;
                    while (ce < n_ops
                           && strcmp(ops[ce].type, "delete") == 0
                           && !ad_layer_is_line_op(&ops[ce]))
                        ce++;
                }

                if (ce > j + 1) {
                    /* Content deletes found (first at col 1).
                     * Emit at join_line + 1 + line_off. */
                    for (int k = j + 1; k < ce && n_out < out_cap; k++) {
                        Op tmp = ops[k];
                        tmp.line = join_line + 1 + line_off;
                        out[n_out++] = tmp;
                    }
                    /* Save the join for deferred emission. */
                    if (n_pending < 4096)
                        pending_joins[n_pending++] = ops[j];
                    line_off++;
                    j = ce;  /* advance past content deletes */
                } else {
                    /* No content deletes after this join — trailing join.
                     * Save it and end the block. */
                    if (n_pending < 4096)
                        pending_joins[n_pending++] = ops[j];
                    j++;
                    break;  /* end of block */
                }
            }

            /* Emit all pending joins (at their original lines). */
            for (int k = 0; k < n_pending && n_out < out_cap; k++)
                out[n_out++] = pending_joins[k];

            i = j;
            continue;
        }

        /* No match — emit unchanged */
        if (n_out < out_cap)
            out[n_out++] = ops[i];
        i++;
    }

    return n_out;
}

/* Interleaved mode pass-through: emit ops unchanged. */
static int layer_passthrough(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n = (n_ops < out_cap) ? n_ops : out_cap;
    for (int i = 0; i < n; i++)
        out[i] = ops[i];
    return n;
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
                "Pattern: join_lines(L) + delete(content at col 1) + join_lines(L) + ...\n"
                "Handles arbitrary N-line deletions via a sliding 2-line window.\n"
                "Only matches full-line deletions (col 1). Partial content at col > 1\n"
                "is left unchanged.\n");
            return 0;
        }
    }

    if (ldi_mode == 1)
        return ad_layer_run(layer_passthrough);

    return ad_layer_run(layer_line_delete_in_place);
}
