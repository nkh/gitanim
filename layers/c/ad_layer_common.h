/* ---
 * ad_layer_common.h — Shared infrastructure for postprocess layers.
 *
 * Design principles (from user spec):
 *   1. Each layer is a pure function: Op[] → Op[]. No side effects.
 *   2. Each layer can be enabled/disabled.
 *   3. Each layer can dump input/output for debugging.
 *      AD_DEBUG_LAYERS=path → dumps to $path/N_layername_input.txt
 *      and $path/N_layername_output.txt (TSV format).
 * *   4. No special-case line fixes. The 4-sweep reorder handles ordering.
 *   5. Layers can be piped (standalone) or linked into one executable.
 *   6. Layers may need the input file (old file path passed via env var).
 *
 * Layer function signature:
 *   int layer_N(Op *in, int in_count, Op *out, int out_cap,
 *               const char *old_file);
 *   Returns: number of output ops.
 *
 * Standalone mode:
 *   cc -DPP_STANDALONE -I animator/c -o pp_layerN pp_layerN.c
 *   Reads TSV stdin → parses to Op[] → calls layer → writes TSV stdout.
 *
 * Include mode:
 *   #include "pp_layerN.c"  (or link object file)
 *   Calls layer_N() directly with in-memory Op array.
 */

#ifndef PP_COMMON_H
#define PP_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>

/* ── Constants ─────────────────────────────────────────────────────── */

#define PP_MAX_LINE   1048576   /* 1MB max line */
#define PP_TYPE_LEN   20        /* max op type string length */

/* ── Op struct ─────────────────────────────────────────────────────── */

typedef struct {
    char type[PP_TYPE_LEN];  /* "keep", "delete", "insert", "overwrite_insert" */
    int  code;               /* char code (10=\n, 32=space, 9=tab, etc.) */
    int  line;               /* 1-indexed line number */
    int  col;                /* 1-indexed column number */
} Op;

/* ── Hunk struct ───────────────────────────────────────────────────── */

typedef struct {
    int target;
    int del;
    int ins;
    int end_ins;
    int end_del;
} Hunk;

/* ── Debug/Logging ─────────────────────────────────────────────────── */
/* ---
 * AD_DEBUG_LAYERS=path  →  dumps to $path/N_layername_input.txt
 *                                and $path/N_layername_output.txt (TSV)
 *
 * If AD_DEBUG_LAYERS=1 (just "1"), uses /tmp/ad_debug/ as the path.
 */

static const char *pp_debug_dir = NULL;
static FILE *pp_log_file = NULL;

/* Initialize debug for a layer. Call at start of main() or layer init. */
__attribute__((unused)) static void pp_debug_init(const char *layer_id, const char *layer_name) {
    const char *env = getenv("AD_DEBUG_LAYERS");
    if (!env || env[0] == 0) return;

    /* "1" means use default path */
    if (strcmp(env, "1") == 0)
        pp_debug_dir = "/tmp/ad_debug";
    else
        pp_debug_dir = env;

    /* Create directory */
    mkdir(pp_debug_dir, 0755);

    /* Open log (append — all layers share one log) */
    char log_path[512];
    snprintf(log_path, sizeof(log_path), "%s/postprocess.log", pp_debug_dir);
    pp_log_file = fopen(log_path, "a");
    if (pp_log_file) {
        fprintf(pp_log_file, "\n--- %s: %s ---\n", layer_id, layer_name);
    }
}

/* Log a message. */
__attribute__((unused)) static void pp_log(const char *msg) {
    if (!pp_log_file) return;
    fprintf(pp_log_file, "%s\n", msg);
    fflush(pp_log_file);
}

/* Log a formatted message. */
static void pp_logf(const char *fmt, ...) {
    if (!pp_log_file) return;
    va_list args;
    va_start(args, fmt);
    vfprintf(pp_log_file, fmt, args);
    fprintf(pp_log_file, "\n");
    va_end(args);
    fflush(pp_log_file);
}

/* Dump Op array to a TSV file. Filename: $dir/N_layername_suffix.txt */
static void pp_dump_ops(const char *layer_id, const char *suffix,
                        Op *ops, int count) {
    if (!pp_debug_dir) return;
    char path[512];
    snprintf(path, sizeof(path), "%s/%s_%s", pp_debug_dir, layer_id, suffix);
    FILE *f = fopen(path, "w");
    if (!f) return;
    for (int i = 0; i < count; i++) {
        fprintf(f, "%s\t%d\t%d\t%d\n", ops[i].type, ops[i].line,
                ops[i].col, ops[i].code);
    }
    fclose(f);
}

/* ── char_repr helper ───────────────────────────────────────────────── */
/* ---
 * Returns a human-readable representation of a char code.
 * Used for the 5th TSV field (cosmetic, not stored in Op struct).
 *   10 → \n, 9 → \t, 32 → space, 33-126 → 'x', else → number
 */
static const char *pp_char_repr(int code) {
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

/* Parse a TSV line into an Op. Returns 1 on success, 0 on failure.
 * Format: type\tline\tcol\tcode  (char_repr field ignored if present) */
static int pp_parse_op(const char *line, Op *op) {
    char type[PP_TYPE_LEN];
    int l, c, code;
    int n = sscanf(line, "%19s\t%d\t%d\t%d", type, &l, &c, &code);
    if (n >= 4) {
        size_t tlen = strlen(type);
        if (tlen >= PP_TYPE_LEN) tlen = PP_TYPE_LEN - 1;
        memcpy(op->type, type, tlen);
        op->type[tlen] = 0;
        op->line = l;
        op->col = c;
        op->code = code;
        return 1;
    }
    return 0;
}

/* ── TSV Writing ──────────────────────────────────────────────────── */

/* Write an Op to stdout in V2 TSV format (5 fields, with char_repr). */
static void pp_write_op(Op *op) {
    printf("%s\t%d\t%d\t%d\t%s\n", op->type, op->line, op->col,
           op->code, pp_char_repr(op->code));
}

/* Write a HUNK header. */
static void pp_write_hunk(Hunk *h) {
    printf("HUNK\t%d\t%d\t%d\t%d\t%d\n", h->target, h->del, h->ins,
           h->end_ins, h->end_del);
}

/* Write HUNK_END. */
static void pp_write_hunk_end(void) {
    printf("HUNK_END\n");
}

/* ── Debug op insertion ───────────────────────────────────────────── */
/* ---
 * Insert a debug op into the stream. Debug ops are ignored by all
 * other layers and the animator. They carry human-readable text
 * that explains what a layer did.
 *
 * Format: debug\t<layer_id>\t<message>
 *
 * The message is a single line of text (no tabs, no newlines).
 * Example: debug\tL2_indent_last\tmoved 4 leading spaces to end of group
 */
__attribute__((unused)) static void pp_write_debug_op(const char *layer_id, const char *message) {
    printf("debug\t%s\t%s\n", layer_id, message);
}

/* Check if an op is a debug op (so layers can skip them). */
__attribute__((unused)) static int pp_is_debug_op(Op *op) {
    return strcmp(op->type, "debug") == 0;
}

/* ── Debug dump helpers (used by pp_run_layer) ──────────────────── */

/* Dump ops to a file in V2 TSV format */
__attribute__((unused)) static void pp_dump_ops_to_file(FILE *f, Op *ops, int count) {
    if (!f) return;
    for (int i = 0; i < count; i++) {
        fprintf(f, "%s\t%d\t%d\t%d\t%s\n", ops[i].type, ops[i].line,
                ops[i].col, ops[i].code, pp_char_repr(ops[i].code));
    }
}

/* Dump changes between input and output ops.
 * Since layers may reorder ops (different positions in the array),
 * we compare each output op against ALL input ops to find a match.
 * If no match found, it's a new/changed op. */
__attribute__((unused)) static void pp_dump_changes_to_file(FILE *f,
        Op *in_ops, int in_count, Op *out_ops, int out_count) {
    if (!f) return;
    fprintf(f, "=== Changes (input: %d ops, output: %d ops) ===\n", in_count, out_count);

    for (int i = 0; i < out_count; i++) {
        /* Try to find this op in the input (same type+code, different position) */
        int found = 0;
        for (int j = 0; j < in_count; j++) {
            if (strcmp(out_ops[i].type, in_ops[j].type) == 0 &&
                out_ops[i].code == in_ops[j].code) {
                if (out_ops[i].line != in_ops[j].line || out_ops[i].col != in_ops[j].col) {
                    fprintf(f, "[%2d] %s (%d,%d) → (%d,%d) code=%d  [position changed]\n",
                            i, out_ops[i].type,
                            in_ops[j].line, in_ops[j].col,
                            out_ops[i].line, out_ops[i].col,
                            out_ops[i].code);
                }
                found = 1;
                break;
            }
        }
        if (!found) {
            fprintf(f, "[%2d] %s (%d,%d) code=%d  [NEW/changed op]\n",
                    i, out_ops[i].type, out_ops[i].line, out_ops[i].col,
                    out_ops[i].code);
        }
    }

    /* Check for dropped ops (in input but not output) */
    for (int j = 0; j < in_count; j++) {
        int found = 0;
        for (int i = 0; i < out_count; i++) {
            if (strcmp(out_ops[i].type, in_ops[j].type) == 0 &&
                out_ops[i].code == in_ops[j].code) {
                found = 1; break;
            }
        }
        if (!found) {
            fprintf(f, "     %s (%d,%d) code=%d  [DROPPED]\n",
                    in_ops[j].type, in_ops[j].line, in_ops[j].col,
                    in_ops[j].code);
        }
    }
}

/* ── Standalone Layer Runner ────────────────────────────────────────
 * Reads TSV from stdin, parses into Op array per hunk, calls the
 * layer function for each hunk, writes the result to stdout.
 *
 * Headers and HUNK/HUNK_END are passed through.
 * Debug ops (type="debug") are passed through unchanged.
 *
 * Usage in standalone file:
 *   int my_layer(Op *in, int in_count, Op *out, int out_cap,
 *                const char *old_file) { ... }
 *   #ifdef PP_STANDALONE
 *   int main(void) {
 *       pp_debug_init("L1", "Reorder");
 *       return pp_run_layer(my_layer);
 *   }
 *   #endif
 */

__attribute__((unused)) static int pp_run_layer(int (*layer_func)(Op *in, int in_count,
                                          Op *out, int out_cap,
                                          const char *old_file)) {
    char line[PP_MAX_LINE];
    Op *in_ops = NULL;
    int in_count = 0;
    int in_cap = 0;
    int in_hunk = 0;
    Hunk current_hunk = {0};
    int hunk_count = 0;
    int line_offset = 0;  /* cumulative (\n_ins - \n_del) from prior hunks */

    /* Debug flags from env / command line */
    const char *dump_input  = getenv("AD_DUMP_INPUT");
    const char *dump_output = getenv("AD_DUMP_OUTPUT");
    const char *dump_changes = getenv("AD_DUMP_CHANGES");
    /* int trace_decisions = getenv("AD_TRACE_DECISIONS") != NULL; */
    FILE *dump_in_f = NULL, *dump_out_f = NULL, *dump_chg_f = NULL;

    if (dump_input && dump_input[0]) {
        dump_in_f = fopen(dump_input, "w");
        if (dump_in_f) fprintf(stderr, "dump-input: %s\n", dump_input);
    }
    if (dump_output && dump_output[0]) {
        dump_out_f = fopen(dump_output, "w");
        if (dump_out_f) fprintf(stderr, "dump-output: %s\n", dump_output);
    }
    if (dump_changes && dump_changes[0]) {
        dump_chg_f = fopen(dump_changes, "w");
        if (dump_chg_f) fprintf(stderr, "dump-changes: %s\n", dump_changes);
    }

    /* Get old file path from env (layers may need it) */
    const char *old_file = getenv("AD_OLD_FILE");
    if (!old_file) old_file = "";

    /* Allocate initial capacity */
    in_cap = 4096;
    in_ops = (Op *)malloc(in_cap * sizeof(Op));
    if (!in_ops) { fprintf(stderr, "out of memory\n"); return 1; }

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
            /* If we were in a hunk, process it first */
            if (in_hunk && in_count > 0) {
                /* Apply cross-hunk line_offset to all ops */
                for (int j = 0; j < in_count; j++)
                    in_ops[j].line += line_offset;

                Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
                if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

                pp_dump_ops("L", "input.txt", in_ops, in_count);

                int out_count = layer_func(in_ops, in_count, out_ops, in_cap, old_file);

                pp_dump_ops("L", "output.txt", out_ops, out_count);
                if (dump_in_f) pp_dump_ops_to_file(dump_in_f, in_ops, in_count);
                if (dump_out_f) pp_dump_ops_to_file(dump_out_f, out_ops, out_count);
                if (dump_chg_f) pp_dump_changes_to_file(dump_chg_f, in_ops, in_count, out_ops, out_count);
                pp_logf("Hunk %d: %d ops → %d ops", hunk_count, in_count, out_count);

                pp_write_hunk(&current_hunk);
                for (int i = 0; i < out_count; i++)
                    pp_write_op(&out_ops[i]);
                pp_write_hunk_end();

                /* Update line_offset for next hunk */
                { int ni=0, nd=0;
                  for (int j=0; j<out_count; j++) {
                      if (strcmp(out_ops[j].type,"insert")==0 && out_ops[j].code==10) ni++;
                      if (strcmp(out_ops[j].type,"delete")==0 && out_ops[j].code==10) nd++;
                  }
                  line_offset += ni - nd;
                }

                free(out_ops);
                in_count = 0;
            }

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
                /* Apply cross-hunk line_offset to all ops */
                for (int j = 0; j < in_count; j++)
                    in_ops[j].line += line_offset;

                Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
                if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

                pp_dump_ops("L", "input.txt", in_ops, in_count);

                int out_count = layer_func(in_ops, in_count, out_ops, in_cap, old_file);

                pp_dump_ops("L", "output.txt", out_ops, out_count);
                if (dump_in_f) pp_dump_ops_to_file(dump_in_f, in_ops, in_count);
                if (dump_out_f) pp_dump_ops_to_file(dump_out_f, out_ops, out_count);
                if (dump_chg_f) pp_dump_changes_to_file(dump_chg_f, in_ops, in_count, out_ops, out_count);
                pp_logf("Hunk %d: %d ops → %d ops", hunk_count, in_count, out_count);

                pp_write_hunk(&current_hunk);
                for (int i = 0; i < out_count; i++)
                    pp_write_op(&out_ops[i]);
                pp_write_hunk_end();

                /* Update line_offset for next hunk */
                { int ni=0, nd=0;
                  for (int j=0; j<out_count; j++) {
                      if (strcmp(out_ops[j].type,"insert")==0 && out_ops[j].code==10) ni++;
                      if (strcmp(out_ops[j].type,"delete")==0 && out_ops[j].code==10) nd++;
                  }
                  line_offset += ni - nd;
                }

                free(out_ops);
                in_count = 0;
            }
            in_hunk = 0;
            continue;
        }

        /* Debug ops — pass through unchanged */
        if (strncmp(line, "debug\t", 6) == 0) {
            if (in_hunk) {
                if (in_count >= in_cap) {
                    in_cap *= 2;
                    in_ops = (Op *)realloc(in_ops, in_cap * sizeof(Op));
                }
                /* Parse as a regular op (type="debug", line/col from fields) */
                pp_parse_op(line, &in_ops[in_count]);
                in_count++;
            }
            continue;
        }

        /* Op line — parse and add to current hunk's array */
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

    /* Handle last hunk if no HUNK_END */
    if (in_hunk && in_count > 0) {
        /* Apply cross-hunk line_offset to all ops */
        for (int j = 0; j < in_count; j++)
            in_ops[j].line += line_offset;

        Op *out_ops = (Op *)malloc(in_cap * sizeof(Op));
        if (!out_ops) { fprintf(stderr, "out of memory\n"); return 1; }

        pp_dump_ops("L", "input.txt", in_ops, in_count);

        int out_count = layer_func(in_ops, in_count, out_ops, in_cap, old_file);

        pp_dump_ops("L", "output.txt", out_ops, out_count);
        if (dump_in_f) pp_dump_ops_to_file(dump_in_f, in_ops, in_count);
        if (dump_out_f) pp_dump_ops_to_file(dump_out_f, out_ops, out_count);
        if (dump_chg_f) pp_dump_changes_to_file(dump_chg_f, in_ops, in_count, out_ops, out_count);
        pp_logf("Last hunk: %d ops → %d ops", in_count, out_count);

        pp_write_hunk(&current_hunk);
        for (int i = 0; i < out_count; i++)
            pp_write_op(&out_ops[i]);
        pp_write_hunk_end();

        free(out_ops);
    }

    printf("\n");  /* trailing blank line */
    pp_logf("Total: %d hunks", hunk_count);
    free(in_ops);
    return 0;
}

#endif /* PP_COMMON_H */
