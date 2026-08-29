/* ad_layer_highlight — Insert decoration ops into the timed op stream.
 *
 * Reads a timed op stream from stdin, inserts decoration ops
 * (highlight, dim, fold, sign, marker) based on the options, writes
 * the decorated stream to stdout.
 *
 * Both the vimscript animator and the C animator interpret the
 * decoration ops the same way.
 *
 * New op types (TSV):
 *   highlight\t<start_line>\t<start_col>\t<end_line>\t<end_col>\t<type>\t<duration_ms>
 *       <type>: insert|delete|hunk
 *       Renderer: highlight the region, wait <duration_ms>, then clear
 *
 *   dim\t<start_line>\t<end_line>\t<pct>
 *       Renderer: dim the specified line range
 *
 *   fold\t<start_line>\t<end_line>
 *       Renderer: fold the specified line range
 *
 *   sign\t<line>\t<type>
 *       <type>: add|del
 *       Renderer: place a sign in the sign column
 *
 *   marker\t<line>\t<col>\t<text>
 *       Renderer: show <text> at the given position (e.g. git blame)
 *
 * Usage: ad_layer_highlight [options]
 *   --highlight none|inline|word|hunk   (default: none)
 *   --highlight-duration-ms N           (default: 200)
 *   --dim-unchanged                     Dim unchanged anchor lines
 *   --dim-unchanged-pct N              Dim percentage (default: 60)
 *   --context N                        Fold unchanged regions >2N lines
 *   --fold-unchanged                   Fold unchanged regions
 *   --sign-column                      Place +/- signs
 *   --git-blame                        Insert blame markers
 *   --max-hunk-chars N                 Skip animation for hunks >N chars
 *   --theme dark|light|high-contrast   Color theme
 *
 * Build: cc -O2 -o ad_layer_highlight decorate.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ad_layer_common.h"
#define MAX_LINE AD_LAYER_MAX_LINE


/* Options */
static char highlight_mode[32] = "none";
static int highlight_duration_ms = 200;
static int dim_unchanged = 0;
static int dim_unchanged_pct = 60;
static int context_lines = 0;
static int fold_unchanged = 0;
static int sign_column = 0;
static int git_blame = 0;
static char old_file_path[1024] = "";  /* set by --old-file=PATH */
static int max_hunk_chars = 0;
static char theme[32] = "";

/* Read all input lines */
static char **all_lines = NULL;
static int n_lines = 0;
static int cap_lines = 0;

void ensure_capacity(int needed) {
    if (needed <= cap_lines) return;
    int nc = cap_lines == 0 ? 4096 : cap_lines;
    while (nc < needed) nc *= 2;
    { char **_tmp = realloc(all_lines, nc * sizeof(char *)); if (!_tmp) { fprintf(stderr, "out of memory\n"); exit(1); } all_lines = _tmp; }
    if (!all_lines) { fprintf(stderr, "out of memory\n"); exit(1); }
    cap_lines = nc;
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--highlight") == 0 && i+1 < argc)
            strncpy(highlight_mode, argv[++i], 31);
        else if (strcmp(argv[i], "--highlight-duration-ms") == 0 && i+1 < argc)
            highlight_duration_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--dim-unchanged") == 0)
            dim_unchanged = 1;
        else if (strcmp(argv[i], "--dim-unchanged-pct") == 0 && i+1 < argc)
            dim_unchanged_pct = atoi(argv[++i]);
        else if (strcmp(argv[i], "--context") == 0 && i+1 < argc)
            context_lines = atoi(argv[++i]);
        else if (strcmp(argv[i], "--fold-unchanged") == 0)
            fold_unchanged = 1;
        else if (strcmp(argv[i], "--sign-column") == 0)
            sign_column = 1;
        else if (strcmp(argv[i], "--git-blame") == 0)
            git_blame = 1;
        else if (strncmp(argv[i], "--old-file=", 11) == 0)
            strncpy(old_file_path, argv[i] + 11, sizeof(old_file_path) - 1);
        else if (strcmp(argv[i], "--max-hunk-chars") == 0 && i+1 < argc)
            max_hunk_chars = atoi(argv[++i]);
        else if (strcmp(argv[i], "--theme") == 0 && i+1 < argc)
            strncpy(theme, argv[++i], 31);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: ad_layer_highlight [options]\n");
            fprintf(stderr, "  --highlight none|inline|word|hunk  Highlight mode (default: none)\n");
            fprintf(stderr, "  --highlight-duration-ms N        Highlight duration (default: 200)\n");
            fprintf(stderr, "  --dim-unchanged                   Dim unchanged lines\n");
            fprintf(stderr, "  --dim-unchanged-pct N             Dim percentage (default: 60)\n");
            fprintf(stderr, "  --context N                       Fold unchanged regions >2N lines\n");
            fprintf(stderr, "  --fold-unchanged                  Fold unchanged regions\n");
            fprintf(stderr, "  --sign-column                     Place +/- signs\n");
            fprintf(stderr, "  --git-blame                       Insert blame markers\n");
            fprintf(stderr, "  --max-hunk-chars N                Skip animation for hunks >N chars\n");
            fprintf(stderr, "  --theme dark|light|high-contrast  Color theme\n");
            exit(0);
        }
    }
}


/* Check if a line is a keep op (unchanged content) */
int is_keep_op(const char *line) {
    return strncmp(line, "keep\t", 5) == 0;
}

/* Check if a line is a delete or insert op (changed content) */
int is_change_op(const char *line) {
    return strncmp(line, "delete\t", 7) == 0 || strncmp(line, "insert\t", 7) == 0;
}

/* Check if a line is a delay op */
int is_delay_op(const char *line) {
    return strncmp(line, "delay\t", 6) == 0;
}

/* Get the line number from an op */
int get_op_line(const char *line) {
    char buf[MAX_LINE];
    strncpy(buf, line, MAX_LINE - 1);
    buf[MAX_LINE - 1] = 0;
    char *toks[8];
    int n = ad_layer_parse_tsv(buf, toks, 8);
    if (n >= 2) return atoi(toks[1]);
    return 0;
}

/* Get the col from an op */
int get_op_col(const char *line) {
    char buf[MAX_LINE];
    strncpy(buf, line, MAX_LINE - 1);
    buf[MAX_LINE - 1] = 0;
    char *toks[8];
    int n = ad_layer_parse_tsv(buf, toks, 8);
    if (n >= 3) return atoi(toks[2]);
    return 0;
}

/* Get the code from an op */
int get_op_code(const char *line) {
    char buf[MAX_LINE];
    strncpy(buf, line, MAX_LINE - 1);
    buf[MAX_LINE - 1] = 0;
    char *toks[8];
    int n = ad_layer_parse_tsv(buf, toks, 8);
    if (n >= 4) return atoi(toks[3]);
    return 0;
}

/* Get the op type (keep/delete/insert/overwrite_insert) */
const char *get_op_type(const char *line) {
    static char type[32];  /* large enough for "overwrite_insert" (16) + NUL + slack */
    size_t n = 0;
    while (line[n] && line[n] != '\t' && n < sizeof(type) - 1) {
        type[n] = line[n];
        n++;
    }
    type[n] = 0;
    return type;
}

/* Emit a highlight op */
void emit_highlight(int start_line, int start_col, int end_line, int end_col,
                    const char *type, int duration_ms) {
    printf("highlight\t%d\t%d\t%d\t%d\t%s\t%d\n",
           start_line, start_col, end_line, end_col, type, duration_ms);
}

/* Emit a dim op */
void emit_dim(int start_line, int end_line, int pct) {
    printf("dim\t%d\t%d\t%d\n", start_line, end_line, pct);
}

/* Emit a fold op */
void emit_fold(int start_line, int end_line) {
    printf("fold\t%d\t%d\n", start_line, end_line);
}

/* Emit a sign op */
void emit_sign(int line, const char *type) {
    printf("sign\t%d\t%s\n", line, type);
}

/* Emit a marker op */
void emit_marker(int line, int col, const char *text) {
    printf("marker\t%d\t%d\t%s\n", line, col, text);
}

/* Emit a max-hunk-chars skip op (tells renderer to apply instantly) */
void emit_skip_hunk(void) {
    printf("skip_hunk\n");
}

/* Track hunk state for context/fold/sign insertion */
static int hunk_start_line = 0;
static int hunk_end_line = 0;
static int hunk_char_count = 0;
static int in_hunk = 0;
static int last_changed_line = 0;

/* Process: --highlight inline
 * After each delete/insert op, emit a highlight op for that position */
void do_highlight_inline(int idx) {
    const char *line = all_lines[idx];
    if (!is_change_op(line)) return;
    int op_line = get_op_line(line);
    int op_col = get_op_col(line);
    const char *type = get_op_type(line);
    if (strcmp(type, "delete") == 0)
        emit_highlight(op_line, op_col, op_line, op_col, "delete", highlight_duration_ms);
    else if (strcmp(type, "insert") == 0 || strcmp(type, "overwrite_insert") == 0)
        emit_highlight(op_line, op_col, op_line, op_col, "insert", highlight_duration_ms);
}

/* Check if a line is an op (keep/delete/insert/overwrite_insert). */
static int is_op(const char *line) {
    return strncmp(line, "keep\t", 5) == 0 ||
           strncmp(line, "delete\t", 7) == 0 ||
           strncmp(line, "insert\t", 7) == 0 ||
           strncmp(line, "overwrite_insert\t", 17) == 0;
}

/* Process: --highlight word
 * After each delete/insert op, highlight the entire word containing
 * the change. A "word" is a run of non-whitespace chars on the same
 * line. Walk backward and forward from the change op to find word
 * boundaries (whitespace or newline). */
void do_highlight_word(int idx) {
    const char *line = all_lines[idx];
    if (!is_change_op(line) || is_delay_op(line)) return;

    int op_line = get_op_line(line);
    int op_col = get_op_col(line);
    const char *type = get_op_type(line);

    /* Walk backward to find word start (first col of the word). */
    int word_start = op_col;
    for (int j = idx - 1; j >= 0; j--) {
        const char *prev = all_lines[j];
        if (is_delay_op(prev) || !is_op(prev)) break;
        int prev_line = get_op_line(prev);
        int prev_col = get_op_col(prev);
        int prev_code = get_op_code(prev);
        if (prev_line != op_line) break;  /* different line */
        if (prev_code == 32 || prev_code == 9 || prev_code == 10) break; /* whitespace */
        word_start = prev_col;
    }

    /* Walk forward to find word end (last col of the word). */
    int word_end = op_col;
    for (int j = idx + 1; j < n_lines; j++) {
        const char *next = all_lines[j];
        if (is_delay_op(next) || !is_op(next)) break;
        int next_line = get_op_line(next);
        int next_col = get_op_col(next);
        int next_code = get_op_code(next);
        if (next_line != op_line) break;  /* different line */
        if (next_code == 32 || next_code == 9 || next_code == 10) break; /* whitespace */
        word_end = next_col;
    }

    /* Emit highlight covering the entire word. */
    if (strcmp(type, "delete") == 0)
        emit_highlight(op_line, word_start, op_line, word_end, "delete_word", highlight_duration_ms);
    else
        emit_highlight(op_line, word_start, op_line, word_end, "insert_word", highlight_duration_ms);
}

/* Process: --highlight hunk
 * At HUNK_END, emit a highlight covering the entire hunk */
void do_highlight_hunk(void) {
    if (hunk_start_line > 0 && hunk_end_line > 0) {
        emit_highlight(hunk_start_line, 1, hunk_end_line, 1, "hunk", highlight_duration_ms);
    }
}

/* Process: --sign-column
 * For each changed line, emit a sign */
void do_sign_column(int idx) {
    const char *line = all_lines[idx];
    if (!is_change_op(line)) return;
    int op_line = get_op_line(line);
    const char *type = get_op_type(line);
    if (strcmp(type, "delete") == 0)
        emit_sign(op_line, "del");
    else if (strcmp(type, "insert") == 0 || strcmp(type, "overwrite_insert") == 0)
        emit_sign(op_line, "add");
}

/* Process: --dim-unchanged
 * After HUNK_END, emit dim ops for unchanged lines between hunks */
void do_dim_unchanged(int prev_hunk_end, int curr_hunk_start) {
    if (prev_hunk_end > 0 && curr_hunk_start > prev_hunk_end + 1) {
        emit_dim(prev_hunk_end + 1, curr_hunk_start - 1, dim_unchanged_pct);
    }
}

/* Process: --context N / --fold-unchanged
 * After HUNK_END, emit fold ops for unchanged regions >2N lines */
void do_context_fold(int prev_hunk_end, int curr_hunk_start) {
    if (context_lines > 0 || fold_unchanged) {
        if (prev_hunk_end > 0 && curr_hunk_start > prev_hunk_end + 1) {
            int gap = curr_hunk_start - prev_hunk_end - 1;
            if (fold_unchanged) {
                /* Fold entire gap */
                emit_fold(prev_hunk_end + 1, curr_hunk_start - 1);
            } else if (context_lines > 0 && gap > 2 * context_lines) {
                /* Fold middle of gap, keep N context lines */
                emit_fold(prev_hunk_end + context_lines + 1,
                          curr_hunk_start - context_lines - 1);
            }
        }
    }
}

/* Process: --max-hunk-chars
 * At HUNK_END, if hunk_char_count > max_hunk_chars, emit skip_hunk */
void do_max_hunk_chars(void) {
    if (max_hunk_chars > 0 && hunk_char_count > max_hunk_chars) {
        emit_skip_hunk();
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);

    /* Read all input */
    char buf[MAX_LINE];
    while (fgets(buf, sizeof(buf), stdin)) {
        buf[strcspn(buf, "\n")] = 0;
        ensure_capacity(n_lines + 1);
        all_lines[n_lines] = strdup(buf);
        n_lines++;
    }

    /* Emit header */
    printf("# diffvim decorated ops v2\n");
    printf("# highlight %s\n", highlight_mode);
    printf("# dim_unchanged %d\n", dim_unchanged);
    printf("# sign_column %d\n", sign_column);

    /* Process lines */
    int prev_hunk_end_line = 0;

    for (int i = 0; i < n_lines; i++) {
        char *line = all_lines[i];

        /* Skip comments */
        if (line[0] == '#' || line[0] == 0) continue;

        /* Detect HUNK start */
        if (strncmp(line, "HUNK\t", 5) == 0) {
            int target = get_op_line(line);
            hunk_start_line = target;
            hunk_char_count = 0;
            last_changed_line = 0;  /* Reset per hunk — prevents stale value from previous hunk */
            in_hunk = 1;

            /* Dim unchanged region before this hunk */
            if (dim_unchanged) {
                do_dim_unchanged(prev_hunk_end_line, target);
            }
            /* Fold unchanged region before this hunk */
            do_context_fold(prev_hunk_end_line, target);

            printf("%s\n", line);
            continue;
        }

        /* Detect HUNK_END */
        if (strcmp(line, "HUNK_END") == 0) {
            in_hunk = 0;
            hunk_end_line = last_changed_line;

            /* Highlight hunk */
            if (strcmp(highlight_mode, "hunk") == 0) {
                do_highlight_hunk();
            }
            /* Max hunk chars */
            if (max_hunk_chars > 0) {
                do_max_hunk_chars();
            }

            prev_hunk_end_line = hunk_end_line;
            printf("%s\n", line);
            continue;
        }

        /* For change ops: track hunk state */
        if (is_change_op(line)) {
            int op_line = get_op_line(line);
            if (op_line > last_changed_line) last_changed_line = op_line;
            hunk_char_count++;
        }

        /* Emit the op */
        printf("%s\n", line);

        /* After change ops, emit decorations */
        if (is_change_op(line) && !is_delay_op(line)) {
            if (strcmp(highlight_mode, "inline") == 0) {
                do_highlight_inline(i);
            } else if (strcmp(highlight_mode, "word") == 0) {
                do_highlight_word(i);
            }
            if (sign_column) {
                do_sign_column(i);
            }
            /* Git blame: run `git blame` on the old file and emit markers
             * with the commit hash for each changed line. */
            if (git_blame && old_file_path[0]) {
                const char *blame_type = get_op_type(all_lines[i]);
                if (strcmp(blame_type, "delete") == 0 || strcmp(blame_type, "insert") == 0) {
                    int op_line = get_op_line(all_lines[i]);
                    if (op_line > 0) {
                        /* Run git blame for this line, extract commit hash. */
                        char cmd[2048];
                        snprintf(cmd, sizeof(cmd),
                            "git blame -L %d,%d --porcelain '%s' 2>/dev/null | head -1 | cut -d' ' -f1",
                            op_line, op_line, old_file_path);
                        FILE *fp = popen(cmd, "r");
                        if (fp) {
                            char hash[64] = "";
                            if (fgets(hash, sizeof(hash), fp)) {
                                hash[strcspn(hash, "\n")] = 0;
                                if (hash[0]) {
                                    char marker[128];
                                    snprintf(marker, sizeof(marker), "blame %s", hash);
                                    emit_marker(op_line, 1, marker);
                                }
                            }
                            pclose(fp);
                        }
                    }
                }
            }
        }
    }

    printf("\n");  /* blank line at bottom */

    /* Free memory */
    for (int i = 0; i < n_lines; i++) free(all_lines[i]);
    free(all_lines);
    return 0;
}
