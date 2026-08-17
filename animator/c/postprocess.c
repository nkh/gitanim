/* diffvim-postprocess — Post-process raw char ops.
 *
 * Reads raw char ops from stdin, applies post-processing, writes to stdout.
 *
 * Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup]
 *                             [--indent-aware] [--overwrite]
 *
 * Build: cc -O2 -o diffvim-postprocess postprocess.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_OPS 100000
#define MAX_LINE 4096

typedef struct { char type[8]; int code; } Op;

static Op ops_in[MAX_OPS];
static Op ops_out[MAX_OPS];
static int n_ops = 0;

/* Header lines (passed through) */
static char header[100][MAX_LINE];
static int n_header = 0;

/* Hunk info */
typedef struct { int target, del, ins, end_ins, end_del; int op_start, op_count; } Hunk;
static Hunk hunks[1000];
static int n_hunks = 0;

static int op_order_optimize = 1;
static int do_semantic = 0;
static int do_indent = 0;
static int do_overwrite = 0;

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
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup] [--indent-aware] [--overwrite]\n");
            exit(0);
        }
    }
}

void read_input(void) {
    char line[MAX_LINE];
    int current_hunk = -1;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#') {
            if (n_header < 100) strncpy(header[n_header++], line, MAX_LINE-1);
            continue;
        }
        if (strncmp(line, "HUNK", 4) == 0) {
            if (n_hunks < 1000) {
                int t,d,i,ei,ed;
                sscanf(line, "HUNK %d %d %d %d %d", &t,&d,&i,&ei,&ed);
                hunks[n_hunks].target = t; hunks[n_hunks].del = d;
                hunks[n_hunks].ins = i; hunks[n_hunks].end_ins = ei;
                hunks[n_hunks].end_del = ed;
                hunks[n_hunks].op_start = n_ops;
                hunks[n_hunks].op_count = 0;
                current_hunk = n_hunks;
                n_hunks++;
            }
            continue;
        }
        if (strncmp(line, "keep", 4) == 0 || strncmp(line, "delete", 6) == 0 || strncmp(line, "insert", 6) == 0) {
            char type[8]; int code;
            sscanf(line, "%s %d", type, &code);
            if (n_ops < MAX_OPS) {
                strncpy(ops_in[n_ops].type, type, 7);
                ops_in[n_ops].code = code;
                n_ops++;
                if (current_hunk >= 0) hunks[current_hunk].op_count++;
            }
        }
    }
}

/* Optimize: within each change region (between keeps), deletes before inserts */
int optimize_line(Op *in, int count, Op *out) {
    int n_out = 0;
    int buf_start = 0; /* start of current change region */

    for (int i = 0; i <= count; i++) {
        if (i == count || strcmp(in[i].type, "keep") == 0) {
            /* Flush buffer: deletes first, then inserts */
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0) out[n_out++] = in[j];
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

/* Reorder ops within each line (delimited by code==10) */
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

    /* Write hunks */
    int op_idx = 0;
    for (int h = 0; h < n_hunks; h++) {
        printf("HUNK %d %d %d %d %d\n",
               hunks[h].target, hunks[h].del, hunks[h].ins,
               hunks[h].end_ins, hunks[h].end_del);

        int count = hunks[h].op_count;
        Op *in = &ops_in[op_idx];
        Op temp_out[MAX_OPS];
        int n_out = count;

        if (do_semantic) {
            n_out = semantic_cleanup(in, count, temp_out);
            in = temp_out;
            count = n_out;
        }
        if (op_order_optimize) {
            Op temp2[MAX_OPS];
            n_out = reorder_hunk_ops(in, count, temp2);
            in = temp2;
        }

        for (int i = 0; i < n_out; i++)
            printf("%s %d\n", in[i].type, in[i].code);

        op_idx += hunks[h].op_count;
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    read_input();
    write_output();
    return 0;
}
