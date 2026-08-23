/*
 * pp_layer0_v2.c — Layer 0: V2 Conversion
 *
 * Purpose:
 *   Convert compute output (raw ops) to V2 TSV format.
 *   NO modification of ops — no reordering, no cursor changes,
 *   no transforms. Just format conversion.
 *
 * Input:  Raw compute output on stdin (V1 space-separated or V2 tab-separated)
 * Output: V2 TSV on stdout (tab-separated, with headers)
 *
 * Debug logging:
 *   When DV_DEBUG_POSTPROCESS=1, writes a log to stderr showing
 *   every conversion decision (V1 detected, V2 passthrough, etc.)
 *   and a layer dump to /tmp/dv_debug/layer0_output.txt
 *
 * Build: part of postprocess.c (or standalone: cc -o pp_layer0 pp_layer0_v2.c)
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <sys/stat.h>

/* ── Logging ────────────────────────────────────────────────────────── */

static int debug_enabled = 0;
static FILE *debug_log = NULL;

/* Called once at startup. Opens the debug log if enabled. */
void pp_debug_init(void) {
    const char *env = getenv("DV_DEBUG_POSTPROCESS");
    debug_enabled = (env && env[0] == '1');
    if (debug_enabled) {
        mkdir("/tmp/dv_debug", 0755);
        debug_log = fopen("/tmp/dv_debug/postprocess.log", "w");
        if (debug_log) {
            fprintf(debug_log, "=== Postprocess Debug Log ===\n");
            fprintf(debug_log, "Layer 0: V2 Conversion\n\n");
        }
    }
}

/* Log a message to the debug log (and stderr if interactive). */
void pp_log(const char *layer, const char *msg) {
    if (!debug_enabled || !debug_log) return;
    fprintf(debug_log, "[%s] %s\n", layer, msg);
}

/* Log a formatted message. */
void pp_logf(const char *layer, const char *fmt, ...) {
    if (!debug_enabled || !debug_log) return;
    va_list args;
    va_start(args, fmt);
    fprintf(debug_log, "[%s] ", layer);
    vfprintf(debug_log, fmt, args);
    fprintf(debug_log, "\n");
    va_end(args);
}

/* Dump the current op array to a file (for layer debugging). */
void pp_dump(const char *filename, const char *data, size_t len) {
    if (!debug_enabled) return;
    char path[256];
    snprintf(path, sizeof(path), "/tmp/dv_debug/%s", filename);
    FILE *f = fopen(path, "w");
    if (!f) return;
    fwrite(data, 1, len, f);
    fclose(f);
}

/* ── Layer 0: V2 Conversion ───────────────────────────────────────── */

/*
 * Format detection:
 *
 * V1 format (space-separated):
 *   HUNK <target> <del> <ins> <end_ins> <end_del>
 *   op <type> <line> <col> <code>
 *   newline_delete <line>
 *   newline_insert <line> <col>
 *   hunk_start <del> <ins>
 *   hunk_end
 *
 * V2 format (tab-separated):
 *   HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
 *   <type>\t<line>\t<col>\t<code>
 *
 * Detection rules:
 *   - If a line starts with "HUNK " (space) → V1
 *   - If a line starts with "HUNK\t" (tab) → V2
 *   - If a line starts with "op\t" → V1
 *   - If a line starts with "newline_" → V1
 *   - If a line starts with "hunk_" → V1
 *   - Otherwise → V2 (pass through)
 */

/* Check if a line is V1 format (space-separated HUNK or op prefix). */
static int is_v1_format(const char *line) {
    if (strncmp(line, "HUNK ", 5) == 0) return 1;
    if (strncmp(line, "op\t", 3) == 0) return 1;
    if (strncmp(line, "op ", 3) == 0) return 1;
    if (strncmp(line, "newline_delete", 14) == 0) return 1;
    if (strncmp(line, "newline_insert", 14) == 0) return 1;
    if (strncmp(line, "hunk_start", 10) == 0) return 1;
    if (strncmp(line, "hunk_end", 8) == 0) return 1;
    return 0;
}

/* Convert a V1 HUNK line to V2.
 * V1: "HUNK <target> <del> <ins> <end_ins> <end_del>"
 * V2: "HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>" */
static void convert_v1_hunk(const char *v1_line, char *v2_out, size_t out_sz) {
    int target, del, ins, end_ins, end_del;
    /* V1 uses spaces */
    int n = sscanf(v1_line, "HUNK %d %d %d %d %d",
                   &target, &del, &ins, &end_ins, &end_del);
    if (n >= 5) {
        snprintf(v2_out, out_sz, "HUNK\t%d\t%d\t%d\t%d\t%d",
                 target, del, ins, end_ins, end_del);
    } else if (n >= 3) {
        /* V1 might not have end_ins/end_del */
        snprintf(v2_out, out_sz, "HUNK\t%d\t%d\t%d\t0\t0",
                 target, del, ins);
    } else {
        /* Malformed — pass through as-is */
        { size_t _l = strlen(v1_line); if (_l >= out_sz) _l = out_sz - 1; memcpy(v2_out, v1_line, _l); v2_out[_l] = 0; }
        
    }
}

/* Convert a V1 "op <type> <line> <col> <code>" line to V2.
 * V1: "op\tkeep\t<line>\t<col>\t<code>"
 * V2: "keep\t<line>\t<col>\t<code>" (drop "op" prefix) */
static void convert_v1_op(const char *v1_line, char *v2_out, size_t out_sz) {
    char type[20];
    int line, col, code;
    int n = sscanf(v1_line, "op\t%19s\t%d\t%d\t%d", type, &line, &col, &code);
    if (n >= 4) {
        snprintf(v2_out, out_sz, "%s\t%d\t%d\t%d", type, line, col, code);
    } else {
        n = sscanf(v1_line, "op %19s %d %d %d", type, &line, &col, &code);
        if (n >= 4) {
            snprintf(v2_out, out_sz, "%s\t%d\t%d\t%d", type, line, col, code);
        } else {
            { size_t _l = strlen(v1_line); if (_l >= out_sz) _l = out_sz - 1; memcpy(v2_out, v1_line, _l); v2_out[_l] = 0; }
            
        }
    }
}

/* Convert a V1 "newline_delete <line>" to V2.
 * V1: "newline_delete\t<line>"
 * V2: "delete\t<line>\t1\t10" (delete \n at end of line) */
static void convert_v1_newline_delete(const char *v1_line, char *v2_out, size_t out_sz) {
    int line;
    int n = sscanf(v1_line, "newline_delete %d", &line);
    if (n >= 1) {
        snprintf(v2_out, out_sz, "delete\t%d\t1\t10", line);
    } else {
        n = sscanf(v1_line, "newline_delete\t%d", &line);
        if (n >= 1) {
            snprintf(v2_out, out_sz, "delete\t%d\t1\t10", line);
        } else {
            { size_t _l = strlen(v1_line); if (_l >= out_sz) _l = out_sz - 1; memcpy(v2_out, v1_line, _l); v2_out[_l] = 0; }
            
        }
    }
}

/* Convert a V1 "newline_insert <line> <col>" to V2.
 * V1: "newline_insert\t<line>\t<col>"
 * V2: "insert\t<line>\t<col>\t10" */
static void convert_v1_newline_insert(const char *v1_line, char *v2_out, size_t out_sz) {
    int line, col;
    int n = sscanf(v1_line, "newline_insert %d %d", &line, &col);
    if (n >= 2) {
        snprintf(v2_out, out_sz, "insert\t%d\t%d\t10", line, col);
    } else {
        n = sscanf(v1_line, "newline_insert\t%d\t%d", &line, &col);
        if (n >= 2) {
            snprintf(v2_out, out_sz, "insert\t%d\t%d\t10", line, col);
        } else {
            { size_t _l = strlen(v1_line); if (_l >= out_sz) _l = out_sz - 1; memcpy(v2_out, v1_line, _l); v2_out[_l] = 0; }
            
        }
    }
}

/* ── Layer 0 main function ─────────────────────────────────────────── */

/*
 * Reads raw compute output from stdin, converts to V2 TSV, writes to stdout.
 *
 * Returns: 0 on success, 1 on error.
 *
 * The function:
 *   1. Detects V1 vs V2 format
 *   2. Converts V1 → V2 (if needed)
 *   3. Writes V2 headers
 *   4. Passes through V2 ops unchanged
 *   5. Dumps output to /tmp/dv_debug/layer0_output.txt (if debug enabled)
 */
int layer0_v2_convert(void) {
    char line[1048576];  /* 1MB max line (same as MAX_LINE_LEN) */
    int v1_detected = 0;
    int format_checked = 0;
    int line_num = 0;
    int op_count = 0;
    int hunk_count = 0;

    /* Dynamic buffer for debug dump */
    char *dump_buf = NULL;
    size_t dump_cap = 0, dump_len = 0;
    if (debug_enabled) {
        dump_cap = 65536;
        dump_buf = (char *)malloc(dump_cap);
    }

    pp_log("Layer 0", "Starting V2 conversion");

    /* Read all input, detect format, convert, write output */
    while (fgets(line, sizeof(line), stdin)) {
        line_num++;

        /* Strip trailing newline */
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = 0;

        /* Skip empty lines (but remember to output a blank line at end) */
        if (len == 0) {
            /* Pass through blank lines */
            printf("\n");
            continue;
        }

        /* Detect format on first non-comment, non-empty line */
        if (!format_checked && line[0] != '#') {
            if (is_v1_format(line)) {
                v1_detected = 1;
                pp_logf("Layer 0", "Input format: V1 (space-separated, line %d)", line_num);
            } else {
                format_checked = 1; // V2 detected
                pp_logf("Layer 0", "Input format: V2 (tab-separated, line %d)", line_num);
            }
            format_checked = 1;
        }

        char v2_line[1048576];

        /* Process based on format */
        if (v1_detected) {
            /* V1 → V2 conversion */
            if (strncmp(line, "HUNK ", 5) == 0) {
                convert_v1_hunk(line, v2_line, sizeof(v2_line));
                hunk_count++;
                pp_logf("Layer 0", "V1→V2 HUNK: '%s' → '%s'", line, v2_line);
            } else if (strncmp(line, "op\t", 3) == 0 || strncmp(line, "op ", 3) == 0) {
                convert_v1_op(line, v2_line, sizeof(v2_line));
                op_count++;
            } else if (strncmp(line, "newline_delete", 14) == 0) {
                convert_v1_newline_delete(line, v2_line, sizeof(v2_line));
                op_count++;
                pp_logf("Layer 0", "V1→V2 newline_delete → '%s'", v2_line);
            } else if (strncmp(line, "newline_insert", 14) == 0) {
                convert_v1_newline_insert(line, v2_line, sizeof(v2_line));
                op_count++;
                pp_logf("Layer 0", "V1→V2 newline_insert → '%s'", v2_line);
            } else if (strncmp(line, "hunk_start", 10) == 0) {
                /* V1 hunk_start → V2 HUNK (skip — will be handled by HUNK) */
                pp_logf("Layer 0", "V1 hunk_start skipped: '%s'", line);
                continue;
            } else if (strncmp(line, "hunk_end", 8) == 0) {
                /* V1 hunk_end → V2 HUNK_END */
                snprintf(v2_line, sizeof(v2_line), "HUNK_END");
            } else if (line[0] == '#') {
                /* Header line — convert headers */
                { size_t _l = strlen(line); if (_l >= sizeof(v2_line)) _l = sizeof(v2_line) - 1; memcpy(v2_line, line, _l); v2_line[_l] = 0; }
            } else {
                /* Unknown V1 line — pass through as V2 */
                { size_t _l = strlen(line); if (_l >= sizeof(v2_line)) _l = sizeof(v2_line) - 1; memcpy(v2_line, line, _l); v2_line[_l] = 0; }
                pp_logf("Layer 0", "V1 unknown line (passthrough): '%s'", line);
            }
        } else {
            /* V2 — pass through unchanged */
            { size_t _l = strlen(line); if (_l >= sizeof(v2_line)) _l = sizeof(v2_line) - 1; memcpy(v2_line, line, _l); v2_line[_l] = 0; }

            /* Count ops and hunks for logging */
            if (strncmp(line, "HUNK\t", 5) == 0)
                hunk_count++;
            else if (strncmp(line, "keep\t", 5) == 0 ||
                     strncmp(line, "delete\t", 7) == 0 ||
                     strncmp(line, "insert\t", 7) == 0)
                op_count++;
        }

        /* Convert headers */
        if (v2_line[0] == '#') {
            if (strncmp(v2_line, "# diffvim raw diff", 18) == 0) {
                printf("# diffvim post-processed v2\n");
                pp_log("Layer 0", "Header: raw diff → post-processed v2");
            } else if (strncmp(v2_line, "# diffvim precomputed", 20) == 0) {
                printf("# diffvim post-processed v2\n");
            } else {
                /* Pass through other headers */
                printf("%s\n", v2_line);
            }
        } else {
            printf("%s\n", v2_line);
        }

        /* Append to debug dump */
        if (debug_enabled && dump_buf) {
            size_t v2_len = strlen(v2_line);
            if (dump_len + v2_len + 2 > dump_cap) {
                dump_cap *= 2;
                dump_buf = (char *)realloc(dump_buf, dump_cap);
            }
            memcpy(dump_buf + dump_len, v2_line, v2_len);
            dump_len += v2_len;
            dump_buf[dump_len++] = '\n';
        }
    }

    /* Ensure a trailing blank line */
    printf("\n");

    /* Log summary */
    pp_logf("Layer 0", "Conversion complete: %d ops, %d hunks", op_count, hunk_count);
    pp_logf("Layer 0", "Format: %s", v1_detected ? "V1->V2 converted" : "V2 passthrough");

    /* Write debug dump */
    if (debug_enabled && dump_buf) {
        pp_dump("layer0_output.txt", dump_buf, dump_len);
        free(dump_buf);
        pp_logf("Layer 0", "Debug dump written to /tmp/dv_debug/layer0_output.txt");
    }

    return 0;
}

/* ── Standalone main (for testing layer 0 in isolation) ───────────── */

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init();
    return layer0_v2_convert();
}
#endif
