/* ad_layer_split_in_place.c — Insert content AFTER splitting lines.
 *
 * When the diff engine expands one old line into N new lines, it produces:
 *   insert(L, col 1, chars)+ → split_line(L, K)
 * The inserted text and old content are momentarily concatenated. This
 * layer reorders to: split_line(L, 1) → insert(L, col 1, chars)+
 *
 * Safety: only reorders when the HUNK has del > 0 (old lines being
 * replaced — the line exists and has content). For pure-insert hunks
 * (del=0, end-of-file), the line might not exist in the buffer, so the
 * split would clamp to the wrong line — skip.
 *
 * Build: make layers
 * Usage:  ad_layer_split_in_place < ops.tsv
 */
#include "ad_layer_common.h"

/* Custom main — does NOT use ad_layer_run because we need access to the
 * HUNK header's del count to know if the line has existing content. */
int main(int argc, char **argv) {
    __argc = argc; __argv = argv;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_split_in_place — insert content after splitting lines\n\n"
                "Usage: ad_layer_split_in_place < ops.tsv\n\n"
                "Reorders: insert(L,col1)+ + split_line(L,K)\n"
                "      to: split_line(L,1) + insert(L,col1)+\n\n"
                "Only reorders when the HUNK has del > 0 (line has old content).\n"
                "Symmetric of ad_layer_line_delete_inplace.\n");
            return 0;
        }
    }

    char line[AD_LAYER_MAX_LINE];
    Op *ops = NULL;
    int n_ops = 0, cap = 0;
    int in_hunk = 0;
    int hunk_del = 0;
    int hunk_end_insert = 0;

    /* Read all lines, process per-hunk */
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;

        /* Pass through comments and blank lines */
        if (line[0] == '#' || line[0] == 0) {
            printf("%s\n", line);
            continue;
        }

        /* HUNK header — start collecting ops */
        if (strncmp(line, "HUNK\t", 5) == 0) {
            int t, d, i, ei, ed;
            sscanf(line, "HUNK\t%d\t%d\t%d\t%d\t%d", &t, &d, &i, &ei, &ed);
            hunk_del = d;
            hunk_end_insert = ei;
            
            in_hunk = 1;
            n_ops = 0;
            printf("%s\n", line);
            continue;
        }

        /* HUNK_END — process collected ops, then flush */
        if (strncmp(line, "HUNK_END", 8) == 0) {
            in_hunk = 0;

            /* Process the collected ops for this hunk */
            int i = 0;
            while (i < n_ops) {
                /* Pattern: insert(col1)+ + split_line(L, K) */
                if (i + 1 < n_ops
                    && strcmp(ops[i].type, "insert") == 0
                    && ops[i].col == 1) {

                    /* Scan forward for consecutive inserts on same line */
                    int ie = i;
                    int insert_line = ops[i].line;
                    while (ie < n_ops
                           && strcmp(ops[ie].type, "insert") == 0
                           && ops[ie].line == insert_line
                           && ops[ie].col == (ie - i) + 1)
                        ie++;
                    int insert_count = ie - i;

                    /* Check: trailing split_line on same line? */
                    if (insert_count > 0
                        && ie < n_ops
                        && strcmp(ops[ie].type, "split_line") == 0
                        && ops[ie].line == insert_line
                        && ops[ie].col == insert_count + 1
                        && (hunk_del > 0 || !hunk_end_insert)) {

                        /* Reorder: split_line FIRST (at col 1), then inserts */
                        Op split_first = ops[ie];
                        split_first.col = 1;
                        printf("split_line\t%d\t1\n", split_first.line);
                        for (int k = i; k < ie; k++)
                            printf("%s\t%d\t%d\t%d\n", ops[k].type,
                                   ops[k].line, ops[k].col, ops[k].code);
                        i = ie + 1;
                        continue;
                    }
                }

                /* Emit unchanged */
                Op *op = &ops[i];
                if (op->code > 0)
                    printf("%s\t%d\t%d\t%d\n", op->type, op->line, op->col, op->code);
                else if (strcmp(op->type, "split_line") == 0)
                    printf("split_line\t%d\t%d\n", op->line, op->col);
                else if (strcmp(op->type, "join_lines") == 0)
                    printf("join_lines\t%d\n", op->line);
                else if (strcmp(op->type, "keep_line") == 0)
                    printf("keep_line\t%d\n", op->line);
                else
                    printf("%s\t%d\t%d\t%d\n", op->type, op->line, op->col, op->code);
                i++;
            }

            printf("HUNK_END\n");
            n_ops = 0;
            continue;
        }

        /* Collect ops within a hunk */
        if (in_hunk) {
            if (n_ops >= cap) {
                cap = cap > 0 ? cap * 2 : 256;
                ops = (Op *)realloc(ops, cap * sizeof(Op));
            }
            Op *op = &ops[n_ops];
            memset(op, 0, sizeof(Op));
            char type[AD_LAYER_TYPE_LEN];
            int fld = sscanf(line, "%19s", type);
            if (fld < 1) { n_ops++; continue; }
            strncpy(op->type, type, AD_LAYER_TYPE_LEN - 1);
            op->type[AD_LAYER_TYPE_LEN - 1] = 0;

            if (strcmp(type, "split_line") == 0)
                sscanf(line, "%*s\t%d\t%d", &op->line, &op->col);
            else if (strcmp(type, "join_lines") == 0)
                sscanf(line, "%*s\t%d", &op->line);
            else if (strcmp(type, "keep_line") == 0)
                sscanf(line, "%*s\t%d", &op->line);
            else if (strcmp(type, "keep") == 0 || strcmp(type, "delete") == 0
                     || strcmp(type, "insert") == 0)
                sscanf(line, "%*s\t%d\t%d\t%d", &op->line, &op->col, &op->code);
            else
                sscanf(line, "%*s\t%d\t%d\t%d", &op->line, &op->col, &op->code);
            n_ops++;
        } else {
            /* Outside hunk — pass through */
            printf("%s\n", line);
        }
    }

    free(ops);
    return 0;
}
