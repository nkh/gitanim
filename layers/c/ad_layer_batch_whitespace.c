/* ad_layer_batch_whitespace.c — Batch consecutive whitespace insert ops.
 *
 * Replaces runs of consecutive whitespace inserts (tab=9, space=32)
 * with a single batch_insert op:
 *   batch_insert\t<line>\t<col>\t<code1>,<code2>,...
 *
 * All other lines are passed through unchanged.
 */
#include "ad_layer_common.h"

#define WS_TAB   9
#define WS_SPACE 32

static int is_ws(int code) { return code == WS_TAB || code == WS_SPACE; }

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_batch_whitespace — batch whitespace insert ops\n\n"
                "Usage: ad_layer_batch_whitespace < ops.tsv\n\n"
                "Replaces runs of consecutive whitespace inserts (tab=9,\n"
                "space=32) with a single batch_insert op.\n");
            return 0;
        }
    }

    char line[AD_LAYER_MAX_LINE];
    char **hunk_lines = NULL;
    int n_hunk = 0, cap_hunk = 0;
    int in_hunk = 0;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;

        if (line[0] == '#' || line[0] == 0) {
            printf("%s\n", line);
            continue;
        }
        if (strncmp(line, "HUNK\t", 5) == 0) {
            in_hunk = 1;
            n_hunk = 0;
            printf("%s\n", line);
            continue;
        }
        if (strncmp(line, "HUNK_END", 8) == 0) {
            in_hunk = 0;
            int i = 0;
            while (i < n_hunk) {
                int ln = 0, col = 0, code = 0;
                if (sscanf(hunk_lines[i], "insert\t%d\t%d\t%d", &ln, &col, &code) >= 3
                    && is_ws(code)) {
                    int start = i;
                    int exp_col = col;
                    while (i < n_hunk) {
                        int ln2 = 0, col2 = 0, code2 = 0;
                        if (sscanf(hunk_lines[i], "insert\t%d\t%d\t%d", &ln2, &col2, &code2) >= 3
                            && ln2 == ln && col2 == exp_col && is_ws(code2)) {
                            exp_col++;
                            i++;
                        } else break;
                    }
                    int count = i - start;
                    if (count >= 2) {
                        printf("batch_insert\t%d\t%d\t", ln, col);
                        for (int k = start; k < i; k++) {
                            int c = 0;
                            sscanf(hunk_lines[k], "insert\t%d\t%d\t%d", &ln, &col, &c);
                            printf("%s%d", k > start ? "," : "", c);
                        }
                        printf("\n");
                        continue;
                    }
                    i = start;
                }
                printf("%s\n", hunk_lines[i]);
                i++;
            }
            printf("HUNK_END\n");
            for (int j = 0; j < n_hunk; j++) free(hunk_lines[j]);
            n_hunk = 0;
            continue;
        }
        if (!in_hunk) {
            printf("%s\n", line);
            continue;
        }
        if (n_hunk >= cap_hunk) {
            cap_hunk = cap_hunk > 0 ? cap_hunk * 2 : 256;
            hunk_lines = realloc(hunk_lines, cap_hunk * sizeof(char *));
        }
        hunk_lines[n_hunk++] = strdup(line);
    }
    for (int j = 0; j < n_hunk; j++) free(hunk_lines[j]);
    free(hunk_lines);
    return 0;
}
