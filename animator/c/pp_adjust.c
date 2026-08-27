/*
 * pp_adjust.c — Line/Col Position Adjustment (shared infrastructure)
 *
 * adjust_positions: recursive function that adjusts (line, col) for
 * every op based on \n deletes. Tracks deleted_lines and current_characters
 * (cursor position). Handles JOIN (line with content + \n delete) via
 * recursive calls.
 *
 * This file is compiled into the main postprocess binary AND can be
 * compiled standalone for use by individual layer binaries.
 *
 * When compiled standalone (-DPP_ADJUST_STANDALONE), provides a
 * command-line tool that reads V2 TSV, runs adjust_positions, and
 * writes V2 TSV.
 *
 * Build standalone:
 *   cc -DPP_ADJUST_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
 *      -I animator/c -o animator/bin/pp_adjust animator/c/pp_adjust.c
 */

#include "pp_common.h"

/* ── adjust_positions: recursive line/col adjustment ──────────────── */
/*
 * Walks ops in order and adjusts (line, col) based on \n deletes.
 *
 * State:
 *   deleted_lines: count of \n deletes (incremented on every \n delete)
 *   current_characters: cursor position on the current line
 *   content_on_line: keeps+inserts on current line (for JOIN detection)
 *
 * Rules:
 *   1. Line changed → current_characters = op.col, update current_line
 *   2. Count chars (code != \n): keep +1, insert +1, delete +0, overwrite_insert +0
 *   3. Set op position: op.line -= deleted_lines, op.col = current_characters
 *   4. \n delete: deleted_lines++. If content_on_line > 0 → recursive JOIN call
 *   5. \n keep/insert/overwrite_insert → current_characters = 0, content_on_line = 0
 *
 * A line always has ≥1 char (the \n). JOIN is detected when content_on_line > 0
 * (there are content chars beyond just the \n).
 *
 * Returns: deleted_lines and ops_consumed via output params.
 */
void adjust_positions(Op *ops, int n_ops, int current_characters_in,
                      int deleted_lines_in,
                      int *deleted_lines_out, int *ops_consumed_out) {
    int deleted_lines = deleted_lines_in;
    int current_characters = current_characters_in;
    int content_on_line = 0;
    int current_line = (current_characters_in == 0) ? -1 : (ops[0].line - deleted_lines);
    int i = 0;

    while (i < n_ops) {
        if (pp_is_debug_op(&ops[i])) { i++; continue; }

        /* Rule 1: line changed? */
        if ((ops[i].line - deleted_lines) != current_line) {
            current_characters = ops[i].col;
            current_line = ops[i].line - deleted_lines;
            content_on_line = 0;
        }

        /* Rule 3: set this op's position (in place) */
        ops[i].line = ops[i].line - deleted_lines;
        ops[i].col  = current_characters;

        /* Rule 2: advance current_characters (code != \n first) */
        if (ops[i].code != 10) {
            if (strcmp(ops[i].type, "keep") == 0) {
                current_characters += 1;
                content_on_line++;
            } else if (strcmp(ops[i].type, "insert") == 0) {
                current_characters += 1;
                content_on_line++;
            }
            /* delete: no change */
            /* overwrite_insert: net 0 */
        }

        /* Rules 4 & 5: \n ops */
        if (ops[i].code == 10) {
            if (strcmp(ops[i].type, "delete") == 0) {
                /* Rule 4: \n delete */
                deleted_lines += 1;
                if (content_on_line > 0) {
                    /* JOIN: content chars remain on this line.
                     * Recursive call on the merged line's ops. */
                    int sub_deleted, sub_consumed;
                    adjust_positions(&ops[i + 1], n_ops - i - 1,
                                      current_characters, deleted_lines,
                                      &sub_deleted, &sub_consumed);
                    deleted_lines = sub_deleted;
                    i += 1 + sub_consumed;
                    continue;
                }
            } else {
                /* Rule 5: \n keep / \n insert / \n overwrite_insert */
                current_characters = 0;
                content_on_line = 0;
            }
        }

        i++;
    }

    *deleted_lines_out = deleted_lines;
    *ops_consumed_out = i;
}

/* Wrapper for top-level call */
__attribute__((unused)) int run_adjust_positions(Op *ops, int n_ops) {
    int deleted_lines, ops_consumed;
    adjust_positions(ops, n_ops, 0, 0, &deleted_lines, &ops_consumed);
    return deleted_lines;
}

#ifdef PP_ADJUST_STANDALONE
int main(void) {
    pp_debug_init("adjust", "Position Adjustment");
    /* Read V2 TSV from stdin, parse into Op array per hunk,
     * run adjust_positions, write V2 TSV to stdout */
    char line[PP_MAX_LINE];
    int in_hunk = 0;
    Hunk current_hunk = {0};
    Op *ops = NULL;
    int n_ops = 0;
    int ops_cap = 0;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n\r")] = 0;
        if (line[0] == 0) continue;
        if (line[0] == '#') { printf("%s\n", line); continue; }

        if (strncmp(line, "HUNK\t", 5) == 0) {
            sscanf(line, "HUNK\t%d\t%d\t%d\t%d\t%d",
                   &current_hunk.target, &current_hunk.del, &current_hunk.ins,
                   &current_hunk.end_ins, &current_hunk.end_del);
            in_hunk = 1;
            n_ops = 0;
            if (!ops) { ops_cap = 4096; ops = (Op *)malloc(ops_cap * sizeof(Op)); }
            continue;
        }

        if (strncmp(line, "HUNK_END", 8) == 0) {
            if (in_hunk && n_ops > 0) {
                run_adjust_positions(ops, n_ops);
                pp_write_hunk(&current_hunk);
                for (int i = 0; i < n_ops; i++) pp_write_op(&ops[i]);
                pp_write_hunk_end();
            }
            in_hunk = 0;
            n_ops = 0;
            continue;
        }

        if (in_hunk) {
            if (n_ops >= ops_cap) {
                ops_cap *= 2;
                ops = (Op *)realloc(ops, ops_cap * sizeof(Op));
            }
            pp_parse_op(line, &ops[n_ops]);
            n_ops++;
        }
    }

    if (in_hunk && n_ops > 0) {
        run_adjust_positions(ops, n_ops);
        pp_write_hunk(&current_hunk);
        for (int i = 0; i < n_ops; i++) pp_write_op(&ops[i]);
        pp_write_hunk_end();
    }

    printf("\n");
    if (ops) free(ops);
    return 0;
}
#endif
