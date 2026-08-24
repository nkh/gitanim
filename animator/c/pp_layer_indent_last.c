/*
 * pp_layer_indent_last.c — Transform Layer: Indentation-Last
 *
 * Purpose:
 *   When deleting a whole line that starts with spaces or tabs
 *   (indentation), defer those indentation deletes to the END of the
 *   line's ops — after all other content is deleted.
 *
 *   This makes the animation look natural: the text content disappears
 *   first (line shrinks from the right), then the indentation is
 *   removed last (the line vanishes). Without this, deleting the
 *   indentation first causes the remaining text to shift left, which
 *   looks jarring.
 *
 * Example:
 *   Line: "    print('hello')"   (4 spaces of indentation)
 *   Ops:  delete ' ', delete ' ', delete ' ', delete ' ',
 *         delete 'p', delete 'r', delete 'i', delete 'n', delete 't', ...
 *
 *   Without indent-last:
 *     delete ' ', delete ' ', delete ' ', delete ' ',     ← indentation first
 *     delete 'p', delete 'r', delete 'i', delete 'n', ... ← content second
 *     Animation: text shifts left by 4, then disappears. Bad.
 *
 *   With indent-last:
 *     delete 'p', delete 'r', delete 'i', delete 'n', ... ← content first
 *     delete ' ', delete ' ', delete ' ', delete ' ',     ← indentation last
 *     Animation: text shrinks from the right, then indentation vanishes. Good.
 *
 * Rules:
 *   1. Only applies to delete ops (not keep or insert).
 *   2. Only applies to spaces (code 32) and tabs (code 9).
 *   3. Only applies to ops at the BEGINNING of a line — the leading
 *      whitespace before any other content. Once we see a non-whitespace
 *      delete, the "leading" phase is over.
 *   4. The deferred indentation deletes are placed just before the
 *      \n delete (if present) or at the end of the line's ops.
 *
 * Line boundaries:
 *   A "line" is defined as a sequence of ops up to (and including)
 *   a \n op, OR a change in the line number between consecutive ops.
 *   This handles cases where \n ops are missing (compute doesn't
 *   always emit them).
 *
 * Trigger:
 *   --indent-last  (env: DV_INDENT_LAST=1)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_indent_last animator/c/pp_layer_indent_last.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=path  →  dumps to $path/L_indent_last_input.txt etc.
 *   DV_OP_DEBUG=1              →  inserts debug ops into the stream
 */

#include "pp_common.h"

static int env_flag(const char *name) {
    const char *v = getenv(name);
    return v && v[0] == '1';
}

/*
 * Layer: Indentation-Last
 *
 * Algorithm:
 *
 *   Walk the ops. Identify "line segments" — each segment is a run of
 *   ops that belong to the same line. A new segment starts when:
 *     - We encounter a \n op (the next op starts a new line)
 *     - The line number changes between two consecutive ops
 *
 *   Within each segment, find the "leading indentation" — a run of
 *   space/tab DELETE ops at the very beginning, before any other op.
 *
 *   Move those leading indentation deletes to the END of the segment
 *   (just before the \n if present, otherwise at the very end).
 *
 *   All other ops (keeps, inserts, non-whitespace deletes, whitespace
 *   deletes that are NOT leading) stay in their original relative order.
 *
 *   Debug ops (type="debug") are transparent — they don't count as
 *   "content" and don't break the leading phase.
 *
 * Parameters:
 *   in        — input Op array
 *   in_count  — number of input ops
 *   out       — output Op array (pre-allocated)
 *   out_cap   — capacity of out array
 *   old_file  — old file path (unused)
 *
 * Returns: number of output ops (always = input count for this layer)
 */
int layer_indent_last(Op *in, int in_count, Op *out, int out_cap,
                      const char *old_file) {
    (void)old_file;

    int op_debug = env_flag("DV_OP_DEBUG");
    int n_out = 0;
    int seg_start = 0;

    pp_logf("Indent-last: %d input ops, op_debug=%s",
            in_count, op_debug ? "on" : "off");

    /* Walk through ops, identifying line segments */
    for (int i = 0; i <= in_count; i++) {
        /* Check if this is a segment boundary */
        int is_boundary = (i == in_count);

        if (i < in_count && i > seg_start) {
            /* Check: \n op ends a segment */
            if (in[i].code == 10 && !pp_is_debug_op(&in[i])) {
                is_boundary = 1;
            }
            /* Check: line number changed between previous and current op */
            if (!pp_is_debug_op(&in[i]) && !pp_is_debug_op(&in[i-1])) {
                if (in[i].line != in[i-1].line) {
                    is_boundary = 1;
                }
            }
        }

        if (is_boundary) {
            /* Process the segment [seg_start, i) */
            int seg_len = i - seg_start;

            if (seg_len > 0 && n_out + seg_len <= out_cap) {
                /* Step 1: Find leading indentation — consecutive space/tab
                 * DELETE ops at the start of the segment, before any
                 * non-whitespace or non-delete op. Skip debug ops. */
                int indent_end = seg_start;
                for (int j = seg_start; j < i; j++) {
                    if (pp_is_debug_op(&in[j])) {
                        continue;  /* debug ops don't break the leading phase */
                    }
                    if (strcmp(in[j].type, "delete") == 0 &&
                        (in[j].code == 32 || in[j].code == 9)) {
                        indent_end = j + 1;  /* still in leading phase */
                    } else {
                        break;  /* hit non-whitespace — leading phase over */
                    }
                }

                int n_indent = indent_end - seg_start;

                if (n_indent == 0) {
                    /* No leading indentation — copy segment as-is */
                    for (int j = seg_start; j < i; j++) {
                        out[n_out++] = in[j];
                    }
                } else {
                    /* Step 2: Find where to insert the deferred indentation.
                     * It goes just before the \n op (if present) or at the end. */

                    /* Find the \n op position (if any) */
                    int nl_pos = -1;
                    for (int j = i - 1; j >= indent_end; j--) {
                        if (!pp_is_debug_op(&in[j]) && in[j].code == 10) {
                            nl_pos = j;
                            break;
                        }
                    }

                    /* Step 3: Rebuild the segment:
                     *   a) Content ops (everything after indentation, before \n)
                     *   b) Indentation ops (the deferred leading whitespace)
                     *   c) \n op (if present) */

                    /* Debug op before the deferred indentation */
                    if (op_debug) {
                        strcpy(out[n_out].type, "debug");
                        out[n_out].code = 0;
                        out[n_out].line = in[seg_start].line;
                        out[n_out].col = in[seg_start].col;
                        n_out++;
                    }

                    /* a) Content: ops from indent_end to end of segment
                     *    (or to \n, excluding \n) */
                    int content_end = (nl_pos >= 0) ? nl_pos : i;
                    for (int j = indent_end; j < content_end; j++) {
                        out[n_out++] = in[j];
                    }

                    /* b) Indentation: the leading whitespace deletes.
                     *
                     * Mark each deferred delete with pos_set=1 and col=1.
                     * Layer 3 will respect this position instead of
                     * computing it from cursor state.
                     *
                     * Why col=1 for ALL deferred deletes (not 1, 2, 3, 4)?
                     *   In the animator's cursor-tracking model, deletes
                     *   don't advance the cursor — chars shift left to fill
                     *   the gap. So after the first delete at col 1, the next
                     *   leading-whitespace char shifts to col 1, and the
                     *   next delete (also at col 1) removes it. All deferred
                     *   deletes are at col 1.
                     *
                     * This requires Layer 3's buffer simulation to find
                     * the content deletes at their actual positions (e.g.,
                     * col 5+ if there are 4 leading spaces), so that the
                     * leading whitespace remains in the buffer when these
                     * deferred deletes execute. */
                    for (int j = seg_start; j < indent_end; j++) {
                        out[n_out] = in[j];
                        out[n_out].col = 1;
                        out[n_out].pos_set = 1;
                        n_out++;
                    }

                    /* c) \n op (if present) */
                    if (nl_pos >= 0) {
                        out[n_out++] = in[nl_pos];
                    }

                    pp_logf("Indent-last: deferred %d leading whitespace "
                            "ops on line %d", n_indent, in[seg_start].line);
                }
            }

            seg_start = i;
        }
    }

    pp_logf("Indent-last: %d ops → %d ops", in_count, n_out);
    return n_out;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L_indent_last", "Indentation-Last");
    return pp_run_layer(layer_indent_last);
}
#endif
