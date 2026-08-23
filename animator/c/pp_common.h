/*
 * pp_common.h — Shared types and helpers for postprocess layers.
 *
 * All layers (C) include this header. It provides:
 *   - The Op struct (one diff operation)
 *   - Debug/logging helpers (pp_debug_init, pp_log, pp_logf, pp_dump)
 *   - The layer main loop (read TSV → Op array → process → write TSV)
 *
 * Design:
 *   Each layer is a function: int layer_N(Op *in, int count, Op *out)
 *   The function reads N ops, processes them, writes M ops.
 *   M can be < N (some ops merged), = N (passthrough), or > N (ops added).
 *
 *   The layer can be:
 *     1. Compiled into the main postprocess executable (linked)
 *     2. Compiled standalone (cc -DPP_STANDALONE -o pp_layerN pp_layerN.c)
 *
 *   In standalone mode, the binary reads TSV from stdin, parses into
 *   Op array, calls the layer function, writes TSV to stdout.
 */

#ifndef PP_COMMON_H
#define PP_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>

/* ── Constants ─────────────────────────────────────────────────────── */

#define PP_MAX_LINE  1048576   /* 1MB max line length */
#define PP_MAX_OPS   1000000   /* max ops in one hunk (grows dynamically) */
#define PP_TYPE_LEN  20        /* max length of op type string */
#define PP_NUM_LAYERS 4        /* total number of layers */

/* ── Op struct ─────────────────────────────────────────────────────── */

typedef struct {
    char type[PP_TYPE_LEN];  /* "keep", "delete", "insert", "overwrite_insert" */
    int  code;               /* char code (10=\n, 32=space, 9=tab, etc.) */
    int  line;               /* 1-indexed line number */
    int  col;                /* 1-indexed column number */
} Op;

/* ── Hunk struct ───────────────────────────────────────────────────── */

typedef struct {
    int target;     /* target line in old file */
    int del;        /* deleted line count */
    int ins;        /* inserted line count */
    int end_ins;    /* is_end_insert flag */
    int end_del;    /* is_end_delete flag */
    int op_start;   /* index into ops array where this hunk's ops begin */
    int op_count;   /* number of ops in this hunk */
} Hunk;

/* ── Debug/Logging ─────────────────────────────────────────────────── */

static int pp_debug = 0;
static FILE *pp_log_file = NULL;
static const char *pp_layer_name = "unknown";

/* Initialize debug logging. Call once at startup. */
static void pp_debug_init(const char *layer_name) {
    pp_layer_name = layer_name;
    const char *env = getenv("DV_DEBUG_POSTPROCESS");
    pp_debug = (env && env[0] == '1');
    if (pp_debug) {
        mkdir("/tmp/dv_debug", 0755);
        /* Append to the log (all layers share one log) */
        pp_log_file = fopen("/tmp/dv_debug/postprocess.log", "a");
        if (pp_log_file) {
            fprintf(pp_log_file, "\n--- %s ---\n", layer_name);
        }
    }
}

/* Log a message. */
static void pp_log(const char *msg) {
    if (!pp_debug || !pp_log_file) return;
    fprintf(pp_log_file, "[%s] %s\n", pp_layer_name, msg);
}

/* Log a formatted message. */
static void pp_logf(const char *fmt, ...) {
    if (!pp_debug || !pp_log_file) return;
    va_list args;
    va_start(args, fmt);
    fprintf(pp_log_file, "[%s] ", pp_layer_name);
    vfprintf(pp_log_file, fmt, args);
    fprintf(pp_log_file, "\n");
    va_end(args);
}

/* Dump an Op array to a file (for layer debugging). */
static void pp_dump_ops(const char *filename, Op *ops, int count) {
    if (!pp_debug) return;
    char path[256];
    snprintf(path, sizeof(path), "/tmp/dv_debug/%s", filename);
    FILE *f = fopen(path, "w");
    if (!f) return;
    for (int i = 0; i < count; i++) {
        fprintf(f, "%s\t%d\t%d\t%d\n", ops[i].type, ops[i].line, ops[i].col, ops[i].code);
    }
    fclose(f);
}

/* Dump raw TSV data to a file. */
__attribute__((unused))
static void pp_dump_raw(const char *filename, const char *data, size_t len) {
    if (!pp_debug) return;
    char path[256];
    snprintf(path, sizeof(path), "/tmp/dv_debug/%s", filename);
    FILE *f = fopen(path, "w");
    if (!f) return;
    fwrite(data, 1, len, f);
    fclose(f);
}

/* ── TSV Parsing ──────────────────────────────────────────────────── */

/* Parse a TSV line into an Op. Returns 1 on success, 0 on failure. */
static int pp_parse_op(const char *line, Op *op) {
    /* Format: type\tline\tcol\tcode */
    /* Note: compute output may have extra fields (char_repr) — ignore them */
    char type[PP_TYPE_LEN];
    int l, c, code;
    int n = sscanf(line, "%19s\t%d\t%d\t%d", type, &l, &c, &code);
    if (n >= 4) {
        strncpy(op->type, type, PP_TYPE_LEN - 1);
        op->type[PP_TYPE_LEN - 1] = 0;
        op->line = l;
        op->col = c;
        op->code = code;
        return 1;
    }
    return 0;
}

/* ── TSV Writing ──────────────────────────────────────────────────── */

/* Write an Op to stdout in TSV format. */
static void pp_write_op(Op *op) {
    printf("%s\t%d\t%d\t%d\n", op->type, op->line, op->col, op->code);
}

/* Write a HUNK header. */
static void pp_write_hunk(Hunk *h) {
    printf("HUNK\t%d\t%d\t%d\t%d\t%d\n", h->target, h->del, h->ins, h->end_ins, h->end_del);
}

/* Write HUNK_END. */
static void pp_write_hunk_end(void) {
    printf("HUNK_END\n");
}

/* ── Standalone Layer Runner ──────────────────────────────────────── */

/*
 * A standalone layer binary uses this function as its main().
 * It:
 *   1. Reads TSV from stdin
 *   2. Parses into Op array
 *   3. Calls the layer function
 *   4. Writes the result to stdout
 *
 * The layer function signature:
 *   int layer_func(Op *in, int in_count, Op *out, int out_cap)
 *   Returns: number of output ops (can be <, =, or > input)
 *
 * Usage in standalone file:
 *   #include "pp_common.h"
 *   int my_layer(Op *in, int in_count, Op *out, int out_cap) { ... }
 *   #ifdef PP_STANDALONE
 *   int main(void) {
 *       pp_debug_init("Layer N: Name");
 *       return pp_run_layer(my_layer);
 *   }
 *   #endif
 */

static int pp_run_layer(int (*layer_func)(Op *in, int in_count, Op *out, int out_cap)) {
    char line[PP_MAX_LINE];
    Op *in_ops = NULL;
    int in_count = 0;
    int in_cap = 0;
    int in_hunk = 0;
    Hunk current_hunk;
    int hunk_count = 0;

    /* Read all input into Op array, tracking hunks */
    /* We read line by line. Headers and HUNK/HUNK_END are handled inline.
     * Op lines are parsed and added to the array. */
    
    /* Allocate initial capacity */
    in_cap = 4096;
    in_ops = (Op *)malloc(in_cap * sizeof(Op));
    if (!in_ops) { fprintf(stderr, "out of memory\n"); return 1; }

    /* Read headers and pass through */
    while (fgets(line, sizeof(line), stdin)) {
        /* Strip newline */
        line[strcspn(line, "\n\r")] = 0;

        /* Skip empty lines */
        if (line[0] == 0) continue;

        /* Headers (# ...) — pass through */
        if (line[0] == '#') {
            /* Rewrite the top header */
            if (strstr(line, "raw diff") || strstr(line, "post-processed")) {
                printf("# diffvim post-processed v2\n");
            } else {
                printf("%s\n", line);
            }
            continue;
        }

        /* HUNK header */
        if (strncmp(line, "HUNK\t", 5) == 0 || strncmp(line, "HUNK ", 5) == 0) {
            /* If we were in a hunk, process it */
            if (in_hunk && in_count > 0) {
                /* Run the layer on this hunk's ops */
                Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
                if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

                pp_logf("Processing hunk %d: %d ops input", hunk_count, in_count);
                pp_dump_ops("layer_input.txt", in_ops, in_count);

                int out_count = layer_func(in_ops, in_count, out_ops, in_cap);

                pp_logf("Hunk %d: %d ops → %d ops", hunk_count, in_count, out_count);
                pp_dump_ops("layer_output.txt", out_ops, out_count);

                /* Write the hunk header and ops */
                pp_write_hunk(&current_hunk);
                for (int i = 0; i < out_count; i++) {
                    pp_write_op(&out_ops[i]);
                }
                pp_write_hunk_end();

                free(out_ops);
                in_count = 0;
            }

            /* Parse new hunk header */
            sscanf(line, "HUNK\t%d\t%d\t%d\t%d\t%d",
                   &current_hunk.target, &current_hunk.del, &current_hunk.ins,
                   &current_hunk.end_ins, &current_hunk.end_del);
            in_hunk = 1;
            hunk_count++;
            continue;
        }

        /* HUNK_END */
        if (strncmp(line, "HUNK_END", 8) == 0) {
            if (in_hunk && in_count > 0) {
                Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
                if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

                pp_logf("Processing hunk %d: %d ops input", hunk_count, in_count);
                pp_dump_ops("layer_input.txt", in_ops, in_count);

                int out_count = layer_func(in_ops, in_count, out_ops, in_cap);

                pp_logf("Hunk %d: %d ops → %d ops", hunk_count, in_count, out_count);
                pp_dump_ops("layer_output.txt", out_ops, out_count);

                pp_write_hunk(&current_hunk);
                for (int i = 0; i < out_count; i++) {
                    pp_write_op(&out_ops[i]);
                }
                pp_write_hunk_end();

                free(out_ops);
                in_count = 0;
            }
            in_hunk = 0;
            continue;
        }

        /* Op line — parse and add to array */
        if (in_hunk) {
            if (in_count >= in_cap) {
                in_cap *= 2;
                in_ops = (Op *)realloc(in_ops, in_cap * sizeof(Op));
                if (!in_ops) { fprintf(stderr, "out of memory\n"); return 1; }
            }
            if (pp_parse_op(line, &in_ops[in_count])) {
                in_count++;
            }
        }
    }

    /* Handle last hunk if no HUNK_END was seen */
    if (in_hunk && in_count > 0) {
        Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
        if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

        pp_logf("Processing last hunk: %d ops", in_count);
        pp_dump_ops("layer_input.txt", in_ops, in_count);

        int out_count = layer_func(in_ops, in_count, out_ops, in_cap);

        pp_logf("Last hunk: %d ops → %d ops", in_count, out_count);
        pp_dump_ops("layer_output.txt", out_ops, out_count);

        pp_write_hunk(&current_hunk);
        for (int i = 0; i < out_count; i++) {
            pp_write_op(&out_ops[i]);
        }
        pp_write_hunk_end();

        free(out_ops);
    }

    /* Trailing blank line */
    printf("\n");

    pp_logf("Total: %d hunks processed", hunk_count);

    free(in_ops);
    return 0;
}

#endif /* PP_COMMON_H */
