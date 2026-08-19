/* diffvim-pace — Transform ordered char ops into a timed op stream.
 * C implementation.
 *
 * PACE ONLY HANDLES PACING (delays + batching). Cursor positioning is
 * done by POSTPROCESS, which embeds (line, col) in every op. The
 * animator reads positions directly from ops; pace just adds timing.
 *
 * Input: TSV op stream from diffvim-postprocess:
 *   hunk_start\t<del>\t<ins>
 *   op\tkeep|delete|insert\t<line>\t<col>\t<code>
 *   newline_delete\t<line>
 *   newline_insert\t<line>\t<col>
 *
 * Output: same op stream with delays and batch operations inserted:
 *   delay\t<ms>
 *   batch_delete\t<line>\t<col>\t<count>
 *   batch_insert\t<line>\t<col>\t<code1>\t<code2>\t...
 *
 * Usage: diffvim-pace [--delete-pacing MODE] [--delete-speed MODE]
 *                     [--delete-threshold N] [--insert-pacing MODE]
 *                     [--insert-speed MODE] [--pacing MODE] [--snapshot FILE]
 *
 * Build: cc -O2 -o diffvim-pace pace.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 1048576  // 1MB — was 8192

typedef struct {
    char type[8];  /* keep|delete|insert|newline_delete|newline_insert|hunk_start */
    int code;      /* char code (0 for newline_*) */
    int line;      /* 1-indexed buffer line */
    int col;       /* 1-indexed buffer col */
} Op;
typedef struct { int del, ins; Op *ops; int n_ops; } Hunk;

static char delete_pacing[32] = "word";
static char delete_speed[32] = "normal";
static int delete_threshold = 3;
static char insert_pacing[32] = "char";
static char insert_speed[32] = "normal";
static char pacing_mode[32] = "uniform";
static char snapshot_file[256] = "";

/* Timing defaults */
static int type_delay = 50;
static int delete_delay = 40;
static int hunk_pause = 250;
static int rapid_eol_delay = 80;
static int awd_start_chars = 3;
static int awd_start_ms = 80;
static int awd_min_ms = 15;
static double awd_accel = 0.85;
static int word_pause = 150;
static int move_min_ms = 250;
static int move_max_ms = 1600;
static int move_ms_per_unit = 6;

/* Dynamic arrays — grow as needed */
static Hunk *hunks = NULL;
static int n_hunks = 0;
static int cap_hunks = 0;
static Op *all_ops = NULL;
static int n_all_ops = 0;
static int cap_all_ops = 0;

/* Grow all_ops if needed */
static void ensure_ops_capacity(int needed) {
    if (needed <= cap_all_ops) return;
    int new_cap = cap_all_ops == 0 ? 4096 : cap_all_ops;
    while (new_cap < needed) new_cap *= 2;
    Op *new_ops = (Op *)realloc(all_ops, new_cap * sizeof(Op));
    if (!new_ops) { fprintf(stderr, "diffvim-pace: out of memory (ops %d)\n", new_cap); exit(1); }
    all_ops = new_ops;
    /* Fix up hunk pointers — they point into all_ops, which may have moved */
    int offset = 0;
    for (int h = 0; h < n_hunks; h++) {
        hunks[h].ops = &all_ops[offset];
        offset += hunks[h].n_ops;
    }
    cap_all_ops = new_cap;
}

/* Grow hunks if needed */
static void ensure_hunks_capacity(int needed) {
    if (needed <= cap_hunks) return;
    int new_cap = cap_hunks == 0 ? 64 : cap_hunks;
    while (new_cap < needed) new_cap *= 2;
    Hunk *new_hunks = (Hunk *)realloc(hunks, new_cap * sizeof(Hunk));
    if (!new_hunks) { fprintf(stderr, "diffvim-pace: out of memory (hunks %d)\n", new_cap); exit(1); }
    hunks = new_hunks;
    cap_hunks = new_cap;
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
        else if (strcmp(argv[i], "--pacing") == 0 && i+1 < argc)
            strncpy(pacing_mode, argv[++i], 31);
        else if (strcmp(argv[i], "--snapshot") == 0 && i+1 < argc)
            strncpy(snapshot_file, argv[++i], 255);
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-pace [--delete-pacing MODE] [--delete-speed MODE] [--delete-threshold N] [--insert-pacing MODE] [--insert-speed MODE] [--pacing MODE] [--snapshot FILE]\n");
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
        type_delay /= 2;
        word_pause /= 2;
    } else if (strcmp(insert_speed, "slow") == 0) {
        type_delay *= 2;
        word_pause *= 2;
    }
}

void read_input(void) {
    char line[MAX_LINE];
    int cur_hunk = -1;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#') continue;
        if (line[0] == 0) continue;

        /* TSV format from postprocess: tokens separated by tabs. */
        /* Tokenize on tab. */
        char *toks[16];
        int ntok = 0;
        char *p = line;
        char *tab = strchr(p, '\t');
        while (tab && ntok < 15) {
            *tab = 0;
            toks[ntok++] = p;
            p = tab + 1;
            tab = strchr(p, '\t');
        }
        toks[ntok++] = p;

        if (strcmp(toks[0], "hunk_start") == 0 && ntok >= 3) {
            ensure_hunks_capacity(n_hunks + 1);
            hunks[n_hunks].del = atoi(toks[1]);
            hunks[n_hunks].ins = atoi(toks[2]);
            hunks[n_hunks].ops = &all_ops[n_all_ops];
            hunks[n_hunks].n_ops = 0;
            cur_hunk = n_hunks;
            n_hunks++;
            continue;
        }
        if (strcmp(toks[0], "op") == 0 && ntok >= 5) {
            /* op\t<type>\t<line>\t<col>\t<code> */
            ensure_ops_capacity(n_all_ops + 1);
            strncpy(all_ops[n_all_ops].type, toks[1], 7);
            all_ops[n_all_ops].type[7] = 0;
            all_ops[n_all_ops].line = atoi(toks[2]);
            all_ops[n_all_ops].col = atoi(toks[3]);
            all_ops[n_all_ops].code = atoi(toks[4]);
            n_all_ops++;
            if (cur_hunk >= 0) hunks[cur_hunk].n_ops++;
            continue;
        }
        if (strcmp(toks[0], "newline_delete") == 0 && ntok >= 2) {
            /* newline_delete\t<line> — represent as a delete op with code 10. */
            ensure_ops_capacity(n_all_ops + 1);
            strcpy(all_ops[n_all_ops].type, "delete");
            all_ops[n_all_ops].line = atoi(toks[1]);
            all_ops[n_all_ops].col = 1;
            all_ops[n_all_ops].code = 10;
            n_all_ops++;
            if (cur_hunk >= 0) hunks[cur_hunk].n_ops++;
            continue;
        }
        if (strcmp(toks[0], "newline_insert") == 0 && ntok >= 3) {
            /* newline_insert\t<line>\t<col> — represent as an insert with code 10. */
            ensure_ops_capacity(n_all_ops + 1);
            strcpy(all_ops[n_all_ops].type, "insert");
            all_ops[n_all_ops].line = atoi(toks[1]);
            all_ops[n_all_ops].col = atoi(toks[2]);
            all_ops[n_all_ops].code = 10;
            n_all_ops++;
            if (cur_hunk >= 0) hunks[cur_hunk].n_ops++;
            continue;
        }
        /* ignore hunk_end, done, and any unknown tokens */
    }
}

/* Process AWD (adaptive word delete) for a run of non-newline deletes.
 *
 * IMPORTANT: deletes do NOT advance the column. After deleting a char at
 * col C, the next char (which was at col C+1) is now at col C. So all
 * deletes in this run target the SAME (line, col) = ops[start].(line, col).
 * We use the per-op line/col from the original ops when emitting individual
 * 'op delete' lines, but for batch_delete we always target ops[start].col
 * because that's where the cursor stays.
 */
int process_awd(FILE *w, Op *ops, int start, int count) {
    int end = start + count;
    int i = start;
    int cur_line = ops[start].line;
    int cur_col = ops[start].col;

    /* Phase 1: Skip spaces instantly */
    while (i < end && (ops[i].code == 32 || ops[i].code == 9)) i++;
    if (i > start) {
        fprintf(w, "batch_delete\t%d\t%d\t%d\n", cur_line, cur_col, i - start);
        fprintf(w, "delay\tawd_space\t%d\n", awd_min_ms);
        /* cur_col NOT incremented: deletes don't advance. */
    }

    int remaining = end - i;
    if (remaining <= awd_start_chars) {
        if (remaining > 0) {
            fprintf(w, "batch_delete\t%d\t%d\t%d\n", cur_line, cur_col, remaining);
            fprintf(w, "delay\tawd_word\t%d\n", awd_min_ms);
        }
        return start + count;
    }

    /* Phase 2: Delete start_chars slowly */
    for (int k = i; k < i + awd_start_chars; k++) {
        /* Each individual delete uses the original op's (line, col), which
         * is the same for all ops in this run. */
        fprintf(w, "op\tdelete\t%d\t%d\t%d\n", ops[k].line, ops[k].col, ops[k].code);
        fprintf(w, "delay\tawd_start\t%d\n", awd_start_ms);
        /* cur_col NOT incremented. */
    }
    i += awd_start_chars;

    /* Phase 3: Delete words with acceleration */
    double delay = (double)awd_start_ms;
    while (i < end) {
        int word_len = 0;
        while (i + word_len < end && ops[i + word_len].code != 32 && ops[i + word_len].code != 9)
            word_len++;
        if (word_len > 0) {
            /* Batch deletes all target the same col — the cursor doesn't
             * move between deletes. */
            fprintf(w, "batch_delete\t%d\t%d\t%d\n", cur_line, cur_col, word_len);
            delay *= awd_accel;
            if (delay < (double)awd_min_ms) delay = (double)awd_min_ms;
            fprintf(w, "delay\tawd_word\t%d\n", (int)delay);
            i += word_len;
        }
        /* Skip spaces */
        if (i < end && (ops[i].code == 32 || ops[i].code == 9)) {
            int space_start = i;
            while (i < end && (ops[i].code == 32 || ops[i].code == 9)) i++;
            fprintf(w, "batch_delete\t%d\t%d\t%d\n", cur_line, cur_col, i - space_start);
            fprintf(w, "delay\tawd_space\t%d\n", awd_min_ms);
            /* cur_col NOT incremented. */
        }
    }
    return start + count;
}

int process_delete(FILE *w, Op *ops, int start, int total_ops) {
    /* Count consecutive non-newline deletes ON THE SAME LINE */
    int count = 0;
    int start_line = ops[start].line;
    while (start + count < total_ops &&
           ops[start + count].type[0] == 'd' &&
           ops[start + count].code != 10 &&
           ops[start + count].line == start_line)
        count++;
    if (count == 0) return start;

    if (strcmp(delete_pacing, "char") == 0) {
        fprintf(w, "op\tdelete\t%d\t%d\t%d\n", ops[start].line, ops[start].col, ops[start].code);
        fprintf(w, "delay\tdelete\t%d\n", delete_delay);
        return start + 1;
    }
    if (strcmp(delete_pacing, "instant") == 0) {
        fprintf(w, "batch_delete\t%d\t%d\t%d\n", ops[start].line, ops[start].col, count);
        fprintf(w, "delay\trapid_eol\t%d\n", rapid_eol_delay);
        return start + count;
    }
    if (strcmp(delete_pacing, "rapid-eol") == 0) {
        int next = start + count;
        int at_eol = (next >= total_ops) ||
                     (ops[next].type[0] == 'k' && ops[next].code == 10) ||
                     (ops[next].type[0] == 'd' && ops[next].code == 10);
        if (at_eol && count >= delete_threshold) {
            fprintf(w, "batch_delete\t%d\t%d\t%d\n", ops[start].line, ops[start].col, count);
            fprintf(w, "delay\trapid_eol\t%d\n", rapid_eol_delay);
            return start + count;
        }
        fprintf(w, "op\tdelete\t%d\t%d\t%d\n", ops[start].line, ops[start].col, ops[start].code);
        fprintf(w, "delay\tdelete\t%d\n", delete_delay);
        return start + 1;
    }
    if (strcmp(delete_pacing, "word") == 0) {
        return process_awd(w, ops, start, count);
    }
    /* Default */
    fprintf(w, "op\tdelete\t%d\t%d\t%d\n", ops[start].line, ops[start].col, ops[start].code);
    fprintf(w, "delay\tdelete\t%d\n", delete_delay);
    return start + 1;
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    apply_speeds();
    read_input();

    printf("# timed op stream v2\n");
    printf("# format: TSV, every op carries (line, col) — 1-indexed\n");
    printf("# delays are typed: delay\t<type>\t<ms>\n");
    printf("# generated by: diffvim-pace --delete-pacing %s --delete-speed %s --insert-pacing %s --pacing %s\n",
           delete_pacing, delete_speed, insert_pacing, pacing_mode);
    printf("# delete_threshold %d\n", delete_threshold);

    for (int h = 0; h < n_hunks; h++) {
        Op *ops = hunks[h].ops;
        int n_ops = hunks[h].n_ops;

        printf("hunk_start\t%d\t%d\n", hunks[h].del, hunks[h].ins);

        int i = 0;
        while (i < n_ops) {
            Op *op = &ops[i];

            if (strcmp(op->type, "keep") == 0) {
                printf("op\tkeep\t%d\t%d\t%d\n", op->line, op->col, op->code);
                printf("delay\tkeep\t1\n");
                i++;
            } else if (strcmp(op->type, "delete") == 0) {
                if (op->code == 10) {
                    printf("newline_delete\t%d\n", op->line);
                    printf("delay\tnewline_delete\t%d\n", delete_delay);
                    i++;
                } else {
                    i = process_delete(stdout, ops, i, n_ops);
                }
            } else if (strcmp(op->type, "insert") == 0) {
                if (op->code == 10) {
                    printf("newline_insert\t%d\t%d\n", op->line, op->col);
                    printf("delay\tnewline_insert\t%d\n", type_delay);
                    i++;
                } else if (strcmp(insert_pacing, "word") == 0) {
                    /* Batch short words */
                    int word_len = 0;
                    while (i + word_len < n_ops && ops[i + word_len].type[0] == 'i'
                           && ops[i + word_len].code != 10 && ops[i + word_len].code != 32)
                        word_len++;
                    if (word_len >= 2 && word_len <= 8) {
                        printf("batch_insert\t%d\t%d", ops[i].line, ops[i].col);
                        for (int k = 0; k < word_len; k++)
                            printf("\t%d", ops[i + k].code);
                        printf("\n");
                        printf("delay\tword_insert\t%d\n", word_pause);
                        i += word_len;
                    } else {
                        printf("op\tinsert\t%d\t%d\t%d\n", op->line, op->col, op->code);
                        printf("delay\ttype\t%d\n", type_delay);
                        i++;
                    }
                } else {
                    printf("op\tinsert\t%d\t%d\t%d\n", op->line, op->col, op->code);
                    printf("delay\ttype\t%d\n", type_delay);
                    i++;
                }
            } else {
                i++;
            }
        }

        printf("hunk_end\n");
        if (h < n_hunks - 1)
            printf("delay\thunk_pause\t%d\n", hunk_pause);
    }

    if (snapshot_file[0])
        printf("snapshot\t%s\n", snapshot_file);
    printf("done\n");

    free(all_ops);
    free(hunks);
    return 0;
}
