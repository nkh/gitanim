/*
 * postprocess.c — Main postprocess executable.
 *
 * Reads V2 TSV from stdin (compute output is already V2), runs transform
 * layers, adjusts line/col positions, writes V2 TSV to stdout.
 *
 * Pipeline:
 *   1. Read stdin (V2 TSV from compute) into Op array per hunk
 *   2. overwrite layer (optional, --overwrite) — reduces op count by
 *      merging delete+insert pairs at the same position
 *   3. delete-indent-last layer (optional, --indent-last) — moves
 *      leading-whitespace DELETE ops to end of line group
 *   4. reorder layer — reorders ops within each line group:
 *      content deletes → content inserts → \n deletes → \n inserts
 *   5. adjust_positions — adjusts (line, col) based on \n deletes
 *   6. Write V2 TSV to stdout
 *
 * Build: cc -O2 -Wall -Wextra -Wunused -Werror \
 *          -I animator/c -o diffvim-postprocess postprocess.c \
 *          pp_layer1_reorder.c pp_layer_indent_last.c pp_layer_overwrite.c
 *
 * Usage: diffvim-postprocess [--indent-last] [--overwrite]
 */

#define _POSIX_C_SOURCE 200809L
#include "pp_common.h"
#include <unistd.h>
#include <fcntl.h>

/* Layer functions */
extern int layer1_reorder(Op *in, int in_count, Op *out, int out_cap,
                            const char *old_file);
extern int layer_overwrite(Op *in, int in_count, Op *out, int out_cap,
                            const char *old_file);
extern int layer_indent_last(Op *in, int in_count, Op *out, int out_cap,
                             const char *old_file);
extern int layer_line_delete_in_place(Op *in, int in_count, Op *out, int out_cap,
                                    const char *old_file);

/* adjust_positions from pp_adjust.c */
extern void adjust_positions(Op *ops, int n_ops, int current_characters_in,
                              int deleted_lines_in,
                              int *deleted_lines_out, int *ops_consumed_out);
extern int run_adjust_positions(Op *ops, int n_ops);


/* ── Buffer-based layer runner ─────────────────────────────────────── */
static int run_layer_on_buffer(int (*layer_func)(Op *in, int in_count,
                                                  Op *out, int out_cap,
                                                  const char *old_file),
                                Op *in, int in_count,
                                const char *layer_name,
                                const char *old_file) {
    int out_cap = in_count * 2 + 1024;
    Op *out = (Op *)malloc(out_cap * sizeof(Op));
    if (!out) { fprintf(stderr, "out of memory\n"); return in_count; }

    pp_logf("Running %s on %d ops", layer_name, in_count);
    pp_dump_ops("main", "input.txt", in, in_count);

    int out_count = layer_func(in, in_count, out, out_cap, old_file);

    pp_dump_ops("main", "output.txt", out, out_count);
    pp_logf("%s: %d ops → %d ops", layer_name, in_count, out_count);

    if (out_count <= in_count) {
        memcpy(in, out, out_count * sizeof(Op));
    } else {
        memcpy(in, out, in_count * sizeof(Op));
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
            fprintf(stderr, "  --indent-last     Enable delete-indent-last transform\n");
            fprintf(stderr, "  --overwrite       Enable overwrite transform\n");
            fprintf(stderr, "  --op-debug        Insert debug ops into stream\n");
            fprintf(stderr, "  --help, -h        Show this help\n");
            fprintf(stderr, "\nReads V2 TSV from stdin, writes V2 TSV to stdout.\n");
            exit(0);
        }
    }

    pp_debug_init("main", "Postprocess");

    /* Read V2 TSV directly from stdin (compute output is already V2) */
    char line[PP_MAX_LINE];
    int in_hunk = 0;
    Hunk current_hunk = {0};
    int hunk_count = 0;
    int line_offset = 0;
    Op *ops = NULL;
    int n_ops = 0;
    int ops_cap = 0;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n\r")] = 0;

        if (line[0] == 0) continue;

        if (line[0] == '#') {
            printf("%s\n", line);
            continue;
        }

        if (strncmp(line, "HUNK\t", 5) == 0) {
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
            if (in_hunk && n_ops > 0) {
                hunk_count++;

                /* 1. Overwrite layer (optional) — reduces op count first */
                if (do_overwrite) {
                    n_ops = run_layer_on_buffer(layer_overwrite, ops, n_ops,
                                                "overwrite", old_file);
                }

                /* 2. delete-indent-last layer (optional) */
                if (do_indent_last) {
                    n_ops = run_layer_on_buffer(layer_indent_last, ops, n_ops,
                                                "indent_last", old_file);
                }

                /* 3. Reorder layer — 4-sweep: content del → content ins → \n del → \n ins */
                n_ops = run_layer_on_buffer(layer1_reorder, ops, n_ops,
                                            "reorder", old_file);

                /* 4. line-delete-in-place layer — always runs.
                 * TODO: This layer has a bug that breaks large examples.
                 * Disabled until fixed. */
                /* n_ops = run_layer_on_buffer(layer_line_delete_in_place, ops, n_ops, */
                /*                             "line_delete_in_place", old_file); */

                /* Apply cross-hunk line_offset to all ops */
                { for (int j = 0; j < n_ops; j++) ops[j].line += line_offset; }

                /* 5. Adjust line/col based on \n deletes (ONCE, after all layers) */
                run_adjust_positions(ops, n_ops);

                /* Update line_offset for next hunk */
                { int ni=0, nd=0; for (int j=0; j<n_ops; j++) { if (strcmp(ops[j].type,"insert")==0 && ops[j].code==10) ni++; if (strcmp(ops[j].type,"delete")==0 && ops[j].code==10) nd++; } line_offset += ni - nd; }

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
        if (do_overwrite) {
            n_ops = run_layer_on_buffer(layer_overwrite, ops, n_ops,
                                        "overwrite", old_file);
        }
        if (do_indent_last) {
            n_ops = run_layer_on_buffer(layer_indent_last, ops, n_ops,
                                        "indent_last", old_file);
        }
        n_ops = run_layer_on_buffer(layer1_reorder, ops, n_ops,
                                    "reorder", old_file);
        /* TODO: line_delete_in_place disabled — breaks large examples */
        /* n_ops = run_layer_on_buffer(layer_line_delete_in_place, ops, n_ops, */
        /*                             "line_delete_in_place", old_file); */
        { for (int j = 0; j < n_ops; j++) ops[j].line += line_offset; }
        run_adjust_positions(ops, n_ops);
        pp_write_hunk(&current_hunk);
        for (int i = 0; i < n_ops; i++) {
            pp_write_op(&ops[i]);
        }
        pp_write_hunk_end();
    }

    printf("\n");

    pp_logf("Total: %d hunks processed", hunk_count);

    if (ops) free(ops);

    (void)op_debug;
    return 0;
}
