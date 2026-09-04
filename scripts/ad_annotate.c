/* ad_annotate.c — Add context comments to ops.
 *
 * Reads old/new files and ops from stdin. Outputs annotated ops to stdout.
 *
 * ANNOTATION RULES:
 *   - HUNK header: # old: <full old line> / # new: <full new line>
 *   - Keep bundle (2+ consecutive, same line, no \n):
 *       # keep: "<text>" (line N, cols X-Y)
 *   - Keep bundle (1 op, or \n keep): NO comment
 *   - Delete bundle (any size):
 *       # old: "<line before deletes>"
 *       # new: "<line after deletes>"
 *   - Insert bundle (any size):
 *       # old: "<line before inserts>"
 *       # new: "<line after inserts>"
 *
 * The tool simulates a char-level buffer to show the line content before
 * and after each delete/insert bundle.
 *
 * USAGE:
 *   ad_annotate <oldfile> <newfile> < ops.tsv > annotated_ops.tsv
 *
 * BUILD:
 *   cc -O2 -Wall -Wextra -o bin/ad_annotate scripts/ad_annotate.c
 *
 * PORTING NOTES (for other languages):
 *   - The buffer is a dynamic array of lines, each line is a dynamic
 *     array of int (char codes). This maps to:
 *       C:     int **buffer (array of int arrays)
 *       Perl:  @buffer = ([])  (array of arrayrefs)
 *       Python: buffer = [[]]  (list of lists)
 *   - All line/col values are 1-indexed (matching the TSV format).
 *   - Char codes are Unicode code points (int), not bytes.
 *   - The "escape" function handles \n, \t, \\ in output comments.
 *   - Bundle collection: consecutive ops of the same type.
 *     For keeps: split on \n (code 10) or line number change.
 *     For deletes/inserts: split only on type change.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ── Constants ────────────────────────────────────────────────────── */

#define MAX_LINE_LEN  4096
#define MAX_LINES     100000
#define MAX_BUNDLE    4096
#define MAX_BUF_LINES 100000
#define MAX_BUF_CHARS 65536
#define MAX_OUT_TEXT  65536

#define CHAR_NEWLINE  10
#define CHAR_TAB      9
#define CHAR_BACKSLASH 92

/* ── Op struct (matches the TSV format) ───────────────────────────── */

typedef struct {
    char type[32];   /* "keep", "delete", "insert", "overwrite_insert" */
    int  line;       /* 1-indexed line number */
    int  col;        /* 1-indexed column number */
    int  code;       /* Unicode code point */
    char raw[512];  /* original TSV line (for pass-through output) */
} Op;

/* ── Buffer: array of lines, each line is array of int (char codes) ── */

typedef struct {
    int **lines;       /* lines[L] = array of char codes (0-indexed) */
    int *line_lens;    /* line_lens[L] = number of chars in line L */
    int  n_lines;      /* number of lines (0-indexed, so lines[0..n-1]) */
    int  cap_lines;    /* capacity of lines array */
} Buffer;

/* ── File reading ─────────────────────────────────────────────────── */

/* Read a file into an array of lines (each line is a string).
 * Returns array of malloc'd strings, sets *n_lines.
 * Lines are split on \n. The \n itself is NOT included.
 * Empty trailing line (from trailing \n) is NOT included. */
static char **read_file_lines(const char *filename, int *n_lines) {
    FILE *f = fopen(filename, "r");
    if (!f) {
        fprintf(stderr, "ad_annotate: cannot open %s\n", filename);
        exit(1);
    }

    int cap = 1024;
    char **lines = (char **)malloc(cap * sizeof(char *));
    *n_lines = 0;

    char buf[MAX_LINE_LEN];
    while (fgets(buf, sizeof(buf), f)) {
        /* Strip trailing \n */
        int len = strlen(buf);
        while (len > 0 && (buf[len-1] == '\n' || buf[len-1] == '\r'))
            buf[--len] = 0;

        if (*n_lines >= cap) {
            cap *= 2;
            lines = (char **)realloc(lines, cap * sizeof(char *));
        }
        lines[*n_lines] = strdup(buf);
        (*n_lines)++;
    }
    fclose(f);
    return lines;
}

/* ── Buffer management ────────────────────────────────────────────── */

/* Initialize buffer from old file lines.
 * Each line becomes a buffer line with char codes. */
static void buffer_init(Buffer *buf, char **old_lines, int n_old) {
    buf->cap_lines = n_old > 0 ? n_old : 1;
    buf->lines = (int **)malloc(buf->cap_lines * sizeof(int *));
    buf->line_lens = (int *)calloc(buf->cap_lines, sizeof(int));

    for (int i = 0; i < n_old; i++) {
        int len = strlen(old_lines[i]);
        buf->lines[i] = (int *)malloc((len + 1) * sizeof(int));
        for (int j = 0; j < len; j++) {
            /* Simple: assume ASCII. For UTF-8, would need to decode. */
            buf->lines[i][j] = (unsigned char)old_lines[i][j];
        }
        buf->line_lens[i] = len;
    }
    buf->n_lines = n_old;
}

/* Free buffer contents (not the struct itself). */
static void buffer_free(Buffer *buf) {
    for (int i = 0; i < buf->cap_lines; i++) {
        if (buf->lines[i]) free(buf->lines[i]);
    }
    free(buf->lines);
    free(buf->line_lens);
    buf->lines = NULL;
    buf->line_lens = NULL;
    buf->n_lines = 0;
}

/* Get buffer line content as a string (for annotation output).
 * Returns a malloc'd string. Caller must free. */
static char *buffer_get_line_str(Buffer *buf, int line_1idx) {
    int idx = line_1idx - 1;
    if (idx < 0 || idx >= buf->n_lines) {
        return strdup("");
    }
    int len = buf->line_lens[idx];
    char *s = (char *)malloc(len + 1);
    for (int i = 0; i < len; i++) {
        int code = buf->lines[idx][i];
        if (code < 128) {
            s[i] = (char)code;
        } else {
            /* Simplified: just use '?' for non-ASCII */
            s[i] = '?';
        }
    }
    s[len] = 0;
    return s;
}

/* Apply a delete op to the buffer. */
static void buffer_apply_delete(Buffer *buf, int line_1idx, int col_1idx, int code) {
    int idx = line_1idx - 1;
    int col = col_1idx - 1;

    if (idx < 0 || idx >= buf->n_lines) return;

    if (code == CHAR_NEWLINE) {
        /* \n delete: join this line with the next line */
        if (idx + 1 < buf->n_lines) {
            int next_len = buf->line_lens[idx + 1];
            int cur_len = buf->line_lens[idx];
            buf->lines[idx] = (int *)realloc(buf->lines[idx],
                (cur_len + next_len + 1) * sizeof(int));
            memcpy(&buf->lines[idx][cur_len], buf->lines[idx + 1],
                next_len * sizeof(int));
            buf->line_lens[idx] = cur_len + next_len;

            /* Shift lines down */
            free(buf->lines[idx + 1]);
            for (int i = idx + 1; i < buf->n_lines - 1; i++) {
                buf->lines[i] = buf->lines[i + 1];
                buf->line_lens[i] = buf->line_lens[i + 1];
            }
            buf->n_lines--;
        }
    } else {
        /* Non-\n delete: remove char at col */
        if (col >= 0 && col < buf->line_lens[idx]) {
            memmove(&buf->lines[idx][col], &buf->lines[idx][col + 1],
                (buf->line_lens[idx] - col - 1) * sizeof(int));
            buf->line_lens[idx]--;
        }
    }
}

/* Apply an insert op to the buffer. */
static void buffer_apply_insert(Buffer *buf, int line_1idx, int col_1idx, int code) {
    int idx = line_1idx - 1;
    int col = col_1idx - 1;

    /* Extend buffer if needed */
    if (idx >= buf->cap_lines) {
        int new_cap = idx + 1;
        buf->lines = (int **)realloc(buf->lines, new_cap * sizeof(int *));
        buf->line_lens = (int *)realloc(buf->line_lens, new_cap * sizeof(int));
        for (int i = buf->cap_lines; i < new_cap; i++) {
            buf->lines[i] = NULL;
            buf->line_lens[i] = 0;
        }
        buf->cap_lines = new_cap;
    }
    /* Fill empty lines if needed */
    while (buf->n_lines <= idx) {
        buf->lines[buf->n_lines] = (int *)malloc(sizeof(int));
        buf->line_lens[buf->n_lines] = 0;
        buf->n_lines++;
    }
    if (buf->lines[idx] == NULL) {
        buf->lines[idx] = (int *)malloc(sizeof(int));
        buf->line_lens[idx] = 0;
    }

    if (code == CHAR_NEWLINE) {
        /* \n insert: split line at col */
        int cur_len = buf->line_lens[idx];
        if (col > cur_len) col = cur_len;

        int after_len = cur_len - col;
        int *after = (int *)malloc((after_len + 1) * sizeof(int));
        memcpy(after, &buf->lines[idx][col], after_len * sizeof(int));

        buf->line_lens[idx] = col;

        /* Shift lines up to make room for new line */
        if (buf->n_lines >= buf->cap_lines) {
            buf->cap_lines *= 2;
            buf->lines = (int **)realloc(buf->lines, buf->cap_lines * sizeof(int *));
            buf->line_lens = (int *)realloc(buf->line_lens, buf->cap_lines * sizeof(int));
        }
        for (int i = buf->n_lines; i > idx + 1; i--) {
            buf->lines[i] = buf->lines[i - 1];
            buf->line_lens[i] = buf->line_lens[i - 1];
        }
        buf->lines[idx + 1] = after;
        buf->line_lens[idx + 1] = after_len;
        buf->n_lines++;
    } else {
        /* Non-\n insert: insert char at col */
        int cur_len = buf->line_lens[idx];
        if (col > cur_len) col = cur_len;

        buf->lines[idx] = (int *)realloc(buf->lines[idx], (cur_len + 2) * sizeof(int));
        memmove(&buf->lines[idx][col + 1], &buf->lines[idx][col],
            (cur_len - col) * sizeof(int));
        buf->lines[idx][col] = code;
        buf->line_lens[idx]++;
    }
}

/* ── Escape function for output ───────────────────────────────────── */

/* Escape a string for comment output: \n, \t, \\ become visible. */
static void escape_print(const char *s) {
    putchar('"');
    for (const char *p = s; *p; p++) {
        if (*p == '\n') { putchar('\\'); putchar('n'); }
        else if (*p == '\t') { putchar('\\'); putchar('t'); }
        else if (*p == '\\') { putchar('\\'); putchar('\\'); }
        else putchar(*p);
    }
    putchar('"');
}

/* ── Op parsing ───────────────────────────────────────────────────── */

/* Parse a TSV op line into an Op struct.
 * Returns 1 on success, 0 if not a valid op. */
static int parse_op(const char *line, Op *op) {
    /* Copy raw line for pass-through */
    strncpy(op->raw, line, sizeof(op->raw) - 1);
    op->raw[sizeof(op->raw) - 1] = 0;

    /* Parse: type \t line \t col \t code */
    char type[32];
    int l, c, code;
    int n = sscanf(line, "%31s\t%d\t%d\t%d", type, &l, &c, &code);
    if (n < 4) return 0;

    strncpy(op->type, type, sizeof(op->type) - 1);
    op->type[sizeof(op->type) - 1] = 0;
    op->line = l;
    op->col = c;
    op->code = code;
    return 1;
}

/* Check if a line is a passthrough line (not an op). */
static int is_passthrough(const char *line) {
    if (line[0] == '#' || line[0] == 0) return 1;
    if (strncmp(line, "HUNK\t", 5) == 0) return 1;
    if (strncmp(line, "HUNK_END", 8) == 0) return 1;
    if (strncmp(line, "delay\t", 6) == 0) return 1;
    if (strncmp(line, "snapshot\t", 9) == 0) return 1;
    if (strncmp(line, "highlight\t", 10) == 0) return 1;
    if (strncmp(line, "dim\t", 4) == 0) return 1;
    if (strncmp(line, "fold\t", 5) == 0) return 1;
    if (strncmp(line, "sign\t", 5) == 0) return 1;
    if (strncmp(line, "marker\t", 7) == 0) return 1;
    if (strncmp(line, "glide\t", 6) == 0) return 1;
    if (strncmp(line, "skip_hunk", 9) == 0) return 1;
    if (strcmp(line, "EOF") == 0) return 1;
    return 0;
}

/* ── Main ─────────────────────────────────────────────────────────── */

int main(int argc, char **argv) {
    if (argc < 3 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        printf("ad_annotate — Add context comments to ops.\n\n");
        printf("USAGE\n");
        printf("    ad_annotate <oldfile> <newfile> < ops.tsv > annotated.tsv\n");
        printf("    ad_annotate --help | -h\n\n");
        printf("DESCRIPTION\n");
        printf("    Reads ops from stdin, simulates the buffer, and inserts\n");
        printf("    comment lines showing the text content before/after each\n");
        printf("    bundle of delete or insert ops. Keep bundles (2+) get a\n");
        printf("    summary comment. Single keeps and \\n keeps get no comment.\n\n");
        printf("OUTPUT FORMAT\n");
        printf("    # old: <full old line>        ← before each HUNK\n");
        printf("    # new: <full new line>\n");
        printf("    # keep: \"text\" (line N, cols X-Y)  ← before keep bundles\n");
        printf("    # old: \"line before\"          ← before delete bundles\n");
        printf("    # new: \"line after\"\n");
        printf("    # old: \"line before\"          ← before insert bundles\n");
        printf("    # new: \"line after\"\n\n");
        printf("SEE ALSO\n");
        printf("    ad_gen_ops --annotate  (calls ad_annotate automatically)\n");
        return argc < 3 ? 1 : 0;
    }

    /* Read old and new files */
    int n_old = 0, n_new = 0;
    char **old_lines = read_file_lines(argv[1], &n_old);
    char **new_lines = read_file_lines(argv[2], &n_new);

    /* Buffer for simulation */
    Buffer buf;
    memset(&buf, 0, sizeof(buf));

    /* Read all input lines */
    char **input = (char **)malloc(MAX_LINES * sizeof(char *));
    int n_input = 0;
    char line[MAX_LINE_LEN];

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n\r")] = 0;
        if (n_input >= MAX_LINES) break;
        input[n_input++] = strdup(line);
    }

    /* Allocate bundle array (heap, not stack) */
    Op *bundle = (Op *)malloc(MAX_BUNDLE * sizeof(Op));

    /* Process input */
    int i = 0;
    while (i < n_input) {
        const char *cur = input[i];

        /* Pass through comments, empty lines, EOF */
        if (cur[0] == '#' || cur[0] == 0 || strcmp(cur, "EOF") == 0) {
            printf("%s\n", cur);
            i++;
            continue;
        }

        /* HUNK header: re-init buffer and annotate */
        if (strncmp(cur, "HUNK\t", 5) == 0) {
            int target = 1;
            sscanf(cur, "HUNK\t%d", &target);

            /* Free old buffer, init from old file */
            buffer_free(&buf);
            buffer_init(&buf, old_lines, n_old);

            /* Print hunk annotation */
            char *old_content = (target >= 1 && target <= n_old)
                ? old_lines[target - 1] : "";
            char *new_content = (target >= 1 && target <= n_new)
                ? new_lines[target - 1] : "";

            printf("# old: %s\n", old_content);
            printf("# new: %s\n", new_content);
            printf("%s\n", cur);
            i++;
            continue;
        }

        /* Other passthrough lines */
        if (is_passthrough(cur)) {
            printf("%s\n", cur);
            i++;
            continue;
        }

        /* Parse first op of potential bundle */
        Op first_op;
        if (!parse_op(cur, &first_op)) {
            printf("%s\n", cur);
            i++;
            continue;
        }

        /* Collect bundle: consecutive ops of same type.
         * For keeps: split on \n (code 10) or line change.
         * For deletes/inserts: split only on type change. */
        int n_bundle = 0;
        bundle[n_bundle++] = first_op;

        int j = i + 1;
        while (j < n_input) {
            const char *next = input[j];
            if (is_passthrough(next)) break;

            Op next_op;
            if (!parse_op(next, &next_op)) break;

            /* Must be same type */
            if (strcmp(next_op.type, first_op.type) != 0) break;

            /* For keeps: split on \n or line change */
            if (strcmp(first_op.type, "keep") == 0) {
                if (first_op.code == CHAR_NEWLINE) break;  /* current is \n keep */
                if (next_op.code == CHAR_NEWLINE) break;   /* next is \n keep */
                if (next_op.line != first_op.line) break;   /* line changed */
            }

            bundle[n_bundle++] = next_op;
            j++;
            if (n_bundle >= MAX_BUNDLE) break;
        }

        /* Annotate based on bundle type */
        if (strcmp(first_op.type, "keep") == 0) {
            if (n_bundle >= 2) {
                /* Build text from bundle */
                char text[MAX_OUT_TEXT];
                int text_len = 0;
                for (int k = 0; k < n_bundle && text_len < MAX_OUT_TEXT - 10; k++) {
                    int code = bundle[k].code;
                    if (code == CHAR_NEWLINE) {
                        text[text_len++] = '\\'; text[text_len++] = 'n';
                    } else if (code == CHAR_TAB) {
                        text[text_len++] = '\\'; text[text_len++] = 't';
                    } else if (code < 128) {
                        text[text_len++] = (char)code;
                    } else {
                        text[text_len++] = '?';
                    }
                }
                text[text_len] = 0;

                printf("# keep: \"");
                /* Print escaped text directly */
                for (int k = 0; k < text_len; k++) {
                    if (text[k] == '\\' && k + 1 < text_len) {
                        putchar('\\'); putchar(text[k]); putchar(text[k+1]);
                        k++;
                    } else {
                        putchar(text[k]);
                    }
                }
                printf("\" (line %d, cols %d-%d)\n",
                    first_op.line, first_op.col, bundle[n_bundle-1].col);
            }
            /* Keeps don't change buffer */
        }
        else if (strcmp(first_op.type, "delete") == 0) {
            /* Get line content before deletes */
            char *before = buffer_get_line_str(&buf, first_op.line);

            /* Apply all deletes to buffer */
            for (int k = 0; k < n_bundle; k++) {
                buffer_apply_delete(&buf, bundle[k].line, bundle[k].col, bundle[k].code);
            }

            /* Get line content after deletes */
            char *after = buffer_get_line_str(&buf, first_op.line);

            printf("# old: ");
            escape_print(before);
            printf("\n# new: ");
            escape_print(after);
            printf("\n");

            free(before);
            free(after);
        }
        else if (strcmp(first_op.type, "insert") == 0
                 || strcmp(first_op.type, "overwrite_insert") == 0) {
            /* Get line content before inserts */
            char *before = buffer_get_line_str(&buf, first_op.line);

            /* Apply all inserts to buffer */
            for (int k = 0; k < n_bundle; k++) {
                buffer_apply_insert(&buf, bundle[k].line, bundle[k].col, bundle[k].code);
            }

            /* Get line content after inserts */
            char *after = buffer_get_line_str(&buf, first_op.line);

            printf("# old: ");
            escape_print(before);
            printf("\n# new: ");
            escape_print(after);
            printf("\n");

            free(before);
            free(after);
        }

        /* Output the ops */
        for (int k = 0; k < n_bundle; k++) {
            printf("%s\n", bundle[k].raw);
        }

        i = j;
    }

    /* Cleanup */
    buffer_free(&buf);
    for (int k = 0; k < n_old; k++) free(old_lines[k]);
    for (int k = 0; k < n_new; k++) free(new_lines[k]);
    free(old_lines);
    free(new_lines);
    for (int k = 0; k < n_input; k++) free(input[k]);
    free(bundle);
    free(input);

    return 0;
}
