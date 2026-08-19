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

/* Ctrl+C handler: restore terminal before exiting */
static void cleanup_handler(int sig) {
    printf("\033[?25h\033[0m\033[2J\033[H");
    fflush(stdout);
    exit(1);
}



/* Dynamic arrays — grow as needed */
static char **lines = NULL;
static int n_lines = 0;
static int cap_lines = 0;
static int cursor_l = 0; /* 0-indexed */
static int cursor_c = 0; /* 0-indexed */

static int no_display = 0;
static int show_line_numbers = 0;
static int show_progress = 0;
static int verbose = 0;
static int dry_run = 0;
static double speed_mult = 1.0;
static char output_file[256] = "";
static char snapshot_file_path[256] = "";
static char old_file_path[256] = "";
static char colormap_old_path[256] = "";
static char colormap_new_path[256] = "";

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
    if (n_lines == 1 && lines[0][0] == 0) {
        /* Empty buffer — write nothing */
    } else {
        for (int i = 0; i < n_lines; i++)
            fprintf(f, "%s\n", lines[i]);
    }
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
}

void delete_char(int code) {
    if (code == 10) {
        /* Delete newline — ghost-line fix.
         *
         * If the current line is EMPTY (all content already deleted by
         * preceding char deletes), remove the empty line entirely.
         * The cursor stays at the same line index (now pointing to what
         * was the next line). This avoids the visual jump where the next
         * line's content appears on the current line.
         *
         * If the current line still has content, JOIN it with the next
         * line (original behavior — needed for mixed delete+insert
         * sequences where the line isn't fully emptied first).
         */
        if (cursor_l < n_lines - 1) {
            char *cur = lines[cursor_l];
            if (cur[0] == '\0') {
                /* Current line is empty — remove it entirely.
                 * Cursor moves to the next line (now at same index). */
                free(lines[cursor_l]);
                for (int i = cursor_l; i < n_lines - 1; i++)
                    lines[i] = lines[i + 1];
                n_lines--;
                cursor_c = 0;
            } else {
                /* Current line has content — join with next. */
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
        } else if (cursor_l > 0) {
            /* Last line — remove it and move to previous */
            free(lines[cursor_l]);
            n_lines--;
            cursor_l--;
            cursor_c = strlen(lines[cursor_l]);
        }
    } else {
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        int byte_len = strlen(s);
        int next = byte + 1;
        while (next < byte_len && (s[next] & 0xC0) == 0x80) next++;
        memmove(s + byte, s + next, byte_len - next + 1);
    }
}

void insert_char(int code) {
    if (code == 10) {
        /* Split line */
        int byte = char_to_byte(cursor_l, cursor_c);
        char *s = lines[cursor_l];
        int len = strlen(s);
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
    int max = n_lines > 40 ? 40 : n_lines;
    for (int i = 0; i < max; i++) {
        /* Use colormap for unmodified lines; plain text for modified ones. */
        char *colored = NULL;
        if (colormap_old && i < colormap_old_count && i < line_modified_cap && !line_modified[i])
            colored = colormap_old[i];
        if (colored) {
            if (show_line_numbers) printf("%4d ", i + 1);
            if (i == cursor_l)
                printf("\033[7m%s\033[0m\n", colored);
            else
                printf("%s\n", colored);
        } else {
            if (show_line_numbers) printf("%4d ", i + 1);
            if (i == cursor_l)
                printf("\033[7m%s\033[0m\n", lines[i]);
            else
                printf("%s\n", lines[i]);
        }
    }
    if (show_progress) {
        printf("\033[%d;1H\033[2K[progress]\n", (n_lines > 40 ? 40 : n_lines) + 1);
    }
    printf("\033[%d;%dH", cursor_l + 1, cursor_c + 1 + (show_line_numbers ? 5 : 0));
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
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == 0 || line[0] == '#') continue;

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

        if (strcmp(cmd, "op") == 0 && ntok >= 5) {
            /* op\t<type>\t<line>\t<col>\t<code> */
            char *type = toks[1];
            int op_line = atoi(toks[2]);
            int op_col = atoi(toks[3]);
            int code = atoi(toks[4]);
            set_cursor(op_line, op_col);
            if (strcmp(type, "keep") == 0) keep_char(code);
            else if (strcmp(type, "delete") == 0) { delete_char(code); mark_modified(cursor_l); }
            else if (strcmp(type, "insert") == 0) { insert_char(code); mark_modified(cursor_l); }
            render();
        } else if (strcmp(cmd, "delay") == 0 && ntok >= 2) {
            /* Parse both delay\t<ms> and delay\t<type>\t<ms> */
            int ms;
            if (ntok >= 3) {
                /* Typed delay: delay\t<type>\t<ms> — type is toks[1], ms is toks[2] */
                ms = atoi(toks[2]);
                /* Future: apply per-type multiplier here based on toks[1] */
            } else {
                /* Untyped delay: delay\t<ms> */
                ms = atoi(toks[1]);
            }
            if (speed_mult > 0) ms = (int)(ms / speed_mult);
            if (!no_display) sleep_ms(ms);
        } else if (strcmp(cmd, "batch_delete") == 0 && ntok >= 4) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            int n = atoi(toks[3]);
            set_cursor(op_line, op_col);
            batch_delete(n);
            mark_modified(cursor_l);
            render();
        } else if (strcmp(cmd, "batch_insert") == 0 && ntok >= 4) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            set_cursor(op_line, op_col);
            int *codes = NULL; int n = 0; int cap = 0;
            for (int i = 3; i < ntok; i++) {
                if (n >= cap) {
                    cap = cap == 0 ? 16 : cap * 2;
                    int *new_codes = (int *)realloc(codes, cap * sizeof(int));
                    if (!new_codes) { fprintf(stderr, "diffvim-animator-c: out of memory (batch_insert)\n"); free(codes); exit(1); }
                    codes = new_codes;
                }
                codes[n++] = atoi(toks[i]);
            }
            batch_insert(codes, n);
            free(codes);
            mark_modified(cursor_l);
            render();
        } else if (strcmp(cmd, "newline_delete") == 0 && ntok >= 2) {
            int op_line = atoi(toks[1]);
            set_cursor(op_line, 1);
            delete_char(10);
            mark_modified(cursor_l);
            render();
        } else if (strcmp(cmd, "newline_insert") == 0 && ntok >= 3) {
            int op_line = atoi(toks[1]);
            int op_col = atoi(toks[2]);
            set_cursor(op_line, op_col);
            insert_char(10);
            mark_modified(cursor_l);
            render();
        } else if (strcmp(cmd, "snapshot") == 0 && ntok >= 2) {
            buffer_write(toks[1]);
        } else if (strcmp(cmd, "done") == 0) {
            break;
        }
        /* hunk_start, hunk_end, glide (if any) are no-ops for the animator. */
    }

    if (snapshot_file_path[0]) buffer_write(snapshot_file_path);
    if (output_file[0]) buffer_write(output_file);
    if (!no_display) { printf("\033[?25h\033[0m\n"); printf("Animation complete.\n"); }
    return 0;
}
