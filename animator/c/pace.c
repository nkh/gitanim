/* diffvim-pace — Transform ordered char ops into a timed op stream.
 * C implementation — produces identical output to Perl and Go versions.
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

#define MAX_OPS 200000
#define MAX_LINE 8192

typedef struct { char type[8]; int code; } Op;
typedef struct { int target, del, ins, end_ins, end_del; Op *ops; int n_ops; int newline_inserts, newline_deletes; } Hunk;

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

static Hunk *hunks = NULL;
static int n_hunks = 0;
static Op *all_ops = NULL;
static int n_all_ops = 0;

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
    all_ops = malloc(MAX_OPS * sizeof(Op));
    hunks = malloc(1000 * sizeof(Hunk));
    char line[MAX_LINE];
    int cur_hunk = -1;

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#') continue;
        if (strncmp(line, "HUNK", 4) == 0) {
            int t, d, i, ei, ed;
            if (sscanf(line, "HUNK %d %d %d %d %d", &t, &d, &i, &ei, &ed) == 5) {
                hunks[n_hunks].target = t;
                hunks[n_hunks].del = d;
                hunks[n_hunks].ins = i;
                hunks[n_hunks].end_ins = ei;
                hunks[n_hunks].end_del = ed;
                hunks[n_hunks].ops = &all_ops[n_all_ops];
                hunks[n_hunks].n_ops = 0;
                hunks[n_hunks].newline_inserts = 0;
                hunks[n_hunks].newline_deletes = 0;
                cur_hunk = n_hunks;
                n_hunks++;
            }
            continue;
        }
        char type[8]; int code;
        if (sscanf(line, "%7s %d", type, &code) == 2 &&
            (strcmp(type, "keep") == 0 || strcmp(type, "delete") == 0 || strcmp(type, "insert") == 0)) {
            if (n_all_ops < MAX_OPS) {
                strcpy(all_ops[n_all_ops].type, type);
                all_ops[n_all_ops].code = code;
                n_all_ops++;
                if (cur_hunk >= 0) {
                    hunks[cur_hunk].n_ops++;
                    if (code == 10) {
                        if (strcmp(type, "insert") == 0) hunks[cur_hunk].newline_inserts++;
                        else if (strcmp(type, "delete") == 0) hunks[cur_hunk].newline_deletes++;
                    }
                }
            }
        }
    }
}

/* Process AWD (adaptive word delete) for a run of non-newline deletes */
int process_awd(FILE *w, Op *ops, int start, int count) {
    int end = start + count;
    int i = start;

    /* Phase 1: Skip spaces instantly */
    while (i < end && (ops[i].code == 32 || ops[i].code == 9)) i++;
    if (i > start) {
        fprintf(w, "batch_delete %d\n", i - start);
        fprintf(w, "delay %d\n", awd_min_ms);
    }

    int remaining = end - i;
    if (remaining <= awd_start_chars) {
        if (remaining > 0) {
            fprintf(w, "batch_delete %d\n", remaining);
            fprintf(w, "delay %d\n", awd_min_ms);
        }
        return start + count;
    }

    /* Phase 2: Delete start_chars slowly */
    for (int k = i; k < i + awd_start_chars; k++) {
        fprintf(w, "op delete %d\n", ops[k].code);
        fprintf(w, "delay %d\n", awd_start_ms);
    }
    i += awd_start_chars;

    /* Phase 3: Delete words with acceleration */
    double delay = (double)awd_start_ms;
    while (i < end) {
        int word_len = 0;
        while (i + word_len < end && ops[i + word_len].code != 32 && ops[i + word_len].code != 9)
            word_len++;
        if (word_len > 0) {
            fprintf(w, "batch_delete %d\n", word_len);
            delay *= awd_accel;
            if (delay < (double)awd_min_ms) delay = (double)awd_min_ms;
            fprintf(w, "delay %d\n", (int)delay);
            i += word_len;
        }
        /* Skip spaces */
        if (i < end && (ops[i].code == 32 || ops[i].code == 9)) {
            int space_start = i;
            while (i < end && (ops[i].code == 32 || ops[i].code == 9)) i++;
            fprintf(w, "batch_delete %d\n", i - space_start);
            fprintf(w, "delay %d\n", awd_min_ms);
        }
    }
    return start + count;
}

int process_delete(FILE *w, Op *ops, int start, int total_ops) {
    /* Count consecutive non-newline deletes */
    int count = 0;
    while (start + count < total_ops && ops[start + count].type[0] == 'd' && ops[start + count].code != 10)
        count++;
    if (count == 0) return start;

    if (strcmp(delete_pacing, "char") == 0) {
        fprintf(w, "op delete %d\n", ops[start].code);
        fprintf(w, "delay %d\n", delete_delay);
        return start + 1;
    }
    if (strcmp(delete_pacing, "instant") == 0) {
        fprintf(w, "batch_delete %d\n", count);
        fprintf(w, "delay %d\n", rapid_eol_delay);
        return start + count;
    }
    if (strcmp(delete_pacing, "rapid-eol") == 0) {
        int next = start + count;
        int at_eol = (next >= total_ops) ||
                     (ops[next].type[0] == 'k' && ops[next].code == 10) ||
                     (ops[next].type[0] == 'd' && ops[next].code == 10);
        if (at_eol && count >= delete_threshold) {
            fprintf(w, "batch_delete %d\n", count);
            fprintf(w, "delay %d\n", rapid_eol_delay);
            return start + count;
        }
        fprintf(w, "op delete %d\n", ops[start].code);
        fprintf(w, "delay %d\n", delete_delay);
        return start + 1;
    }
    if (strcmp(delete_pacing, "word") == 0) {
        return process_awd(w, ops, start, count);
    }
    /* Default */
    fprintf(w, "op delete %d\n", ops[start].code);
    fprintf(w, "delay %d\n", delete_delay);
    return start + 1;
}

int main(int argc, char **argv) {
    parse_args(argc, argv);
    apply_speeds();
    read_input();

    printf("# timed op stream v1\n");
    printf("# generated by: diffvim-pace --delete-pacing %s --delete-speed %s --insert-pacing %s --pacing %s\n",
           delete_pacing, delete_speed, insert_pacing, pacing_mode);
    printf("# delete_threshold %d\n", delete_threshold);

    int current_line = 1;
    int line_offset = 0;  /* Cumulative (inserts - deletes) from previous hunks */

    for (int h = 0; h < n_hunks; h++) {
        int target = hunks[h].target;
        Op *ops = hunks[h].ops;
        int n_ops = hunks[h].n_ops;

        /* Apply cumulative line offset so glide targets the CURRENT buffer
         * position, not the original line number in the old file. */
        int actual_target = target + line_offset;

        /* Compute glide */
        int dl = abs(actual_target - current_line);
        int distance = dl * 80;
        int glide_ms = move_min_ms;
        if (distance * move_ms_per_unit > move_min_ms) {
            glide_ms = distance * move_ms_per_unit;
            if (glide_ms > move_max_ms) glide_ms = move_max_ms;
        }

        printf("hunk_start %d %d %d\n", actual_target, hunks[h].del, hunks[h].ins);
        printf("glide %d:1\n", actual_target);
        printf("delay %d\n", glide_ms);

        current_line = actual_target;

        int i = 0;
        while (i < n_ops) {
            Op *op = &ops[i];

            if (strcmp(op->type, "keep") == 0) {
                if (op->code == 10) { current_line++; }
                printf("op keep %d\n", op->code);
                printf("delay 1\n");
                i++;
            } else if (strcmp(op->type, "delete") == 0) {
                if (op->code == 10) {
                    printf("newline_delete\n");
                    printf("delay %d\n", delete_delay);
                    current_line++;
                    i++;
                } else {
                    i = process_delete(stdout, ops, i, n_ops);
                }
            } else if (strcmp(op->type, "insert") == 0) {
                if (op->code == 10) {
                    printf("newline_insert\n");
                    printf("delay %d\n", type_delay);
                    current_line++;
                    i++;
                } else if (strcmp(insert_pacing, "word") == 0) {
                    /* Batch short words */
                    int word_len = 0;
                    while (i + word_len < n_ops && ops[i + word_len].type[0] == 'i'
                           && ops[i + word_len].code != 10 && ops[i + word_len].code != 32)
                        word_len++;
                    if (word_len >= 2 && word_len <= 8) {
                        printf("batch_insert");
                        for (int k = 0; k < word_len; k++)
                            printf(" %d", ops[i + k].code);
                        printf("\n");
                        printf("delay %d\n", word_pause);
                        i += word_len;
                    } else {
                        printf("op insert %d\n", op->code);
                        printf("delay %d\n", type_delay);
                        i++;
                    }
                } else {
                    printf("op insert %d\n", op->code);
                    printf("delay %d\n", type_delay);
                    i++;
                }
            } else {
                i++;
            }
        }

        printf("hunk_end\n");
        if (h < n_hunks - 1)
            printf("delay %d\n", hunk_pause);

        /* Update cumulative line offset */
        line_offset += hunks[h].newline_inserts - hunks[h].newline_deletes;
    }

    if (snapshot_file[0])
        printf("snapshot %s\n", snapshot_file);
    printf("done\n");

    free(all_ops);
    free(hunks);
    return 0;
}
