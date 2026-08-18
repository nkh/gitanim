/* diffvim-postprocess — Post-process raw char ops.
 *
 * Reads raw char ops from stdin, applies post-processing, computes
 * per-op (line, col) positions, and writes tab-separated ops to stdout.
 *
 * The postprocess stage OWNS cursor positioning. The pace stage only
 * handles delays and batching. The animator reads (line, col) from each
 * op and applies it at that exact position — scroll-safe.
 *
 * Output format (TSV, 1-indexed line/col):
 *   hunk_start\t<del_count>\t<ins_count>
 *   op\tkeep\t<line>\t<col>\t<code>
 *   op\tdelete\t<line>\t<col>\t<code>
 *   op\tinsert\t<line>\t<col>\t<code>
 *   newline_delete\t<line>
 *   newline_insert\t<line>\t<col>
 *
 * Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup]
 *                             [--indent-aware] [--overwrite]
 *
 * Build: cc -O2 -o diffvim-postprocess postprocess.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 4096

typedef struct { char type[8]; int code; } Op;

/* Dynamic arrays — grow as needed */
static Op *ops_in = NULL;
static Op *ops_out = NULL;
static int n_ops = 0;
static int cap_ops = 0;

/* Header lines (passed through) — dynamic */
static char **header = NULL;
static int n_header = 0;
static int cap_header = 0;

/* Hunk info */
typedef struct { int target, del, ins, end_ins, end_del; int op_start, op_count; } Hunk;
static Hunk *hunks = NULL;
static int n_hunks = 0;
static int cap_hunks = 0;

static int op_order_optimize = 1;
static int do_semantic = 0;
static int do_indent = 0;
static int do_overwrite = 0;

/* Apply a --transform NAME[:VALUE] spec. */
void apply_transform(const char *spec) {
    if (strncmp(spec, "op-order:", 9) == 0) {
        const char *mode = spec + 9;
        if (strcmp(mode, "natural") == 0) op_order_optimize = 0;
        else if (strcmp(mode, "optimize") == 0) op_order_optimize = 1;
        /* other modes not yet implemented */
    } else if (strcmp(spec, "semantic-cleanup") == 0) {
        do_semantic = 1;
    } else if (strcmp(spec, "indent-aware") == 0) {
        do_indent = 1;
    } else if (strcmp(spec, "overwrite") == 0) {
        do_overwrite = 1;
    } else {
        fprintf(stderr, "diffvim-postprocess: unknown transform '%s'\n", spec);
        fprintf(stderr, "  Available: op-order:natural|optimize, semantic-cleanup, indent-aware, overwrite\n");
        exit(1);
    }
}

void list_transforms(void) {
    printf("Available transforms (use --transform NAME[:VALUE]):\n");
    printf("  op-order:natural        No reordering (raw patience order)\n");
    printf("  op-order:optimize       Deletes before inserts within each line (default)\n");
    printf("  semantic-cleanup        Merge adjacent delete+insert pairs that cancel out\n");
    printf("  indent-aware            Handle indent-only changes as keeps\n");
    printf("  overwrite               Transform delete+insert into in-place overwrite\n");
    printf("\nTransforms are applied in the order specified.\n");
    printf("Multiple --transform flags can be given.\n");
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--op-order") == 0 && i+1 < argc) {
            i++;
            if (strcmp(argv[i], "natural") == 0) op_order_optimize = 0;
        } else if (strcmp(argv[i], "--semantic-cleanup") == 0) {
            do_semantic = 1;
        } else if (strcmp(argv[i], "--indent-aware") == 0) {
            do_indent = 1;
        } else if (strcmp(argv[i], "--overwrite") == 0) {
            do_overwrite = 1;
        } else if (strcmp(argv[i], "--transform") == 0 && i+1 < argc) {
            apply_transform(argv[++i]);
        } else if (strcmp(argv[i], "--list-transforms") == 0) {
            list_transforms();
            exit(0);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-postprocess [options]\n");
            fprintf(stderr, "  --transform NAME[:VALUE]  Apply a transformation (repeatable)\n");
            fprintf(stderr, "  --list-transforms        List available transforms\n");
            fprintf(stderr, "  --op-order MODE          Shorthand for --transform op-order:MODE\n");
            fprintf(stderr, "  --semantic-cleanup       Shorthand for --transform semantic-cleanup\n");
            fprintf(stderr, "  --indent-aware           Shorthand for --transform indent-aware\n");
            fprintf(stderr, "  --overwrite              Shorthand for --transform overwrite\n");
            exit(0);
        }
    }
}

/* Grow ops_in if needed */
void ensure_ops_capacity(int needed) {
    if (needed <= cap_ops) return;
    int new_cap = cap_ops == 0 ? 4096 : cap_ops;
    while (new_cap < needed) new_cap *= 2;
    ops_in = (Op *)realloc(ops_in, new_cap * sizeof(Op));
    if (!ops_in) { fprintf(stderr, "diffvim-postprocess: out of memory (ops_in %d)\n", new_cap); exit(1); }
    /* ops_out also needs to be at least as big */
    if (ops_out) ops_out = (Op *)realloc(ops_out, new_cap * sizeof(Op));
    else ops_out = (Op *)malloc(new_cap * sizeof(Op));
    if (!ops_out) { fprintf(stderr, "diffvim-postprocess: out of memory (ops_out %d)\n", new_cap); exit(1); }
    cap_ops = new_cap;
}

/* Grow hunks if needed */
void ensure_hunks_capacity(int needed) {
    if (needed <= cap_hunks) return;
    int new_cap = cap_hunks == 0 ? 64 : cap_hunks;
    while (new_cap < needed) new_cap *= 2;
    hunks = (Hunk *)realloc(hunks, new_cap * sizeof(Hunk));
    if (!hunks) { fprintf(stderr, "diffvim-postprocess: out of memory (hunks %d)\n", new_cap); exit(1); }
    cap_hunks = new_cap;
}

/* Grow header if needed */
void ensure_header_capacity(int needed) {
    if (needed <= cap_header) return;
    int new_cap = cap_header == 0 ? 32 : cap_header;
    while (new_cap < needed) new_cap *= 2;
    header = (char **)realloc(header, new_cap * sizeof(char *));
    if (!header) { fprintf(stderr, "diffvim-postprocess: out of memory (header %d)\n", new_cap); exit(1); }
    for (int i = cap_header; i < new_cap; i++) {
        header[i] = (char *)malloc(MAX_LINE);
        if (!header[i]) { fprintf(stderr, "diffvim-postprocess: out of memory (header line)\n"); exit(1); }
    }
    cap_header = new_cap;
}

void read_input(void) {
    char line[MAX_LINE];
    int current_hunk = -1;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#') {
            ensure_header_capacity(n_header + 1);
            strncpy(header[n_header++], line, MAX_LINE - 1);
            header[n_header - 1][MAX_LINE - 1] = 0;
            continue;
        }
        if (strncmp(line, "HUNK", 4) == 0) {
            ensure_hunks_capacity(n_hunks + 1);
            int t, d, i, ei, ed;
            sscanf(line, "HUNK %d %d %d %d %d", &t, &d, &i, &ei, &ed);
            hunks[n_hunks].target = t; hunks[n_hunks].del = d;
            hunks[n_hunks].ins = i; hunks[n_hunks].end_ins = ei;
            hunks[n_hunks].end_del = ed;
            hunks[n_hunks].op_start = n_ops;
            hunks[n_hunks].op_count = 0;
            current_hunk = n_hunks;
            n_hunks++;
            continue;
        }
        if (strncmp(line, "keep", 4) == 0 || strncmp(line, "delete", 6) == 0 || strncmp(line, "insert", 6) == 0) {
            char type[8]; int code;
            sscanf(line, "%7s %d", type, &code);
            ensure_ops_capacity(n_ops + 1);
            strncpy(ops_in[n_ops].type, type, 7);
            ops_in[n_ops].type[7] = 0;
            ops_in[n_ops].code = code;
            n_ops++;
            if (current_hunk >= 0) hunks[current_hunk].op_count++;
        }
    }
}

/* Optimize: within each change region (between keeps), deletes before inserts.
 * Within deletes, put \n (code 10) deletes LAST so the line content
 * is deleted before the \n is removed. */
int optimize_line(Op *in, int count, Op *out) {
    int n_out = 0;
    int buf_start = 0;

    for (int i = 0; i <= count; i++) {
        if (i == count || strcmp(in[i].type, "keep") == 0) {
            /* Flush buffer: content deletes, \n deletes, then inserts */
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code != 10) out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code == 10) out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "insert") == 0) out[n_out++] = in[j];
            if (i < count) out[n_out++] = in[i]; /* the keep */
            buf_start = i + 1;
        }
    }
    return n_out;
}

/* Semantic cleanup: merge canceling delete+insert pairs */
int semantic_cleanup(Op *in, int count, Op *out) {
    int n_out = 0;
    int i = 0;
    while (i < count) {
        if (i + 1 < count &&
            strcmp(in[i].type, "delete") == 0 &&
            strcmp(in[i+1].type, "insert") == 0 &&
            in[i].code == in[i+1].code) {
            strcpy(out[n_out].type, "keep");
            out[n_out].code = in[i].code;
            n_out++;
            i += 2;
        } else if (i + 1 < count &&
                   strcmp(in[i].type, "insert") == 0 &&
                   strcmp(in[i+1].type, "delete") == 0 &&
                   in[i].code == in[i+1].code) {
            strcpy(out[n_out].type, "keep");
            out[n_out].code = in[i].code;
            n_out++;
            i += 2;
        } else {
            out[n_out++] = in[i];
            i++;
        }
    }
    return n_out;
}

/* Reorder ops. Split at ANY \n (keep, delete, or insert).
 * Each line group includes its \n. optimize_line puts content
 * deletes before \n deletes within each group. */
int reorder_hunk_ops(Op *in, int count, Op *out) {
    int n_out = 0;
    int line_start = 0;
    for (int i = 0; i <= count; i++) {
        if (i == count || in[i].code == 10) {
            int line_len = i - line_start;
            if (i < count) line_len++; /* include the \n */
            if (op_order_optimize && line_len > 1) {
                n_out += optimize_line(in + line_start, line_len, out + n_out);
            } else {
                memcpy(out + n_out, in + line_start, line_len * sizeof(Op));
                n_out += line_len;
            }
            line_start = i + 1;
        }
    }
    return n_out;
}

/* Write ops with per-op (line, col) positions.
 *
 * For each hunk, we walk the ops and simulate the cursor position
 * assuming the original file is the buffer. Line/col are 1-indexed.
 * `line_offset` accumulates net (newline_inserts - newline_deletes)
 * across hunks so each hunk targets the CURRENT buffer position,
 * not the original line in the old file.
 */
void write_output(void) {
    /* Write header */
    for (int i = 0; i < n_header; i++) {
        if (strncmp(header[i], "# semantic_cleanup", 18) == 0)
            printf("# semantic_cleanup %d\n", do_semantic);
        else if (strncmp(header[i], "# indent_aware", 14) == 0)
            printf("# indent_aware %d\n", do_indent);
        else if (strncmp(header[i], "# optimize_sequence", 19) == 0)
            printf("# optimize_sequence %d\n", op_order_optimize);
        else if (strncmp(header[i], "# hunk_count", 12) == 0)
            printf("# hunk_count %d\n", n_hunks);
        else
            printf("%s\n", header[i]);
    }

    int line_offset = 0;  /* Cumulative (newline_inserts - newline_deletes) from prior hunks */

    int op_idx = 0;
    for (int h = 0; h < n_hunks; h++) {
        /* hunk_start no longer carries a target line — the position is
         * implicit in the first op's (line, col). */
        printf("hunk_start\t%d\t%d\n", hunks[h].del, hunks[h].ins);

        int count = hunks[h].op_count;
        Op *in = &ops_in[op_idx];

        Op *temp = ops_out;
        int n_out = count;

        if (do_semantic) {
            n_out = semantic_cleanup(in, count, temp);
            in = temp;
            count = n_out;
        }

        /* Always produce a final op array (optimized or not). */
        Op *final_ops;
        if (op_order_optimize) {
            Op *temp2 = (Op *)malloc(cap_ops * sizeof(Op));
            if (!temp2) { fprintf(stderr, "diffvim-postprocess: out of memory (temp2)\n"); exit(1); }
            n_out = reorder_hunk_ops(in, count, temp2);
            final_ops = temp2;
        } else {
            final_ops = in;
        }

        /* Compute per-op (line, col) and emit TSV. cur_line/cur_col
         * are 1-indexed and track where the cursor SHOULD be after
         * applying each op to the (virtual) buffer. */
        int cur_line = hunks[h].target + line_offset;
        int cur_col = 1;
        int newl_ins = 0, newl_del = 0;
        for (int i = 0; i < n_out; i++) {
            Op *op = &final_ops[i];
            if (op->code == 10) {
                if (strcmp(op->type, "keep") == 0) {
                    /* keep \n: cursor advances to next line, col resets. */
                    printf("op\tkeep\t%d\t%d\t%d\n", cur_line, cur_col, op->code);
                    cur_line++;
                    cur_col = 1;
                } else if (strcmp(op->type, "delete") == 0) {
                    /* newline_delete: the line at cur_line is joined
                     * with the next. Cursor stays at the same line+col. */
                    printf("newline_delete\t%d\n", cur_line);
                    newl_del++;
                } else if (strcmp(op->type, "insert") == 0) {
                    /* newline_insert: a new line is inserted AFTER cur_line
                     * at cur_col. Cursor moves to the new line. */
                    printf("newline_insert\t%d\t%d\n", cur_line, cur_col);
                    cur_line++;
                    cur_col = 1;
                    newl_ins++;
                }
            } else {
                printf("op\t%s\t%d\t%d\t%d\n", op->type, cur_line, cur_col, op->code);
                if (strcmp(op->type, "keep") == 0 || strcmp(op->type, "insert") == 0) {
                    cur_col++;
                }
                /* delete: cursor stays at the same col. */
            }
        }

        if (op_order_optimize) free(final_ops);

        line_offset += newl_ins - newl_del;
        op_idx += hunks[h].op_count;
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    read_input();
    write_output();

    /* Cleanup */
    free(ops_in);
    free(ops_out);
    free(hunks);
    for (int i = 0; i < cap_header; i++) free(header[i]);
    free(header);
    return 0;
}
