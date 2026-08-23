/*
 * pp_layer0_v2.c — Layer 0: V2 Conversion
 *
 * Purpose:
 *   Convert compute output to V2 TSV format. No modification of ops.
 *   This is the ONLY layer that does format conversion. All subsequent
 *   layers receive and produce V2 TSV.
 *
 *   After this layer, a normalization layer may be added to ensure
 *   consistent op structure (e.g., ensure every deleted line has a
 *   \n delete). But that's a separate layer, not Layer 0.
 *
 * Input:  Raw compute output on stdin (V1 space-separated or V2 tab-separated)
 * Output: V2 TSV on stdout (tab-separated, with headers)
 *
 * Build standalone:
 *   cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_layer0 animator/c/pp_layer0_v2.c
 *
 * Debug:
 *   DV_DEBUG_POSTPROCESS=/path  →  dumps to $path/L0_v2_conversion_input.txt
 *                                  and $path/L0_v2_conversion_output.txt
 *   DV_DEBUG_POSTPROCESS=1      →  uses /tmp/dv_debug/ as path
 *
 * Old file:
 *   Set DV_OLD_FILE env var to pass the old file path to layers.
 */

#include "pp_common.h"

/* ── V1 detection ──────────────────────────────────────────────────── */

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

/* ── V1 → V2 conversion helpers ────────────────────────────────────── */

static void convert_v1_hunk(const char *v1, char *v2, size_t sz) {
    int t, d, i, ei, ed;
    if (sscanf(v1, "HUNK %d %d %d %d %d", &t, &d, &i, &ei, &ed) >= 5)
        snprintf(v2, sz, "HUNK\t%d\t%d\t%d\t%d\t%d", t, d, i, ei, ed);
    else if (sscanf(v1, "HUNK %d %d %d", &t, &d, &i) >= 3)
        snprintf(v2, sz, "HUNK\t%d\t%d\t%d\t0\t0", t, d, i);
    else { size_t l = strlen(v1); if (l >= sz) l = sz-1; memcpy(v2, v1, l); v2[l] = 0; }
}

static void convert_v1_op(const char *v1, char *v2, size_t sz) {
    char type[PP_TYPE_LEN]; int l, c, code;
    if (sscanf(v1, "op\t%19s\t%d\t%d\t%d", type, &l, &c, &code) >= 4)
        snprintf(v2, sz, "%s\t%d\t%d\t%d", type, l, c, code);
    else if (sscanf(v1, "op %19s %d %d %d", type, &l, &c, &code) >= 4)
        snprintf(v2, sz, "%s\t%d\t%d\t%d", type, l, c, code);
    else { size_t l2 = strlen(v1); if (l2 >= sz) l2 = sz-1; memcpy(v2, v1, l2); v2[l2] = 0; }
}

static void convert_v1_nl_delete(const char *v1, char *v2, size_t sz) {
    int l;
    if (sscanf(v1, "newline_delete %d", &l) >= 1 || sscanf(v1, "newline_delete\t%d", &l) >= 1)
        snprintf(v2, sz, "delete\t%d\t1\t10", l);
    else { size_t l2 = strlen(v1); if (l2 >= sz) l2 = sz-1; memcpy(v2, v1, l2); v2[l2] = 0; }
}

static void convert_v1_nl_insert(const char *v1, char *v2, size_t sz) {
    int l, c;
    if (sscanf(v1, "newline_insert %d %d", &l, &c) >= 2 || sscanf(v1, "newline_insert\t%d\t%d", &l, &c) >= 2)
        snprintf(v2, sz, "insert\t%d\t%d\t10", l, c);
    else { size_t l2 = strlen(v1); if (l2 >= sz) l2 = sz-1; memcpy(v2, v1, l2); v2[l2] = 0; }
}

/* ── Layer 0 main ─────────────────────────────────────────────────── */

/*
 * Reads raw compute output from stdin, converts to V2 TSV, writes to stdout.
 * Returns 0 on success, 1 on error.
 */
int layer0_v2_convert(void) {
    char line[PP_MAX_LINE];
    int v1 = 0;
    int format_checked = 0;
    int line_num = 0;
    int op_count = 0;
    int hunk_count = 0;

    /* Dynamic buffer for debug dump */
    char *dump = NULL; size_t dump_cap = 0, dump_len = 0;
    if (pp_debug_dir) { dump_cap = 65536; dump = (char*)malloc(dump_cap); }

    pp_log("Starting V2 conversion");

    while (fgets(line, sizeof(line), stdin)) {
        line_num++;
        line[strcspn(line, "\n\r")] = 0;
        if (line[0] == 0) { printf("\n"); continue; }

        /* Detect format on first non-comment line */
        if (!format_checked && line[0] != '#') {
            v1 = is_v1_format(line);
            pp_logf(v1 ? "Input: V1 (space-separated)" : "Input: V2 (tab-separated)");
            format_checked = 1;
        }

        char v2[PP_MAX_LINE];

        if (v1) {
            if (strncmp(line, "HUNK ", 5) == 0) {
                convert_v1_hunk(line, v2, sizeof(v2));
                hunk_count++;
            } else if (strncmp(line, "op\t", 3) == 0 || strncmp(line, "op ", 3) == 0) {
                convert_v1_op(line, v2, sizeof(v2));
                op_count++;
            } else if (strncmp(line, "newline_delete", 14) == 0) {
                convert_v1_nl_delete(line, v2, sizeof(v2));
                op_count++;
            } else if (strncmp(line, "newline_insert", 14) == 0) {
                convert_v1_nl_insert(line, v2, sizeof(v2));
                op_count++;
            } else if (strncmp(line, "hunk_start", 10) == 0) {
                continue;  /* skip V1 hunk_start */
            } else if (strncmp(line, "hunk_end", 8) == 0) {
                snprintf(v2, sizeof(v2), "HUNK_END");
            } else if (line[0] == '#') {
                size_t l = strlen(line); if (l >= sizeof(v2)) l = sizeof(v2)-1;
                memcpy(v2, line, l); v2[l] = 0;
            } else {
                size_t l = strlen(line); if (l >= sizeof(v2)) l = sizeof(v2)-1;
                memcpy(v2, line, l); v2[l] = 0;
            }
        } else {
            /* V2 passthrough */
            size_t l = strlen(line); if (l >= sizeof(v2)) l = sizeof(v2)-1;
            memcpy(v2, line, l); v2[l] = 0;
            if (strncmp(line, "HUNK\t", 5) == 0) hunk_count++;
            else if (strncmp(line, "keep\t", 5) == 0 ||
                     strncmp(line, "delete\t", 7) == 0 ||
                     strncmp(line, "insert\t", 7) == 0) op_count++;
        }

        /* Rewrite top header */
        if (v2[0] == '#') {
            if (strstr(v2, "raw diff") || strstr(v2, "post-processed"))
                printf("# diffvim post-processed v2\n");
            else
                printf("%s\n", v2);
        } else {
            printf("%s\n", v2);
        }

        /* Append to debug dump */
        if (dump) {
            size_t vl = strlen(v2);
            if (dump_len + vl + 2 > dump_cap) {
                dump_cap *= 2; dump = (char*)realloc(dump, dump_cap);
            }
            memcpy(dump + dump_len, v2, vl);
            dump_len += vl; dump[dump_len++] = '\n';
        }
    }

    printf("\n");

    pp_logf("Done: %d ops, %d hunks, format: %s",
            op_count, hunk_count, v1 ? "V1→V2" : "V2 passthrough");

    if (dump) {
        char path[512];
        snprintf(path, sizeof(path), "%s/L0_v2_conversion_output.txt", pp_debug_dir);
        FILE *f = fopen(path, "w");
        if (f) { fwrite(dump, 1, dump_len, f); fclose(f); }
        free(dump);
    }

    return 0;
}

#ifdef PP_STANDALONE
int main(void) {
    pp_debug_init("L0", "V2 Conversion");
    return layer0_v2_convert();
}
#endif
