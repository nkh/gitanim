/* ad_layer_line_replace.c — Replace char ops with line-level ops.
 *
 * For ANY line that has at least one delete or insert op, collapse all
 * its char ops into:
 *   delete_line\t<L>
 *   insert_line\t<L>\t<final_text>
 *   delay\t<line_delay_ms>\tline   (if --line-delay-ms > 0)
 *
 * The <final_text> is the line's content AFTER applying all ops (keeps,
 * deletes, inserts) to the original line. Even a single-char change
 * produces a delete_line + insert_line.
 *
 * Lines with only keeps (no changes) are passed through as char ops.
 *
 * The layer groups ops by line number (not by \n boundaries) to handle
 * the diff engine's interleaved op layout correctly.
 *
 * Usage:
 *   ad_layer_line_replace [--line-delay-ms N] < ops.tsv > replaced.tsv
 *   ad_layer_line_replace --help
 */
#include "ad_layer_common.h"

static int line_delay_ms = 0;

/* Max lines we can track */
#define MAX_LINES 100000

/* Per-line info */
typedef struct {
    int has_change;       /* has any delete or insert */
    int has_keep;         /* has any keep */
    int line_num;         /* the line number (1-indexed) */
    char *final_text;     /* final line text after applying all ops */
    int text_len;         /* length of final_text */
    int text_cap;         /* capacity of final_text */
} LineInfo;

/* Ensure final_text has enough capacity */
static void line_ensure_cap(LineInfo *li, int needed) {
    if (needed < li->text_cap) return;
    int new_cap = li->text_cap == 0 ? 256 : li->text_cap;
    while (new_cap <= needed) new_cap *= 2;
    char *tmp = realloc(li->final_text, new_cap);
    if (!tmp) return;  /* out of memory — text will be truncated */
    li->final_text = tmp;
    li->text_cap = new_cap;
}

/* Append a char to final_text */
static void line_append_char(LineInfo *li, int code) {
    if (li->text_len >= li->text_cap - 1)
        line_ensure_cap(li, li->text_len + 2);
    if (li->text_len < li->text_cap - 1) {
        if (code == AD_LAYER_CHAR_SPACE) li->final_text[li->text_len++] = ' ';
        else if (code == AD_LAYER_CHAR_TAB) li->final_text[li->text_len++] = '\t';
        else if (code >= 32 && code < 127) li->final_text[li->text_len++] = (char)code;
        else if (code == AD_LAYER_CHAR_NEWLINE) ;
        else li->final_text[li->text_len++] = '?';
    }
}

static int layer_line_replace(Op *ops, int n_ops, Op *out, int out_cap,
                               int *line_offset) {
    /* Pass 1: scan all ops, build final text for each virtual line.
     * Track virtual line numbers because the diff engine's line field
     * doesn't advance on \n delete. */
    static LineInfo lines[MAX_LINES];
    memset(lines, 0, sizeof(lines));

    int virtual_line = -1;  /* will be set from first op's line */
    for (int i = 0; i < n_ops; i++) {
        if (ad_layer_is_debug_op(&ops[i])) continue;
        if (strncmp(ops[i].type, "HUNK", 4) == 0) continue;

        if (ops[i].code == AD_LAYER_CHAR_NEWLINE) {
            if (strcmp(ops[i].type, "delete") != 0) {
                virtual_line++;
                if (virtual_line >= MAX_LINES) virtual_line = MAX_LINES - 1;
            }
            continue;
        }

        /* Initialize virtual_line from the first op's line field */
        if (virtual_line == -1 && ops[i].line > 0)
            virtual_line = ops[i].line;

        int ln = virtual_line;
        if (ln <= 0 || ln >= MAX_LINES) continue;

        if (strcmp(ops[i].type, "delete") == 0 ||
            strcmp(ops[i].type, "insert") == 0 ||
            strcmp(ops[i].type, "overwrite_insert") == 0) {
            lines[ln].has_change = 1;
        }
        if (strcmp(ops[i].type, "keep") == 0) {
            lines[ln].has_keep = 1;
            line_append_char(&lines[ln], ops[i].code);
        } else if (strcmp(ops[i].type, "insert") == 0 ||
                   strcmp(ops[i].type, "overwrite_insert") == 0) {
            line_append_char(&lines[ln], ops[i].code);
        }
        lines[ln].line_num = ln;
    }

    /* Null-terminate all final_text */
    for (int ln = 1; ln < MAX_LINES; ln++) {
        if (lines[ln].final_text) {
            line_ensure_cap(&lines[ln], lines[ln].text_len + 1);
            if (lines[ln].text_len < lines[ln].text_cap)
                lines[ln].final_text[lines[ln].text_len] = 0;
        }
    }

    /* Pass 2: emit ops, collapsing changed lines */
    int out_count = 0;
    int i = 0;
    virtual_line = -1;
    static int emitted[MAX_LINES];
    memset(emitted, 0, sizeof(emitted));
    while (i < n_ops) {
        if (ad_layer_is_debug_op(&ops[i]) ||
            strncmp(ops[i].type, "HUNK", 4) == 0) {
            if (out_count < out_cap)
                out[out_count++] = ops[i];
            i++;
            continue;
        }

        if (ops[i].code == AD_LAYER_CHAR_NEWLINE) {
            int skip = 0;
            /* Initialize virtual_line from first non-boundary op */
            if (virtual_line == -1 && ops[i].line > 0)
                virtual_line = ops[i].line;
            int ln = virtual_line;
            if (strcmp(ops[i].type, "delete") == 0) {
                if (ln > 0 && ln < MAX_LINES && lines[ln].has_change)
                    skip = 1;
            } else {
                if (ln > 0 && ln < MAX_LINES && lines[ln].has_change)
                    skip = 1;
                if (!skip && ln + 1 < MAX_LINES && lines[ln + 1].has_change)
                    skip = 1;
                virtual_line++;
                if (virtual_line >= MAX_LINES) virtual_line = MAX_LINES - 1;
            }
            if (!skip && out_count < out_cap)
                out[out_count++] = ops[i];
            i++;
            continue;
        }

        /* Initialize virtual_line from first op's line field */
        if (virtual_line == -1 && ops[i].line > 0)
            virtual_line = ops[i].line;
        int ln = virtual_line;
        if (ln <= 0 || ln >= MAX_LINES || !lines[ln].has_change) {
            if (out_count < out_cap)
                out[out_count++] = ops[i];
            i++;
            continue;
        }

        /* Line has changes — skip all its ops, emit delete_line+insert_line
         * once */
        if (!emitted[ln]) {
            Op dl_op = {0};
            strcpy(dl_op.type, "delete_line");
            dl_op.line = ln;
            dl_op.text = NULL;
            if (out_count < out_cap)
                out[out_count++] = dl_op;

            Op il_op = {0};
            strcpy(il_op.type, "insert_line");
            il_op.line = ln;
            il_op.text = strdup(lines[ln].final_text ? lines[ln].final_text : "");
            if (out_count < out_cap)
                out[out_count++] = il_op;

            if (line_delay_ms > 0) {
                Op delay_op = {0};
                strcpy(delay_op.type, "delay");
                delay_op.code = line_delay_ms;
                delay_op.text = NULL;
                if (out_count < out_cap)
                    out[out_count++] = delay_op;
            }
            emitted[ln] = 1;
        }

        /* Skip this op (it's part of a collapsed line) */
        i++;
    }

    /* Free line texts */
    for (int ln = 1; ln < MAX_LINES; ln++) {
        free(lines[ln].final_text);
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
                "For ANY line that has at least one delete or insert op, collapses\n"
                "all its char ops into delete_line + insert_line. The insert_line\n"
                "text is the final line content after applying all ops (keeps +\n"
                "deletes + inserts). Even a single-char change produces a full\n"
                "delete_line + insert_line.\n");
            return 0;
        }
    }

    return ad_layer_run(layer_line_replace);
}
