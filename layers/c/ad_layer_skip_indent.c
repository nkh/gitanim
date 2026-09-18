/* ad_layer_skip_indent — detect whitespace-only LINES and mark them
 * for instant application (skip animation).
 *
 * Phase 2: per-LINE detection (was per-hunk).
 *
 * A LINE is "whitespace-only" if all its delete and insert ops are
 * whitespace (code 32=space, 9=tab) or newline (code 10). The line
 * may contain keeps (any code). The line is bounded by:
 *   - keep_line / join_lines / split_line / delete_line / insert_line ops
 *   - \n char ops (code 10) — these act as line terminators
 *   - hunk boundaries (HUNK / HUNK_END)
 *
 * When a whitespace-only LINE is detected, this layer wraps THAT LINE's
 * ops (only) with marker ops:
 *   delay\t-1\t0\t0       ← before the line's ops (indent_skip_start)
 *   ... (the line's ops, unchanged) ...
 *   delay\t-1\t1\t<N>     ← after the line's ops (indent_skip_end)
 *
 * The pace layer recognizes these markers and sets delays to 0 (instant)
 * within the skip region, plus adds the specified pause after.
 *
 * Ops on other lines in the same hunk (with non-whitespace changes)
 * are NOT wrapped — they animate normally.
 *
 * CLI options:
 *   --pause-after-ms N   Pause duration after each whitespace-only line
 *                        (default: 300)
 *   --help, -h           Show help
 */
#include "ad_layer_common.h"

static int pause_after_ms = AD_LAYER_DEFAULT_SKIP_PAUSE_MS;

/* Check if an op is whitespace or \n (for skip detection). */
static int is_ws_or_newline(int code) {
    return code == AD_LAYER_CHAR_SPACE
        || code == AD_LAYER_CHAR_TAB
        || code == AD_LAYER_CHAR_NEWLINE;
}

/* layer_skip_indent: For each hunk, walk the ops line-by-line. A line
 * is a maximal run of ops between line boundaries. Line boundaries are:
 *   - line ops (keep_line, join_lines, split_line, delete_line, insert_line,
 *     batch_insert)
 *   - \n char ops (code 10)
 *   - hunk end
 * For each line, if ALL its delete/insert/overwrite_insert ops are
 * whitespace or \n, wrap that line's ops with indent_skip_start /
 * indent_skip_end markers. Otherwise, pass the line through unchanged.
 *
 * Keeps within a whitespace-only line are included in the skip region
 * (they don't affect the whitespace-only check — only delete/insert
 * ops do).
 *
 * Inputs:  ops[0..n_ops-1]   — ops for one hunk (positions already set).
 * Outputs: out[0..out_cap-1] — ops with per-line skip markers.
 *          *line_offset       — not modified.
 * Returns: number of output ops written. */
static int layer_skip_indent(Op *ops, int n_ops, Op *out, int out_cap,
                             int *line_offset) {
    (void)line_offset;
    int n_out = 0;

    /* Helper to emit an op to out[]. */
    #define EMIT(op) do { if (n_out < out_cap) out[n_out++] = (op); } while (0)

    /* Helper to emit a skip marker. */
    #define EMIT_SKIP_MARKER(is_start) do { \
        Op m = {0}; \
        strcpy(m.type, "delay"); \
        m.code = (is_start) ? 0 : pause_after_ms; \
        m.line = -1; \
        m.col = (is_start) ? 0 : 1; \
        EMIT(m); \
    } while (0)

    int i = 0;
    while (i < n_ops) {
        /* Find the end of the current line. A line is a maximal run of
         * non-boundary ops. Line boundaries are line ops and \n ops.
         * The boundary op itself is part of the line (emitted before
         * the next line starts). */
        int line_start = i;
        int j = i;
        while (j < n_ops) {
            if (ad_layer_is_debug_op(&ops[j])) { j++; continue; }
            /* Line op = line boundary (included in this line). */
            if (ad_layer_is_line_op(&ops[j])) { j++; break; }
            /* \n op = line boundary (included in this line). */
            if (ops[j].code == AD_LAYER_CHAR_NEWLINE) { j++; break; }
            j++;
        }
        int line_end = j;  /* [line_start, line_end) is one line */

        /* Check if all delete/insert/overwrite_insert ops in this line
         * are whitespace or \n. */
        int has_change = 0;
        int is_ws_only = 1;
        for (int k = line_start; k < line_end; k++) {
            if (ad_layer_is_debug_op(&ops[k])) continue;
            if (strcmp(ops[k].type, "delete") == 0 ||
                strcmp(ops[k].type, "insert") == 0 ||
                strcmp(ops[k].type, "overwrite_insert") == 0) {
                has_change = 1;
                if (!is_ws_or_newline(ops[k].code)) {
                    is_ws_only = 0;
                    break;
                }
            }
        }

        if (has_change && is_ws_only) {
            /* Whitespace-only line — wrap with markers. */
            EMIT_SKIP_MARKER(1);  /* start */
            for (int k = line_start; k < line_end; k++) EMIT(ops[k]);
            EMIT_SKIP_MARKER(0);  /* end */
        } else {
            /* Normal line — pass through unchanged. */
            for (int k = line_start; k < line_end; k++) EMIT(ops[k]);
        }

        i = line_end;
    }

    #undef EMIT
    #undef EMIT_SKIP_MARKER
    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--pause-after-ms") == 0 && i + 1 < argc)
            pause_after_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_skip_indent — skip animation for whitespace-only LINES\n\n"
                "Usage: ad_layer_skip_indent [options] < post_ops > marked_ops\n\n"
                "Options:\n"
                "  --pause-after-ms N  Pause after each whitespace-only line (default: 300)\n"
                "  --help, -h          Show this help\n\n"
                "Detects LINES where all changes are whitespace (spaces/tabs/newlines).\n"
                "Wraps each such line with delay markers so the pace layer applies\n"
                "them instantly. Other lines in the same hunk animate normally.\n\n"
                "Phase 2: per-LINE detection (was per-hunk in Phase 1).\n");
            return 0;
        }
    }

    return ad_layer_run(layer_skip_indent);
}
