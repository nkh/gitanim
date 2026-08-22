#define MAX_LINE_LEN 1048576  // 1MB — was 8192
/* diffvim-animator — Standalone terminal animation application.
 * C implementation.
 *
 * Reads a TSV timed op stream and animates the transformation.
 * Every op carries its own (line, col); the animator moves the cursor
 * to that position before applying the op. This makes the animator
 * scroll-safe — even if the user scrolls mid-animation, each op is
 * applied at the right place.
 *
 * Usage: diffvim-animator [options] <oldfile>
 * Build: cc -O2 -o diffvim-animator animator.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <time.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/ioctl.h>

/* --- Forward declarations --- */
void sleep_ms(int ms);
void disable_raw_mode(void);

/* Ctrl+C handler: restore terminal before exiting */
static void cleanup_handler(int sig) {
    (void)sig;  /* signal number not used — handler is registered for both SIGINT/SIGTERM */
    disable_raw_mode();
    printf("\033[?25h\033[0m\033[2J\033[H");
    fflush(stdout);
    exit(1);
}



/* Dynamic arrays — grow as needed */
static char **lines = NULL;
static int n_lines = 0;
static int cap_lines = 0;
static int cursor_l = 0; /* 0-indexed — internal (used for buffer ops) */
static int cursor_c = 0; /* 0-indexed — internal */
static int disp_l = 0;  /* 0-indexed — displayed cursor (what render() shows) */
static int disp_c = 0;  /* 0-indexed — displayed cursor */

static int no_display = 0;
static int show_line_numbers = 0;
static int show_progress = 0;
static int verbose = 0;
static int dry_run = 0;
static int seek_op = 0;  /* #70: start at this op index */
static int show_diff_stat = 0;  /* #76: diff stat overlay */
static int bell_on_error = 0;  /* #40: terminal bell on error */
static int diff_highlight = 0;  /* #24: green/red highlighting */
static char scroll_mode[8] = "zz";  /* zz|zt|zb|none */
static double speed_mult = 1.0;
static char output_file[256] = "";
static char snapshot_file_path[256] = "";
static char old_file_path[256] = "";
static char colormap_old_path[256] = "";
static char colormap_new_path[256] = "";

/* --- Keyboard input handling ---
 *
 * The animator runs in a terminal and accepts keystrokes during the
 * animation. Since stdin is consumed by the timed op stream (piped
 * from pace), we read keystrokes from /dev/tty directly.
 *
 * Supported keys:
 *   q / Esc / Ctrl-C   stop animation (leave buffer in current state)
 *   Space / p          pause / resume
 *   n                  skip to next hunk (apply rest of current hunk instantly)
 *   +                  speed up (x1.5)
 *   -                  slow down (x0.67)
 *   =                  reset speed to 1.0
 *   ? / h              show help overlay
 */
static int paused = 0;
static int user_quit = 0;
static int skip_to_next_hunk = 0;
static int in_hunk = 0;
static int tty_fd = -1;
static struct termios orig_termios;
static int termios_saved = 0;

/* Open /dev/tty for keyboard input. Returns 0 on success.
 * If no TTY is available (e.g. piped output), keyboard input is disabled. */
void enable_raw_mode(void) {
    if (no_display) return;
    tty_fd = open("/dev/tty", O_RDWR | O_NONBLOCK);
    if (tty_fd < 0) return;
    tcgetattr(tty_fd, &orig_termios);
    termios_saved = 1;
    struct termios raw = orig_termios;
    /* Disable echo and canonical mode */
    raw.c_lflag &= ~(ECHO | ICANON);
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(tty_fd, TCSANOW, &raw);
}

/* Restore terminal to its original state */
void disable_raw_mode(void) {
    if (!termios_saved) return;
    tcsetattr(tty_fd, TCSANOW, &orig_termios);
    close(tty_fd);
    tty_fd = -1;
    termios_saved = 0;
}

/* Poll for a keystroke. Returns 0 if no key, or the char read. */
int poll_key(void) {
    if (tty_fd < 0) return 0;
    char c = 0;
    int n = read(tty_fd, &c, 1);
    if (n <= 0) return 0;
    return (int)c;
}

/* Process a keystroke. Sets global state for the main loop. */
void handle_key(int c) {
    switch (c) {
        case 'q':
        case 'Q':
        case 0x1B:  /* Esc */
        case 0x03:  /* Ctrl-C */
            user_quit = 1;
            break;
        case ' ':
        case 'p':
            paused = !paused;
            break;
        case 'n':
        case 'N':
            skip_to_next_hunk = 1;
            break;
        case '+':
            speed_mult *= 1.5;
            break;
        case '-':
        case '_':
            speed_mult /= 1.5;
            break;
        case '=':
            speed_mult = 1.0;
            break;
        case '?':
        case 'h':
        case 'H':
            /* Show help overlay on stderr */
            fprintf(stderr, "\n--- diffvim-animator keys ---\n");
            fprintf(stderr, "  q/Esc/Ctrl-C  stop animation\n");
            fprintf(stderr, "  Space/p       pause / resume\n");
            fprintf(stderr, "  n             skip to next hunk\n");
            fprintf(stderr, "  +             speed up (x1.5)\n");
            fprintf(stderr, "  -             slow down (x0.67)\n");
            fprintf(stderr, "  =             reset speed to 1.0\n");
            fprintf(stderr, "  ?/h           this help\n");
            break;
    }
}

/* Sleep with ms granularity, polling for keystrokes every 10ms.
 * Returns early if the user pressed a key. */
void sleep_with_kb(int ms) {
    if (ms <= 0) return;
    int elapsed = 0;
    while (elapsed < ms) {
        int step = (ms - elapsed < 10) ? (ms - elapsed) : 10;
        sleep_ms(step);
        elapsed += step;
        int c = poll_key();
        if (c) {
            handle_key(c);
            if (user_quit || paused || skip_to_next_hunk) return;
        }
    }
}

/* Color map: one colored string per line (ANSI-escaped). NULL = no colormap. */
static char **colormap_old = NULL;
static int colormap_old_count = 0;
static char **colormap_new = NULL;
static int colormap_new_count = 0;

/* Track which lines have been modified (color invalidated).
 * Grows dynamically with the buffer. */
static char *line_modified = NULL;
static int line_modified_cap = 0;

/* Ensure line_modified array is large enough for the given line index. */
static void ensure_line_modified(int needed) {
    if (needed < line_modified_cap) return;
    int new_cap = line_modified_cap == 0 ? 1024 : line_modified_cap;
    while (new_cap <= needed) new_cap *= 2;
    line_modified = (char *)realloc(line_modified, new_cap);
    if (!line_modified) { fprintf(stderr, "out of memory (line_modified)\n"); exit(1); }
    memset(line_modified + line_modified_cap, 0, new_cap - line_modified_cap);
    line_modified_cap = new_cap;
}

/* Mark a line as modified (color invalidated). Safe for any cursor_l. */
static void mark_modified(int l) {
    if (!line_modified || l < 0) return;
    if (l >= line_modified_cap) ensure_line_modified(l);
    line_modified[l] = 1;
}

/* Grow lines array if needed */
static void ensure_lines_capacity(int needed) {
    if (needed <= cap_lines) return;
    int new_cap = cap_lines == 0 ? 1024 : cap_lines;
    while (new_cap < needed) new_cap *= 2;
    char **new_lines = (char **)realloc(lines, new_cap * sizeof(char *));
    if (!new_lines) { fprintf(stderr, "diffvim-animator-c: out of memory (lines %d)\n", new_cap); exit(1); }
    lines = new_lines;
    cap_lines = new_cap;
}

/* --- Virtual Buffer --- */

void load_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); exit(1); }
    char buf[MAX_LINE_LEN];
    int first_line = 1;
    while (fgets(buf, sizeof(buf), f)) {
        /* #8: Strip \r (CRLF normalization) */
        buf[strcspn(buf, "\r\n")] = 0;
        /* #9: Strip UTF-8 BOM from first line */
        if (first_line && (unsigned char)buf[0] == 0xEF &&
            (unsigned char)buf[1] == 0xBB && (unsigned char)buf[2] == 0xBF) {
            memmove(buf, buf + 3, strlen(buf + 3) + 1);
        }
        first_line = 0;
        ensure_lines_capacity(n_lines + 1);
        lines[n_lines++] = strdup(buf);
    }
    fclose(f);
    if (n_lines == 0) {
        ensure_lines_capacity(1);
        lines[n_lines++] = strdup("");
    }
}

void buffer_write(const char *path) {
    FILE *f = fopen(path, "w");
    if (!f) { fprintf(stderr, "Cannot write %s\n", path); return; }
    /* Strip trailing empty lines — when the entire file is deleted,
     * the buffer may have multiple empty lines (one per original line).
     * The expected output is an empty file (0 bytes), so strip ALL
     * trailing empty lines. */
    int effective_lines = n_lines;
    while (effective_lines > 0 && lines[effective_lines - 1][0] == 0)
        effective_lines--;
    for (int i = 0; i < effective_lines; i++)
        fprintf(f, "%s\n", lines[i]);
    fclose(f);
}

/* Get char count in a line (UTF-8 aware — counts code points) */
int line_chars(int l) {
    if (l < 0 || l >= n_lines) return 0;
    int count = 0;
    char *s = lines[l];
    while (*s) {
        if ((*s & 0xC0) != 0x80) count++; /* Count leading bytes */
        s++;
    }
    return count;
}

/* Get byte offset for a given char column.
 * Returns the byte offset of the leading byte of the char at position `col`.
 * For multi-byte UTF-8 chars, this correctly skips continuation bytes. */
int char_to_byte(int l, int col) {
    if (l < 0 || l >= n_lines) return 0;
    char *s = lines[l];
    int count = 0, byte = 0;
    /* Walk through the string. When count reaches col, return byte
     * WITHOUT incrementing past the current char. */
    while (s[byte]) {
        if ((s[byte] & 0xC0) != 0x80) {
            /* This is a leading byte (or ASCII char) */
            if (count == col) return byte;
            count++;
        }
        byte++;
    }
    return byte; /* past end of string */
}

/* Set cursor position (1-indexed line/col → 0-indexed internal).
 * Clamps to buffer bounds. When the target line is past the end of
 * the buffer (end-insert case), the cursor is placed at the END of
 * the last line so subsequent inserts append after existing content. */
void set_cursor(int line, int col) {
    cursor_l = line - 1;
    if (cursor_l < 0) cursor_l = 0;
    if (cursor_l >= n_lines) {
        /* Past end of buffer — clamp to last line, position at END. */
        cursor_l = n_lines - 1;
        cursor_c = line_chars(cursor_l);  /* END of last line (0-indexed = past last char) */
        return;
    }
    cursor_c = col - 1;
    if (cursor_c < 0) cursor_c = 0;
    int max_col = line_chars(cursor_l);
    if (cursor_c > max_col) cursor_c = max_col;
    /* Also update the displayed cursor — for content ops, the visual
     * cursor follows the internal cursor. For \n deletes, the delete
     * handler will NOT call set_cursor (it uses a separate path that
     * updates only the internal cursor). */
    disp_l = cursor_l;
    disp_c = cursor_c;
}

void keep_char(int code) {
    /* Note: with per-op positioning, keep_char only advances the cursor
     * within the same line. Line transitions are handled by set_cursor()
     * calls (next op carries the new line). */
    if (code == 10) {
        cursor_l++;
        if (cursor_l >= n_lines) cursor_l = n_lines - 1;
        cursor_c = 0;
    } else {
        cursor_c++;
    }
    /* Update displayed cursor to match */
    disp_l = cursor_l;
    disp_c = cursor_c;
}

void delete_char(int code) {
    if (code == 10) {
        /* Delete \n — join current line with the next line.
         * This is the natural result of removing a newline character
         * from a line-based buffer. No special cases. If there is no
         * next line (cursor at last line), the op is a no-op — the
         * postprocess must not emit delete-\n at the last line.
         *
         * IMPORTANT: do NOT update disp_l/disp_c here. The visual
         * cursor stays at its previous position (the line being
         * deleted), while the internal cursor_l is used for the join.
         * This prevents the cursor from visually jumping UP to the
         * preserved line above when deleting a \n. */
        if (cursor_l < n_lines - 1) {
            char *cur = lines[cursor_l];
            char *next = lines[cursor_l + 1];
            int newlen = strlen(cur) + strlen(next) + 1;
            char *joined = malloc(newlen);
            strcpy(joined, cur);
            strcat(joined, next);
            free(lines[cursor_l]);
            free(lines[cursor_l + 1]);
            lines[cursor_l] = joined;
            for (int i = cursor_l + 1; i < n_lines - 1; i++)
                lines[i] = lines[i + 1];
            n_lines--;
        }
        /* Clamp displayed cursor to new buffer bounds */
        if (disp_l >= n_lines) disp_l = n_lines - 1;
        if (disp_l < 0) disp_l = 0;
    } else {
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        int byte_len = strlen(s);
        int next = byte + 1;
        while (next < byte_len && (s[next] & 0xC0) == 0x80) next++;
        memmove(s + byte, s + next, byte_len - next + 1);
        /* Update displayed cursor to match */
        disp_l = cursor_l;
        disp_c = cursor_c;
    }
}

void insert_char(int code) {
    if (code == 10) {
        /* Split line */
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        char *before = strndup(s, byte);
        char *after = strdup(s + byte);
        free(lines[cursor_l]);
        lines[cursor_l] = before;
        /* Shift lines down — ensure capacity first */
        ensure_lines_capacity(n_lines + 1);
        for (int i = n_lines; i > cursor_l + 1; i--)
            lines[i] = lines[i - 1];
        lines[cursor_l + 1] = after;
        n_lines++;
        cursor_l++;
        cursor_c = 0;
    } else {
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        int len = strlen(s);
        char buf[8];
        int blen;
        if (code < 0x80) {
            buf[0] = code; blen = 1;
        } else if (code < 0x800) {
            buf[0] = 0xC0 | (code >> 6);
            buf[1] = 0x80 | (code & 0x3F);
            blen = 2;
        } else if (code < 0x10000) {
            buf[0] = 0xE0 | (code >> 12);
            buf[1] = 0x80 | ((code >> 6) & 0x3F);
            buf[2] = 0x80 | (code & 0x3F);
            blen = 3;
        } else {
            /* 4-byte UTF-8 (code points >= 0x10000) */
            buf[0] = 0xF0 | (code >> 18);
            buf[1] = 0x80 | ((code >> 12) & 0x3F);
            buf[2] = 0x80 | ((code >> 6) & 0x3F);
            buf[3] = 0x80 | (code & 0x3F);
            blen = 4;
        }
        s = realloc(s, len + blen + 1);
        memmove(s + byte + blen, s + byte, len - byte + 1);
        memcpy(s + byte, buf, blen);
        lines[cursor_l] = s;
        cursor_c++;
    }
}

void batch_delete(int n) {
    for (int i = 0; i < n; i++) {
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        int byte_len = strlen(s);
        if (byte >= byte_len) break;
        int next = byte + 1;
        while (next < byte_len && (s[next] & 0xC0) == 0x80) next++;
        memmove(s + byte, s + next, byte_len - next + 1);
    }
}

void batch_insert(int *codes, int count) {
    for (int i = 0; i < count; i++)
        insert_char(codes[i]);
}

void render(void) {
    if (no_display) return;
    printf("\033[2J\033[H");

    /* Get terminal height (default 24 if unavailable) */
    int term_height = 24;
    struct winsize ws;
    if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &ws) == 0 && ws.ws_row > 0)
        term_height = ws.ws_row;
    /* Reserve 1 line for status */
    int viewport_height = term_height - 1;

    /* Calculate scroll offset based on scroll_mode.
     * zz = center cursor (default), zt = cursor at top, zb = cursor at bottom,
     * none = no scroll (start at line 0). Uses disp_l (displayed cursor). */
    static int scroll_offset = 0;
    int half_viewport = viewport_height / 2;
    int target = disp_l;  /* use displayed cursor for scrolling */
    if (strcmp(scroll_mode, "zt") == 0) {
        /* Cursor at top of viewport */
        scroll_offset = target;
    } else if (strcmp(scroll_mode, "zb") == 0) {
        /* Cursor at bottom of viewport */
        scroll_offset = target - viewport_height + 1;
    } else if (strcmp(scroll_mode, "none") == 0) {
        /* No scroll — start at line 0 */
        scroll_offset = 0;
    } else {
        /* zz (default) — center cursor in viewport */
        if (target < half_viewport) {
            scroll_offset = 0;
        } else if (target >= n_lines - half_viewport) {
            scroll_offset = (n_lines > viewport_height) ? (n_lines - viewport_height) : 0;
        } else {
            scroll_offset = target - half_viewport;
        }
    }
    if (scroll_offset < 0) scroll_offset = 0;
    if (scroll_offset > n_lines - viewport_height && n_lines > viewport_height)
        scroll_offset = n_lines - viewport_height;

    int max = scroll_offset + viewport_height;
    if (max > n_lines) max = n_lines;

    for (int i = scroll_offset; i < max; i++) {
        char *colored = NULL;
        /* Use colormap_old for unmodified lines (original syntax colors),
         * colormap_new for modified lines (new syntax colors). */
        if (line_modified && i < line_modified_cap && line_modified[i]) {
            /* Line was modified — use colormap_new if available */
            if (colormap_new && i < colormap_new_count)
                colored = colormap_new[i];
        } else {
            /* Unmodified line — use colormap_old if available */
            if (colormap_old && i < colormap_old_count)
                colored = colormap_old[i];
        }
        if (colored) {
            if (show_line_numbers) printf("%4d ", i + 1);
            if (i == disp_l)
                printf("\033[7m%s\033[0m\n", colored);
            else
                printf("%s\n", colored);
        } else {
            if (show_line_numbers) printf("%4d ", i + 1);
            if (i == disp_l)
                printf("\033[7m%s\033[0m\n", lines[i]);
            else if (diff_highlight && i < line_modified_cap && line_modified[i])
                /* Diff highlight: modified lines get a subtle background */
                printf("\033[48;5;236m%s\033[0m\n", lines[i]);
            else
                printf("%s\n", lines[i]);
        }
    }
    if (show_progress) {
        printf("\033[%d;1H\033[2K[progress: line %d/%d]\n", viewport_height, disp_l + 1, n_lines);
    }
    /* Diff stat overlay: show changed/total line counts at the bottom */
    if (show_diff_stat) {
        int modified_count = 0;
        for (int i = 0; i < n_lines && i < line_modified_cap; i++)
            if (line_modified[i]) modified_count++;
        printf("\033[%d;1H\033[2K[diff: %d/%d lines changed]\n",
               viewport_height + (show_progress ? 0 : 0),
               modified_count, n_lines);
    }
    /* Terminal bell on error: ring the bell if the last op was at an
     * invalid position (cursor clamped to buffer bounds) */
    if (bell_on_error) {
        /* Ring the terminal bell (\a = BEL) to alert the user of
         * potential cursor clamping or buffer errors. */
        printf("\a");
        fflush(stdout);
    }
    /* Position cursor at the right display row — use disp_l/disp_c
     * (the displayed cursor), NOT cursor_l/cursor_c (the internal
     * cursor used for buffer operations). This decouples the visual
     * cursor from the internal cursor, so \n deletes can move the
     * internal cursor without moving the visual cursor. */
    int dl = disp_l;
    if (dl >= n_lines) dl = n_lines - 1;
    if (dl < 0) dl = 0;
    int dc = disp_c;
    int max_c = line_chars(dl);
    if (dc > max_c) dc = max_c;
    if (dc < 0) dc = 0;
    int display_cursor_row = dl - scroll_offset;
    printf("\033[%d;%dH", display_cursor_row + 1, dc + 1 + (show_line_numbers ? 5 : 0));
    fflush(stdout);
}

/* Load a colormap file: one ANSI-colored string per line. */
void load_colormap(const char *path, char ***map, int *count) {
    FILE *f = fopen(path, "r");
    if (!f) return;
    int cap = 256;
    *map = (char **)malloc(cap * sizeof(char *));
    *count = 0;
    char buf[MAX_LINE_LEN];
    while (fgets(buf, sizeof(buf), f)) {
        buf[strcspn(buf, "\n")] = 0;
        if (*count >= cap) {
            cap *= 2;
            *map = (char **)realloc(*map, cap * sizeof(char *));
        }
        (*map)[(*count)++] = strdup(buf);
    }
    fclose(f);
}

void sleep_ms(int ms) {
    if (ms <= 0) return;
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

int main(int argc, char **argv) {
    signal(SIGINT, cleanup_handler);
    signal(SIGTERM, cleanup_handler);

    /* Enable raw keyboard input mode (no-op in --no-display mode or
     * when stdin isn't a TTY — e.g. when piped from pace). */
    enable_raw_mode();
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--no-display") == 0) no_display = 1;
        else if (strcmp(argv[i], "--speed") == 0 && i+1 < argc) speed_mult = atof(argv[++i]);
        else if (strcmp(argv[i], "--output") == 0 && i+1 < argc) strncpy(output_file, argv[++i], 255);
        else if (strcmp(argv[i], "--snapshot") == 0 && i+1 < argc) strncpy(snapshot_file_path, argv[++i], 255);
        else if (strcmp(argv[i], "--colormap-old") == 0 && i+1 < argc) strncpy(colormap_old_path, argv[++i], 255);
        else if (strcmp(argv[i], "--colormap-new") == 0 && i+1 < argc) strncpy(colormap_new_path, argv[++i], 255);
        else if (strcmp(argv[i], "--line-numbers") == 0) show_line_numbers = 1;
        else if (strcmp(argv[i], "--progress") == 0) show_progress = 1;
        else if (strcmp(argv[i], "--verbose") == 0) verbose = 1;
        else if (strcmp(argv[i], "--dry-run") == 0) dry_run = 1;
        else if (strcmp(argv[i], "--seek") == 0 && i+1 < argc) seek_op = atoi(argv[++i]);
        else if (strcmp(argv[i], "--diff-stat") == 0) show_diff_stat = 1;
        else if (strcmp(argv[i], "--bell") == 0) bell_on_error = 1;
        else if (strcmp(argv[i], "--diff-highlight") == 0) diff_highlight = 1;
        else if (strcmp(argv[i], "--scroll") == 0 && i+1 < argc) {
            /* Scroll mode: zz|zt|zb|none (default: zz)
             * zz = center cursor, zt = top, zb = bottom, none = no scroll */
            strncpy(scroll_mode, argv[++i], 7);
        }
        else if (strcmp(argv[i], "--version") == 0) { printf("diffvim-animator-c 2.0\n"); exit(0); }
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-animator [options] <oldfile>\n");
            fprintf(stderr, "  --colormap-old FILE  ANSI-colored lines for old file\n");
            fprintf(stderr, "  --colormap-new FILE  ANSI-colored lines for new file\n");
            fprintf(stderr, "  --line-numbers       Show line numbers in the margin\n");
            fprintf(stderr, "  --progress           Show progress bar at bottom\n");
            fprintf(stderr, "  --verbose            Show timing info on stderr\n");
            fprintf(stderr, "  --dry-run            Show what would be animated without running\n");
            fprintf(stderr, "  --version            Print version and exit\n");
            exit(0);
        } else if (argv[i][0] != '-') strncpy(old_file_path, argv[i], 255);
    }

    if (!old_file_path[0]) { fprintf(stderr, "Error: oldfile required\n"); exit(1); }
    load_file(old_file_path);
    if (verbose) fprintf(stderr, "diffvim-animator: loaded %d lines from %s\n", n_lines, old_file_path);
    if (dry_run) {
        fprintf(stderr, "diffvim-animator: dry run — %d lines loaded, reading timed op stream...\n", n_lines);
        /* Count ops */
        int op_count = 0;
        char dl[1048576];
        while (fgets(dl, sizeof(dl), stdin)) {
            if (dl[0] && dl[0] != '#' && dl[0] != '\n') op_count++;
        }
        fprintf(stderr, "diffvim-animator: %d ops in stream, would animate\n", op_count);
        return 0;
    }
    if (colormap_old_path[0]) load_colormap(colormap_old_path, &colormap_old, &colormap_old_count);
    if (colormap_new_path[0]) load_colormap(colormap_new_path, &colormap_new, &colormap_new_count);
    line_modified = NULL; // will grow dynamically via mark_modified
    if (!no_display) printf("\033[?25l");

    char line[MAX_LINE_LEN];
    int op_count = 0;
    int ops_total = 0;
    while (fgets(line, sizeof(line), stdin)) {
        /* #70: Seek — skip ops until we reach the seek position */
        if (seek_op > 0 && op_count < seek_op) {
            line[strcspn(line, "\n")] = 0;
            if (line[0] && line[0] != '#') op_count++;
            /* Still apply ops to maintain buffer state, but don't render */
            /* Actually, for seek we need to APPLY ops but not render */
            continue;
        }
        line[strcspn(line, "\n")] = 0;
        if (line[0] == 0 || line[0] == '#') continue;

        /* Detect v1 format and fail loudly with a helpful message. */
        if (strncmp(line, "op\t", 3) == 0) {
            fprintf(stderr, "diffvim-animator-c: ERROR: timed stream uses v1 'op\\t<type>...' prefix\n");
            fprintf(stderr, "  Line: [%s]\n", line);
            fprintf(stderr, "  v2 format has the type directly: keep\\t<line>\\t<col>\\t<code>\\n");
            fprintf(stderr, "  Rebuild the pipeline: make -C compute && make -C animator  (or use 'make all')\n");
            cleanup_handler(1);
            exit(1);
        }
        if (strncmp(line, "newline_delete", 14) == 0 || strncmp(line, "newline_insert", 14) == 0) {
            fprintf(stderr, "diffvim-animator-c: ERROR: timed stream uses v1 'newline_delete'/'newline_insert' op\n");
            fprintf(stderr, "  Line: [%s]\n", line);
            fprintf(stderr, "  v2 format uses delete\\t<line>\\t<col>\\t10\\t\\\\n\n");
            cleanup_handler(1);
            exit(1);
        }
        if (strncmp(line, "hunk_start\t", 11) == 0 || strncmp(line, "hunk_end", 8) == 0) {
            fprintf(stderr, "diffvim-animator-c: ERROR: timed stream uses v1 'hunk_start'/'hunk_end'\n");
            fprintf(stderr, "  Line: [%s]\n", line);
            fprintf(stderr, "  v2 format uses 'HUNK' and 'HUNK_END'\n");
            cleanup_handler(1);
            exit(1);
        }
        if (strncmp(line, "batch_delete", 11) == 0 || strncmp(line, "batch_insert", 12) == 0) {
            fprintf(stderr, "diffvim-animator-c: ERROR: timed stream uses v1 'batch_delete'/'batch_insert'\n");
            fprintf(stderr, "  Line: [%s]\n", line);
            fprintf(stderr, "  v2 format uses single-char delete/insert ops (pace does not batch anymore)\n");
            cleanup_handler(1);
            exit(1);
        }
        if (strncmp(line, "delay\t", 6) == 0) {
            /* Detect reversed delay fields: "delay\\t<type>\\t<ms>" is v1 */
            /* v2: delay\t<ms>\t<type>. The 2nd field should be a number. */
            char *p = line + 6;
            if (*p < '0' || *p > '9') {
                fprintf(stderr, "diffvim-animator-c: ERROR: delay op has non-numeric first arg (v1 format)\n");
                fprintf(stderr, "  Line: [%s]\n", line);
                fprintf(stderr, "  v2 format: delay\\t<ms>\\t<type>\n");
                cleanup_handler(1);
                exit(1);
            }
        }
        ops_total++;

        /* TSV tokenizer. */
        char *toks[32];
        int ntok = 0;
        char *p = line;
        char *tab = strchr(p, '\t');
        while (tab && ntok < 31) {
            *tab = 0;
            toks[ntok++] = p;
            p = tab + 1;
            tab = strchr(p, '\t');
        }
        toks[ntok++] = p;

        char *cmd = toks[0];

        /* v2 format: type is first field directly, no "op" prefix */
        if (strcmp(cmd, "keep") == 0 && ntok >= 4) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            int code = atoi(toks[3]);
            set_cursor(op_line, op_col);
            keep_char(code);
            render();
        } else if (strcmp(cmd, "delete") == 0 && ntok >= 4) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            int code = atoi(toks[3]);
            if (code == 10) {
                /* For \n deletes: update ONLY the internal cursor
                 * (cursor_l/cursor_c) for the join, but leave the
                 * DISPLAYED cursor (disp_l/disp_c) unchanged. The
                 * visual cursor stays at the position of the previous
                 * content op — it NEVER jumps UP to the line where the
                 * \n is being deleted. */
                cursor_l = op_line - 1;
                if (cursor_l < 0) cursor_l = 0;
                if (cursor_l >= n_lines) cursor_l = n_lines - 1;
                cursor_c = op_col - 1;
                if (cursor_c < 0) cursor_c = 0;
                int max_col = line_chars(cursor_l);
                if (cursor_c > max_col) cursor_c = max_col;
                /* disp_l/disp_c NOT updated — visual cursor stays put */
                delete_char(code);
                mark_modified(cursor_l);
                render();
            } else {
                set_cursor(op_line, op_col);
                delete_char(code);
                mark_modified(cursor_l);
                render();
            }
        } else if ((strcmp(cmd, "insert") == 0 || strcmp(cmd, "overwrite_insert") == 0) && ntok >= 4) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            int code = atoi(toks[3]);
            set_cursor(op_line, op_col);
            insert_char(code);
            mark_modified(cursor_l);
            render();
        } else if (strcmp(cmd, "delay") == 0 && ntok >= 3) {
            /* delay\t<ms>\t<type> */
            int ms = atoi(toks[1]);
            if (speed_mult > 0) ms = (int)(ms / speed_mult);

            /* Loop here while paused — when user resumes, continue.
             * If user pressed q, break out of the main loop. */
            while (paused && !user_quit) {
                sleep_with_kb(50);
            }
            if (user_quit) break;

            if (!no_display) sleep_with_kb(ms);
        } else if (strcmp(cmd, "HUNK") == 0 || strcmp(cmd, "HUNK_END") == 0) {
            /* Metadata — track hunk boundaries for the skip feature */
            if (strcmp(cmd, "HUNK") == 0) {
                in_hunk = 1;
                /* If user asked to skip to next hunk, this is the next hunk — reset */
                skip_to_next_hunk = 0;
            } else {
                in_hunk = 0;
            }
        } else if (strcmp(cmd, "highlight") == 0 && ntok >= 7) {
            /* highlight\t<sl>\t<sc>\t<el>\t<ec>\t<type>\t<dur>
             *
             * The Perl/Vim animator uses these coordinates to draw a
             * colored highlight region via matchaddpos(). The C animator
             * has no sign column and no matchaddpos equivalent, so it
             * just re-renders the buffer (the highlight is purely visual
             * and has no effect on the buffer state).
             *
             * The fields are still consumed (assigned to a variable that
             * is intentionally unused) so the op stream is parsed and
             * validated, but the values have no effect on the C
             * animator's buffer. */
            if (!no_display) {
                int hl_sl  = atoi(toks[1]);  /* start line */
                int hl_sc  = atoi(toks[2]);  /* start col */
                int hl_el  = atoi(toks[3]);  /* end line */
                int hl_ec  = atoi(toks[4]);  /* end col */
                const char *hl_type = toks[5];  /* highlight type */
                int hl_dur = atoi(toks[6]);  /* duration ms */
                (void)hl_sl; (void)hl_sc; (void)hl_el; (void)hl_ec;
                (void)hl_type; (void)hl_dur;
                render();
            }
        } else if (strcmp(cmd, "dim") == 0 && ntok >= 4) {
            /* dim\t<sl>\t<el>\t<pct> — pass through, renderer handles */
            render();
        } else if (strcmp(cmd, "fold") == 0 && ntok >= 3) {
            /* fold\t<sl>\t<el> — in C animator, skip rendering folded lines */
            render();
        } else if (strcmp(cmd, "sign") == 0 && ntok >= 3) {
            /* sign\t<line>\t<type> — no-op in C animator (no sign column) */
        } else if (strcmp(cmd, "marker") == 0) {
            /* marker\t<line>\t<col>\t<text> — no-op in C animator */
        } else if (strcmp(cmd, "skip_hunk") == 0) {
            /* skip_hunk — set flag to skip rendering until next HUNK_END */
            /* For C animator: just render without delay */
        } else if (strcmp(cmd, "glide") == 0 && ntok >= 5) {
            /* glide\t<from_line>\t<to_line>\t<duration_ms>\t<show_intermediate>
             *
             * Animate the cursor moving from from_line to to_line over
             * duration_ms, using ease-in-out interpolation. If
             * show_intermediate is 1, render each intermediate line
             * (the buffer content scrolls past). If 0, just animate
             * the cursor position without rendering intermediate lines.
             *
             * Interruptible: if the user presses a key during the glide,
             * the glide is skipped to the end. */
            int from_line = atoi(toks[1]);
            int to_line = atoi(toks[2]);
            int duration_ms = atoi(toks[3]);
            int show_intermediate = atoi(toks[4]);
            if (!no_display && duration_ms > 0) {
                int steps = duration_ms / 16;  /* ~60fps */
                if (steps < 2) steps = 2;
                for (int s = 0; s <= steps; s++) {
                    double t = (double)s / steps;
                    /* Ease-in-out (smoothstep) */
                    double ease = t * t * (3 - 2 * t);
                    disp_l = (int)(from_line + (to_line - from_line) * ease);
                    if (disp_l < 0) disp_l = 0;
                    if (disp_l >= n_lines) disp_l = n_lines - 1;
                    disp_c = 0;
                    if (show_intermediate) {
                        render();
                    } else {
                        /* Just position cursor, don't render full buffer */
                        int dl = disp_l;
                        if (dl >= n_lines) dl = n_lines - 1;
                        if (dl < 0) dl = 0;
                        printf("\033[%d;1H", dl + 1);
                        fflush(stdout);
                    }
                    /* Check for keypress to interrupt */
                    if (poll_key() > 0) break;
                    sleep_ms(duration_ms / steps);
                }
                /* Ensure we end at the target */
                disp_l = to_line - 1;
                if (disp_l < 0) disp_l = 0;
                if (disp_l >= n_lines) disp_l = n_lines - 1;
                disp_c = 0;
                render();
            }
        } else if (strcmp(cmd, "snapshot") == 0 && ntok >= 2) {
            buffer_write(toks[1]);
        } else if (strcmp(cmd, "done") == 0) {
            break;
        }

        /* Skip-to-next-hunk: if user pressed 'n', apply all remaining
         * ops in the current hunk instantly (no delays, no renders). */
        if (skip_to_next_hunk && in_hunk) {
            char skip_line[MAX_LINE_LEN];
            while (fgets(skip_line, sizeof(skip_line), stdin)) {
                skip_line[strcspn(skip_line, "\n")] = 0;
                if (skip_line[0] == 0 || skip_line[0] == '#') continue;
                /* TSV tokenize */
                char *stoks[32];
                int sn = 0;
                char *sp = skip_line;
                char *stab = strchr(sp, '\t');
                while (stab && sn < 31) {
                    *stab = 0;
                    stoks[sn++] = sp;
                    sp = stab + 1;
                    stab = strchr(sp, '\t');
                }
                stoks[sn++] = sp;
                char *scmd = stoks[0];
                if (strcmp(scmd, "HUNK_END") == 0) {
                    skip_to_next_hunk = 0;
                    in_hunk = 0;
                    break;
                }
                if (strcmp(scmd, "HUNK") == 0) {
                    /* New hunk started — don't skip this one */
                    skip_to_next_hunk = 0;
                    /* Re-process this line as the start of a new hunk */
                    /* For simplicity, just render and continue normally */
                    render();
                    break;
                }
                if (strcmp(scmd, "keep") == 0 && sn >= 4) {
                    set_cursor(atoi(stoks[1]), atoi(stoks[2]));
                    keep_char(atoi(stoks[3]));
                } else if (strcmp(scmd, "delete") == 0 && sn >= 4) {
                    set_cursor(atoi(stoks[1]), atoi(stoks[2]));
                    delete_char(atoi(stoks[3]));
                    mark_modified(cursor_l);
                } else if (strcmp(scmd, "insert") == 0 && sn >= 4) {
                    set_cursor(atoi(stoks[1]), atoi(stoks[2]));
                    insert_char(atoi(stoks[3]));
                    mark_modified(cursor_l);
                }
                /* Skip delays inside the skip — no waiting */
            }
            render();
        }
    }

    if (snapshot_file_path[0]) buffer_write(snapshot_file_path);
    if (output_file[0]) buffer_write(output_file);
    if (ops_total == 0) {
        fprintf(stderr, "diffvim-animator-c: WARNING: no ops were applied\n");
        fprintf(stderr, "  The timed op stream was empty or contained only comments.\n");
        fprintf(stderr, "  Did the pipeline stages (compute, postprocess, pace) produce any output?\n");
        fprintf(stderr, "  Run with: bash scripts/dv_debug.sh <old> <new> to inspect each stage.\n");
    }
    disable_raw_mode();
    if (!no_display) {
        printf("\033[?25h\033[0m\n");
        if (user_quit) printf("Animation stopped by user.\n");
        else printf("Animation complete.\n");
    }
    return 0;
}
