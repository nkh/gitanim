/* diffvim-animator — Standalone terminal animation application.
 * C implementation — produces identical results to Perl and Go versions.
 *
 * Reads a timed op stream and animates the transformation.
 * Supports --no-display for testing.
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

#define MAX_LINE_LEN 8192

/* Dynamic arrays — grow as needed */
static char **lines = NULL;
static int n_lines = 0;
static int cap_lines = 0;
static int cursor_l = 0; /* 0-indexed */
static int cursor_c = 0; /* 0-indexed */

static int no_display = 0;
static double speed_mult = 1.0;
static char output_file[256] = "";
static char snapshot_file_path[256] = "";
static char old_file_path[256] = "";

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
    while (fgets(buf, sizeof(buf), f)) {
        buf[strcspn(buf, "\n")] = 0;
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

void keep_char(int code) {
    if (code == 10) { cursor_l++; if (cursor_l >= n_lines) cursor_l = n_lines - 1; cursor_c = 0; }
    else cursor_c++;
}

void delete_char(int code) {
    if (code == 10) {
        /* Delete newline: join current line with next.
         * A \n delete op means the \n character must be removed from the
         * buffer. Removing the \n between lines N and N+1 means joining
         * those two lines. Always join, regardless of line content. */
        if (cursor_l < n_lines - 1) {
            /* Not the last line — join with next */
            char *cur = lines[cursor_l];
            char *next = lines[cursor_l + 1];
            int newlen = strlen(cur) + strlen(next) + 1;
            char *joined = malloc(newlen);
            strcpy(joined, cur);
            strcat(joined, next);
            free(lines[cursor_l]);
            free(lines[cursor_l + 1]);
            lines[cursor_l] = joined;
            /* Shift remaining lines down */
            for (int i = cursor_l + 1; i < n_lines - 1; i++)
                lines[i] = lines[i + 1];
            n_lines--;
            /* Cursor stays at same column on the (now joined) line */
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
        if (i == cursor_l)
            printf("\033[7m%s\033[0m\n", lines[i]);
        else
            printf("%s\n", lines[i]);
    }
    printf("\033[%d;%dH", cursor_l + 1, cursor_c + 1);
    fflush(stdout);
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
        else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-animator [options] <oldfile>\n");
            exit(0);
        } else if (argv[i][0] != '-') strncpy(old_file_path, argv[i], 255);
    }

    if (!old_file_path[0]) { fprintf(stderr, "Error: oldfile required\n"); exit(1); }
    load_file(old_file_path);
    if (!no_display) printf("\033[?25l");

    char line[MAX_LINE_LEN];
    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;
        if (line[0] == 0 || line[0] == '#') continue;

        char cmd[32];
        sscanf(line, "%31s", cmd);
        char *args = line + strlen(cmd);
        while (*args == ' ') args++;

        if (strcmp(cmd, "op") == 0) {
            char type[8]; int code;
            sscanf(args, "%s %d", type, &code);
            if (strcmp(type, "keep") == 0) keep_char(code);
            else if (strcmp(type, "delete") == 0) delete_char(code);
            else if (strcmp(type, "insert") == 0) insert_char(code);
            render();
        } else if (strcmp(cmd, "delay") == 0) {
            int ms = atoi(args);
            if (speed_mult > 0) ms = (int)(ms / speed_mult);
            if (!no_display) sleep_ms(ms);
        } else if (strcmp(cmd, "batch_delete") == 0) {
            batch_delete(atoi(args));
            render();
        } else if (strcmp(cmd, "batch_insert") == 0) {
            /* Parse codes dynamically — no fixed limit */
            int *codes = NULL; int n = 0; int cap = 0;
            char *p = args;
            while (*p) {
                /* skip leading spaces */
                while (*p == ' ') p++;
                if (!*p) break;
                /* ensure capacity */
                if (n >= cap) {
                    cap = cap == 0 ? 16 : cap * 2;
                    int *new_codes = (int *)realloc(codes, cap * sizeof(int));
                    if (!new_codes) { fprintf(stderr, "diffvim-animator-c: out of memory (batch_insert)\n"); free(codes); exit(1); }
                    codes = new_codes;
                }
                codes[n++] = atoi(p);
                while (*p && *p != ' ') p++;
            }
            batch_insert(codes, n);
            free(codes);
            render();
        } else if (strcmp(cmd, "newline_delete") == 0) {
            delete_char(10);
            render();
        } else if (strcmp(cmd, "newline_insert") == 0) {
            insert_char(10);
            render();
        } else if (strcmp(cmd, "glide") == 0) {
            int l, c;
            sscanf(args, "%d:%d", &l, &c);
            cursor_l = l - 1; cursor_c = c - 1;
            if (cursor_l < 0) cursor_l = 0;
            if (cursor_l >= n_lines) {
                /* Past end of buffer — clamp to last line and position
                 * cursor at END of last line so subsequent inserts
                 * append after content (end_insert case). */
                cursor_l = n_lines - 1;
                cursor_c = line_chars(cursor_l);
            }
            render();
        } else if (strcmp(cmd, "snapshot") == 0) {
            char path[256];
            sscanf(args, "%255s", path);
            buffer_write(path);
        } else if (strcmp(cmd, "done") == 0) {
            break;
        }
    }

    if (snapshot_file_path[0]) buffer_write(snapshot_file_path);
    if (output_file[0]) buffer_write(output_file);
    if (!no_display) { printf("\033[?25h\033[0m\n"); printf("Animation complete.\n"); }
    return 0;
}
