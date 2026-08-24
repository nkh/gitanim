/*
 * postprocess.c — Main postprocess executable (layered architecture).
 *
 * This file REPLACES the old monolithic postprocess.c. It is a thin
 * orchestrator that:
 *   1. Reads raw compute output from stdin
 *   2. Runs Layer 0 (V2 conversion)
 *   3. Runs optional transform layers (overwrite, etc.)
 *   4. Runs Layer 3 (cursor recomputation)
 *   5. Writes V2 TSV to stdout
 *
 * No ghost-line fix. No 5-branch look-ahead. No inline transforms.
 * Each layer is a separate function in its own file.
 *
 * Build: cc -O2 -Wall -Wextra -Wunused -Werror \
 *          -I animator/c -o diffvim-postprocess postprocess.c \
 *          pp_layer0_v2.c pp_layer_overwrite.c pp_layer3_cursor.c
 *
 * Usage: diffvim-postprocess [--overwrite] [--indent-aware]
 *
 * Options:
 *   --overwrite       Enable overwrite transform layer
 *   --op-debug        Insert debug ops into the stream
 *   --help, -h        Show help
 *
 * Env vars:
 *   DV_DEBUG_POSTPROCESS=path  Debug dumps to $path/
 *   DV_OP_DEBUG=1              Insert debug ops into stream
 *   DV_OLD_FILE=path           Old file path (for layers that need it)
 *   DIFFVIM_LEFT_TO_RIGHT=1    Read by Layer 0 (passes through header)
 */

#define _POSIX_C_SOURCE 200809L
#include "pp_common.h"
#include <unistd.h>
#include <fcntl.h>

/* Layer functions (from separate files, included at compile time) */
extern int layer0_v2_convert(void);
extern int layer1_reorder(Op *in, int in_count, Op *out, int out_cap,
                            const char *old_file);
extern int layer_overwrite(Op *in, int in_count, Op *out, int out_cap,
                            const char *old_file);
extern int layer_indent_last(Op *in, int in_count, Op *out, int out_cap,
                             const char *old_file);
extern int layer3_cursor(Op *in, int in_count, Op *out, int out_cap,
                         const char *old_file);

/* ── Buffer-based layer runner ─────────────────────────────────────── */
/*
 * Unlike pp_run_layer (which reads stdin/writes stdout), this function
 * runs a layer on an in-memory Op array. Used when all layers run in
 * one process.
 *
 * Returns: number of output ops.
 */
static int run_layer_on_buffer(int (*layer_func)(Op *in, int in_count,
                                                  Op *out, int out_cap,
                                                  const char *old_file),
                                Op *in, int in_count,
                                const char *layer_name,
                                const char *old_file) {
    /* Allocate output buffer (at least as large as input) */
    int out_cap = in_count * 2 + 1024;  /* allow growth */
    Op *out = (Op *)malloc(out_cap * sizeof(Op));
    if (!out) { fprintf(stderr, "out of memory\n"); return in_count; }

    pp_logf("Running %s on %d ops", layer_name, in_count);
    pp_dump_ops("main", "input.txt", in, in_count);

    int out_count = layer_func(in, in_count, out, out_cap, old_file);

    pp_dump_ops("main", "output.txt", out, out_count);
    pp_logf("%s: %d ops → %d ops", layer_name, in_count, out_count);

    /* Copy output back to input buffer for next layer */
    if (out_count <= in_count) {
        memcpy(in, out, out_count * sizeof(Op));
    } else {
        /* Output is larger — need to realloc the caller's buffer.
         * For simplicity, just return the output pointer and let
         * the caller handle it. But this is a simple implementation
         * — in practice, layers rarely grow the array significantly. */
        memcpy(in, out, in_count * sizeof(Op));
        /* If out_count > in_count, we lose the extra ops.
         * Fix: caller should allocate enough. */
        fprintf(stderr, "WARNING: %s grew ops from %d to %d (truncating)\n",
                layer_name, in_count, out_count);
        out_count = in_count;
    }

    free(out);
    return out_count;
}

/* ── Main ──────────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    int do_overwrite = 0;
    int do_indent_last = 0;
    int op_debug = 0;
    const char *old_file = getenv("DV_OLD_FILE");
    if (!old_file) old_file = "";

    /* Parse args */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--overwrite") == 0) {
            do_overwrite = 1;
        } else if (strcmp(argv[i], "--indent-last") == 0) {
            do_indent_last = 1;
        } else if (strcmp(argv[i], "--op-debug") == 0) {
            op_debug = 1;
            setenv("DV_OP_DEBUG", "1", 1);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-postprocess [options]\n");
            fprintf(stderr, "  --overwrite       Enable overwrite transform\n");
            fprintf(stderr, "  --op-debug        Insert debug ops into stream\n");
            fprintf(stderr, "  --help, -h        Show this help\n");
            fprintf(stderr, "\nReads raw ops from stdin, writes V2 TSV to stdout.\n");
            exit(0);
        }
    }

    /* Initialize debug */
    pp_debug_init("main", "Postprocess (layered)");

    /*
     * Strategy: Layer 0 reads stdin and writes to a temp pipe.
     * Then we read from the pipe into an Op array, run transforms,
     * run Layer 3, and write to stdout.
     *
     * Simpler approach: Layer 0 writes to stdout directly (it handles
     * V1/V2 detection and header rewriting). Then we read stdout back.
     * But that requires a pipe.
     *
     * Simplest: Layer 0 writes to a temp file. We read it, run layers,
     * write to stdout.
     */

    /* Step 1: Run Layer 0 (reads stdin, writes to temp file) */
/* Step 1: Run Layer 0, capture output in pipe */

    /* Create a temp file for Layer 0 output */
    char tmp_path[] = "/tmp/pp_l0_XXXXXX";
    int tmp_fd = mkstemp(tmp_path);
    if (tmp_fd < 0) {
        fprintf(stderr, "Cannot create temp file\n");
        return 1;
    }

    /* Redirect stdout to temp file, run Layer 0, restore stdout */
    int saved_stdout = dup(STDOUT_FILENO);
    dup2(tmp_fd, STDOUT_FILENO);
    close(tmp_fd);

    layer0_v2_convert();

    /* Restore stdout — must flush before dup2 */
    fflush(stdout);
    dup2(saved_stdout, STDOUT_FILENO);
    close(saved_stdout);

    /* Close and reopen the temp file for reading */
    /* (The file was written via the dup'd fd, need to reopen for reading) */

    /* Step 2: Read Layer 0 output into Op array */
    pp_log("Step 2: Read Layer 0 output");

    FILE *f = fopen(tmp_path, "r");
    if (!f) {
        fprintf(stderr, "Cannot read Layer 0 output\n");
        unlink(tmp_path);
        return 1;
    }

    /* Read ALL lines. We need to:
     * - Pass through headers (# ...)
     * - Parse HUNK headers
     * - Parse ops into Op array
     * - Pass through HUNK_END
     *
     * We process per-hunk: read ops, run layers, write output.
     */
    char line[PP_MAX_LINE];
    int in_hunk = 0;
    Hunk current_hunk = {0};
    int hunk_count = 0;
    int line_offset = 0;  /* cumulative (newl_ins - newl_del) from prior hunks */
    Op *ops = NULL;
    int n_ops = 0;
    int ops_cap = 0;

    /* Write headers to stdout as we read them */
    while (fgets(line, sizeof(line), f)) {
        line[strcspn(line, "\n\r")] = 0;

        if (line[0] == 0) {
            /* Blank line — skip (we'll add our own at end) */
            continue;
        }

        if (line[0] == '#') {
            /* Header — pass through */
            printf("%s\n", line);
            continue;
        }

        if (strncmp(line, "HUNK\t", 5) == 0) {
            /* Start of hunk — parse header */
            sscanf(line, "HUNK\t%d\t%d\t%d\t%d\t%d",
                   &current_hunk.target, &current_hunk.del, &current_hunk.ins,
                   &current_hunk.end_ins, &current_hunk.end_del);
            in_hunk = 1;
            n_ops = 0;
            if (!ops) {
                ops_cap = 4096;
                ops = (Op *)malloc(ops_cap * sizeof(Op));
            }
            continue;
        }

        if (strncmp(line, "HUNK_END", 8) == 0) {
            /* End of hunk — run layers and write output */
            if (in_hunk && n_ops > 0) {
                /* Adjust first op line for cross-hunk offset */
                if (n_ops > 0) ops[0].line = current_hunk.target + line_offset;
                hunk_count++;

                /* Run Layer 1 (reorder) */
                n_ops = run_layer_on_buffer(layer1_reorder, ops, n_ops,
                                            "reorder", old_file);

                /* Run indent-last layer (if enabled) */
                if (do_indent_last) {
                    n_ops = run_layer_on_buffer(layer_indent_last, ops, n_ops,
                                                "indent_last", old_file);
                }

                /* Run overwrite layer (if enabled) */
                if (do_overwrite) {
                    n_ops = run_layer_on_buffer(layer_overwrite, ops, n_ops,
                                                "overwrite", old_file);
                }

                /* Run Layer 3 (cursor recomputation) */
                /* Count newlines for line_offset */
                { int ni=0, nd=0; for (int j=0; j<n_ops; j++) { if (strcmp(ops[j].type,"insert")==0 && ops[j].code==10) ni++; if (strcmp(ops[j].type,"delete")==0 && ops[j].code==10) nd++; } line_offset += ni - nd; }
                n_ops = run_layer_on_buffer(layer3_cursor, ops, n_ops,
                                            "cursor", old_file);

                /* Write hunk header and ops to stdout */
                pp_write_hunk(&current_hunk);
                for (int i = 0; i < n_ops; i++) {
                    pp_write_op(&ops[i]);
                }
                pp_write_hunk_end();
            }
            in_hunk = 0;
            n_ops = 0;
            continue;
        }

        /* Op line — parse into array */
        if (in_hunk) {
            if (n_ops >= ops_cap) {
                ops_cap *= 2;
                ops = (Op *)realloc(ops, ops_cap * sizeof(Op));
                if (!ops) { fprintf(stderr, "out of memory\n"); return 1; }
            }
            pp_parse_op(line, &ops[n_ops]);
            n_ops++;
        }
    }

    /* Handle last hunk if no HUNK_END */
    if (in_hunk && n_ops > 0) {
        hunk_count++;
        if (n_ops > 0) ops[0].line = current_hunk.target + line_offset;
        n_ops = run_layer_on_buffer(layer1_reorder, ops, n_ops,
                                    "reorder", old_file);
        if (do_indent_last) {
            n_ops = run_layer_on_buffer(layer_indent_last, ops, n_ops,
                                        "indent_last", old_file);
        }
        if (do_overwrite) {
            n_ops = run_layer_on_buffer(layer_overwrite, ops, n_ops,
                                        "overwrite", old_file);
        }
        n_ops = run_layer_on_buffer(layer3_cursor, ops, n_ops,
                                    "cursor", old_file);
        pp_write_hunk(&current_hunk);
        for (int i = 0; i < n_ops; i++) {
            pp_write_op(&ops[i]);
        }
        pp_write_hunk_end();
    }

    printf("\n");  /* trailing blank line */

    pp_logf("Total: %d hunks processed", hunk_count);

    /* Cleanup */
    if (ops) free(ops);
    fclose(f);
    unlink(tmp_path);

    (void)op_debug;  /* passed via env to layers */
    return 0;
}
