/* ad_layer_skip_indent — detect indent-only hunks and mark them for
 * instant application (skip animation).
 *
 * A hunk is "indent-only" if ALL its delete and insert ops are
 * whitespace (code 32=space, 9=tab) or newline (code 10). This means
 * the only change is leading whitespace — the content is unchanged.
 *
 * When an indent-only hunk is detected, this layer wraps its ops with
 * marker ops:
 *   delay\t0\tindent_skip_start       ← before the hunk's ops
 *   ... (original ops, unchanged) ...
 *   delay\t<pause_ms>\tindent_skip_end  ← after the hunk's ops
 *
 * The pace layer recognizes these markers and sets delays to 0 (instant)
 * within the skip region, plus adds the specified pause after.
 * The animator applies all ops instantly but doesn't render each one.
 *
 * Ops are NOT modified — they're all still applied, so the buffer
 * ends up correct. Only the timing/animation is skipped.
 *
 * CLI options:
 *   --pause-after-ms N   Pause duration after indent-only hunk (default: 300)
 *   --help, -h           Show help
 */
#include "ad_layer_common.h"

static int pause_after_ms = AD_LAYER_DEFAULT_SKIP_PAUSE_MS;

/* layer_skip_indent: Detects indent-only hunks (every delete and insert
 * op is whitespace or newline) and wraps them with marker delay ops so
 * that the pace layer can apply them instantly rather than animate them.
 *
 * Marker protocol (recognized by ad_layer_pace):
 *   delay\t0\t-1\t0            (indent_skip_start)  — start instant region
 *   ... original ops, unchanged ...
 *   delay\t<N>\t-1\t1           (indent_skip_end)    — end region, pause N ms
 *
 * The original ops are NOT modified — they are still applied, so the
 * final buffer ends up correct. Only the timing/animation is skipped.
 *
 * Inputs:  ops[0..n_ops-1]   — ops for one hunk (positions already set).
 * Outputs: out[0..out_cap-1] — ops with two delay-marker ops prepended
 *                              and appended if the hunk is indent-only;
 *                              otherwise a verbatim copy.
 *          *line_offset       — not modified.
 * Returns: number of output ops written. */
static int layer_skip_indent(Op *ops, int n_ops, Op *out, int out_cap,
                             int *line_offset) {
    (void)line_offset;

    /* Check if ALL delete/insert ops are whitespace or newline. */
    int has_change = 0;
    int is_indent_only = 1;
    for (int i = 0; i < n_ops; i++) {
        if (ad_layer_is_debug_op(&ops[i])) continue;
        if (strcmp(ops[i].type, "delete") == 0 ||
            strcmp(ops[i].type, "insert") == 0 ||
            strcmp(ops[i].type, "overwrite_insert") == 0) {
            has_change = 1;
            if (ops[i].code != AD_LAYER_CHAR_SPACE && ops[i].code != AD_LAYER_CHAR_TAB && ops[i].code != AD_LAYER_CHAR_NEWLINE) {
                is_indent_only = 0;
                break;
            }
        }
    }

    if (!has_change || !is_indent_only) {
        /* Not indent-only — pass through unchanged. */
        int n = (n_ops < out_cap) ? n_ops : out_cap;
        for (int i = 0; i < n; i++) out[i] = ops[i];
        return n;
    }

    /* Indent-only hunk — wrap with markers.
     * We emit special delay ops that the pace layer recognizes:
     *   delay\t0\tindent_skip_start    — start of instant region
     *   delay\t<N>\tindent_skip_end    — end of region, pause N ms
     *
     * Since Op struct only has type/code/line/col, we use:
     *   type = "delay", code = 0 for start, code = pause_ms for end
     *   line = -1 to signal "this is a skip marker" (line is never -1
     *   in normal ops, which are 1-indexed)
     *   col = 0 for start, col = 1 for end
     */
    int n_out = 0;

    /* Emit indent_skip_start marker. */
    if (n_out < out_cap) {
        strcpy(out[n_out].type, "delay");
        out[n_out].code = 0;        /* 0 ms delay */
        out[n_out].line = -1;       /* marker: indent_skip_start */
        out[n_out].col = 0;
        n_out++;
    }

    /* Copy original ops unchanged. */
    for (int i = 0; i < n_ops && n_out < out_cap; i++) {
        out[n_out++] = ops[i];
    }

    /* Emit indent_skip_end marker with pause. */
    if (n_out < out_cap) {
        strcpy(out[n_out].type, "delay");
        out[n_out].code = pause_after_ms;  /* pause duration */
        out[n_out].line = -1;              /* marker: indent_skip_end */
        out[n_out].col = 1;               /* 1 = end marker */
        n_out++;
    }

    return n_out;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--pause-after-ms") == 0 && i + 1 < argc)
            pause_after_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_skip_indent — skip animation for indent-only hunks\n\n"
                "Usage: ad_layer_skip_indent [options] < post_ops > marked_ops\n\n"
                "Options:\n"
                "  --pause-after-ms N  Pause after indent-only hunk (default: 300)\n"
                "  --help, -h          Show this help\n\n"
                "Detects hunks where all changes are whitespace (spaces/tabs/newlines).\n"
                "Wraps them with delay markers so the pace layer applies them instantly.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_skip_indent);
}
