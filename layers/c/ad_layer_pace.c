/* ad_layer_pace — Insert delays between ops.
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
 * Usage: ad_layer_pace [--delete-pacing MODE] [--delete-speed MODE]
 *                     [--delete-threshold N] [--insert-pacing MODE]
 *                     [--insert-speed MODE] [--pacing MODE]
 *                     [--snapshot FILE]
 *
 * Build: cc -O2 -o ad_layer_pace pace.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "ad_layer_common.h"
#define MAX_LINE AD_LAYER_MAX_LINE


/* Timing defaults (ms) */
static int char_delay = 50;      /* normal typing */
static int delete_delay = 40;    /* per-char delete */
static int hunk_pause = 250;     /* between hunks */
static int flash_pause_ms = 400; /* flash mode: pause after highlight */
static int flash_highlight_ms = 300; /* flash mode: highlight duration */
static int cursor_glide_ms = 0;   /* 0 = off; >0 = glide duration between hunks */
static int cursor_glide_show_intermediate = 1; /* 1 = render intermediate lines */
static int distance_speed = 0;   /* 0 = off; 1 = adaptive */
static int distance_threshold = 10; /* lines: above = fast, below = slow */
static double distance_fast_mult = 3.0; /* multiplier for long distances */
static double distance_slow_mult = 0.5; /* multiplier for short distances */
static int awd_start_chars = 3;  /* chars before acceleration */
static int awd_start_ms = 80;    /* slow start delay */
static int awd_min_ms = 15;      /* minimum accelerated delay */
static double awd_accel = 0.85;  /* acceleration factor */
static int word_pause = 150;     /* after a word */
static int skip_indent_mode = 0;  /* set by indent_skip markers */
static double dist_mult = 1.0;  /* distance-based speed multiplier (applied to delete delays) */

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

/* Loop state (file-scope so handler functions can access/modify it).
 * These were locals in the old monolithic main(); now they are shared
 * across the extracted handler functions. */
static char **all_lines = NULL;   /* input lines (strdup'd) */
static int n_lines = 0;          /* count of input lines */
static int i = 0;                 /* main dispatch loop index */
static int changed_lines = 0;    /* count of changed lines for --pause-after-lines */
static int current_line = 0;     /* last op's line — for glide/distance calc */

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

/* Emit a delay with pacing applied.
 * When skip_indent_mode is active (from ad_layer_skip_indent), all
 * delays are set to 0 so ops are applied instantly. */
static void emit_paced_delay(int ms, const char *type) {
    if (skip_indent_mode) {
        emit_delay(0, type);
        return;
    }
    int adjusted = apply_pacing(ms);
    emit_delay(adjusted, type);
}

/* Emit a delete delay, applying the distance-based speed multiplier.
 * Only delete delays are affected (not inserts, keeps, or hunk pauses). */
static void emit_delete_delay(int ms, const char *type) {
    if (skip_indent_mode) {
        emit_delay(0, type);
        return;
    }
    int adjusted = (int)(ms * dist_mult);
    if (adjusted < 1) adjusted = 1;
    emit_paced_delay(adjusted, type);
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--delete-pacing") == 0 && i+1 < argc)
            strncpy(delete_pacing, argv[++i], 31);
        else if (strcmp(argv[i], "--flash-pause-ms") == 0 && i+1 < argc)
            flash_pause_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--flash-highlight-ms") == 0 && i+1 < argc)
            flash_highlight_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--cursor-glide-ms") == 0 && i+1 < argc)
            cursor_glide_ms = atoi(argv[++i]);
        else if (strcmp(argv[i], "--cursor-glide-show-intermediate") == 0 && i+1 < argc)
            cursor_glide_show_intermediate = atoi(argv[++i]);
        else if (strcmp(argv[i], "--distance-speed") == 0 && i+1 < argc) {
            const char *mode = argv[++i];
            distance_speed = (strcmp(mode, "adaptive") == 0) ? 1 : 0;
        }
        else if (strcmp(argv[i], "--distance-threshold") == 0 && i+1 < argc)
            distance_threshold = atoi(argv[++i]);
        else if (strcmp(argv[i], "--distance-fast-mult") == 0 && i+1 < argc)
            distance_fast_mult = atof(argv[++i]);
        else if (strcmp(argv[i], "--distance-slow-mult") == 0 && i+1 < argc)
            distance_slow_mult = atof(argv[++i]);
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
            fprintf(stderr, "Usage: ad_layer_pace [options]\n");
            fprintf(stderr, "  --delete-pacing MODE  char|rapid|word|instant|flash (default: word)\n");
            fprintf(stderr, "                        flash = highlight whole line, pause, delete in one shot\n");
            fprintf(stderr, "  --flash-pause-ms N    flash mode: pause after highlight (default: 400)\n");
            fprintf(stderr, "  --flash-highlight-ms N flash mode: highlight duration (default: 300)\n");
            fprintf(stderr, "  --cursor-glide-ms N   Glide duration between hunks (0=off, default: 0)\n");
            fprintf(stderr, "  --cursor-glide-show-intermediate 0|1  Show intermediate lines during glide (default: 1)\n");
            fprintf(stderr, "  --distance-speed adaptive|off  Adaptive speed based on hunk distance (default: off)\n");
            fprintf(stderr, "  --distance-threshold N  Lines above which speed increases (default: 10)\n");
            fprintf(stderr, "  --distance-fast-mult F  Speed multiplier for long distances (default: 3.0)\n");
            fprintf(stderr, "  --distance-slow-mult F  Speed multiplier for short distances (default: 0.5)\n");
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


/* AWD: process a run of consecutive non-newline deletes on the same line.
 * Emits each delete op verbatim, with delays between them. */
void process_awd(char *lines[], int start, int count, int same_line) {
    (void)same_line;  /* reserved for future use (accelerated multi-line delete) */
    int i = start;
    int end = start + count;

    /* Phase 1: Skip spaces instantly */
    while (i < end) {
        /* Parse the op to get the code */
        char *toks[AD_LAYER_MAX_TOKENS];
        char buf[MAX_LINE];
        strncpy(buf, lines[i], MAX_LINE - 1);
        buf[MAX_LINE - 1] = 0;
        int nt = ad_layer_parse_tsv(buf, toks, AD_LAYER_MAX_TOKENS);
        int code = (nt >= 4) ? atoi(toks[3]) : 0;

        if (code == AD_LAYER_CHAR_SPACE || code == AD_LAYER_CHAR_TAB) {
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
            char *t2[AD_LAYER_MAX_TOKENS];
            int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
            int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
            if (c2 == AD_LAYER_CHAR_SPACE || c2 == AD_LAYER_CHAR_TAB) break;
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
                char *t3[AD_LAYER_MAX_TOKENS];
                int n3 = ad_layer_parse_tsv(buf3, t3, AD_LAYER_MAX_TOKENS);
                int c3 = (n3 >= 4) ? atoi(t3[3]) : 0;
                if (c3 != AD_LAYER_CHAR_SPACE && c3 != AD_LAYER_CHAR_TAB) break;
                i++;
            }
            for (int k = space_start; k < i; k++)
                passthrough(lines[k]);
            emit_paced_delay(awd_min_ms, "awd_skip");
        }
    }
}


/* ── Delete pacing strategies ──────────────────────────────────────────
 * Each strategy takes the current op line and emits the appropriate
 * delays. They modify the global loop index `i` (advancing it past the
 * ops they consume). */

/* pace_delete_char: Per-character delete pacing — emits each delete op
 * one at a time with the standard delete_delay, adding block-start /
 * block-end pauses around runs longer than block_delete_size. Visual
 * effect: chars disappear one by one (typewriter-like). Used when
 * --delete-pacing=char. Solves: gives the viewer time to see what was
 * removed; without pacing, deletes happen so fast the user can't tell
 * what changed. */
static void pace_delete_char(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
    int start_idx = i;
    while (i < n_lines) {
        char buf2[MAX_LINE];
        strncpy(buf2, all_lines[i], MAX_LINE - 1);
        buf2[MAX_LINE - 1] = 0;
        char *t2[AD_LAYER_MAX_TOKENS];
        int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
        int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
        if (strcmp(t2[0], "delete") != 0 || c2 == AD_LAYER_CHAR_NEWLINE || l2 != start_line)
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
        emit_delete_delay(delete_delay, "char");
    }
    /* Insert pause after if count > block_delete_size */
    if (count > block_delete_size) {
        emit_paced_delay(pause_after_delete_ms, "block_end");
    }
}

/* pace_delete_instant: Delete each char with a 1ms (essentially 0) delay.
 * Visual effect: content vanishes immediately, no per-char animation.
 * Used when --delete-pacing=instant. Solves: for users who find delete
 * animation distracting or want to skim changes quickly; skips the
 * per-char overhead entirely. */
static void pace_delete_instant(char *line) {
    passthrough(line);
    emit_paced_delay(1, "char");
    i++;
}

/* pace_delete_flash: Highlight the entire line being deleted, pause so
 * the viewer sees what's about to go, then delete all chars at once.
 * Visual effect: a brief flash of the doomed line, then it's gone.
 * Used when --delete-pacing=flash. Solves: per-char deletion of a long
 * line is tedious; flash shows the user the whole deletion up front so
 * they understand what was removed without watching it char-by-char. */
static void pace_delete_flash(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
    int start_idx = i;
    int end_col = 1;
    while (i < n_lines) {
        char buf2[MAX_LINE];
        strncpy(buf2, all_lines[i], MAX_LINE - 1);
        buf2[MAX_LINE - 1] = 0;
        char *t2[AD_LAYER_MAX_TOKENS];
        int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
        int col2 = (n2 >= 3) ? atoi(t2[2]) : 1;
        if (strcmp(t2[0], "delete") != 0 || l2 != start_line)
            break;
        if (col2 > end_col) end_col = col2;
        i++;
    }
    int count = i - start_idx;
    /* Emit a highlight op for the whole line.
     * Format: highlight\t<sl>\t<sc>\t<el>\t<ec>\t<type>\t<dur> */
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
}

/* pace_delete_rapid_eol: Delete trailing chars quickly — first char slow
 * (so the viewer sees the deletion start), then each subsequent char
 * accelerates (delay *= awd_accel). Visual effect: chars vanish in a
 * quick accelerating sweep toward end-of-line. Used when
 * --delete-pacing=rapid-eol. Solves: long EOL deletions take forever
 * at uniform speed; acceleration keeps the animation snappy while
 * still signaling "something is being deleted here". */
static void pace_delete_rapid_eol(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
    int start_idx = i;
    while (i < n_lines) {
        char buf2[MAX_LINE];
        strncpy(buf2, all_lines[i], MAX_LINE - 1);
        buf2[MAX_LINE - 1] = 0;
        char *t2[AD_LAYER_MAX_TOKENS];
        int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
        int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
        if (strcmp(t2[0], "delete") != 0 || c2 == AD_LAYER_CHAR_NEWLINE || l2 != start_line)
            break;
        i++;
    }
    int count = i - start_idx;
    if (count <= delete_threshold) {
        /* Short run — just delete each char */
        for (int k = start_idx; k < start_idx + count; k++) {
            passthrough(all_lines[k]);
            emit_delete_delay(delete_delay, "rapid_eol");
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
}

/* pace_delete_rapid_identical: Detect runs of the same char code being
 * deleted (e.g. "    " or "=====") and delete them with acceleration —
 * first slow, then faster. Visual effect: identical-char runs vanish
 * in a quick streak. Used when --delete-pacing=rapid-identical.
 * Solves: deleting 50 identical chars at uniform speed is boring and
 * visually noisy; grouping + acceleration makes it feel like a quick
 * sweep while still showing the user the start of the run. */
static void pace_delete_rapid_identical(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
    int start_code = (nt >= 4) ? atoi(toks[3]) : 0;
    int start_idx = i;
    while (i < n_lines) {
        char buf2[MAX_LINE];
        strncpy(buf2, all_lines[i], MAX_LINE - 1);
        buf2[MAX_LINE - 1] = 0;
        char *t2[AD_LAYER_MAX_TOKENS];
        int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
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
            emit_delete_delay(delete_delay, "rapid_identical");
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
}

/* pace_delete_awd: Adaptive Word Delete — collect consecutive non-newline
 * deletes on a line and delegate to process_awd(), which skips spaces
 * instantly, types start_chars slowly, then accelerates per word
 * batch. Visual effect: words vanish as units, accelerating across the
 * line. Used when --delete-pacing=awd (or "word", the default fallback).
 * Solves: balance readability (viewer sees words being removed) with
 * speed (long deletes don't take forever like per-char would). */
static void pace_delete_awd(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
    int start_idx = i;
    while (i < n_lines) {
        char buf2[MAX_LINE];
        strncpy(buf2, all_lines[i], MAX_LINE - 1);
        buf2[MAX_LINE - 1] = 0;
        char *t2[AD_LAYER_MAX_TOKENS];
        int n2 = ad_layer_parse_tsv(buf2, t2, AD_LAYER_MAX_TOKENS);
        int c2 = (n2 >= 4) ? atoi(t2[3]) : 0;
        int l2 = (n2 >= 2) ? atoi(t2[1]) : 0;
        if (strcmp(t2[0], "delete") != 0 || c2 == AD_LAYER_CHAR_NEWLINE || l2 != start_line)
            break;
        i++;
    }
    int count = i - start_idx;
    process_awd(all_lines, start_idx, count, 1);
}


/* ── Op handlers ───────────────────────────────────────────────────────
 * Each handler processes one op type, modifying the global loop index `i`
 * and printing to stdout exactly as the old inline code did. */

/* HUNK header: emit glide ops if enabled, apply distance-based speed
 * multiplier, then passthrough the HUNK line. */
static void handle_hunk(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int target_line = (nt >= 2) ? atoi(toks[1]) : 1;
    int distance = abs(target_line - current_line);

    /* Distance-based speed: adjust the multiplier for this hunk */
    if (distance_speed) {
        if (distance > distance_threshold) {
            dist_mult = distance_fast_mult;
        } else {
            dist_mult = distance_slow_mult;
        }
    }

    /* Cursor glide: emit glide ops between hunks */
    if (cursor_glide_ms > 0 && distance > 1 && i > 0) {
        printf("glide\t%d\t%d\t%d\t%d\n",
               current_line, target_line,
               cursor_glide_ms, cursor_glide_show_intermediate);
        emit_paced_delay(cursor_glide_ms, "glide");
    }

    passthrough(line);
    current_line = target_line;
    i++;
}

/* HUNK_END marker: passthrough, emit hunk pause if another HUNK follows. */
static void handle_hunk_end(char *line) {
    passthrough(line);
    /* Insert hunk pause if not the last hunk */
    if (i + 1 < n_lines) {
        char nbuf[MAX_LINE];
        strncpy(nbuf, all_lines[i + 1], MAX_LINE - 1);
        nbuf[MAX_LINE - 1] = 0;
        char *ntoks[AD_LAYER_MAX_TOKENS];
        int nnt = ad_layer_parse_tsv(nbuf, ntoks, AD_LAYER_MAX_TOKENS);
        if (nnt >= 1 && strcmp(ntoks[0], "HUNK") == 0) {
            emit_paced_delay(hunk_pause, "hunk");
        }
    }
    i++;
}

/* Helper: process an indent_skip marker from ad_layer_skip_indent.
 *   delay with line==-1, col==0 → start skip mode (0ms delays)
 *   delay with line==-1, col==1 → end skip mode, emit pause
 * Called from handle_delay when the early-return indent_skip check fires. */
static void handle_indent_skip_marker(char *toks[], int nt) {
    int col = (nt >= 3) ? atoi(toks[2]) : 0;
    if (col == 0) {
        /* Start skip mode */
        skip_indent_mode = 1;
    } else {
        /* End skip mode + emit pause */
        skip_indent_mode = 0;
        int pause_ms = (nt >= 4) ? atoi(toks[3]) : AD_LAYER_DEFAULT_SKIP_PAUSE_MS;
        emit_paced_delay(pause_ms, "indent_skip_end");
    }
}

/* delay op: passthrough (delay lines in input are forwarded verbatim).
 * Also handles indent_skip markers from ad_layer_skip_indent:
 *   delay with line==-1, col==0 → start skip mode (0ms delays)
 *   delay with line==-1, col==1 → end skip mode, emit pause */
static void handle_delay(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);

    /* Check for indent_skip markers first (line field == -1, early return). */
    if (nt >= 2 && atoi(toks[1]) == -1) {
        handle_indent_skip_marker(toks, nt);
        i++;
        return;
    }

    /* Normal delay — passthrough. */
    passthrough(line);
    i++;
}

/* keep op: passthrough + minimal char delay, track current line. */
static void handle_keep(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    passthrough(line);
    emit_paced_delay(1, "char");
    /* Track current line for glide/distance calculations */
    if (nt >= 2) current_line = atoi(toks[1]);
    i++;
}

/* delete \n op: either multi-line accel delete or normal \n delete. */
static void handle_delete_newline(char *line) {
    if (accel_delete) {
        /* Collect consecutive \n deletes */
        int start_idx = i;
        while (i < n_lines) {
            char abuf[MAX_LINE];
            strncpy(abuf, all_lines[i], MAX_LINE - 1);
            abuf[MAX_LINE - 1] = 0;
            char *at[AD_LAYER_MAX_TOKENS];
            int an = ad_layer_parse_tsv(abuf, at, AD_LAYER_MAX_TOKENS);
            int ac = (an >= 4) ? atoi(at[3]) : 0;
            if (strcmp(at[0], "delete") != 0 || ac != AD_LAYER_CHAR_NEWLINE) break;
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
        passthrough(line);
        emit_delete_delay(delete_delay, "char");
        changed_lines++;
        if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
            && n_lines > pause_after_threshold) {
            emit_paced_delay(pause_after_ms, "pause_after");
        }
        i++;
    }
}

/* delete char op (non-newline): dispatch to the selected pacing strategy. */
static void handle_delete_char(char *line) {
    if (strcmp(delete_pacing, "char") == 0) {
        pace_delete_char(line);
    } else if (strcmp(delete_pacing, "instant") == 0) {
        pace_delete_instant(line);
    } else if (strcmp(delete_pacing, "flash") == 0) {
        pace_delete_flash(line);
    } else if (strcmp(delete_pacing, "rapid-eol") == 0) {
        pace_delete_rapid_eol(line);
    } else if (strcmp(delete_pacing, "rapid-identical") == 0) {
        pace_delete_rapid_identical(line);
    } else {
        /* AWD (word pacing) is the default / fallback */
        pace_delete_awd(line);
    }
}

/* insert / overwrite_insert op: handle overwrite, word pacing, or char
 * pacing. In word-pacing mode the function returns early (the main loop
 * does not perform the trailing i++ / changed_lines logic in that case). */
static void handle_insert(char *line) {
    char *toks[AD_LAYER_MAX_TOKENS];
    char tbuf[MAX_LINE];
    strncpy(tbuf, line, MAX_LINE - 1);
    tbuf[MAX_LINE - 1] = 0;
    int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);
    int code = (nt >= 4) ? atoi(toks[3]) : 0;

    /* Insert delay based on type and insert-pacing mode */
    if (strcmp(toks[0], "overwrite_insert") == 0) {
        /* Overwrite: minimal delay (preceded by delete at same pos) */
        passthrough(line);
        emit_paced_delay(1, "overwrite");
    } else if (strcmp(insert_pacing, "word") == 0) {
        /* Word pacing: type words instantly, pause after each word.
         * A "word" is a run of non-whitespace chars. When we hit
         * a whitespace char or end of inserts, pause. */
        /* Count \n inserts for changed_lines before the word-pacing
         * return skips the check below. */
        if (code == AD_LAYER_CHAR_NEWLINE) {
            changed_lines++;
            if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
                && n_lines > pause_after_threshold) {
                emit_paced_delay(pause_after_ms, "pause_after");
            }
        }
        /* Collect consecutive insert chars on same line */
        int start_line = (nt >= 2) ? atoi(toks[1]) : 0;
        int start_idx = i;
        while (i < n_lines) {
            char ibuf2[MAX_LINE];
            strncpy(ibuf2, all_lines[i], MAX_LINE - 1);
            ibuf2[MAX_LINE - 1] = 0;
            char *it2[AD_LAYER_MAX_TOKENS];
            int in2 = ad_layer_parse_tsv(ibuf2, it2, AD_LAYER_MAX_TOKENS);
            int ic2 = (in2 >= 4) ? atoi(it2[3]) : 0;
            int il2 = (in2 >= 2) ? atoi(it2[1]) : 0;
            if (strcmp(it2[0], "insert") != 0 || ic2 == AD_LAYER_CHAR_NEWLINE || il2 != start_line)
                break;
            i++;
        }
        int count = i - start_idx;
        /* Emit all inserts with minimal delay, then pause after */
        for (int k = start_idx; k < start_idx + count; k++) {
            passthrough(all_lines[k]);
            emit_paced_delay(char_delay, "char");
        }
        /* Check if the last char was whitespace — if so, pause */
        if (count > 0) {
            char lastbuf[MAX_LINE];
            strncpy(lastbuf, all_lines[start_idx + count - 1], MAX_LINE - 1);
            lastbuf[MAX_LINE - 1] = 0;
            char *lt2[AD_LAYER_MAX_TOKENS];
            int ln2 = ad_layer_parse_tsv(lastbuf, lt2, AD_LAYER_MAX_TOKENS);
            int last_code = (ln2 >= 4) ? atoi(lt2[3]) : 0;
            if (last_code == AD_LAYER_CHAR_SPACE || last_code == AD_LAYER_CHAR_TAB) {
                /* Whitespace — pause after word */
                emit_paced_delay(word_pause, "word");
            }
        }
        /* Already advanced i, skip the i++ at the end */
        if (nt >= 2) current_line = atoi(toks[1]);
        return;
    } else {
        /* char pacing (default) */
        passthrough(line);
        emit_paced_delay(char_delay, "char");
    }

    if (code == AD_LAYER_CHAR_NEWLINE) {
        /* \n insert — counts as a changed line */
        changed_lines++;
        if (pause_after_lines > 0 && changed_lines % pause_after_lines == 0
            && n_lines > pause_after_threshold) {
            emit_paced_delay(pause_after_ms, "pause_after");
        }
    }
    /* Track current line for glide/distance calculations */
    if (nt >= 2) current_line = atoi(toks[1]);
    i++;
}

/* Catch-all passthrough for glide, snapshot, highlight, dim, fold, sign,
 * marker, and any other unrecognized op. */
static void handle_passthrough_op(char *line) {
    passthrough(line);
    i++;
}


int main(int argc, char **argv) {
    srand(time(NULL));
    parse_args(argc, argv);
    apply_speeds();

    printf("# diffvim timed ops v2\n");
    printf("# delete_pacing %s\n", delete_pacing);
    printf("# insert_pacing %s\n", insert_pacing);

    /* Read all lines first (we need lookahead for AWD) */
    int cap_lines = 0;
    char buf[MAX_LINE];
    int ops_seen = 0;
    int line_no = 0;

    while (fgets(buf, sizeof(buf), stdin)) {
        line_no++;
        buf[strcspn(buf, "\n")] = 0;
        if (buf[0] == 0 || buf[0] == '#') {
            /* Skip headers and blank lines from input */
            continue;
        }

        /* Detect v1 format — space-separated HUNK or "op\tkeep..." prefix */
        if (strncmp(buf, "HUNK ", 5) == 0) {
            fprintf(stderr, "ad_layer_pace: ERROR: input is v1 format (space-separated HUNK)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  Expected v2 TSV format. Pipe through ad_postprocess first.\n");
            exit(1);
        }
        if (strncmp(buf, "op\t", 3) == 0) {
            fprintf(stderr, "ad_layer_pace: ERROR: input has 'op\\t<type>...' prefix (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format has the type directly: keep\\t<line>\\t<col>\\t<code>\\n");
            exit(1);
        }
        if (strncmp(buf, "newline_delete", 14) == 0 || strncmp(buf, "newline_insert", 14) == 0) {
            fprintf(stderr, "ad_layer_pace: ERROR: input has 'newline_delete'/'newline_insert' op (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format uses delete\\t<line>\\t<col>\\t10\\t\\\\n\n");
            exit(1);
        }
        if (strncmp(buf, "hunk_start\t", 11) == 0 || strncmp(buf, "hunk_end", 8) == 0) {
            fprintf(stderr, "ad_layer_pace: ERROR: input has 'hunk_start'/'hunk_end' (v1 format)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, buf);
            fprintf(stderr, "  v2 format uses 'HUNK' and 'HUNK_END'\n");
            exit(1);
        }

        if (n_lines >= cap_lines) {
            cap_lines = cap_lines == 0 ? AD_LAYER_INIT_CAPACITY : cap_lines * 2;
            { char **_tmp = realloc(all_lines, cap_lines * sizeof(char *)); if (!_tmp) { fprintf(stderr, "out of memory\n"); exit(1); } all_lines = _tmp; }
            if (!all_lines) { fprintf(stderr, "ad_layer_pace: out of memory\n"); exit(1); }
        }
        all_lines[n_lines] = strdup(buf);
        n_lines++;
        ops_seen++;
    }

    if (ops_seen == 0) {
        fprintf(stderr, "ad_layer_pace: WARNING: no ops read from input\n");
        fprintf(stderr, "  Input was empty or all comments/blank lines.\n");
    }

    i = 0;
    current_line = 0;
    changed_lines = 0;

    /* Dispatch loop: parse the op type and delegate to the matching handler.
     * HUNK/HUNK_END short-circuit with `continue` (they don't track op type).
     * For all other ops, track_op_type("keep") is called first, then
     * overridden by "delete"/"insert" as appropriate. */
    while (i < n_lines) {
        char *toks[AD_LAYER_MAX_TOKENS];
        char tbuf[MAX_LINE];
        strncpy(tbuf, all_lines[i], MAX_LINE - 1);
        tbuf[MAX_LINE - 1] = 0;
        int nt = ad_layer_parse_tsv(tbuf, toks, AD_LAYER_MAX_TOKENS);

        if (strcmp(toks[0], "HUNK") == 0) {
            handle_hunk(all_lines[i]);
            continue;
        }
        if (strcmp(toks[0], "HUNK_END") == 0) {
            handle_hunk_end(all_lines[i]);
            continue;
        }

        track_op_type("keep");

        if (strcmp(toks[0], "keep") == 0) {
            handle_keep(all_lines[i]);
        } else if (strcmp(toks[0], "delete") == 0) {
            track_op_type("delete");
            int code = (nt >= 4) ? atoi(toks[3]) : 0;
            if (code == AD_LAYER_CHAR_NEWLINE) {
                handle_delete_newline(all_lines[i]);
            } else {
                handle_delete_char(all_lines[i]);
            }
        } else if (strcmp(toks[0], "insert") == 0
                   || strcmp(toks[0], "overwrite_insert") == 0) {
            track_op_type("insert");
            handle_insert(all_lines[i]);
        } else if (strcmp(toks[0], "delay") == 0) {
            handle_delay(all_lines[i]);
        } else {
            /* Unknown line — pass through (glide, snapshot, highlight,
             * dim, fold, sign, marker, etc.) */
            handle_passthrough_op(all_lines[i]);
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
