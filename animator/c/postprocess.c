/* diffvim-postprocess — Post-process raw char ops.
 *
 * Reads raw char ops from stdin, applies post-processing, computes
 * per-op (line, col) positions, and writes tab-separated ops to stdout.
 *
 * The postprocess stage OWNS cursor positioning. The pace stage only
 * handles delays and batching. The animator reads (line, col) from each
 * op and applies it at that exact position — scroll-safe.
 *
 * Output format (TSV, 1-indexed line/col):
 *   hunk_start\t<del_count>\t<ins_count>
 *   op\tkeep\t<line>\t<col>\t<code>
 *   op\tdelete\t<line>\t<col>\t<code>
 *   op\tinsert\t<line>\t<col>\t<code>
 *   newline_delete\t<line>
 *   newline_insert\t<line>\t<col>
 *
 * Usage: diffvim-postprocess [--op-order MODE] [--semantic-cleanup]
 *                             [--indent-aware] [--overwrite]
 *
 * Build: cc -O2 -o diffvim-postprocess postprocess.c
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_LINE 1048576  // 1MB — was 4096

typedef struct { char type[20]; int code; int line; int col; } Op;

/* Dynamic arrays — grow as needed */
static Op *ops_in = NULL;
static Op *ops_out = NULL;
static int n_ops = 0;
static int cap_ops = 0;

/* Header lines (passed through) — dynamic */
static char **header = NULL;
static int n_header = 0;
static int cap_header = 0;

/* Hunk info */
typedef struct { int target, del, ins, end_ins, end_del; int op_start, op_count; } Hunk;
static Hunk *hunks = NULL;
static int n_hunks = 0;
static int cap_hunks = 0;

static int op_order_optimize = 1;
static int op_order_left_to_right = 0;
static int op_order_end_first = 0;
static int op_order_end_first_smart = 0;
static int do_semantic = 0;
static int do_indent = 0;
static int do_overwrite = 0;
static int stream_mode = 0;

/* Apply a --transform NAME[:VALUE] spec. */
void apply_transform(const char *spec) {
    if (strncmp(spec, "op-order:", 9) == 0) {
        const char *mode = spec + 9;
        if (strcmp(mode, "natural") == 0) { op_order_optimize = 0; }
        else if (strcmp(mode, "optimize") == 0) { op_order_optimize = 1; }
        else if (strcmp(mode, "left-to-right") == 0) { op_order_left_to_right = 1; }
        else if (strcmp(mode, "end-first") == 0) { op_order_end_first = 1; }
        else if (strcmp(mode, "end-first-smart") == 0) { op_order_end_first_smart = 1; }
    } else if (strcmp(spec, "semantic-cleanup") == 0) {
        do_semantic = 1;
    } else if (strcmp(spec, "indent-aware") == 0) {
        do_indent = 1;
    } else if (strcmp(spec, "overwrite") == 0) {
        do_overwrite = 1;
    } else {
        fprintf(stderr, "diffvim-postprocess: unknown transform '%s'\n", spec);
        fprintf(stderr, "  Available: op-order:natural|optimize, semantic-cleanup, indent-aware, overwrite\n");
        exit(1);
    }
}

void list_transforms(void) {
    printf("Available transforms (use --transform NAME[:VALUE]):\n");
    printf("  op-order:natural        No reordering (raw patience order)\n");
    printf("  op-order:optimize       Deletes before inserts within each line (default)\n");
    printf("  semantic-cleanup        Merge adjacent delete+insert pairs that cancel out\n");
    printf("  indent-aware            Handle indent-only changes as keeps\n");
    printf("  overwrite               Transform delete+insert into in-place overwrite\n");
    printf("\nTransforms are applied in the order specified.\n");
    printf("Multiple --transform flags can be given.\n");
}

void parse_args(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--op-order") == 0 && i+1 < argc) {
            i++;
            if (strcmp(argv[i], "natural") == 0) { op_order_optimize = 0; }
            else if (strcmp(argv[i], "optimize") == 0) { op_order_optimize = 1; }
            else if (strcmp(argv[i], "left-to-right") == 0) { op_order_left_to_right = 1; }
            else if (strcmp(argv[i], "end-first") == 0) { op_order_end_first = 1; }
            else if (strcmp(argv[i], "end-first-smart") == 0) { op_order_end_first_smart = 1; }
        } else if (strcmp(argv[i], "--semantic-cleanup") == 0) {
            do_semantic = 1;
        } else if (strcmp(argv[i], "--indent-aware") == 0) {
            do_indent = 1;
        } else if (strcmp(argv[i], "--overwrite") == 0) {
            do_overwrite = 1;
        } else if (strcmp(argv[i], "--stream") == 0) {
            stream_mode = 1;
        } else if (strcmp(argv[i], "--transform") == 0 && i+1 < argc) {
            apply_transform(argv[++i]);
        } else if (strcmp(argv[i], "--list-transforms") == 0) {
            list_transforms();
            exit(0);
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fprintf(stderr, "Usage: diffvim-postprocess [options]\n");
            fprintf(stderr, "  --transform NAME[:VALUE]  Apply a transformation (repeatable)\n");
            fprintf(stderr, "  --list-transforms        List available transforms\n");
            fprintf(stderr, "  --op-order MODE          Shorthand for --transform op-order:MODE\n");
            fprintf(stderr, "  --semantic-cleanup       Shorthand for --transform semantic-cleanup\n");
            fprintf(stderr, "  --indent-aware           Shorthand for --transform indent-aware\n");
            fprintf(stderr, "  --overwrite              Shorthand for --transform overwrite\n");
            exit(0);
        }
    }
}

/* Grow ops_in if needed */
void ensure_ops_capacity(int needed) {
    if (needed <= cap_ops) return;
    int new_cap = cap_ops == 0 ? 4096 : cap_ops;
    while (new_cap < needed) new_cap *= 2;
    ops_in = (Op *)realloc(ops_in, new_cap * sizeof(Op));
    if (!ops_in) { fprintf(stderr, "diffvim-postprocess: out of memory (ops_in %d)\n", new_cap); exit(1); }
    /* ops_out also needs to be at least as big */
    if (ops_out) ops_out = (Op *)realloc(ops_out, new_cap * sizeof(Op));
    else ops_out = (Op *)malloc(new_cap * sizeof(Op));
    if (!ops_out) { fprintf(stderr, "diffvim-postprocess: out of memory (ops_out %d)\n", new_cap); exit(1); }
    cap_ops = new_cap;
}

/* Grow hunks if needed */
void ensure_hunks_capacity(int needed) {
    if (needed <= cap_hunks) return;
    int new_cap = cap_hunks == 0 ? 64 : cap_hunks;
    while (new_cap < needed) new_cap *= 2;
    hunks = (Hunk *)realloc(hunks, new_cap * sizeof(Hunk));
    if (!hunks) { fprintf(stderr, "diffvim-postprocess: out of memory (hunks %d)\n", new_cap); exit(1); }
    cap_hunks = new_cap;
}

/* Grow header if needed */
void ensure_header_capacity(int needed) {
    if (needed <= cap_header) return;
    int new_cap = cap_header == 0 ? 32 : cap_header;
    while (new_cap < needed) new_cap *= 2;
    header = (char **)realloc(header, new_cap * sizeof(char *));
    if (!header) { fprintf(stderr, "diffvim-postprocess: out of memory (header %d)\n", new_cap); exit(1); }
    for (int i = cap_header; i < new_cap; i++) {
        header[i] = (char *)malloc(MAX_LINE);
        if (!header[i]) { fprintf(stderr, "diffvim-postprocess: out of memory (header line)\n"); exit(1); }
    }
    cap_header = new_cap;
}

void read_input(void) {
    char line[MAX_LINE];
    int current_hunk = -1;
    int header_seen_v2 = 0;
    int header_seen_v1 = 0;
    int line_no = 0;
    int ops_outside_hunk = 0;
    while (fgets(line, sizeof(line), stdin)) {
        line_no++;
        line[strcspn(line, "\n")] = 0;
        if (line[0] == '#' || line[0] == 0) {
            if (line[0] == '#') {
                /* Detect input format version from header */
                if (strncmp(line, "# diffvim raw diff v2", 21) == 0 ||
                    strncmp(line, "# diffvim precomputed diff v2", 30) == 0 ||
                    strncmp(line, "# diffvim post-processed v2", 27) == 0) {
                    header_seen_v2 = 1;
                }
                if (strncmp(line, "# diffvim raw diff v1", 21) == 0 ||
                    strncmp(line, "# diffvim precomputed diff v1", 30) == 0 ||
                    strncmp(line, "# diffvim post-processed v1", 27) == 0) {
                    header_seen_v1 = 1;
                }
                /* Detect v1 format by space-separated HUNK */
                if (strncmp(line, "# diffvim", 9) != 0 && strstr(line, "HUNK ") != NULL) {
                    /* not a known header but contains "HUNK " — likely v1 */
                }
                ensure_header_capacity(n_header + 1);
                strncpy(header[n_header++], line, MAX_LINE - 1);
                header[n_header - 1][MAX_LINE - 1] = 0;
            }
            continue;
        }

        /* Detect v1 format (space-separated HUNK or space-separated ops).
         * v2 uses tabs exclusively. If we see a HUNK line that uses spaces
         * instead of tabs, the input is v1 and we cannot parse it. */
        if (strncmp(line, "HUNK ", 5) == 0) {
            fprintf(stderr, "diffvim-postprocess: ERROR: input is v1 format (space-separated HUNK)\n");
            fprintf(stderr, "  Line %d: [%s]\n", line_no, line);
            fprintf(stderr, "  Expected v2 TSV format: HUNK\\t<target>\\t<del>\\t<ins>\\t<end_ins>\\t<end_del>\n");
            fprintf(stderr, "  Rebuild the compute binary: make -C compute clean && make -C compute\n");
            fprintf(stderr, "  (compute/bin/diffvim-compute-cpp is gitignored — git pull does not update it)\n");
            exit(1);
        }

        /* TSV tokenize */
        char *toks[8];
        int ntok = 0;
        char *p = line;
        char *tab = strchr(p, '\t');
        while (tab && ntok < 7) {
            *tab = 0;
            toks[ntok++] = p;
            p = tab + 1;
            tab = strchr(p, '\t');
        }
        toks[ntok++] = p;

        if (strcmp(toks[0], "HUNK") == 0 && ntok >= 6) {
            ensure_hunks_capacity(n_hunks + 1);
            hunks[n_hunks].target = atoi(toks[1]);
            hunks[n_hunks].del = atoi(toks[2]);
            hunks[n_hunks].ins = atoi(toks[3]);
            hunks[n_hunks].end_ins = atoi(toks[4]);
            hunks[n_hunks].end_del = atoi(toks[5]);
            hunks[n_hunks].op_start = n_ops;
            hunks[n_hunks].op_count = 0;
            current_hunk = n_hunks;
            n_hunks++;
            continue;
        }
        if (strcmp(toks[0], "HUNK_END") == 0) {
            current_hunk = -1;
            continue;
        }
        if ((strcmp(toks[0], "keep") == 0 || strcmp(toks[0], "delete") == 0 ||
             strcmp(toks[0], "insert") == 0) && ntok >= 4) {
            /* Warn if op appears outside a HUNK block */
            if (current_hunk < 0) {
                ops_outside_hunk++;
                /* Only warn once per file to avoid spam */
                if (ops_outside_hunk == 1) {
                    fprintf(stderr, "diffvim-postprocess: WARNING: op outside HUNK block at line %d: [%s]\n", line_no, line);
                    fprintf(stderr, "  (suppressing further warnings of this type)\n");
                }
                continue;
            }
            ensure_ops_capacity(n_ops + 1);
            strncpy(ops_in[n_ops].type, toks[0], 7);
            ops_in[n_ops].type[7] = 0;
            ops_in[n_ops].line = atoi(toks[1]);
            ops_in[n_ops].col = atoi(toks[2]);
            ops_in[n_ops].code = atoi(toks[3]);
            n_ops++;
            hunks[current_hunk].op_count++;
        }
    }

    /* Sanity checks after reading */
    if (header_seen_v1 && !header_seen_v2) {
        fprintf(stderr, "diffvim-postprocess: ERROR: input header indicates v1 format\n");
        fprintf(stderr, "  This binary only parses v2 TSV format.\n");
        fprintf(stderr, "  Rebuild compute: make -C compute clean && make -C compute\n");
        exit(1);
    }
    if (n_hunks == 0 && n_ops == 0) {
        fprintf(stderr, "diffvim-postprocess: WARNING: no hunks and no ops parsed from input\n");
        fprintf(stderr, "  Input may be empty or in an unrecognized format.\n");
        fprintf(stderr, "  First few header lines:\n");
        for (int i = 0; i < n_header && i < 5; i++)
            fprintf(stderr, "    %s\n", header[i]);
    }
    if (ops_outside_hunk > 0) {
        fprintf(stderr, "diffvim-postprocess: WARNING: %d ops found outside any HUNK block (skipped)\n", ops_outside_hunk);
    }
}

/* Optimize: within each change region (between keeps), deletes before inserts.
 * Within deletes, put \n (code 10) deletes LAST so the line content
 * is deleted before the \n is removed. */
int optimize_line(Op *in, int count, Op *out) {
    int n_out = 0;
    int buf_start = 0;

    for (int i = 0; i <= count; i++) {
        if (i == count || strcmp(in[i].type, "keep") == 0) {
            /* Flush buffer: content deletes, \n deletes, then inserts */
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code != 10) out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "delete") == 0 && in[j].code == 10) out[n_out++] = in[j];
            for (int j = buf_start; j < i; j++)
                if (strcmp(in[j].type, "insert") == 0) out[n_out++] = in[j];
            if (i < count) out[n_out++] = in[i]; /* the keep */
            buf_start = i + 1;
        }
    }
    return n_out;
}

/* Semantic cleanup: merge canceling delete+insert pairs */
int semantic_cleanup(Op *in, int count, Op *out) {
    int n_out = 0;
    int i = 0;
    while (i < count) {
        if (i + 1 < count &&
            strcmp(in[i].type, "delete") == 0 &&
            strcmp(in[i+1].type, "insert") == 0 &&
            in[i].code == in[i+1].code) {
            strcpy(out[n_out].type, "keep");
            out[n_out].code = in[i].code;
            n_out++;
            i += 2;
        } else if (i + 1 < count &&
                   strcmp(in[i].type, "insert") == 0 &&
                   strcmp(in[i+1].type, "delete") == 0 &&
                   in[i].code == in[i+1].code) {
            strcpy(out[n_out].type, "keep");
            out[n_out].code = in[i].code;
            n_out++;
            i += 2;
        } else {
            out[n_out++] = in[i];
            i++;
        }
    }
    return n_out;
}

/* Left-to-right: within each line group, emit keeps, then deletes, then inserts.
 * (Similar to the compute's left_to_right, but applied at postprocess level.) */
int left_to_right_line(Op *in, int count, Op *out) {
    int n_out = 0;
    for (int j = 0; j < count; j++)
        if (strcmp(in[j].type, "keep") == 0) out[n_out++] = in[j];
    for (int j = 0; j < count; j++)
        if (strcmp(in[j].type, "delete") == 0) out[n_out++] = in[j];
    for (int j = 0; j < count; j++)
        if (strcmp(in[j].type, "insert") == 0) out[n_out++] = in[j];
    return n_out;
}

/* End-first: move trailing deletes before inserts.
 * Detects trailing deletes at the end of the line group (before \n)
 * and moves them before the inserts. */
int end_first_line(Op *in, int count, Op *out) {
    /* First optimize (deletes before inserts) */
    int n_out = optimize_line(in, count, out);
    /* Find if the last non-\n op is a delete (trailing delete) */
    int last_non_nl = n_out - 1;
    if (in[count-1].code == 10) last_non_nl = count - 2;
    if (last_non_nl >= 0 && strcmp(out[last_non_nl].type, "delete") == 0) {
        /* There are trailing deletes — they're already before inserts
         * after optimize_line, so end-first is the same as optimize for
         * single-line groups. The real difference is for multi-line
         * groups, which we don't handle here. */
    }
    return n_out;
}

/* Reorder ops within each line group. */
int reorder_hunk_ops(Op *in, int count, Op *out) {
    int n_out = 0;
    int line_start = 0;
    for (int i = 0; i <= count; i++) {
        if (i == count || in[i].code == 10) {
            int line_len = i - line_start;
            if (i < count) line_len++;
            if (line_len > 1) {
                if (op_order_left_to_right) {
                    n_out += left_to_right_line(in + line_start, line_len, out + n_out);
                } else if (op_order_end_first || op_order_end_first_smart) {
                    n_out += end_first_line(in + line_start, line_len, out + n_out);
                } else if (op_order_optimize) {
                    n_out += optimize_line(in + line_start, line_len, out + n_out);
                } else {
                    memcpy(out + n_out, in + line_start, line_len * sizeof(Op));
                    n_out += line_len;
                }
            } else {
                memcpy(out + n_out, in + line_start, line_len * sizeof(Op));
                n_out += line_len;
            }
            line_start = i + 1;
        }
    }
    return n_out;
}

/* Overwrite transform: mark delete+insert pairs as overwrite.
 * When a delete is immediately followed by an insert (after reordering),
 * and both are non-\n chars, mark the insert's type to "overwrite_insert".
 * The pace tool will use zero delay between the delete and the overwrite_insert. */
int overwrite_transform(Op *in, int count, Op *out) {
    int n_out = 0;
    for (int i = 0; i < count; i++) {
        out[n_out++] = in[i];
        /* Check if this delete is followed by an insert at same position */
        if (do_overwrite && i + 1 < count
            && strcmp(in[i].type, "delete") == 0 && in[i].code != 10
            && strcmp(in[i+1].type, "insert") == 0 && in[i+1].code != 10) {
            /* Mark the insert as overwrite_insert */
            strcpy(out[n_out - 1].type, "delete");  /* keep as delete */
            i++;
            out[n_out] = in[i];
            strcpy(out[n_out].type, "overwrite_insert");
            n_out++;
        }
    }
    return n_out;
}

/* Write ops with per-op (line, col) positions.
 *
 * For each hunk, we walk the ops and simulate the cursor position
 * assuming the original file is the buffer. Line/col are 1-indexed.
 * `line_offset` accumulates net (newline_inserts - newline_deletes)
 * across hunks so each hunk targets the CURRENT buffer position,
 * not the original line in the old file.
 */
void write_output(void) {
    /* Write header — convert v1 headers to v2, skip obsolete ones */
    for (int i = 0; i < n_header; i++) {
        if (strncmp(header[i], "# diffvim raw diff", 18) == 0) {
            printf("# diffvim post-processed v2\n");
        } else if (strncmp(header[i], "# diffvim precomputed", 21) == 0) {
            printf("# diffvim post-processed v2\n");
        } else if (strncmp(header[i], "# semantic_cleanup", 18) == 0)
            printf("# semantic_cleanup %d\n", do_semantic);
        else if (strncmp(header[i], "# indent_aware", 14) == 0)
            printf("# indent_aware %d\n", do_indent);
        else if (strncmp(header[i], "# optimize_sequence", 19) == 0)
            printf("# optimize_sequence %d\n", op_order_optimize);
        else if (strncmp(header[i], "# hunk_count", 12) == 0)
            printf("# hunk_count %d\n", n_hunks);
        else if (strncmp(header[i], "# word_diff", 11) == 0 ||
                 strncmp(header[i], "# left_to_right", 15) == 0)
            printf("%s\n", header[i]);
        /* skip unknown headers */
    }

    int line_offset = 0;  /* Cumulative (newline_inserts - newline_deletes) from prior hunks */

    int op_idx = 0;
    for (int h = 0; h < n_hunks; h++) {
        printf("HUNK\t%d\t%d\t%d\t%d\t%d\n",
               hunks[h].target, hunks[h].del, hunks[h].ins,
               hunks[h].end_ins, hunks[h].end_del);

        int count = hunks[h].op_count;
        Op *in = &ops_in[op_idx];

        Op *temp = ops_out;
        int n_out = count;

        if (do_semantic) {
            n_out = semantic_cleanup(in, count, temp);
            in = temp;
            count = n_out;
        }

        /* Always produce a final op array (optimized or not). */
        Op *final_ops;
        if (op_order_optimize) {
            Op *temp2 = (Op *)malloc(cap_ops * sizeof(Op));
            if (!temp2) { fprintf(stderr, "diffvim-postprocess: out of memory (temp2)\n"); exit(1); }
            n_out = reorder_hunk_ops(in, count, temp2);
            /* Apply overwrite transform after reordering */
            if (do_overwrite) {
                Op *temp3 = (Op *)malloc(cap_ops * sizeof(Op));
                if (!temp3) { fprintf(stderr, "out of memory\n"); exit(1); }
                n_out = overwrite_transform(temp2, n_out, temp3);
                free(temp2);
                final_ops = temp3;
            } else {
                final_ops = temp2;
            }
        } else {
            final_ops = in;
        }

/* Helper: convert char code to readable representation */
const char *char_repr_c(int code) {
    static char buf[8];
    switch (code) {
        case 10: return "\\n";
        case 9: return "\\t";
        case 13: return "\\r";
        case 32: return "space";
        default:
            if (code >= 33 && code <= 126) {
                buf[0] = '\'';
                buf[1] = (char)code;
                buf[2] = '\'';
                buf[3] = 0;
                return buf;
            }
            snprintf(buf, sizeof(buf), "%d", code);
            return buf;
    }
}

/* Emit an op in TSV format: type\tline\tcol\tcode\tchar_repr */
void emit_op(const char *type, int line, int col, int code) {
    printf("%s\t%d\t%d\t%d\t%s\n", type, line, col, code, char_repr_c(code));
}

        /* Compute per-op (line, col) and emit TSV.
         *
         * Ghost-line fix: when delete \n and the line has kept content
         * (not empty), AND the next ops are content deletes (the joined-in
         * content of the next line is about to be deleted):
         *
         * 1. Emit the content deletes at (cur_line+1, 1) — targeting the
         *    next line directly (the \n stays, so the next line is separate)
         * 2. Emit the \n delete at (cur_line+1) — the next line is now
         *    empty, so remove it
         * 3. cur_line stays the same (the next line was removed, lines
         *    shifted up to fill the gap) */
        int cur_line = hunks[h].target + line_offset;
        int cur_col = 1;
        int newl_ins = 0, newl_del = 0;
        int line_has_content = 0;
        int i = 0;
        while (i < n_out) {
            Op *op = &final_ops[i];
            if (op->code == 10) {
                if (strcmp(op->type, "keep") == 0) {
                    emit_op("keep", cur_line, cur_col, op->code);
                    cur_line++;
                    cur_col = 1;
                    line_has_content = 0;
                } else if (strcmp(op->type, "delete") == 0) {
                    /* "Delete last line" pattern: the first op in an
                     * is_end_delete hunk is a delete-\n, followed by
                     * content deletes (no keeps/inserts after).
                     *
                     * The compute generates "delete \n, delete content"
                     * for "delete last line". We reorder to: content
                     * deletes first (emptying the line), then \n delete
                     * targeting (cur_line - 1, 1) — which joins the
                     * PREVIOUS line with the now-empty last line,
                     * effectively removing the last line.
                     *
                     * This way the animator just applies ops — no
                     * special handling for "delete \n at last line". */
                    if (i == 0 && hunks[h].end_del && cur_line > 1) {
                        /* Find the end of the content deletes */
                        int j = i + 1;
                        while (j < n_out &&
                               strcmp(final_ops[j].type, "delete") == 0 &&
                               final_ops[j].code != 10)
                            j++;
                        int n_content = j - (i + 1);
                        int followed_by_keep_or_insert = 0;
                        if (j < n_out) {
                            if (strcmp(final_ops[j].type, "keep") == 0 ||
                                strcmp(final_ops[j].type, "insert") == 0) {
                                followed_by_keep_or_insert = 1;
                            }
                        }
                        if (n_content > 0 && !followed_by_keep_or_insert) {
                            /* Emit content deletes at (cur_line, 1) */
                            for (int k = i + 1; k < j; k++)
                                emit_op("delete", cur_line, 1, final_ops[k].code);
                            /* Emit \n delete at (cur_line - 1, 1) */
                            emit_op("delete", cur_line - 1, 1, 10);
                            newl_del++;
                            i = j;
                            continue;
                        }
                    }
                    if (line_has_content) {
                        int j = i + 1;
                        while (j < n_out &&
                               strcmp(final_ops[j].type, "delete") == 0 &&
                               final_ops[j].code != 10)
                            j++;
                        int n_content = j - (i + 1);
                        int followed_by_keep_or_insert = 0;
                        if (j < n_out) {
                            if (strcmp(final_ops[j].type, "keep") == 0 ||
                                strcmp(final_ops[j].type, "insert") == 0) {
                                followed_by_keep_or_insert = 1;
                            }
                        }
                        if (n_content > 0 && !followed_by_keep_or_insert) {
                            /* Ghost-line pattern! */
                            for (int k = i + 1; k < j; k++)
                                emit_op("delete", cur_line + 1, 1, final_ops[k].code);
                            emit_op("delete", cur_line + 1, 1, 10);  /* \n delete */
                            newl_del++;
                            i = j;
                            continue;
                        }
                    }
                    /* Normal \n delete */
                    emit_op("delete", cur_line, cur_col, 10);
                    newl_del++;
                    line_has_content = 0;
                } else if (strcmp(op->type, "insert") == 0) {
                    emit_op("insert", cur_line, cur_col, 10);
                    cur_line++;
                    cur_col = 1;
                    newl_ins++;
                    line_has_content = 0;
                }
            } else {
                /* For overwrite_insert, emit as 'insert' in output (pace will
                 * detect it via the op type and use zero delay) */
                const char *emit_type = op->type;
                if (strcmp(op->type, "overwrite_insert") == 0)
                    emit_type = "overwrite_insert";
                emit_op(emit_type, cur_line, cur_col, op->code);
                if (strcmp(op->type, "keep") == 0) {
                    cur_col++;
                    line_has_content = 1;
                } else if (strcmp(op->type, "insert") == 0
                           || strcmp(op->type, "overwrite_insert") == 0) {
                    cur_col++;
                }
            }
            i++;
        }

        if (op_order_optimize) free(final_ops);

        printf("HUNK_END\n");

        line_offset += newl_ins - newl_del;
        op_idx += hunks[h].op_count;
    }
    printf("\n");  /* blank line at bottom */
}

/* Process a single hunk: apply transformations and emit TSV output.
 * Used by both batch and streaming modes.
 * cur_line_ptr tracks the current line (modified by newline ops).
 * line_offset_ptr tracks cumulative newline_inserts - newline_deletes.
 * Returns the number of newline_inserts - newline_deletes for this hunk.
 */
int process_one_hunk(int target, int del, int ins, int end_ins, int end_del,
                      Op *in_ops, int count, int line_offset) {
    int cur_line = target + line_offset;
    int cur_col = 1;
    int newl_ins = 0, newl_del = 0;

    Op *temp = ops_out;
    int n_out = count;
    

    if (do_semantic) {
        n_out = semantic_cleanup(in_ops, count, temp);
        in_ops = temp;
        count = n_out;
    }

    Op *final_ops;
    if (op_order_optimize) {
        Op *temp2 = (Op *)malloc(cap_ops * sizeof(Op));
        if (!temp2) { fprintf(stderr, "out of memory\n"); exit(1); }
        n_out = reorder_hunk_ops(in_ops, count, temp2);
        final_ops = temp2;
    } else {
        final_ops = in_ops;
    }

    for (int i = 0; i < n_out; i++) {
        Op *op = &final_ops[i];
        if (op->code == 10) {
            if (strcmp(op->type, "keep") == 0) {
                printf("op\tkeep\t%d\t%d\t%d\n", cur_line, cur_col, op->code);
                cur_line++;
                cur_col = 1;
            } else if (strcmp(op->type, "delete") == 0) {
                printf("newline_delete\t%d\n", cur_line);
                newl_del++;
            } else if (strcmp(op->type, "insert") == 0) {
                printf("newline_insert\t%d\t%d\n", cur_line, cur_col);
                cur_line++;
                cur_col = 1;
                newl_ins++;
            }
        } else {
            printf("op\t%s\t%d\t%d\t%d\n", op->type, cur_line, cur_col, op->code);
            if (strcmp(op->type, "keep") == 0 || strcmp(op->type, "insert") == 0) {
                cur_col++;
            }
        }
    }

    if (op_order_optimize) free(final_ops);
    return newl_ins - newl_del;
}

/* Streaming mode: read and process one hunk at a time.
 * Emits header immediately, then processes each hunk as it's read.
 * This allows true Unix pipes: compute | postprocess --stream | pace | animator
 */
void stream_process(void) {
    char line[MAX_LINE];
    int header_written = 0;
    int line_offset = 0;
    int in_hunk = 0;
    int hunk_target = 0, hunk_del = 0, hunk_ins = 0, hunk_end_ins = 0, hunk_end_del = 0;

    /* Dynamic array for current hunk's ops */
    int hunk_op_cap = 4096;
    Op *hunk_ops = (Op *)malloc(hunk_op_cap * sizeof(Op));
    int hunk_op_count = 0;

    /* Ensure ops_out is allocated for semantic_cleanup */
    if (!ops_out) {
        ops_out = (Op *)malloc(hunk_op_cap * sizeof(Op));
        cap_ops = hunk_op_cap;
    }

    while (fgets(line, sizeof(line), stdin)) {
        line[strcspn(line, "\n")] = 0;

        if (line[0] == '#') {
            /* Header line — emit immediately (with flag updates).
             * Skip hunk_count in streaming mode (unknown until all hunks read). */
            if (!header_written) {
                if (strncmp(line, "# hunk_count", 12) == 0)
                    continue;  /* skip — will emit -1 after header */
                if (strncmp(line, "# semantic_cleanup", 18) == 0)
                    printf("# semantic_cleanup %d\n", do_semantic);
                else if (strncmp(line, "# indent_aware", 14) == 0)
                    printf("# indent_aware %d\n", do_indent);
                else if (strncmp(line, "# optimize_sequence", 19) == 0)
                    printf("# optimize_sequence %d\n", op_order_optimize);
                else
                    printf("%s\n", line);
            }
            continue;
        }

        /* Write hunk_count placeholder once we know we have at least one hunk */
        if (!header_written) {
            printf("# hunk_count -1\n");  /* unknown in streaming mode */
            header_written = 1;
        }

        if (strncmp(line, "HUNK", 4) == 0) {
            /* If we were already in a hunk, process it first */
            if (in_hunk && hunk_op_count > 0) {
                printf("hunk_start\t%d\t%d\n", hunk_del, hunk_ins);
                line_offset += process_one_hunk(hunk_target, hunk_del, hunk_ins,
                                                  hunk_end_ins, hunk_end_del,
                                                  hunk_ops, hunk_op_count, line_offset);
                printf("hunk_end\n");
                hunk_op_count = 0;
            }

            /* Start new hunk */
            sscanf(line, "HUNK %d %d %d %d %d", &hunk_target, &hunk_del, &hunk_ins,
                   &hunk_end_ins, &hunk_end_del);
            in_hunk = 1;
            hunk_op_count = 0;
            continue;
        }

        if (strncmp(line, "keep", 4) == 0 || strncmp(line, "delete", 6) == 0 || strncmp(line, "insert", 6) == 0) {
            char type[8]; int code;
            sscanf(line, "%7s %d", type, &code);
            if (hunk_op_count >= hunk_op_cap) {
                hunk_op_cap *= 2;
                hunk_ops = (Op *)realloc(hunk_ops, hunk_op_cap * sizeof(Op));
            }
            strncpy(hunk_ops[hunk_op_count].type, type, 7);
            hunk_ops[hunk_op_count].type[7] = 0;
            hunk_ops[hunk_op_count].code = code;
            hunk_op_count++;
        }
    }

    /* Process last hunk */
    if (in_hunk && hunk_op_count > 0) {
        printf("hunk_start\t%d\t%d\n", hunk_del, hunk_ins);
        line_offset += process_one_hunk(hunk_target, hunk_del, hunk_ins,
                                          hunk_end_ins, hunk_end_del,
                                          hunk_ops, hunk_op_count, line_offset);
        printf("hunk_end\n");
    }

    free(hunk_ops);
}

int main(int argc, char **argv) {
    parse_args(argc, argv);

    if (stream_mode) {
        stream_process();
        return 0;
    }

    read_input();
    write_output();

    /* Cleanup */
    free(ops_in);
    free(ops_out);
    free(hunks);
    for (int i = 0; i < cap_header; i++) free(header[i]);
    free(header);
    return 0;
}
