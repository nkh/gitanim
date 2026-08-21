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
#include <time.h>

#define MAX_LINE 1048576

/* Timing defaults (ms) */
static int char_delay = 50;      /* normal typing */
static int delete_delay = 40;    /* per-char delete */
static int hunk_pause = 250;     /* between hunks */
static int flash_pause_ms = 400; /* flash mode: pause after highlight */
static int flash_highlight_ms = 300; /* flash mode: highlight duration */
static int awd_start_chars = 3;  /* chars before acceleration */
static int awd_start_ms = 80;    /* slow start delay */
static int awd_min_ms = 15;      /* minimum accelerated delay */
static double awd_accel = 0.85;  /* acceleration factor */
static int word_pause = 150;     /* after a word */

static char delete_pacing[32] = "word";
static char delete_speed[32] = "normal";
static int delete_threshold = 3;
static char insert_pacing[32] = "char";
static char insert_speed[32] = "normal";
static char pacing_mode[32] = "uniform";
static int gaussian_jitter_pct = 20;  /* default ±20% */
static int pause_after_lines = 0;     /* pause after N changed lines (0=off) */
static int pause_after_threshold = 50; /* only pause if >N total lines */
static int pause_after_ms = 500;      /* pause duration */
static int accel_delete = 0;          /* multi-line accel delete (0=off, 1=on) */
static int accel_delete_start_ms = 80; /* initial slow delay */
static int accel_delete_min_ms = 10;   /* minimum accelerated delay */
static double accel_delete_accel = 0.85; /* acceleration factor */
static int block_delete_size = 3;     /* group deletes into blocks of N */
static int pause_before_delete_ms = 200; /* pause before a delete block */
static int pause_after_delete_ms = 200;  /* pause after a delete block */
static char snapshot_file[256] = "";

/* Pacing state for adaptive mode */
static char prev_op_type[8] = "";
static int adaptive_run_count = 0;

/* Output a delay line (base — no pacing applied) */
static void emit_delay(int ms, const char *type) {
    printf("delay\t%d\t%s\n", ms, type);
}

/* Output a line verbatim (pass through) */
static void passthrough(const char *line) {
    printf("%s\n", line);
}

/* Apply pacing mode to a delay value. Returns adjusted delay. */
static int apply_pacing(int delay) {
    if (delay <= 0) return 0;

    if (strcmp(pacing_mode, "review") == 0) {
        return delay * 2;
    }

    if (strcmp(pacing_mode, "gaussian") == 0) {
        int jitter = (delay * gaussian_jitter_pct) / 100;
        if (jitter > 0) {
            int offset = (rand() % (2 * jitter + 1)) - jitter;
            int result = delay + offset;
            if (result < 1) result = 1;
            return result;
        }
        return delay;
    }

    if (strcmp(pacing_mode, "adaptive") == 0) {
        if (adaptive_run_count > 20) return (int)(delay * 0.4);
        if (adaptive_run_count > 10) return (int)(delay * 0.6);
        if (adaptive_run_count > 5) return (int)(delay * 0.8);
        return delay;
    }

    /* uniform (default): no change */
    return delay;
}

/* Track op type for adaptive mode */
static void track_op_type(const char *type) {
    if (strcmp(type, prev_op_type) == 0) {
        adaptive_run_count++;
    } else {
        strncpy(prev_op_type, type, 7);
        prev_op_type[7] = 0;
        adaptive_run_count = 0;
    }
}

/* Emit a delay with pacing applied */
static void emit_paced_delay(int ms, const char *type) {
    int adjusted = apply_pacing(ms);
    emit_delay(adjusted, type);
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--delete-pacing") == 0 && i+1 < argc)
            strncpy(delete_pacing, argv[++i], 31);
        else if (strcmp(argv[i], "--flash-pause-ms") == 0 && i+1 < argc)
            flash_pause_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--flash-highlight-ms") == 0 && i+1 < argc)
            flash_highlight_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--delete-speed") == 0 && i+1 < argc)
            strncpy(delete_speed, argv[++i], 31);
        else if (strcmp(argv[i], "--delete-threshold") == 0 && i+1 < argc)
            delete_threshold = atoi(argv[++i]);
        else if (strcmp(argv[i], "--insert-pacing") == 0 && i+1 < argc)
            strncpy(insert_pacing, argv[++i], 31);
        else if (strcmp(argv[i], "--insert-speed") == 0 && i+1 < argc)
            strncpy(insert_speed, argv[++i], 31);
        else if (strcmp(argv[i], "--pacing") == 0 && i+1 < argc)
            strncpy(pacing_mode, argv[++i], 31);
        else if (strcmp(argv[i], "--gaussian-jitter-pct") == 0 && i+1 < argc)
            gaussian_jitter_pct = atoi(argv[++i]);
        else if (strcmp(argv[i], "--pause-after-lines") == 0 && i+1 < argc)
            pause_after_lines = atoi(argv[++i]);
        else if (strcmp(argv[i], "--pause-after-threshold") == 0 && i+1 < argc)
            pause_after_threshold = atoi(argv[++i]);
        else if (strcmp(argv[i], "--pause-after-ms") == 0 && i+1 < argc)
            pause_after_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--accel-delete") == 0)
            accel_delete = 1;
        else if (strcmp(argv[i], "--accel-delete-start-ms") == 0 && i+1 < argc)
            accel_delete_start_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--accel-delete-min-ms") == 0 && i+1 < argc)
            accel_delete_min_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--accel-delete-accel") == 0 && i+1 < argc)
            accel_delete_accel = atof(argv[++i]);
        else if (strcmp(argv[i], "--block-delete-size") == 0 && i+1 < argc)
            block_delete_size = atoi(argv[++i]);
        else if (strcmp(argv[i], "--pause-before-delete-ms") == 0 && i+1 < argc)
            pause_before_delete_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--pause-after-delete-ms") == 0 && i+1 < argc)
            pause_after_delete_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--snapshot") == 0 && i+1 < argc)
            strncpy(snapshot_file, argv[++i], 255);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-pace [options]\n");
            fprintf(stderr, "  --delete-pacing MODE  char|rapid|word|instant|flash (default: word)\n");
            fprintf(stderr, "                        flash = highlight whole line, pause, delete in one shot\n");
            fprintf(stderr, "  --flash-pause-ms N    flash mode: pause after highlight (default: 400)\n");
            fprintf(stderr, "  --flash-highlight-ms N flash mode: highlight duration (default: 300)\n");
            fprintf(stderr, "  --delete-speed MODE   slow|normal|fast|instant (default: normal)\n");
            fprintf(stderr, "  --insert-pacing MODE  char|word (default: char)\n");
            fprintf(stderr, "  --insert-speed MODE   slow|normal|fast (default: normal)\n");
            fprintf(stderr, "  --pacing MODE         uniform|adaptive|gaussian|review (default: uniform)\n");
            fprintf(stderr, "  --gaussian-jitter-pct N  Jitter percentage for gaussian mode (default: 20)\n");
            fprintf(stderr, "  --pause-after-lines N   Pause after every N changed lines (default: 0=off)\n");
            fprintf(stderr, "  --pause-after-threshold N  Only pause if file has >N lines (default: 50)\n");
            fprintf(stderr, "  --pause-after-ms N      Pause duration in ms (default: 500)\n");
            fprintf(stderr, "  --accel-delete         Enable multi-line accelerated deletion\n");
            fprintf(stderr, "  --accel-delete-start-ms N  Initial slow delay (default: 80)\n");
            fprintf(stderr, "  --accel-delete-min-ms N    Minimum accelerated delay (default: 10)\n");
            fprintf(stderr, "  --accel-delete-accel F     Acceleration factor 0-1 (default: 0.85)\n");
            fprintf(stderr, "  --block-delete-size N   Group deletes into blocks of N (default: 3)\n");
            fprintf(stderr, "  --pause-before-delete-ms N  Pause before delete block (default: 200)\n");
            fprintf(stderr, "  --pause-after-delete-ms N   Pause after delete block (default: 200)\n");
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
    (void)same_line;  /* reserved for future use (accelerated multi-line delete) */
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
            emit_paced_delay(awd_min_ms, "awd_skip");
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
            emit_paced_delay(awd_min_ms, "awd_fast");
        }
        return;
    }

    /* Phase 2: Delete start_chars slowly */
    for (int k = i; k < i + awd_start_chars; k++) {
        passthrough(lines[k]);
        emit_paced_delay(awd_start_ms, "awd_slow");
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
            emit_paced_delay((int)delay, "awd_fast");
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
            emit_paced_delay(awd_min_ms, "awd_skip");
        }
    }
}


int main(int argc, char **argv) {
    srand(time(NULL));
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
    int ops_seen = 0;
    int line_no = 0;
    int changed_lines = 0;  /* count of changed lines for --pause-after-lines */

    while (fgets(buf, sizeof(buf), stdin)) {
        line_no++;
        buf[strcspn(buf, "\n")] = 0;
        if (buf[0] == 0 || buf[0] == '#') {
            /* Skip headers and blank lines from input */
            continue;
        }

        /* Detect v1 format — space-separated HUNK or "op\tkeep..." prefix */
        if (strncmp(buf, "HUNK ", 5) == 0) {
            fprintf(stderr, "diffvim-pace: ERROR: input is v1 format (space-separated HUNK)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  Expected v2 TSV format. Pipe through diffvim-postprocess first.\n");
            exit(1);
        }
        if (strncmp(buf, "op\t", 3) == 0) {
            fprintf(stderr, "diffvim-pace: ERROR: input has 'op\\t<type>...' prefix (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format has the type directly: keep\\t<line>\\t<col>\\t<code>\\n");
            exit(1);
        }
        if (strncmp(buf, "newline_delete", 14) == 0 || strncmp(buf, "newline_insert", 14) == 0) {
            fprintf(stderr, "diffvim-pace: ERROR: input has 'newline_delete'/'newline_insert' op (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format uses delete\\t<line>\\t<col>\\t10\\t\\\\n\n");
            exit(1);
        }
        if (strncmp(buf, "hunk_start\t", 11) == 0 || strncmp(buf, "hunk_end", 8) == 0) {
            fprintf(stderr, "diffvim-pace: ERROR: input has 'hunk_start'/'hunk_end' (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format uses 'HUNK' and 'HUNK_END'\n");
            exit(1);
        }

        if (n_lines >= cap_lines) {
            cap_lines = cap_lines == 0 ? 4096 : cap_lines * 2;
            all_lines = (char **)realloc(all_lines, cap_lines * sizeof(char *));
            if (!all_lines) { fprintf(stderr, "diffvim-pace: out of memory\n"); exit(1); }
        }
        all_lines[n_lines] = strdup(buf);
        n_lines++;
        ops_seen++;
    }

    if (ops_seen == 0) {
        fprintf(stderr, "diffvim-pace: WARNING: no ops read from input\n");
        fprintf(stderr, "  Input was empty or all comments/blank lines.\n");
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
                    emit_paced_delay(hunk_pause, "hunk");
                }
            }
            i++;
            continue;
        }

        track_op_type("keep");
        if (strcmp(toks[0], "keep") == 0) {
            passthrough(all_lines[i]);
            emit_paced_delay(1, "char");
            i++;
        } else if (strcmp(toks[0], "delete") == 0) {
            track_op_type("delete");
            int code = (nt >= 4) ? atoi(toks[3]) : 0;
            if (code == 10) {
                /* \n delete — check for multi-line accel delete */
                if (accel_delete) {
                    /* Collect consecutive \n deletes */
                    int start_idx = i;
                    while (i < n_lines) {
                        char abuf[MAX_LINE];
                        strncpy(abuf, all_lines[i], MAX_LINE - 1);
                        abuf[MAX_LINE - 1] = 0;
                        char *at[8];
                        int an = parse_tsv(abuf, at, 8);
                        int ac = (an >= 4) ? atoi(at[3]) : 0;
                        if (strcmp(at[0], "delete") != 0 || ac != 10) break;
                        i++;
                    }
                    int count = i - start_idx;
                    /* Emit with acceleration: first lines slow, middle fast, last lines slow */
                    double delay = accel_delete_start_ms;
                    for (int k = start_idx; k < start_idx + count; k++) {
                        passthrough(all_lines[k]);
                        int remaining = (start_idx + count) - k;
                        /* Decelerate for last 3 lines */
                        if (remaining <= 3) {
                            double d = accel_delete_start_ms * (4 - remaining) / 3.0;
                            emit_paced_delay((int)d, "accel_delete");
                        } else {
                            emit_paced_delay((int)delay, "accel_delete");
                            delay *= accel_delete_accel;
                            if (delay < accel_delete_min_ms) delay = accel_delete_min_ms;
                        }
                        changed_lines++;
                        if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
                            && n_lines > pause_after_threshold) {
                            emit_paced_delay(pause_after_ms, "pause_after");
                        }
                    }
                } else {
                    /* Normal \n delete */
                    passthrough(all_lines[i]);
                    emit_paced_delay(delete_delay, "char");
                    changed_lines++;
                    if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
                        && n_lines > pause_after_threshold) {
                        emit_paced_delay(pause_after_ms, "pause_after");
                    }
                    i++;
                }
            } else {
                /* Non-newline delete: handle pacing */
                if (strcmp(delete_pacing, "char") == 0) {
                    /* Block delete: group consecutive char deletes, pause before/after */
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
                    /* Insert pause before if count > block_delete_size */
                    if (count > block_delete_size) {
                        emit_paced_delay(pause_before_delete_ms, "block_start");
                    }
                    /* Emit each delete char */
                    for (int k = start_idx; k < start_idx + count; k++) {
                        passthrough(all_lines[k]);
                        emit_paced_delay(delete_delay, "char");
                    }
                    /* Insert pause after if count > block_delete_size */
                    if (count > block_delete_size) {
                        emit_paced_delay(pause_after_delete_ms, "block_end");
                    }
                } else if (strcmp(delete_pacing, "instant") == 0) {
                    passthrough(all_lines[i]);
                    emit_paced_delay(1, "char");
                    i++;
                } else if (strcmp(delete_pacing, "flash") == 0) {
                    /* Flash: highlight the whole line, pause, then
                     * delete all content in one shot (instant).
                     * Collect all consecutive deletes on the same line
                     * (including the \n delete if present), emit a
                     * highlight op for the line range, pause, then
                     * emit all deletes with minimal delay. */
                    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
                    int start_idx = i;
                    int end_col = 1;
                    while (i < n_lines) {
                        char buf2[MAX_LINE];
                        strncpy(buf2, all_lines[i], MAX_LINE - 1);
                        buf2[MAX_LINE - 1] = 0;
                        char *t2[8];
                        int n2 = parse_tsv(buf2, t2, 8);
                        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
                        int col2 = (n2 >= 3) ? atoi(t2[2]) : 1;
                        if (strcmp(t2[0], "delete") != 0 || l2 != start_line)
                            break;
                        if (col2 > end_col) end_col = col2;
                        i++;
                    }
                    int count = i - start_idx;
                    /* Emit a highlight op for the whole line.
                     * Format: highlight\t<sl>\t<sc>\t<el>\t<ec>\t<type>\t<dur>
                     * The animator/decorate will render this as a
                     * colored highlight on the line before deletion. */
                    printf("highlight\t%d\t1\t%d\t%d\tflash\t%d\n",
                           start_line, start_line, end_col + 1,
                           flash_highlight_ms);
                    /* Pause to let the user see the highlight */
                    emit_paced_delay(flash_pause_ms, "flash_pause");
                    /* Delete all content instantly */
                    for (int k = start_idx; k < start_idx + count; k++) {
                        passthrough(all_lines[k]);
                        emit_paced_delay(1, "flash_delete");
                    }
                    /* Brief pause after deletion */
                    emit_paced_delay(flash_pause_ms / 2, "flash_end");
                } else if (strcmp(delete_pacing, "rapid-eol") == 0) {
                    /* Rapid EOL: delete trailing chars rapidly.
                     * Collect consecutive deletes on same line, delete first
                     * char slowly (delete_delay), then accelerate each
                     * subsequent char. */
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
                    if (count <= delete_threshold) {
                        /* Short run — just delete each char */
                        for (int k = start_idx; k < start_idx + count; k++) {
                            passthrough(all_lines[k]);
                            emit_paced_delay(delete_delay, "rapid_eol");
                        }
                    } else {
                        /* Long run — first char slow, then accelerate */
                        double delay = delete_delay;
                        for (int k = start_idx; k < start_idx + count; k++) {
                            passthrough(all_lines[k]);
                            emit_paced_delay((int)delay, "rapid_eol");
                            delay *= awd_accel;
                            if (delay < awd_min_ms) delay = awd_min_ms;
                        }
                    }
                } else if (strcmp(delete_pacing, "rapid-identical") == 0) {
                    /* Rapid identical: delete runs of the same char rapidly.
                     * Detect consecutive deletes of the same char code,
                     * delete first slowly, then accelerate. */
                    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
                    int start_idx = i;
                    int start_code = code;
                    while (i < n_lines) {
                        char buf2[MAX_LINE];
                        strncpy(buf2, all_lines[i], MAX_LINE - 1);
                        buf2[MAX_LINE - 1] = 0;
                        char *t2[8];
                        int n2 = parse_tsv(buf2, t2, 8);
                        int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
                        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
                        if (strcmp(t2[0], "delete") != 0 || c2 != start_code || l2 != start_line)
                            break;
                        i++;
                    }
                    int count = i - start_idx;
                    if (count <= delete_threshold) {
                        for (int k = start_idx; k < start_idx + count; k++) {
                            passthrough(all_lines[k]);
                            emit_paced_delay(delete_delay, "rapid_identical");
                        }
                    } else {
                        double delay = delete_delay;
                        for (int k = start_idx; k < start_idx + count; k++) {
                            passthrough(all_lines[k]);
                            emit_paced_delay((int)delay, "rapid_identical");
                            delay *= awd_accel;
                            if (delay < awd_min_ms) delay = awd_min_ms;
                        }
                    }
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
        } else if (strcmp(toks[0], "insert") == 0
                   || strcmp(toks[0], "overwrite_insert") == 0) {
            track_op_type("insert");
            int code = (nt >= 4) ? atoi(toks[3]) : 0;
            /* Pass through op */
            passthrough(all_lines[i]);
            /* Insert delay based on type */
            if (strcmp(toks[0], "overwrite_insert") == 0) {
                /* Overwrite: minimal delay (preceded by delete at same pos) */
                emit_paced_delay(1, "overwrite");
            } else {
                emit_paced_delay(char_delay, "char");
            }
            if (code == 10) {
                /* \n insert — counts as a changed line */
                changed_lines++;
                if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
                    && n_lines > pause_after_threshold) {
                    emit_paced_delay(pause_after_ms, "pause_after");
                }
            }
            i++;
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
