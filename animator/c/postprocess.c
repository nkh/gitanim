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

/* ── adjust_positions: recursive line/col adjustment ──────────────── */
/*
 * Walks ops in order and adjusts (line, col) based on \n deletes.
 *
 * A line always has at least 1 char (the \n). So current_characters
 * starts at op.col (≥1). JOIN is detected when current_characters > 1
 * (i.e., there are content chars BEYOND the \n).
 *
 * Returns: deleted_lines and ops_consumed via output params.
 */
static int ap_depth = 0;  /* recursion depth for debug */

static void adjust_positions(Op *ops, int n_ops, int current_characters_in,
                              int deleted_lines_in,
                              int *deleted_lines_out, int *ops_consumed_out) {
    int deleted_lines = deleted_lines_in;
    int current_characters = current_characters_in;
    int content_on_line = 0;  /* keeps+inserts on current line (for JOIN detection) */
    /* For top-level call (current_characters_in == 0):
     *   - Set current_line = -1 so Rule 1 fires for the first op.
     * For recursive call (current_characters_in > 0, the carry):
     *   - Set current_line = ops[0].line - deleted_lines so Rule 1 does NOT
     *     fire for the first op (joined line), keeping the carry. */
    int current_line = (current_characters_in == 0) ? -1 : (ops[0].line - deleted_lines);
    int i = 0;

    /* Debug: print call info */
    if (getenv("DV_DEBUG_ADJUST")) {
        fprintf(stderr, "%*sCALL depth=%d n_ops=%d carry=%d dl_in=%d first_op_line=%d\n",
                ap_depth * 2, "", ap_depth, n_ops, current_characters_in,
                deleted_lines_in, n_ops > 0 ? ops[0].line : -1);
    }
    ap_depth++;

    while (i < n_ops) {
        if (pp_is_debug_op(&ops[i])) { i++; continue; }

        /* Debug: print op before processing */
        if (getenv("DV_DEBUG_ADJUST")) {
            fprintf(stderr, "%*s  [%2d] %s\t%d\t%d\t%d  (dl=%d cc=%d col=%d)",
                    ap_depth * 2, "", i, ops[i].type, ops[i].line, ops[i].col,
                    ops[i].code, deleted_lines, current_characters, content_on_line);
        }

        /* Rule 1: line changed? */
        int line_changed = 0;
        if ((ops[i].line - deleted_lines) != current_line) {
            current_characters = ops[i].col;
            current_line = ops[i].line - deleted_lines;
            content_on_line = 0;
            line_changed = 1;
        }

        /* Rule 3: set this op's position (in place) */
        ops[i].line = ops[i].line - deleted_lines;
        ops[i].col  = current_characters;

        /* Rule 2: advance current_characters (code != \n first) */
        if (ops[i].code != 10) {
            if (strcmp(ops[i].type, "keep") == 0) {
                current_characters += 1;
                content_on_line++;
            } else if (strcmp(ops[i].type, "insert") == 0) {
                current_characters += 1;
                content_on_line++;
            }
            /* delete: no change */
            /* overwrite_insert: net 0 */
        }

        /* Debug: print result */
        if (getenv("DV_DEBUG_ADJUST")) {
            if (line_changed) fprintf(stderr, " LINE_CHANGED");
            fprintf(stderr, " → line=%d col=%d", ops[i].line, ops[i].col);
        }

        /* Rules 4 & 5: \n ops */
        if (ops[i].code == 10) {
            if (strcmp(ops[i].type, "delete") == 0) {
                /* Rule 4: \n delete */
                deleted_lines += 1;
                if (content_on_line > 0) {
                    /* JOIN: content chars remain on this line.
                     * Recursive call on the merged line's ops. */
                    if (getenv("DV_DEBUG_ADJUST")) {
                        fprintf(stderr, " JOIN(cc=%d)→RECURSE", current_characters);
                    }
                    int sub_deleted, sub_consumed;
                    adjust_positions(&ops[i + 1], n_ops - i - 1,
                                      current_characters,
                                      deleted_lines,  /* pass current deleted_lines */
                                      &sub_deleted, &sub_consumed);
                    /* sub_deleted is the TOTAL deleted_lines from the recursive
                     * call (including the passed-in deleted_lines). So we
                     * set deleted_lines = sub_deleted (not += ). */
                    deleted_lines = sub_deleted;
                    if (getenv("DV_DEBUG_ADJUST")) {
                        fprintf(stderr, " (sub_del=%d sub_con=%d → dl=%d)",
                                sub_deleted, sub_consumed, deleted_lines);
                    }
                    i += 1 + sub_consumed;
                    if (getenv("DV_DEBUG_ADJUST")) fprintf(stderr, "\n");
                    continue;
                } else {
                    if (getenv("DV_DEBUG_ADJUST")) fprintf(stderr, " FULL_DEL");
                }
            } else {
                /* Rule 5: \n keep / \n insert / \n overwrite_insert */
                current_characters = 0;
                content_on_line = 0;
                if (getenv("DV_DEBUG_ADJUST")) fprintf(stderr, " RESET");
            }
        }

        if (getenv("DV_DEBUG_ADJUST")) fprintf(stderr, "\n");
        i++;
    }

    ap_depth--;
    if (getenv("DV_DEBUG_ADJUST")) {
        fprintf(stderr, "%*sRETURN depth=%d deleted_lines=%d (added %d) ops_consumed=%d\n",
                ap_depth * 2, "", ap_depth, deleted_lines,
                deleted_lines - deleted_lines_in, i);
    }

    *deleted_lines_out = deleted_lines;
    *ops_consumed_out = i;
}

/* Wrapper for top-level call */
static int run_adjust_positions(Op *ops, int n_ops) {
    int deleted_lines, ops_consumed;
    adjust_positions(ops, n_ops, 0, 0, &deleted_lines, &ops_consumed);
    return deleted_lines;
}

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

                /* Apply cross-hunk line_offset to all ops */
                { for (int j = 0; j < n_ops; j++) ops[j].line += line_offset; }

                /* 4. Adjust line/col based on \n deletes */
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
