/* ad_layer_overwrite.c — merge delete+insert runs into overwrite_insert.
 *
 * Contract: a maximal run of N non-line-op deletes at (L, C) immediately
 * followed by a maximal run of M non-line-op inserts starting at (L, C)
 * and advancing by 1 col each is rewritten as:
 *
 *     min(N, M) overwrite_insert ops   (using the first min(N, M) insert codes)
 *     |N - M| leftover delete ops      (if N > M, from the tail of the delete run)
 *     |N - M| leftover insert ops      (if M > N, from the tail of the insert run)
 *
 * This is "Option C" from docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md §4.2.
 * It supersedes the previous "Option A" behaviour (single-pair merge only),
 * which left middle-of-run deletes unmerged and produced
 * backspace+retype flicker on multi-char replacements like hello->greet.
 *
 * Operates ONLY on non-line-op deletes/inserts — line ops (keep_line,
 * join_lines, split_line, delete_line, batch_insert) are passed through
 * untouched and act as run boundaries.
 *
 * Position handling:
 *   - For non-\n ops: recompute (current_line, current_col) based on
 *     keeps/inserts/overwrite_inserts advancing the cursor.
 *   - For \n ops: KEEP original position. Never touch.
 *   This mirrors the Perl twin so the two produce byte-identical output.
 */
#include "ad_layer_common.h"

static int layer_overwrite(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int out_count = 0;
    int i = 0;

    while (i < n_ops) {
        /* Detect start of a potential merge run: a non-line-op delete. */
        if (strcmp(ops[i].type, "delete") == 0 && !ad_layer_is_line_op(&ops[i])) {
            int L = ops[i].line;
            int C = ops[i].col;

            /* Scan maximal run of non-line-op deletes at (L, C). */
            int del_start = i;
            int del_end = i;
            while (del_end < n_ops
                   && strcmp(ops[del_end].type, "delete") == 0
                   && !ad_layer_is_line_op(&ops[del_end])
                   && ops[del_end].line == L
                   && ops[del_end].col == C) {
                del_end++;
            }
            int N = del_end - del_start;

            /* Scan maximal run of non-line-op inserts starting at (L, C)
             * and advancing by 1 col each subsequent insert. The first
             * insert must be at (L, C) — same position as the deletes. */
            int ins_start = del_end;
            int ins_end = ins_start;
            int expected_col = C;
            while (ins_end < n_ops
                   && strcmp(ops[ins_end].type, "insert") == 0
                   && !ad_layer_is_line_op(&ops[ins_end])
                   && ops[ins_end].line == L
                   && ops[ins_end].col == expected_col) {
                expected_col++;
                ins_end++;
            }
            int M = ins_end - ins_start;

            if (M > 0) {
                /* Run-level merge. Emit min(N, M) overwrite_insert ops using
                 * the first min(N, M) insert codes/positions. */
                int k = (N < M) ? N : M;
                for (int j = 0; j < k; j++) {
                    if (out_count < out_cap) {
                        strncpy(out[out_count].type, "overwrite_insert",
                                AD_LAYER_TYPE_LEN - 1);
                        out[out_count].type[AD_LAYER_TYPE_LEN - 1] = 0;
                        out[out_count].code = ops[ins_start + j].code;
                        out[out_count].line = ops[ins_start + j].line;
                        out[out_count].col  = ops[ins_start + j].col;
                        out[out_count].text = NULL;
                        out_count++;
                    }
                }
                /* Leftover deletes (N > M): the last N-M deletes from the
                 * delete run are unpaired. Emit them unchanged. */
                for (int j = k; j < N; j++) {
                    if (out_count < out_cap) out[out_count++] = ops[del_start + j];
                }
                /* Leftover inserts (M > N): the last M-N inserts from the
                 * insert run are unpaired. Emit them unchanged. */
                for (int j = k; j < M; j++) {
                    if (out_count < out_cap) out[out_count++] = ops[ins_start + j];
                }
                i = ins_end;
                continue;
            }

            /* M == 0: deletes with no following inserts at the same (L, C).
             * Pass all N deletes through unchanged. */
            for (int j = del_start; j < del_end; j++) {
                if (out_count < out_cap) out[out_count++] = ops[j];
            }
            i = del_end;
            continue;
        }

        /* Default: pass the op through unchanged. */
        if (out_count < out_cap) out[out_count++] = ops[i];
        i++;
    }

    /* ── Position walk ──
     * Recompute (line, col) on the output so leftover deletes/inserts
     * land at the correct cursor position after the overwrite_inserts
     * that preceded them. Mirrors the Perl twin exactly:
     *   - non-\n op: assign (current_line, current_col); advance col
     *     for keep / insert / overwrite_insert.
     *   - \n op: KEEP original position; reset (current_line, current_col)
     *     to (original_line + 1, 1) for the next iteration.
     *   - line op: KEEP original position but UPDATE current_line/
     *     current_col so subsequent non-line ops get the right position:
     *     keep_line L, split_line L C, insert_line L → line L+1, col 1
     *     join_lines L → stays on line L (content joined, col unchanged)
     *     delete_line L → stays (line removed, lines shift up)
     *     batch_insert L C → col advances (rare, approximated)
     */
    if (out_count > 0) {
        int current_line = out[0].line;
        int current_col = 1;
        for (int j = 0; j < out_count; j++) {
            if (ad_layer_is_debug_op(&out[j])) continue;
            if (ad_layer_is_line_op(&out[j])) {
                /* Update cursor for subsequent ops but don't touch
                 * the line op's own position. */
                if (strcmp(out[j].type, "keep_line") == 0
                    || strcmp(out[j].type, "split_line") == 0
                    || strcmp(out[j].type, "insert_line") == 0) {
                    current_line = out[j].line + 1;
                    current_col = 1;
                } else if (strcmp(out[j].type, "join_lines") == 0) {
                    /* Join: cursor stays on the joined line. */
                    current_line = out[j].line;
                    /* col stays — content is appended at current col. */
                } else if (strcmp(out[j].type, "delete_line") == 0) {
                    /* Delete: cursor stays (lines shift up). */
                    /* current_line stays. */
                }
                /* batch_insert: col advances — approximated, not exact. */
                continue;
            }

            int is_newline_op = (out[j].code == AD_LAYER_CHAR_NEWLINE);

            if (!is_newline_op) {
                out[j].line = current_line;
                out[j].col = current_col;
                if (strcmp(out[j].type, "keep") == 0
                    || strcmp(out[j].type, "insert") == 0
                    || strcmp(out[j].type, "overwrite_insert") == 0) {
                    current_col++;
                }
            } else {
                /* \n op: KEEP original position. Don't touch. */
                current_line = out[j].line + 1;
                current_col = 1;
            }
        }
    }

    return out_count;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_overwrite);
}
