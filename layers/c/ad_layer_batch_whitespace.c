/* ad_layer_batch_whitespace.c — Batch consecutive whitespace insert ops.
 *
 * Replaces runs of consecutive insert ops of whitespace chars
 * (tab=9, space=32) with a single insert_text op:
 *
 *   insert L C 9 '\t'
 *   insert L C+1 9 '\t'
 *   insert L C+2 32 ' '
 *   →
 *   insert_text L C 9,9,32
 *
 * This reduces the op count (and thus the number of animation delays)
 * for files with lots of indentation. The animator handles insert_text
 * by inserting all chars at once.
 *
 * Only batches WHITESPACE chars (tab=9, space=32). Other chars are left
 * as individual insert ops.
 *
 * Build: make layers
 * Usage:  ad_layer_batch_whitespace < ops.tsv
 */
#include "ad_layer_common.h"

#define WS_TAB   9
#define WS_SPACE 32

static int is_whitespace(int code) {
    return code == WS_TAB || code == WS_SPACE;
}

static int layer_batch_whitespace(Op *ops, int n_ops, Op *out, int out_cap, int *line_offset) {
    (void)line_offset;
    int n_out = 0;
    int i = 0;

    while (i < n_ops) {
        /* Look for: insert(L, C, ws)+ — a run of whitespace inserts */
        if (strcmp(ops[i].type, "insert") == 0 && is_whitespace(ops[i].code)) {
            int start = i;
            int line = ops[i].line;
            int col = ops[i].col;

            /* Scan forward for consecutive whitespace inserts on same line */
            while (i < n_ops
                   && strcmp(ops[i].type, "insert") == 0
                   && ops[i].line == line
                   && ops[i].col == col + (i - start)
                   && is_whitespace(ops[i].code)) {
                i++;
            }
            int count = i - start;

            if (count >= 2) {
                /* Batch: emit insert_text with comma-separated codes */
                if (n_out < out_cap) {
                    Op *op = &out[n_out++];
                    strcpy(op->type, "insert_text");
                    op->line = line;
                    op->col = col;
                    op->code = 0;
                    /* Build the codes string in op->text */
                    char buf[AD_LAYER_MAX_LINE];
                    int pos = 0;
                    for (int k = start; k < i; k++) {
                        if (k > start) buf[pos++] = ',';
                        pos += sprintf(buf + pos, "%d", ops[k].code);
                    }
                    buf[pos] = 0;
                    op->text = strdup(buf);
                }
                continue;
            }
            /* Single whitespace insert — fall through to emit as-is */
            i = start;  /* rewind */
        }

        /* Emit unchanged */
        if (n_out < out_cap)
            out[n_out++] = ops[i];
        i++;
    }

    return n_out;
}

/* Custom main — the insert_text op has a text field (comma-separated
 * codes) that ad_layer_run doesn't know how to write. */
int main(int argc, char **argv) {
    __argc = argc; __argv = argv;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_batch_whitespace — batch whitespace insert ops\n\n"
                "Usage: ad_layer_batch_whitespace < ops.tsv\n\n"
                "Replaces runs of consecutive whitespace inserts (tab=9,\n"
                "space=32) with a single insert_text op. Reduces op count\n"
                "for files with lots of indentation.\n");
            return 0;
        }
    }

    char line[AD_LAYER_MAX_LINE];
    /* Read all ops, process */
    Op *ops = NULL;
    int n_ops = 0, cap = 0;
    int in_hunk = 0;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;

        if (line[0] == '#' || line[0] == 0) {
            printf("%s\n", line);
            continue;
        }
        if (strncmp(line, "HUNK\t", 5) == 0) {
            in_hunk = 1;
            n_ops = 0;
            printf("%s\n", line);
            continue;
        }
        if (strncmp(line, "HUNK_END", 8) == 0) {
            in_hunk = 0;
            /* Process collected ops */
            int n_out = 0;
            Op *out = (Op *)malloc(n_ops * sizeof(Op));
            int out_cap = n_ops;
            int line_offset = 0;
            n_out = layer_batch_whitespace(ops, n_ops, out, out_cap, &line_offset);

            /* Write output */
            for (int j = 0; j < n_out; j++) {
                if (strcmp(out[j].type, "insert_text") == 0 && out[j].text) {
                    printf("insert_text\t%d\t%d\t%s\n", out[j].line, out[j].col, out[j].text);
                } else if (strcmp(out[j].type, "split_line") == 0) {
                    printf("split_line\t%d\t%d\n", out[j].line, out[j].col);
                } else if (strcmp(out[j].type, "join_lines") == 0) {
                    printf("join_lines\t%d\n", out[j].line);
                } else if (strcmp(out[j].type, "keep_line") == 0) {
                    printf("keep_line\t%d\n", out[j].line);
                } else {
                    printf("%s\t%d\t%d\t%d\n", out[j].type, out[j].line, out[j].col, out[j].code);
                }
            }
            free(out);
            printf("HUNK_END\n");
            /* Free text fields */
            for (int j = 0; j < n_ops; j++) {
                if (ops[j].text) { free(ops[j].text); ops[j].text = NULL; }
            }
            n_ops = 0;
            continue;
        }
        if (strncmp(line, "delay\t", 6) == 0 || strncmp(line, "snapshot\t", 9) == 0 ||
            strncmp(line, "highlight\t", 10) == 0 || strncmp(line, "dim\t", 4) == 0 ||
            strncmp(line, "fold\t", 5) == 0 || strncmp(line, "sign\t", 5) == 0 ||
            strncmp(line, "marker\t", 7) == 0) {
            printf("%s\n", line);
            continue;
        }

        if (in_hunk) {
            if (n_ops >= cap) {
                cap = cap > 0 ? cap * 2 : 256;
                ops = (Op *)realloc(ops, cap * sizeof(Op));
            }
            Op *op = &ops[n_ops];
            memset(op, 0, sizeof(Op));
            char type[AD_LAYER_TYPE_LEN];
            sscanf(line, "%19s", type);
            strncpy(op->type, type, AD_LAYER_TYPE_LEN - 1);
            op->type[AD_LAYER_TYPE_LEN - 1] = 0;

            if (strcmp(type, "split_line") == 0)
                sscanf(line, "%*s\t%d\t%d", &op->line, &op->col);
            else if (strcmp(type, "join_lines") == 0)
                sscanf(line, "%*s\t%d", &op->line);
            else if (strcmp(type, "keep_line") == 0)
                sscanf(line, "%*s\t%d", &op->line);
            else
                sscanf(line, "%*s\t%d\t%d\t%d", &op->line, &op->col, &op->code);
            n_ops++;
        } else {
            printf("%s\n", line);
        }
    }

    /* Free any remaining ops */
    for (int j = 0; j < n_ops; j++) {
        if (ops[j].text) free(ops[j].text);
    }
    free(ops);
    return 0;
}
