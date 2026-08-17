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
#include <time.h>

#define MAX_LINES 100000
#define MAX_LINE_LEN 8192

static char *lines[MAX_LINES];
static int n_lines = 0;
static int cursor_l = 0; /* 0-indexed */
static int cursor_c = 0; /* 0-indexed */

static int no_display = 0;
static double speed_mult = 1.0;
static char output_file[256] = "";
static char snapshot_file_path[256] = "";
static char old_file_path[256] = "";

/* --- Virtual Buffer --- */

void load_file(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) { fprintf(stderr, "Cannot open %s\n", path); exit(1); }
    char buf[MAX_LINE_LEN];
    while (fgets(buf, sizeof(buf), f)) {
        buf[strcspn(buf, "\n")] = 0;
        if (n_lines < MAX_LINES)
            lines[n_lines++] = strdup(buf);
    }
    fclose(f);
    if (n_lines == 0) lines[n_lines++] = strdup("");
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

/* Get byte offset for a given char column */
int char_to_byte(int l, int col) {
    if (l < 0 || l >= n_lines) return 0;
    char *s = lines[l];
    int count = 0, byte = 0;
    while (s[byte] && count < col) {
        if ((s[byte] & 0xC0) != 0x80) count++;
        byte++;
    }
    return byte;
}

void keep_char(int code) {
    if (code == 10) { cursor_l++; if (cursor_l >= n_lines) cursor_l = n_lines - 1; cursor_c = 0; }
    else cursor_c++;
}

/* Deferred line joins */
static int deferred_joins[10000];
static int n_deferred = 0;

void apply_deferred_joins(void) {
    /* Sort in reverse order (simple bubble sort for small arrays) */
    for (int i = 0; i < n_deferred - 1; i++)
        for (int j = i + 1; j < n_deferred; j++)
            if (deferred_joins[i] < deferred_joins[j]) {
                int tmp = deferred_joins[i];
                deferred_joins[i] = deferred_joins[j];
                deferred_joins[j] = tmp;
            }
    for (int i = 0; i < n_deferred; i++) {
        int l = deferred_joins[i];
        if (l < n_lines - 1) {
            int len1 = strlen(lines[l]);
            int len2 = strlen(lines[l + 1]);
            lines[l] = realloc(lines[l], len1 + len2 + 1);
            strcat(lines[l], lines[l + 1]);
            free(lines[l + 1]);
            for (int j = l + 1; j < n_lines - 1; j++)
                lines[j] = lines[j + 1];
            n_lines--;
        }
    }
    n_deferred = 0;
}

void delete_char(int code) {
    if (code == 10) {
        /* Delete newline: join current line with next.
         * If current line is empty: join immediately (removes empty line).
         * If current line has content: defer the join to avoid pulling
         * the next line's content up during animation. */
        char *line = lines[cursor_l];
        if (strlen(line) == 0) {
            /* Empty line — join immediately */
            if (cursor_l < n_lines - 1) {
                int len2 = strlen(lines[cursor_l + 1]);
                lines[cursor_l] = realloc(lines[cursor_l], len2 + 1);
                strcpy(lines[cursor_l], lines[cursor_l + 1]);
                free(lines[cursor_l + 1]);
                for (int i = cursor_l + 1; i < n_lines - 1; i++)
                    lines[i] = lines[i + 1];
                n_lines--;
            }
        } else {
            /* Line has content — defer the join */
            if (cursor_l < n_lines - 1) {
                if (n_deferred < 10000)
                    deferred_joins[n_deferred++] = cursor_l;
                cursor_l++;
                cursor_c = 0;
            } else if (cursor_l > 0) {
                cursor_l--;
                cursor_c = strlen(lines[cursor_l]);
            }
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
        /* Shift lines down */
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
        if (code < 0x80) { buf[0] = code; blen = 1; }
        else if (code < 0x800) { buf[0] = 0xC0 | (code >> 6); buf[1] = 0x80 | (code & 0x3F); blen = 2; }
        else { buf[0] = 0xE0 | (code >> 12); buf[1] = 0x80 | ((code >> 6) & 0x3F); buf[2] = 0x80 | (code & 0x3F); blen = 3; }
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
            int codes[100]; int n = 0;
            char *p = args;
            while (*p && n < 100) { codes[n++] = atoi(p); while (*p && *p != ' ') p++; while (*p == ' ') p++; }
            batch_insert(codes, n);
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
            if (cursor_l >= n_lines) cursor_l = n_lines - 1;
            render();
        } else if (strcmp(cmd, "snapshot") == 0) {
            char path[256];
            sscanf(args, "%255s", path);
            apply_deferred_joins();
            buffer_write(path);
        } else if (strcmp(cmd, "done") == 0) {
            apply_deferred_joins();
            break;
        }
    }

    apply_deferred_joins();
    if (snapshot_file_path[0]) buffer_write(snapshot_file_path);
    if (output_file[0]) buffer_write(output_file);
    if (!no_display) { printf("\033[?25h\033[0m\n"); printf("Animation complete.\n"); }
    return 0;
}
