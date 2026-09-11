/* --- ad_layer_common.h — Shared infrastructure for postprocess layers.
 *
 * Design principles:
 *   1. Each layer is a standalone binary: reads TSV stdin → writes TSV stdout.
 *   2. The ad_layer_run() driver handles all I/O — layers just provide
 *      a transform function.
 *   3. No env vars, no debug dumps, no dead code.
 *
 * Layer function signature:
 *   int layer_func(Op *in, int in_count, Op *out, int out_cap, int *line_offset);
 *   Returns: number of output ops.
 *   May update *line_offset (for cross-hunk position tracking).
 *
 * Standalone mode (each layer .c file):
 *   int main(void) {
 *       return ad_layer_run(my_transform);
 *   }
 */

#ifndef AD_LAYER_COMMON_H
#define AD_LAYER_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

/* ── Globals for argv access (--help) ──────────────────────────────── */
static int __argc = 0;
static char **__argv = NULL;

/* ── Constants ───────────────────────────────────────────────────────
 *
 * NOTE: C does not have `const` for true compile-time constants usable in
 * array sizes / switch labels — we use #define macros. In C++ these would
 * be `constexpr int`. Keep these here so every layer .c file shares the
 * same values (no magic numbers scattered across files). */

#define AD_LAYER_MAX_LINE   1048576   /* 1MB max line */
#define AD_LAYER_TYPE_LEN   20        /* max op type string length */

/* Capacity / sizing magic numbers */
#define AD_LAYER_INIT_CAPACITY  4096  /* initial op array capacity */
#define AD_LAYER_OUTPUT_SLACK   1024  /* extra slots in output buffer */

/* TSV parsing */
#define AD_LAYER_MAX_TOKENS     8     /* max TSV tokens per line */

/* ASCII character codes (used for char-code comparisons) */
#define AD_LAYER_CHAR_SPACE     32    /* ASCII space */
#define AD_LAYER_CHAR_TAB       9     /* ASCII tab */
#define AD_LAYER_CHAR_NEWLINE   10    /* ASCII newline */

/* Default pause (ms) after an indent-only hunk is skipped */
#define AD_LAYER_DEFAULT_SKIP_PAUSE_MS 300

/* ── Op struct ─────────────────────────────────────────────────────── */

typedef struct {
    char type[AD_LAYER_TYPE_LEN];  /* "keep", "delete", "insert", "overwrite_insert",
                                    * "delete_line", "insert_line", "delay", etc. */
    int  code;               /* char code (10=\n, 32=space, 9=tab, etc.) */
    int  line;               /* 1-indexed line number */
    int  col;                /* 1-indexed column number */
    char *text;              /* text for insert_line ops (NULL otherwise) */
} Op;

/* ── Hunk struct ───────────────────────────────────────────────────── */

typedef struct {
    int target;
    int del;
    int ins;
    int end_ins;
    int end_del;
} Hunk;

/* ── char_repr helper ──────────────────────────────────────────────── */

static const char *ad_layer_char_repr(int code) {
    static char buf[8];
    switch (code) {
        case 10: return "\\n";
        case 9:  return "\\t";
        case 13: return "\\r";
        case 32: return "space";
        default:
            if (code >= 33 && code <= 126) {
                buf[0] = '\''; buf[1] = (char)code; buf[2] = '\''; buf[3] = 0;
                return buf;
            }
            snprintf(buf, sizeof(buf), "%d", code);
            return buf;
    }
}

/* ── TSV Parsing ──────────────────────────────────────────────────── */

static int ad_layer_parse_op(const char *line, Op *op) {
    op->text = NULL;  /* default: no text */
    char type[AD_LAYER_TYPE_LEN];
    int l, c, code;
    int n = sscanf(line, "%19s\t%d\t%d\t%d", type, &l, &c, &code);
    if (n >= 4) {
        size_t tlen = strlen(type);
        if (tlen >= AD_LAYER_TYPE_LEN) tlen = AD_LAYER_TYPE_LEN - 1;
        memcpy(op->type, type, tlen);
        op->type[tlen] = 0;
        op->line = l;
        op->col = c;
        op->code = code;
        return 1;
    }
    /* Try insert_line format: insert_line\t<line>\t<text> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "insert_line") == 0) {
        strcpy(op->type, "insert_line");
        op->line = l;
        op->col = 0;
        op->code = 0;
        /* Extract text (everything after the second tab) */
        const char *p = line;
        int tab_count = 0;
        while (*p && tab_count < 2) {
            if (*p == '\t') tab_count++;
            p++;
        }
        if (*p) {
            op->text = strdup(p);
        } else {
            op->text = strdup("");
        }
        return 1;
    }
    /* Try keep_line format: keep_line\t<line> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "keep_line") == 0) {
        strcpy(op->type, "keep_line");
        op->line = l; op->col = 0; op->code = 0;
        return 1;
    }
    /* Try join_lines format: join_lines\t<line> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "join_lines") == 0) {
        strcpy(op->type, "join_lines");
        op->line = l; op->col = 0; op->code = 0;
        return 1;
    }
    /* Try split_line format: split_line\t<line>\t<col> */
    if (sscanf(line, "%19s\t%d\t%d", type, &l, &c) >= 3 &&
        strcmp(type, "split_line") == 0) {
        strcpy(op->type, "split_line");
        op->line = l; op->col = c; op->code = 0;
        return 1;
    }
    /* Try delete_line format: delete_line\t<line> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "delete_line") == 0) {
        strcpy(op->type, "delete_line");
        op->line = l;
        op->col = 0;
        op->code = 0;
        return 1;
    }
    /* Try batch_insert format: batch_insert\t<line>\t<col>\t<codes>
     * Store the codes string in op->text (like insert_line). */
    if (sscanf(line, "%19s\t%d\t%d", type, &l, &c) >= 3 &&
        strcmp(type, "batch_insert") == 0) {
        strcpy(op->type, "batch_insert");
        op->line = l;
        op->col = c;
        op->code = 0;
        /* Extract codes (everything after the third tab) */
        const char *p = line;
        int tab_count = 0;
        while (*p && tab_count < 3) {
            if (*p == '\t') tab_count++;
            p++;
        }
        op->text = strdup(*p ? p : "");
        return 1;
    }
    /* Catch-all: if the type has at least a line number, parse it
     * generically and pass through. This ensures unknown op types
     * (delay, snapshot, highlight, etc.) are not dropped. */
    {
        char t2[AD_LAYER_TYPE_LEN];
        int l2, c2, code2;
        int n2 = sscanf(line, "%19s\t%d\t%d\t%d", t2, &l2, &c2, &code2);
        if (n2 >= 1) {
            /* Store the raw line in op->text so it can be written back verbatim */
            strncpy(op->type, t2, AD_LAYER_TYPE_LEN - 1);
            op->type[AD_LAYER_TYPE_LEN - 1] = 0;
            op->line = (n2 >= 2) ? l2 : 0;
            op->col = (n2 >= 3) ? c2 : 0;
            op->code = (n2 >= 4) ? code2 : 0;
            op->text = strdup(line);  /* store raw line for verbatim output */
            return 1;
        }
    }
    return 0;
}

/* ── Parse op fields from a raw TSV line (for layers that tokenize
 * differently). Returns 1 on success. */
__attribute__((unused)) static int ad_layer_parse_op_fields(const char *line, const char *type,
                                     int *out_line, int *out_col, int *out_code) {
    char t[AD_LAYER_TYPE_LEN];
    int n = sscanf(line, "%19s\t%d\t%d\t%d", t, out_line, out_col, out_code);
    if (n >= 4 && strcmp(t, type) == 0) return 1;
    return 0;
}

/* ── Parse TSV line into tokens (for layers that need all fields) ────
 * Splits on \t in place. Returns token count. */
__attribute__((unused)) static int ad_layer_parse_tsv(char *line, char *toks[], int max_toks) {
    int n = 0;
    char *p = line;
    char *tab = strchr(p, '\t');
    while (tab && n < max_toks - 1) {
        *tab = 0;
        toks[n++] = p;
        p = tab + 1;
        tab = strchr(p, '\t');
    }
    toks[n++] = p;
    return n;
}

/* ── TSV Writing ──────────────────────────────────────────────────── */

static void ad_layer_write_op(Op *op) {
    if (strcmp(op->type, "keep_line") == 0) {
        printf("keep_line\t%d\n", op->line);
    } else if (strcmp(op->type, "join_lines") == 0) {
        printf("join_lines\t%d\n", op->line);
    } else if (strcmp(op->type, "split_line") == 0) {
        printf("split_line\t%d\t%d\n", op->line, op->col);
    } else if (strcmp(op->type, "insert_line") == 0) {
        /* insert_line\t<line>\t<text> */
        printf("%s\t%d\t%s\n", op->type, op->line,
               op->text ? op->text : "");
    } else if (strcmp(op->type, "delete_line") == 0) {
        /* delete_line\t<line> */
        printf("%s\t%d\n", op->type, op->line);
    } else if (strcmp(op->type, "batch_insert") == 0) {
        /* batch_insert\t<line>\t<col>\t<codes> */
        printf("%s\t%d\t%d\t%s\n", op->type, op->line, op->col,
               op->text ? op->text : "");
    } else if (op->text && op->text[0] != '\0' &&
               strchr(op->text, '\t') != NULL) {
        /* Catch-all: if op->text contains the raw line (with tabs),
         * write it verbatim. This passes through unknown op types
         * (delay, snapshot, highlight, dim, fold, sign, marker, etc.)
         * without dropping or mangling them. */
        printf("%s\n", op->text);
    } else {
        /* Standard format: type\tline\tcol\tcode\tchar_repr */
        printf("%s\t%d\t%d\t%d\t%s\n", op->type, op->line, op->col,
               op->code, ad_layer_char_repr(op->code));
    }
}

static void ad_layer_write_hunk(Hunk *h) {
    printf("HUNK\t%d\t%d\t%d\t%d\t%d\n", h->target, h->del, h->ins,
           h->end_ins, h->end_del);
}

static void ad_layer_write_hunk_end(void) {
    printf("HUNK_END\n");
}

/* ── Debug op helpers ──────────────────────────────────────────────── */

__attribute__((unused)) static int ad_layer_is_debug_op(Op *op) {
    return strcmp(op->type, "debug") == 0;
}

/* Check if an op is a line-level op (keep_line, join_lines, split_line).
 * These replace the old code==10 (\n) char ops. Line ops are segment
 * boundaries in layers — they delimit line segments. */
__attribute__((unused)) static int ad_layer_is_line_op(Op *op) {
    return strcmp(op->type, "keep_line") == 0 ||
           strcmp(op->type, "join_lines") == 0 ||
           strcmp(op->type, "split_line") == 0 ||
           strcmp(op->type, "delete_line") == 0;
}

/* ── Shared position-walk function ──────────────────────────────────
 * Recompute (line, col) for every op in the output array.
 *
 * Walks forward, tracking current_line and current_col based on
 * each op's type:
 *   - non-\n op: assign (current_line, current_col), advance col for keep/insert
 *   - \n delete: assign position, DON'T advance (join brings content here)
 *   - \n keep/insert: assign position, advance to next line
 *
 * This is THE correct position-walk (verified by reorder's 42/42 pass rate).
 * Every layer should call this after its transform.
 */
__attribute__((unused)) static void ad_layer_recompute_positions(Op *out, int n_out) {
    if (n_out <= 0) return;
    int current_line = out[0].line;
    int current_col = 1;
    for (int i = 0; i < n_out; i++) {
        if (ad_layer_is_debug_op(&out[i])) continue;
        
        int is_newline = (out[i].code == AD_LAYER_CHAR_NEWLINE);
        
        if (!is_newline) {
            out[i].line = current_line;
            out[i].col = current_col;
            if (strcmp(out[i].type, "keep") == 0
                || strcmp(out[i].type, "insert") == 0
                || strcmp(out[i].type, "overwrite_insert") == 0) {
                current_col++;
            }
        } else {
            out[i].line = current_line;
            out[i].col = current_col;
            if (strcmp(out[i].type, "delete") == 0) {
                /* \n delete: join — DON'T advance */
            } else {
                /* \n keep/insert: advance to next line */
                current_line++;
                current_col = 1;
            }
        }
    }
}

/* ── Standalone Layer Runner ────────────────────────────────────────
 * Reads TSV from stdin, parses into Op array per hunk, calls the
 * layer function for each hunk, writes the result to stdout.
 *
 * The layer function:
 *   int func(Op *in, int in_count, Op *out, int out_cap, int *line_offset)
 *   - Reads from in[0..in_count-1]
 *   - Writes to out[0..out_cap-1]
 *   - May update *line_offset (for cross-hunk tracking)
 *   - Returns number of output ops
 *
 * Headers, HUNK/HUNK_END lines, and blank lines are handled by the runner.
 * Debug ops (type="debug") are passed through to the layer function.
 */
__attribute__((unused)) static int ad_layer_run(
    int (*layer_func)(Op *in, int in_count, Op *out, int out_cap, int *line_offset)
) {
    char line[AD_LAYER_MAX_LINE];
    Op *in_ops = NULL;
    int in_count = 0;
    int in_cap = 0;
    int in_hunk = 0;
    Hunk current_hunk = {0};
    int hunk_count = 0;
    int line_offset = 0;  /* cumulative (\n_ins - \n_del) from prior hunks */

    /* Check for --help / -h in argv */
    for (int i = 1; i < __argc; i++) {
        if (strcmp(__argv[i], "--help") == 0 || strcmp(__argv[i], "-h") == 0) {
            const char *name = __argv[0] ? strrchr(__argv[0], '/') : NULL;
            name = name ? name + 1 : (__argv[0] ? __argv[0] : "ad_layer");
            fprintf(stderr, "Usage: %s < ops.tsv > processed.tsv\n", name);
            fprintf(stderr, "  Reads V2 TSV ops from stdin, applies the layer transform, writes to stdout.\n");
            fprintf(stderr, "  --help, -h   Show this help and exit.\n");
            fprintf(stderr, "\n");
            fprintf(stderr, "See man/%s.1 for full documentation.\n", name);
            return 0;
        }
    }

    in_cap = AD_LAYER_INIT_CAPACITY;
    in_ops = (Op *)malloc(in_cap * sizeof(Op));
    if (!in_ops) { fprintf(stderr, "out of memory\n"); return 1; }

    /* Process a completed hunk: call the layer function, write output,
     * update line_offset. */
    #define AD_LAYER_FLUSH_HUNK() do {                                    \
        if (in_hunk && in_count > 0) {                                   \
            Op *out_ops = (Op *)malloc((in_count + AD_LAYER_OUTPUT_SLACK) * sizeof(Op)); \
            if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; } \
            int out_count = layer_func(in_ops, in_count, out_ops,       \
                                       in_count + AD_LAYER_OUTPUT_SLACK, &line_offset);  \
            ad_layer_write_hunk(&current_hunk);                         \
            for (int i = 0; i < out_count; i++)                         \
                ad_layer_write_op(&out_ops[i]);                        \
            ad_layer_write_hunk_end();                                   \
            free(out_ops);                                              \
        }                                                                \
        in_count = 0;                                                   \
    } while (0)

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n\r")] = 0;

        /* Skip empty lines */
        if (line[0] == 0) continue;

        /* Headers (# ...) — rewrite top header, pass through rest */
        if (line[0] == '#') {
            if (strstr(line, "raw diff") || strstr(line, "post-processed"))
                printf("# diffvim post-processed v2\n");
            else
                printf("%s\n", line);
            continue;
        }

        /* HUNK header */
        if (strncmp(line, "HUNK\t", 5) == 0) {
            AD_LAYER_FLUSH_HUNK();
            sscanf(line, "HUNK\t%d\t%d\t%d\t%d\t%d",
                   &current_hunk.target, &current_hunk.del, &current_hunk.ins,
                   &current_hunk.end_ins, &current_hunk.end_del);
            in_hunk = 1;
            hunk_count++;
            continue;
        }

        /* HUNK_END */
        if (strncmp(line, "HUNK_END", 8) == 0) {
            AD_LAYER_FLUSH_HUNK();
            in_hunk = 0;
            continue;
        }

        /* EOF — stop reading. Any ops after EOF are ignored. */
        if (strcmp(line, "EOF") == 0) {
            break;
        }

        /* Op line — parse and add to current hunk's array */
        if (in_hunk) {
            if (in_count >= in_cap) {
                in_cap *= 2;
                Op *tmp = (Op *)realloc(in_ops, in_cap * sizeof(Op));
                if (!tmp) { fprintf(stderr, "out of memory\n"); free(in_ops); return 1; }
                in_ops = tmp;
            }
            if (ad_layer_parse_op(line, &in_ops[in_count])) {
                in_count++;
            }
        }
    }

    /* Handle last hunk if no HUNK_END was seen */
    AD_LAYER_FLUSH_HUNK();

    printf("\n");  /* trailing blank line */
    free(in_ops);
    return 0;

    #undef AD_LAYER_FLUSH_HUNK
}

#endif /* AD_LAYER_COMMON_H */
