/* diffvim-pace — Insert delays between ops.
 *
 * Reads post-processed ops from stdin, inserts delay lines between them,
 * writes timed ops to stdout.
 *
 * PACE DOES NOT MODIFY, REORDER, OR ADD ANY OPS.
 * It only inserts "delay\t<ms>\t<type>" lines between ops.
 *
 * Delay types:
 *   char      — per-character (normal typing speed)
 *   word      — after completing a word batch
 *   hunk      — between hunks
 *   awd_slow  — AWD: initial slow chars before acceleration
 *   awd_fast  — AWD: accelerated word batches
 *   awd_skip  — AWD: spaces deleted instantly
 *
 * Input format (TSV):
 *   HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
 *   keep\t<line>\t<col>\t<code>\t<char_repr>
 *   delete\t<line>\t<col>\t<code>\t<char_repr>
 *   insert\t<line>\t<col>\t<code>\t<char_repr>
 *   HUNK_END
 *
 * Output format (TSV):
 *   (same as input, with delay lines inserted between ops)
 *   delay\t<ms>\t<type>
 *
 * Usage: diffvim-pace [--delete-pacing MODE] [--delete-speed MODE]
 *                     [--delete-threshold N] [--insert-pacing MODE]
 *                     [--insert-speed MODE] [--pacing MODE]
 *                     [--snapshot FILE]
 *
 * Build: cc -O2 -o diffvim-pace pace.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 1048576

static char delete_pacing[32] = "word";
static char delete_speed[32] = "normal";
static int delete_threshold = 3;
static char insert_pacing[32] = "char";
static char insert_speed[32] = "normal";
static char snapshot_file[256] = "";

/* Timing defaults (ms) */
static int char_delay = 50;      /* normal typing */
static int delete_delay = 40;    /* per-char delete */
static int hunk_pause = 250;     /* between hunks */
static int awd_start_chars = 3;  /* chars before acceleration */
static int awd_start_ms = 80;    /* slow start delay */
static int awd_min_ms = 15;      /* minimum accelerated delay */
static double awd_accel = 0.85;  /* acceleration factor */
static int word_pause = 150;     /* after a word */

/* Output a delay line */
static void emit_delay(int ms, const char *type) {
    printf("delay\t%d\t%s\n", ms, type);
}

/* Output a line verbatim (pass through) */
static void passthrough(const char *line) {
    printf("%s\n", line);
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--delete-pacing") == 0 && i+1 < argc)
            strncpy(delete_pacing, argv[++i], 31);
        else if (strcmp(argv[i], "--delete-speed") == 0 && i+1 < argc)
            strncpy(delete_speed, argv[++i], 31);
        else if (strcmp(argv[i], "--delete-threshold") == 0 && i+1 < argc)
            delete_threshold = atoi(argv[++i]);
        else if (strcmp(argv[i], "--insert-pacing") == 0 && i+1 < argc)
            strncpy(insert_pacing, argv[++i], 31);
        else if (strcmp(argv[i], "--insert-speed") == 0 && i+1 < argc)
            strncpy(insert_speed, argv[++i], 31);
        else if (strcmp(argv[i], "--snapshot") == 0 && i+1 < argc)
            strncpy(snapshot_file, argv[++i], 255);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-pace [options]\n");
            fprintf(stderr, "  --delete-pacing MODE  char|rapid|word|instant (default: word)\n");
            fprintf(stderr, "  --delete-speed MODE   slow|normal|fast|instant (default: normal)\n");
            fprintf(stderr, "  --insert-pacing MODE  char|word (default: char)\n");
            fprintf(stderr, "  --insert-speed MODE   slow|normal|fast (default: normal)\n");
            fprintf(stderr, "  --snapshot FILE       Insert snapshot op at end\n");
            exit(0);
        }
    }
}

void apply_speeds(void) {
    if (strcmp(delete_speed, "fast") == 0) {
        delete_delay /= 2;
        awd_start_ms /= 2;
    } else if (strcmp(delete_speed, "instant") == 0) {
        delete_delay = 1;
        awd_start_ms = 1;
        awd_min_ms = 1;
    }
    if (strcmp(insert_speed, "fast") == 0) {
        char_delay /= 2;
        word_pause /= 2;
    } else if (strcmp(insert_speed, "slow") == 0) {
        char_delay *= 2;
        word_pause *= 2;
    }
}

/* Parse a TSV line into tokens. Returns token count. */
int parse_tsv(char *line, char *toks[], int max_toks) {
    int n = 0;
    char *p = line;
    char *tab = strchr(p, '\t');
    while (tab && n < max_toks - 1) {
        *tab = 0;
        toks[n++] = p;
        p = tab + 1;
        tab = strchr(p, '\t');
    }
    toks[n++] = p;
    return n;
}

/* AWD: process a run of consecutive non-newline deletes on the same line.
 * Emits each delete op verbatim, with delays between them. */
void process_awd(char *lines[], int start, int count, int same_line) {
    int i = start;
    int end = start + count;

    /* Phase 1: Skip spaces instantly */
    while (i < end) {
        /* Parse the op to get the code */
        char *toks[8];
        char buf[MAX_LINE];
        strncpy(buf, lines[i], MAX_LINE - 1);
        buf[MAX_LINE - 1] = 0;
        int nt = parse_tsv(buf, toks, 8);
        int code = (nt >= 4) ? atoi(toks[3]) : 0;

        if (code == 32 || code == 9) {
            passthrough(lines[i]);
            emit_delay(awd_min_ms, "awd_skip");
            i++;
        } else {
            break;
        }
    }

    int remaining = end - i;
    if (remaining <= awd_start_chars) {
        /* Short run — delete all with awd_fast */
        for (int k = i; k < end; k++) {
            passthrough(lines[k]);
            emit_delay(awd_min_ms, "awd_fast");
        }
        return;
    }

    /* Phase 2: Delete start_chars slowly */
    for (int k = i; k < i + awd_start_chars; k++) {
        passthrough(lines[k]);
        emit_delay(awd_start_ms, "awd_slow");
    }
    i += awd_start_chars;

    /* Phase 3: Delete with acceleration */
    double delay = (double)awd_start_ms;
    while (i < end) {
        /* Count word (non-space chars) */
        int word_len = 0;
        while (i + word_len < end) {
            char buf2[MAX_LINE];
            strncpy(buf2, lines[i + word_len], MAX_LINE - 1);
            buf2[MAX_LINE - 1] = 0;
            char *t2[8];
            int n2 = parse_tsv(buf2, t2, 8);
            int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
            if (c2 == 32 || c2 == 9) break;
            word_len++;
        }
        if (word_len > 0) {
            for (int k = i; k < i + word_len; k++)
                passthrough(lines[k]);
            delay *= awd_accel;
            if (delay < awd_min_ms) delay = awd_min_ms;
            emit_delay((int)delay, "awd_fast");
            i += word_len;
        }
        /* Skip spaces */
        if (i < end) {
            int space_start = i;
            while (i < end) {
                char buf3[MAX_LINE];
                strncpy(buf3, lines[i], MAX_LINE - 1);
                buf3[MAX_LINE - 1] = 0;
                char *t3[8];
                int n3 = parse_tsv(buf3, t3, 8);
                int c3 = (n3 >= 4) ? atoi(t3[3]) : 0;
                if (c3 != 32 && c3 != 9) break;
                i++;
            }
            for (int k = space_start; k < i; k++)
                passthrough(lines[k]);
            emit_delay(awd_min_ms, "awd_skip");
        }
    }
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    apply_speeds();

    printf("# diffvim timed ops v2\n");
    printf("# delete_pacing %s\n", delete_pacing);
    printf("# insert_pacing %s\n", insert_pacing);

    /* Read all lines first (we need lookahead for AWD) */
    char **all_lines = NULL;
    int n_lines = 0;
    int cap_lines = 0;
    char buf[MAX_LINE];

    while (fgets(buf, sizeof(buf), stdin)) {
        buf[strcspn(buf, "\n")] = 0;
        if (buf[0] == 0 || buf[0] == '#') {
            /* Skip headers and blank lines from input */
            continue;
        }
        if (n_lines >= cap_lines) {
            cap_lines = cap_lines == 0 ? 4096 : cap_lines * 2;
            all_lines = (char **)realloc(all_lines, cap_lines * sizeof(char *));
            if (!all_lines) { fprintf(stderr, "diffvim-pace: out of memory\n"); exit(1); }
        }
        all_lines[n_lines] = strdup(buf);
        n_lines++;
    }

    int i = 0;
    while (i < n_lines) {
        char *toks[8];
        char tbuf[MAX_LINE];
        strncpy(tbuf, all_lines[i], MAX_LINE - 1);
        tbuf[MAX_LINE - 1] = 0;
        int nt = parse_tsv(tbuf, toks, 8);

        if (strcmp(toks[0], "HUNK") == 0) {
            passthrough(all_lines[i]);
            i++;
            continue;
        }
        if (strcmp(toks[0], "HUNK_END") == 0) {
            passthrough(all_lines[i]);
            /* Insert hunk pause if not the last hunk */
            if (i + 1 < n_lines) {
                /* Check if next is another HUNK */
                char nbuf[MAX_LINE];
                strncpy(nbuf, all_lines[i + 1], MAX_LINE - 1);
                nbuf[MAX_LINE - 1] = 0;
                char *ntoks[8];
                int nnt = parse_tsv(nbuf, ntoks, 8);
                if (nnt >= 1 && strcmp(ntoks[0], "HUNK") == 0) {
                    emit_delay(hunk_pause, "hunk");
                }
            }
            i++;
            continue;
        }

        if (strcmp(toks[0], "keep") == 0) {
            passthrough(all_lines[i]);
            emit_delay(1, "char");
            i++;
        } else if (strcmp(toks[0], "delete") == 0) {
            int code = (nt >= 4) ? atoi(toks[3]) : 0;
            if (code == 10) {
                /* \n delete */
                passthrough(all_lines[i]);
                emit_delay(delete_delay, "char");
                i++;
            } else {
                /* Non-newline delete: handle pacing */
                if (strcmp(delete_pacing, "char") == 0) {
                    passthrough(all_lines[i]);
                    emit_delay(delete_delay, "char");
                    i++;
                } else if (strcmp(delete_pacing, "instant") == 0) {
                    passthrough(all_lines[i]);
                    emit_delay(1, "char");
                    i++;
                } else {
                    /* AWD (word pacing): collect consecutive deletes on same line */
                    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
                    int start_idx = i;
                    while (i < n_lines) {
                        char buf2[MAX_LINE];
                        strncpy(buf2, all_lines[i], MAX_LINE - 1);
                        buf2[MAX_LINE - 1] = 0;
                        char *t2[8];
                        int n2 = parse_tsv(buf2, t2, 8);
                        int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
                        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
                        if (strcmp(t2[0], "delete") != 0 || c2 == 10 || l2 != start_line)
                            break;
                        i++;
                    }
                    int count = i - start_idx;
                    process_awd(all_lines, start_idx, count, 1);
                }
            }
        } else if (strcmp(toks[0], "insert") == 0) {
            int code = (nt >= 4) ? atoi(toks[3]) : 0;
            if (code == 10) {
                /* \n insert */
                passthrough(all_lines[i]);
                emit_delay(char_delay, "char");
                i++;
            } else {
                passthrough(all_lines[i]);
                emit_delay(char_delay, "char");
                i++;
            }
        } else {
            /* Unknown line — pass through */
            passthrough(all_lines[i]);
            i++;
        }
    }

    if (snapshot_file[0])
        printf("snapshot\t%s\n", snapshot_file);
    printf("\n");  /* blank line at bottom */

    /* Free memory */
    for (int k = 0; k < n_lines; k++) free(all_lines[k]);
    free(all_lines);
    return 0;
}
