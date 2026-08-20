/* l2r_tool.c — Standalone left_to_right transform (NOT integrated).
 *
 * Reads v2 TSV ops from stdin, applies the NEW left_to_right algorithm,
 * writes reordered ops with recomputed positions to stdout.
 *
 * Algorithm:
 *   - Keeps stay in place (they are anchors)
 *   - Within each "change region" (consecutive non-keep ops between keeps),
 *     all DELETEs are emitted first, then all INSERTs
 *   - Positions (line, col) are recomputed by walking the output
 *
 * Build: cc -O2 -o l2r_tool l2r_tool.c
 * Usage: ./l2r_tool < input.ops > output.ops
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 1048576

typedef struct {
    char type[8];   /* keep, delete, insert */
    int code;
    /* line/col from input — ignored, we recompute */
} Op;

static Op *ops = NULL;
static int n_ops = 0;
static int cap_ops = 0;

/* Hunk info */
typedef struct {
    int target, del, ins, end_ins, end_del;
    int op_start;
    int op_count;
} Hunk;

static Hunk *hunks = NULL;
static int n_hunks = 0;
static int cap_hunks = 0;

static char **headers = NULL;
static int n_headers = 0;
static int cap_headers = 0;

void ensure_ops(int needed) {
    if (needed <= cap_ops) return;
    int nc = cap_ops == 0 ? 4096 : cap_ops;
    while (nc < needed) nc *= 2;
    ops = realloc(ops, nc * sizeof(Op));
    if (!ops) { fprintf(stderr, "out of memory\n"); exit(1); }
    cap_ops = nc;
}

void ensure_hunks(int needed) {
    if (needed <= cap_hunks) return;
    int nc = cap_hunks == 0 ? 64 : cap_hunks;
    while (nc < needed) nc *= 2;
    hunks = realloc(hunks, nc * sizeof(Hunk));
    if (!hunks) { fprintf(stderr, "out of memory\n"); exit(1); }
    cap_hunks = nc;
}

void ensure_headers(int needed) {
    if (needed <= cap_headers) return;
    int nc = cap_headers == 0 ? 32 : cap_headers;
    while (nc < needed) nc *= 2;
    headers = realloc(headers, nc * sizeof(char *));
    if (!headers) { fprintf(stderr, "out of memory\n"); exit(1); }
    for (int i = cap_headers; i < nc; i++) {
        headers[i] = malloc(MAX_LINE);
        if (!headers[i]) { fprintf(stderr, "out of memory\n"); exit(1); }
    }
    cap_headers = nc;
}

/* Char representation for output */
const char *char_repr(int code) {
    static char buf[8];
    switch (code) {
        case 10: return "\\n";
        case 9: return "\\t";
        case 13: return "\\r";
        case 32: return "space";
        default:
            if (code >= 33 && code <= 126) {
                buf[0] = '\'';
                buf[1] = (char)code;
                buf[2] = '\'';
                buf[3] = 0;
                return buf;
            }
            snprintf(buf, sizeof(buf), "%d", code);
            return buf;
    }
}

void read_input(void) {
    char line[MAX_LINE];
    int current_hunk = -1;
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#' || line[0] == 0) {
            if (line[0] == '#') {
                ensure_headers(n_headers + 1);
                strncpy(headers[n_headers++], line, MAX_LINE - 1);
                headers[n_headers - 1][MAX_LINE - 1] = 0;
            }
            continue;
        }
        /* TSV tokenize */
        char *toks[8];
        int ntok = 0;
        char *p = line;
        char *tab = strchr(p, '\t');
        while (tab && ntok < 7) {
            *tab = 0;
            toks[ntok++] = p;
            p = tab + 1;
            tab = strchr(p, '\t');
        }
        toks[ntok++] = p;

        if (strcmp(toks[0], "HUNK") == 0 && ntok >= 6) {
            ensure_hunks(n_hunks + 1);
            hunks[n_hunks].target = atoi(toks[1]);
            hunks[n_hunks].del = atoi(toks[2]);
            hunks[n_hunks].ins = atoi(toks[3]);
            hunks[n_hunks].end_ins = atoi(toks[4]);
            hunks[n_hunks].end_del = atoi(toks[5]);
            hunks[n_hunks].op_start = n_ops;
            hunks[n_hunks].op_count = 0;
            current_hunk = n_hunks;
            n_hunks++;
            continue;
        }
        if (strcmp(toks[0], "HUNK_END") == 0) {
            current_hunk = -1;
            continue;
        }
        if ((strcmp(toks[0], "keep") == 0 || strcmp(toks[0], "delete") == 0 ||
             strcmp(toks[0], "insert") == 0) && ntok >= 4) {
            ensure_ops(n_ops + 1);
            strncpy(ops[n_ops].type, toks[0], 7);
            ops[n_ops].type[7] = 0;
            ops[n_ops].code = atoi(toks[3]);
            n_ops++;
            if (current_hunk >= 0) hunks[current_hunk].op_count++;
        }
    }
}

/* NEW left_to_right: within each change region (consecutive non-keep,
 * non-newline ops), emit all deletes first, then all inserts.
 * Keeps and \n ops stay in place (they are line boundaries). */
void apply_l2r(Op *in, int count, Op *out) {
    int n_out = 0;
    int i = 0;
    while (i < count) {
        if (strcmp(in[i].type, "keep") == 0 || in[i].code == 10) {
            /* Keep or \n: stays in place (line boundary) */
            out[n_out++] = in[i];
            i++;
        } else {
            /* Start of change region: collect consecutive non-keep, non-\n ops */
            int region_start = i;
            while (i < count && strcmp(in[i].type, "keep") != 0 && in[i].code != 10)
                i++;
            int region_end = i;
            /* Emit all deletes first */
            for (int j = region_start; j < region_end; j++) {
                if (strcmp(in[j].type, "delete") == 0)
                    out[n_out++] = in[j];
            }
            /* Then all inserts */
            for (int j = region_start; j < region_end; j++) {
                if (strcmp(in[j].type, "insert") == 0)
                    out[n_out++] = in[j];
            }
        }
    }
}

void write_output(void) {
    /* Headers */
    for (int i = 0; i < n_headers; i++) {
        if (strncmp(headers[i], "# diffvim raw diff", 18) == 0)
            printf("# diffvim l2r transformed v2\n");
        else if (strncmp(headers[i], "# left_to_right", 15) == 0)
            printf("# left_to_right 1\n");
        else
            printf("%s\n", headers[i]);
    }

    int op_idx = 0;
    for (int h = 0; h < n_hunks; h++) {
        printf("HUNK\t%d\t%d\t%d\t%d\t%d\n",
               hunks[h].target, hunks[h].del, hunks[h].ins,
               hunks[h].end_ins, hunks[h].end_del);

        int count = hunks[h].op_count;
        Op *in = &ops[op_idx];
        Op *out = malloc(count * sizeof(Op));
        apply_l2r(in, count, out);

        /* Recompute positions by walking the output */
        int cur_line = hunks[h].target;
        int cur_col = 1;
        for (int i = 0; i < count; i++) {
            printf("%s\t%d\t%d\t%d\t%s\n", out[i].type, cur_line, cur_col,
                   out[i].code, char_repr(out[i].code));
            if (out[i].code == 10) {
                cur_line++;
                cur_col = 1;
            } else {
                if (strcmp(out[i].type, "keep") == 0 || strcmp(out[i].type, "insert") == 0)
                    cur_col++;
                /* delete: col stays */
            }
        }
        free(out);
        printf("HUNK_END\n");
        op_idx += hunks[h].op_count;
    }
    printf("\n");
}

int main(void) {
    read_input();
    write_output();
    free(ops);
    free(hunks);
    for (int i = 0; i < cap_headers; i++) free(headers[i]);
    free(headers);
    return 0;
}
