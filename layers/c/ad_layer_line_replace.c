/* ad_layer_line_replace.c — Replace char ops with line-level ops.
 *
 * Detects when a line's char ops amount to a full content replacement
 * (all old chars deleted, all new chars inserted) and collapses them
 * into:
 *   delete_line\t<L>
 *   insert_line\t<L>\t<new_text>
 *   delay\t<line_delay_ms>\tline   (if --line-delay-ms > 0)
 *
 * Lines that are only partially changed (some keeps) are passed through
 * as char ops — the layer only fires for full replacements.
 *
 * This produces "line-by-line" animation: the animator deletes the old
 * line and inserts the new one atomically. With --line-delay-ms 0, the
 * change is instant (no flicker). With --line-delay-ms 300, the viewer
 * sees the line disappear, pause, then reappear.
 *
 * Usage:
 *   ad_layer_line_replace [--line-delay-ms N] < ops.tsv > replaced.tsv
 *   ad_layer_line_replace --help
 *
 * Build: make layers
 */
#include "ad_layer_common.h"

static int line_delay_ms = 0;  /* 0 = instant, >0 = visible delay */

/* (is_full_line_change removed — the logic is now inline in
 * layer_line_replace for better same-line detection.) */

static int layer_line_replace(Op *ops, int n_ops, Op *out, int out_cap,
                               int *line_offset) {
    int out_count = 0;

    /* Strategy: walk ops, collecting them per line. When we see a \n op,
     * flush the current line's collected ops. If they constitute a full
     * line change (no keeps), collapse to delete_line/insert_line.
     *
     * We track the "current line" as the diff engine's cur_line — which
     * advances on \n keep/insert but not \n delete. We track it by
     * looking at the line field of ops.
     *
     * Simpler approach: just pass everything through for now, but
     * detect SEQUENCES of same-line ops between \n boundaries.
     * If a sequence has only deletes (no keeps, no inserts) for one line,
     * collapse to delete_line. If only inserts, collapse to insert_line.
     * If both deletes and inserts (no keeps), collapse to both.
     */

    int seg_start = 0;
    int prev_collapsed = 0;

    for (int i = 0; i <= n_ops; i++) {
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i])) {
            if (ops[i].code == AD_LAYER_CHAR_NEWLINE ||
                strncmp(ops[i].type, "HUNK", 4) == 0)
                is_boundary = 1;
        }

        if (is_boundary) {
            /* Check if all ops in [seg_start, i) target the same line
             * and have no keeps */
            int seg_line = 0;
            int same_line = 1;
            int has_keep = 0;
            int has_delete = 0;
            int has_insert = 0;

            for (int j = seg_start; j < i; j++) {
                if (ad_layer_is_debug_op(&ops[j])) continue;
                if (ops[j].code == AD_LAYER_CHAR_NEWLINE) continue;
                if (ops[j].line == 0) continue;

                if (seg_line == 0)
                    seg_line = ops[j].line;
                else if (ops[j].line != seg_line) {
                    same_line = 0;
                    break;
                }

                if (strcmp(ops[j].type, "keep") == 0) has_keep = 1;
                if (strcmp(ops[j].type, "delete") == 0) has_delete = 1;
                if (strcmp(ops[j].type, "insert") == 0 ||
                    strcmp(ops[j].type, "overwrite_insert") == 0) has_insert = 1;
            }

            int collapsed = (same_line && !has_keep && (has_delete || has_insert));

            if (collapsed) {
                /* Build insert text */
                char new_text[AD_LAYER_MAX_LINE];
                int text_len = 0;
                int n_ins = 0;
                int ins_cols[256];
                int ins_codes[256];
                for (int j = seg_start; j < i && n_ins < 256; j++) {
                    if (ad_layer_is_debug_op(&ops[j])) continue;
                    if (ops[j].code == AD_LAYER_CHAR_NEWLINE) continue;
                    if (strcmp(ops[j].type, "insert") == 0 ||
                        strcmp(ops[j].type, "overwrite_insert") == 0) {
                        ins_cols[n_ins] = ops[j].col;
                        ins_codes[n_ins] = ops[j].code;
                        n_ins++;
                    }
                }
                for (int a = 0; a < n_ins - 1; a++) {
                    for (int b = 0; b < n_ins - 1 - a; b++) {
                        if (ins_cols[b] > ins_cols[b + 1]) {
                            int tmp = ins_cols[b]; ins_cols[b] = ins_cols[b + 1]; ins_cols[b + 1] = tmp;
                            tmp = ins_codes[b]; ins_codes[b] = ins_codes[b + 1]; ins_codes[b + 1] = tmp;
                        }
                    }
                }
                for (int a = 0; a < n_ins && text_len < (int)sizeof(new_text) - 1; a++) {
                    if (ins_codes[a] == AD_LAYER_CHAR_SPACE) new_text[text_len++] = ' ';
                    else if (ins_codes[a] == AD_LAYER_CHAR_TAB) new_text[text_len++] = '\t';
                    else if (ins_codes[a] >= 32 && ins_codes[a] < 127) new_text[text_len++] = (char)ins_codes[a];
                    else if (ins_codes[a] == AD_LAYER_CHAR_NEWLINE) ;
                    else new_text[text_len++] = '?';
                }
                new_text[text_len] = 0;

                if (has_delete) {
                    Op dl_op = {0};
                    strcpy(dl_op.type, "delete_line");
                    dl_op.line = seg_line;
                    dl_op.text = NULL;
                    if (out_count < out_cap)
                        out[out_count++] = dl_op;
                }
                if (has_insert) {
                    Op il_op = {0};
                    strcpy(il_op.type, "insert_line");
                    il_op.line = seg_line;
                    il_op.text = strdup(new_text);
                    if (out_count < out_cap)
                        out[out_count++] = il_op;
                }
                if (line_delay_ms > 0) {
                    Op delay_op = {0};
                    strcpy(delay_op.type, "delay");
                    delay_op.code = line_delay_ms;
                    delay_op.text = NULL;
                    if (out_count < out_cap)
                        out[out_count++] = delay_op;
                }
            } else {
                for (int j = seg_start; j < i && out_count < out_cap; j++)
                    out[out_count++] = ops[j];
            }

            /* Emit boundary — skip \n delete/insert if collapsed */
            if (i < n_ops && out_count < out_cap) {
                int skip = 0;
                if (ops[i].code == AD_LAYER_CHAR_NEWLINE &&
                    (strcmp(ops[i].type, "delete") == 0 ||
                     strcmp(ops[i].type, "insert") == 0) &&
                    (collapsed || prev_collapsed))
                    skip = 1;
                if (!skip)
                    out[out_count++] = ops[i];
            }
            prev_collapsed = collapsed;
            seg_start = i + 1;
        }
    }

    int ni = 0, nd = 0;
    for (int j = 0; j < out_count; j++) {
        if (strcmp(out[j].type, "insert_line") == 0) ni++;
        if (strcmp(out[j].type, "delete_line") == 0) nd++;
    }
    *line_offset += ni - nd;

    return out_count;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--line-delay-ms") == 0 && i + 1 < argc) {
            line_delay_ms = atoi(argv[++i]);
        } else if (strcmp(argv[i], "--help") == 0 ||
                   strcmp(argv[i], "-h") == 0) {
            fprintf(stderr,
                "ad_layer_line_replace — replace char ops with line-level ops\n\n"
                "Usage: ad_layer_line_replace [options] < ops.tsv > replaced.tsv\n\n"
                "Options:\n"
                "  --line-delay-ms N  Delay after each line replacement (default: 0 = instant)\n"
                "  --help, -h         Show this help\n\n"
                "Detects when a line's char ops amount to a full content replacement\n"
                "(all old chars deleted, all new chars inserted, no keeps) and collapses\n"
                "them into delete_line + insert_line ops. The animator applies these\n"
                "atomically — no flicker. With --line-delay-ms > 0, a delay is inserted\n"
                "so the change is visible.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_line_replace);
}
