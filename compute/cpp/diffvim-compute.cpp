// diffvim-compute.cpp — External diff computer for diffvim (C++ version).
//
// Reads two files, computes line-level + char-level diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Supports three line-diff algorithms (lcs, myers, patience) selected
// via --algorithm or DIFFVIM_ALGORITHM, and optional semantic cleanup
// of char-level diffs via --semantic-cleanup or DIFFVIM_SEMANTIC_CLEANUP.
//
// Build: make cpp
// Usage: diffvim-compute-cpp <oldfile> <newfile> <outputfile>
//                           [--algorithm lcs|myers|patience] [--semantic-cleanup]
//
// Timing is printed to stderr.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <algorithm>
#include <chrono>
#include <fstream>
#include <iostream>
#include <sstream>

using namespace std;
using Clock = chrono::high_resolution_clock;

enum OpType { OP_KEEP, OP_DELETE, OP_INSERT };

struct LineOp { OpType type; int a_idx, b_idx; };
struct CharOp { OpType type; int code; };

struct Hunk {
    int target_line, deleted_count, inserted_count;
    int is_end_insert, is_end_delete;
    vector<CharOp> char_ops;
};

static double ms_diff(Clock::time_point from, Clock::time_point to) {
    return chrono::duration<double, milli>(to - from).count();
}

vector<string> read_lines(const string& path) {
    vector<string> lines;
    ifstream f(path, ios::binary);
    if (!f) return lines;
    string content((istreambuf_iterator<char>(f)), istreambuf_iterator<char>());
    size_t start = 0;
    for (size_t i = 0; i <= content.size(); i++) {
        if (i == content.size() || content[i] == '\n') {
            size_t len = i - start;
            /* If at end of buffer and last char was newline, don't emit
             * trailing empty line — matches vim's readfile(). */
            if (i == content.size() && len == 0 && !lines.empty()) break;
            lines.push_back(content.substr(start, len));
            start = i + 1;
        }
    }
    return lines;
}

/* Read an entire file (or stdin if path is "-") into a string.
 * Returns false on error. */
static bool read_file_or_stdin(const string& path, string& out) {
    if (path == "-") {
        out.assign((istreambuf_iterator<char>(cin)), istreambuf_iterator<char>());
        return true;
    }
    ifstream f(path, ios::binary);
    if (!f) return false;
    out.assign((istreambuf_iterator<char>(f)), istreambuf_iterator<char>());
    return true;
}

/* Parse a unified diff (patch file) into old_lines and new_lines.
 *
 * Reads from `path` (or stdin if "-"). Fills old_lines and new_lines.
 *
 * Unified diff rules:
 *   - `---` prefix  → old file header, ignore.
 *   - `+++` prefix  → new file header, ignore.
 *   - `@@`  prefix  → hunk header, ignore (we recompute our own hunks).
 *   - `\`   prefix  → diff metadata, ignore.
 *   - `-`   prefix  (not `---`) → old file line; strip leading `-`.
 *   - `+`   prefix  (not `+++`) → new file line; strip leading `+`.
 *   - ` `   prefix  → context line; strip leading ` `; appears in BOTH.
 *   - empty line    → treated as a space-prefixed empty context line.
 *   - anything else → unrecognized; skip.
 *
 * Multiple hunks are concatenated to reconstruct the full old/new content.
 * Returns true on success, false if the diff file can't be read. */
static bool parse_unified_diff(const string& path, vector<string>& old_lines,
                                vector<string>& new_lines) {
    string content;
    if (!read_file_or_stdin(path, content)) return false;
    old_lines.clear();
    new_lines.clear();

    size_t start = 0;
    for (size_t i = 0; i <= content.size(); i++) {
        if (i == content.size() || content[i] == '\n') {
            size_t len = i - start;
            /* Skip a trailing empty line (matches vim's readfile()). */
            if (i == content.size() && len == 0) break;

            if (len == 0) {
                /* Empty line in the diff = empty context line in both files. */
                old_lines.push_back("");
                new_lines.push_back("");
            } else if (len >= 3 && content.compare(start, 3, "---") == 0) {
                /* old file header — ignore */
            } else if (len >= 3 && content.compare(start, 3, "+++") == 0) {
                /* new file header — ignore */
            } else if (len >= 2 && content.compare(start, 2, "@@") == 0) {
                /* hunk header — ignore */
            } else if (content[start] == '\\') {
                /* metadata — ignore */
            } else if (content[start] == '-') {
                /* delete line — strip leading '-' */
                old_lines.push_back(content.substr(start + 1, len - 1));
            } else if (content[start] == '+') {
                /* insert line — strip leading '+' */
                new_lines.push_back(content.substr(start + 1, len - 1));
            } else if (content[start] == ' ') {
                /* context line — strip leading ' ', present in both */
                string s = content.substr(start + 1, len - 1);
                old_lines.push_back(s);
                new_lines.push_back(s);
            }
            /* else: unrecognized line (e.g. "diff --git") — skip */

            start = i + 1;
        }
    }
    return true;
}

/* --- Line-level LCS diff over a sub-range [a_start,a_end) x [b_start,b_end).
 * Produces ops with ABSOLUTE indices into a/b. */
static vector<LineOp> line_diff_range(const vector<string>& a, int a_start, int a_end,
                                       const vector<string>& b, int b_start, int b_end) {
    int na = a_end - a_start;
    int nb = b_end - b_start;
    vector<vector<int>> dp(na + 1, vector<int>(nb + 1, 0));
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++)
            dp[i][j] = (a[a_start + i - 1] == b[b_start + j - 1]) ? dp[i-1][j-1] + 1
                       : max(dp[i-1][j], dp[i][j-1]);
    vector<LineOp> ops;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && a[a_start + i - 1] == b[b_start + j - 1]) {
            ops.push_back({OP_KEEP, a_start + i - 1, b_start + j - 1}); i--; j--;
        } else if (j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j])) {
            ops.push_back({OP_INSERT, -1, b_start + j - 1}); j--;
        } else {
            ops.push_back({OP_DELETE, a_start + i - 1, -1}); i--;
        }
    }
    reverse(ops.begin(), ops.end());
    return ops;
}

vector<LineOp> line_diff(const vector<string>& a, const vector<string>& b) {
    return line_diff_range(a, 0, (int)a.size(), b, 0, (int)b.size());
}

/* --- Myers diff algorithm (O(ND)) --- */
/* Faster than LCS for small diffs. Falls back to LCS for very large N+M. */
vector<LineOp> myers_diff(const vector<string>& a, const vector<string>& b) {
    int na = a.size(), nb = b.size();
    /* For very large inputs, Myers can use excessive memory; fall back to LCS. */
    if (na + nb > 200000) {
        return line_diff(a, b);
    }
    int max = na + nb;
    vector<int> v(2 * max + 1, 0);
    auto V = [&](int k) -> int& { return v[k + max]; };
    /* trace stores the v array at each d for backtracking. */
    vector<vector<int>> trace(max + 1);

    for (int d = 0; d <= max; d++) {
        trace[d] = v;  /* copy v at the START of depth d */
        for (int k = -d; k <= d; k += 2) {
            int x;
            if (k == -d || (k != d && V(k-1) < V(k+1)))
                x = V(k+1);
            else
                x = V(k-1) + 1;
            int y = x - k;
            while (x < na && y < nb && a[x] == b[y]) {
                x++; y++;
            }
            V(k) = x;
            if (x >= na && y >= nb) {
                /* Backtrack from (x, y) at depth d. */
                vector<LineOp> ops;
                ops.reserve(d + na + nb);
                int cx = na, cy = nb;
                for (int dd = d; dd > 0; dd--) {
                    vector<int>& vp = trace[dd];
                    auto TV = [&](int kk) -> int { return vp[kk + max]; };
                    int k = cx - cy;
                    int prev_x, prev_y;
                    int from_below;  /* 1 = came from k+1 (insert), 0 = came from k-1 (delete) */
                    if (k == -dd) {
                        from_below = 1;
                    } else if (k == dd) {
                        from_below = 0;
                    } else {
                        from_below = (TV(k-1) < TV(k+1)) ? 1 : 0;
                    }
                    if (from_below) {
                        prev_x = TV(k+1);
                        prev_y = prev_x - (k + 1);
                    } else {
                        prev_x = TV(k-1) + 1;
                        prev_y = prev_x - (k - 1);
                    }
                    /* Emit diagonal keeps from (cx,cy) back to (prev_x, prev_y) */
                    while (cx > prev_x && cy > prev_y) {
                        ops.push_back({OP_KEEP, cx - 1, cy - 1});
                        cx--; cy--;
                    }
                    /* The single non-diagonal step */
                    if (from_below) {
                        ops.push_back({OP_INSERT, -1, cy - 1});
                        cy--;
                    } else {
                        ops.push_back({OP_DELETE, cx - 1, -1});
                        cx--;
                    }
                }
                /* Handle any diagonal keeps at the very start (depth 0) */
                while (cx > 0 && cy > 0) {
                    ops.push_back({OP_KEEP, cx - 1, cy - 1});
                    cx--; cy--;
                }
                reverse(ops.begin(), ops.end());
                return ops;
            }
        }
    }
    /* Fallback */
    return line_diff(a, b);
}

/* --- Patience diff algorithm --- */
/* Anchors on unique common lines, then recurses on the gaps. */

/* Find unique common lines between a[a_start..a_end) and b[b_start..b_end).
 * Returns matching (a_idx, b_idx) pairs (in increasing a_idx order, then
 * filtered to the LIS of b_idx) via out_a_idx / out_b_idx.
 * Returns the count. */
static int find_patience_anchors(const vector<string>& a, int a_start, int a_end,
                                  const vector<string>& b, int b_start, int b_end,
                                  vector<int>& out_a_idx, vector<int>& out_b_idx) {
    out_a_idx.clear();
    out_b_idx.clear();
    for (int i = a_start; i < a_end; i++) {
        /* Check if a[i] appears exactly once in a[a_start..a_end) */
        int a_count = 0;
        for (int k = a_start; k < a_end; k++) {
            if (a[i] == a[k]) a_count++;
        }
        if (a_count != 1) continue;
        /* Find the unique match in b[b_start..b_end) */
        int b_match = -1;
        int b_count = 0;
        for (int k = b_start; k < b_end; k++) {
            if (a[i] == b[k]) {
                b_match = k;
                b_count++;
            }
        }
        if (b_count == 1) {
            out_a_idx.push_back(i);
            out_b_idx.push_back(b_match);
        }
    }
    int count = out_a_idx.size();
    if (count <= 1) return count;
    /* LIS of b_idx via patience sorting. */
    vector<int> lis_prev(count);
    vector<int> lis_tail_idx(count);
    int lis_len = 0;
    for (int i = 0; i < count; i++) {
        int lo = 0, hi = lis_len;
        while (lo < hi) {
            int mid = (lo + hi) / 2;
            if (out_b_idx[lis_tail_idx[mid]] < out_b_idx[i])
                lo = mid + 1;
            else
                hi = mid;
        }
        lis_prev[i] = (lo > 0) ? lis_tail_idx[lo - 1] : -1;
        if (lo == lis_len) {
            lis_tail_idx[lis_len] = i;
            lis_len++;
        } else {
            lis_tail_idx[lo] = i;
        }
    }
    /* Reconstruct LIS */
    vector<int> keep_a(lis_len), keep_b(lis_len);
    int idx = lis_tail_idx[lis_len - 1];
    for (int i = lis_len - 1; i >= 0; i--) {
        keep_a[i] = out_a_idx[idx];
        keep_b[i] = out_b_idx[idx];
        idx = lis_prev[idx];
    }
    /* Copy back */
    out_a_idx = keep_a;
    out_b_idx = keep_b;
    return lis_len;
}

static vector<LineOp> patience_diff_range(const vector<string>& a, int a_start, int a_end,
                                           const vector<string>& b, int b_start, int b_end) {
    int na = a_end - a_start;
    int nb = b_end - b_start;
    vector<LineOp> ops;

    if (na == 0 && nb == 0) {
        return ops;
    }
    if (na == 0) {
        for (int j = 0; j < nb; j++) {
            ops.push_back({OP_INSERT, -1, b_start + j});
        }
        return ops;
    }
    if (nb == 0) {
        for (int i = 0; i < na; i++) {
            ops.push_back({OP_DELETE, a_start + i, -1});
        }
        return ops;
    }

    /* Find patience anchors */
    vector<int> anchor_a, anchor_b;
    int n_anchors = find_patience_anchors(a, a_start, a_end, b, b_start, b_end,
                                           anchor_a, anchor_b);

    if (n_anchors == 0) {
        /* No unique common lines — fall back to LCS for this range. */
        return line_diff_range(a, a_start, a_end, b, b_start, b_end);
    }

    /* Diff the gaps between anchors. */
    int prev_a = a_start, prev_b = b_start;
    for (int k = 0; k <= n_anchors; k++) {
        int cur_a = (k < n_anchors) ? anchor_a[k] : a_end;
        int cur_b = (k < n_anchors) ? anchor_b[k] : b_end;
        if (cur_a > prev_a || cur_b > prev_b) {
            vector<LineOp> sub_ops = patience_diff_range(a, prev_a, cur_a, b, prev_b, cur_b);
            for (auto& op : sub_ops) ops.push_back(move(op));
        }
        if (k < n_anchors) {
            ops.push_back({OP_KEEP, anchor_a[k], anchor_b[k]});
            prev_a = anchor_a[k] + 1;
            prev_b = anchor_b[k] + 1;
        }
    }
    return ops;
}

vector<LineOp> patience_diff(const vector<string>& a, const vector<string>& b) {
    return patience_diff_range(a, 0, (int)a.size(), b, 0, (int)b.size());
}

/* --- Diff dispatcher --- */
vector<LineOp> compute_line_diff(const vector<string>& a, const vector<string>& b,
                                  const string& algorithm) {
    if (algorithm == "myers")
        return myers_diff(a, b);
    if (algorithm == "patience")
        return patience_diff(a, b);
    return line_diff(a, b);  /* default: lcs */
}

vector<CharOp> char_diff(const string& a, const string& b) {
    // Use Unicode code points (not bytes) for char-level diff.
    // This matches vim's split(str, '\zs') behavior.
    // Simple UTF-8 decoder: iterate over the string extracting code points.
    vector<int> ac, bc;
    for (size_t i = 0; i < a.size(); ) {
        unsigned char c = a[i];
        if (c < 0x80) { ac.push_back(c); i++; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < a.size()) {
            ac.push_back(((c & 0x1F) << 6) | ((unsigned char)a[i+1] & 0x3F));
            i += 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < a.size()) {
            ac.push_back(((c & 0x0F) << 12) | (((unsigned char)a[i+1] & 0x3F) << 6) | ((unsigned char)a[i+2] & 0x3F));
            i += 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < a.size()) {
            ac.push_back(((c & 0x07) << 18) | (((unsigned char)a[i+1] & 0x3F) << 12) | (((unsigned char)a[i+2] & 0x3F) << 6) | ((unsigned char)a[i+3] & 0x3F));
            i += 4;
        } else { ac.push_back(c); i++; }  /* invalid, treat as byte */
    }
    for (size_t i = 0; i < b.size(); ) {
        unsigned char c = b[i];
        if (c < 0x80) { bc.push_back(c); i++; }
        else if ((c & 0xE0) == 0xC0 && i + 1 < b.size()) {
            bc.push_back(((c & 0x1F) << 6) | ((unsigned char)b[i+1] & 0x3F));
            i += 2;
        } else if ((c & 0xF0) == 0xE0 && i + 2 < b.size()) {
            bc.push_back(((c & 0x0F) << 12) | (((unsigned char)b[i+1] & 0x3F) << 6) | ((unsigned char)b[i+2] & 0x3F));
            i += 3;
        } else if ((c & 0xF8) == 0xF0 && i + 3 < b.size()) {
            bc.push_back(((c & 0x07) << 18) | (((unsigned char)b[i+1] & 0x3F) << 12) | (((unsigned char)b[i+2] & 0x3F) << 6) | ((unsigned char)b[i+3] & 0x3F));
            i += 4;
        } else { bc.push_back(c); i++; }
    }
    int na = ac.size(), nb = bc.size();
    vector<vector<int>> dp(na + 1, vector<int>(nb + 1, 0));
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++)
            dp[i][j] = (ac[i-1] == bc[j-1]) ? dp[i-1][j-1] + 1
                       : max(dp[i-1][j], dp[i][j-1]);
    vector<CharOp> ops;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && ac[i-1] == bc[j-1]) {
            ops.push_back({OP_KEEP, ac[i-1]}); i--; j--;
        } else if (j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j])) {
            ops.push_back({OP_INSERT, bc[j-1]}); j--;
        } else {
            ops.push_back({OP_DELETE, ac[i-1]}); i--;
        }
    }
    reverse(ops.begin(), ops.end());
    return ops;
}

/* --- Semantic cleanup: merge adjacent delete+insert pairs that cancel --- */
vector<CharOp> semantic_cleanup(vector<CharOp> ops) {
    if (ops.size() < 2) return ops;
    vector<CharOp> out;
    out.reserve(ops.size());
    size_t i = 0;
    while (i < ops.size()) {
        if (i + 1 < ops.size()) {
            /* delete X followed by insert X -> keep X */
            if (ops[i].type == OP_DELETE && ops[i+1].type == OP_INSERT && ops[i].code == ops[i+1].code) {
                out.push_back({OP_KEEP, ops[i].code});
                i += 2;
                continue;
            }
            /* insert X followed by delete X -> keep X */
            if (ops[i].type == OP_INSERT && ops[i+1].type == OP_DELETE && ops[i].code == ops[i+1].code) {
                out.push_back({OP_KEEP, ops[i].code});
                i += 2;
                continue;
            }
        }
        out.push_back(ops[i]);
        i++;
    }
    return out;
}

/* --- Op-sequence optimization: consolidate interleaved del/ins --- */
vector<CharOp> optimize_sequence(vector<CharOp> ops) {
    if (ops.size() < 4) return ops;
    vector<CharOp> out;
    out.reserve(ops.size());
    size_t i = 0;
    while (i < ops.size()) {
        if (ops[i].type != OP_KEEP && ops[i].code != 10) {
            while (i < ops.size()) {
                if (ops[i].type == OP_KEEP) break;
                if (ops[i].code == 10) break;
                out.push_back(ops[i]);
                i++;
            }
        } else {
            out.push_back(ops[i]);
            i++;
        }
    }
    return out;
}

/* --- Left-to-right: sort ops within each line by type --- */
vector<CharOp> left_to_right(vector<CharOp> ops) {
    if (ops.size() < 2) return ops;
    vector<CharOp> out;
    out.reserve(ops.size());
    size_t i = 0;
    while (i < ops.size()) {
        size_t line_start = i;
        while (i < ops.size() && ops[i].code != 10) i++;
        size_t line_end = i;
        for (size_t k = line_start; k < line_end; k++)
            if (ops[k].type == OP_KEEP) out.push_back(ops[k]);
        for (size_t k = line_start; k < line_end; k++)
            if (ops[k].type == OP_DELETE) out.push_back(ops[k]);
        for (size_t k = line_start; k < line_end; k++)
            if (ops[k].type == OP_INSERT) out.push_back(ops[k]);
        if (i < ops.size()) { out.push_back(ops[i]); i++; }
    }
    return out;
}

/* --- Word-level diff --- */
/* Splits text into tokens (maximal runs of non-whitespace + maximal runs of
 * whitespace), runs LCS at the token level, then expands each token to
 * individual char ops. Produces more natural typing patterns than char-level
 * LCS because consecutive chars within a word are grouped.
 *
 * Matches vimscript s:WordDiff + s:SplitWords. */

static bool is_ws_byte(unsigned char c) {
    /* Vim's \s matches [ \t\n\r\f\v] */
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

struct Token { int start; int len; };

/* Split text into tokens: maximal runs of whitespace OR maximal runs of
 * non-whitespace. E.g. "hello world" -> ["hello", " ", "world"]. */
static vector<Token> split_words(const string& text) {
    vector<Token> toks;
    int len = (int)text.size();
    int i = 0;
    while (i < len) {
        int start = i;
        if (is_ws_byte((unsigned char)text[i])) {
            while (i < len && is_ws_byte((unsigned char)text[i])) i++;
        } else {
            while (i < len && !is_ws_byte((unsigned char)text[i])) i++;
        }
        toks.push_back({start, i - start});
    }
    return toks;
}

static inline bool token_eq(const string& a, const Token& ta, const string& b, const Token& tb) {
    return ta.len == tb.len && memcmp(a.data() + ta.start, b.data() + tb.start, ta.len) == 0;
}

/* Decode one UTF-8 sequence from s starting at *pos (up to end).
 * Updates *pos to point past the decoded character.
 * Returns the Unicode code point, or -1 on error. */
static int utf8_decode_at(const string& s, int end, int *pos) {
    if (*pos >= end) return -1;
    unsigned char c = (unsigned char)s[*pos];
    if (c < 0x80) { (*pos)++; return c; }
    int cp, extra;
    if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; extra = 1; }
    else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; extra = 2; }
    else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; extra = 3; }
    else { (*pos)++; return c; }
    if (*pos + extra >= end) { (*pos)++; return c; }
    for (int k = 1; k <= extra; k++) {
        unsigned char b = (unsigned char)s[*pos + k];
        if ((b & 0xC0) != 0x80) { (*pos)++; return c; }
        cp = (cp << 6) | (b & 0x3F);
    }
    *pos += 1 + extra;
    return cp;
}

vector<CharOp> word_diff(const string& a, const string& b) {
    vector<Token> ta = split_words(a);
    vector<Token> tb = split_words(b);
    int na = (int)ta.size(), nb = (int)tb.size();

    /* LCS at token level */
    vector<vector<int>> dp(na + 1, vector<int>(nb + 1, 0));
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++)
            dp[i][j] = token_eq(a, ta[i-1], b, tb[j-1]) ? dp[i-1][j-1] + 1
                       : max(dp[i-1][j], dp[i][j-1]);

    /* Backtrack at token level, collecting (type, is_a, tok_idx) in reverse. */
    struct TokenOp { OpType type; int is_a; int tok_idx; };
    vector<TokenOp> tops;
    tops.reserve(na + nb);
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && token_eq(a, ta[i-1], b, tb[j-1])) {
            tops.push_back({OP_KEEP, 1, i - 1}); i--; j--;
        } else if (j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j])) {
            tops.push_back({OP_INSERT, 0, j - 1}); j--;
        } else {
            tops.push_back({OP_DELETE, 1, i - 1}); i--;
        }
    }
    /* Reverse token ops so chars within each token are in forward order. */
    reverse(tops.begin(), tops.end());

    /* Expand each token to char ops (UTF-8 code points). */
    vector<CharOp> ops;
    ops.reserve(a.size() + b.size());
    for (auto& top : tops) {
        const string& text = top.is_a ? a : b;
        const Token& tok = top.is_a ? ta[top.tok_idx] : tb[top.tok_idx];
        int pos = tok.start;
        int end = tok.start + tok.len;
        while (pos < end) {
            int cp = utf8_decode_at(text, end, &pos);
            if (cp < 0) break;
            ops.push_back({top.type, cp});
        }
    }
    return ops;
}

/* Strip leading whitespace (spaces and tabs) from a line.
 * Used by --indent-aware so lines that differ only in indentation are
 * treated as "keep" at the line level. */
string normalize_indent(const string& line) {
    int start = 0;
    while (start < (int)line.size() && (line[start] == ' ' || line[start] == '\t')) start++;
    return line.substr(start);
}

int main(int argc, char** argv) {
    auto t_start = Clock::now();

    const char* alg_env = getenv("DIFFVIM_ALGORITHM");
    string algorithm = (alg_env && *alg_env) ? string(alg_env) : "lcs";
    const char* sem_env = getenv("DIFFVIM_SEMANTIC_CLEANUP");
    bool do_semantic = sem_env && sem_env[0] == '1';
    const char* wd_env = getenv("DIFFVIM_WORD_DIFF");
    bool do_word_diff = wd_env && wd_env[0] == '1';
    const char* ia_env = getenv("DIFFVIM_INDENT_AWARE");
    bool do_indent_aware = ia_env && ia_env[0] == '1';
    const char* opt_env = getenv("DIFFVIM_OPTIMIZE_SEQUENCE");
    bool do_optimize = !opt_env || opt_env[0] != '0';  /* default on */
    const char* l2r_env = getenv("DIFFVIM_LEFT_TO_RIGHT");
    bool do_l2r = l2r_env && l2r_env[0] == '1';

    /* Parse args:
     *   Two-file mode: <oldfile> <newfile> <outputfile> [options]
     *   Diff mode:     --diff <patchfile> <outputfile> [options]
     * Options: --algorithm lcs|myers|patience, --semantic-cleanup,
     *          --word-diff, --indent-aware. May appear in any position. */
    bool diff_mode = false;
    vector<string> positionals;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--algorithm") == 0 && i + 1 < argc) {
            algorithm = argv[++i];
        } else if (strcmp(argv[i], "--semantic-cleanup") == 0) {
            do_semantic = true;
        } else if (strcmp(argv[i], "--word-diff") == 0) {
            do_word_diff = true;
        } else if (strcmp(argv[i], "--indent-aware") == 0) {
            do_indent_aware = true;
        } else if (strcmp(argv[i], "--optimize-sequence") == 0) {
            do_optimize = true;
        } else if (strcmp(argv[i], "--no-optimize-sequence") == 0) {
            do_optimize = false;
        } else if (strcmp(argv[i], "--left-to-right") == 0) {
            do_l2r = true;
        } else if (strcmp(argv[i], "--diff") == 0) {
            diff_mode = true;
        } else {
            positionals.push_back(argv[i]);
        }
    }

    string oldfile, newfile, outfile, diff_file;
    if (diff_mode) {
        if (positionals.size() < 2) {
            fprintf(stderr, "Usage: %s --diff <patchfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", argv[0]);
            fprintf(stderr, "   or: %s --diff - <outputfile> [options]   (read diff from stdin)\n", argv[0]);
            return 1;
        }
        diff_file = positionals[0];
        outfile = positionals[1];
    } else {
        if (positionals.size() < 3) {
            fprintf(stderr, "Usage: %s <oldfile> <newfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]\n", argv[0]);
            fprintf(stderr, "   or: %s --diff <patchfile> <outputfile> [options]\n", argv[0]);
            return 1;
        }
        oldfile = positionals[0];
        newfile = positionals[1];
        outfile = positionals[2];
    }

    auto t_read_start = Clock::now();
    vector<string> old_lines, new_lines;
    if (diff_mode) {
        if (!parse_unified_diff(diff_file, old_lines, new_lines)) {
            fprintf(stderr, "Error: cannot read diff file %s\n", diff_file.c_str());
            return 1;
        }
    } else {
        old_lines = read_lines(oldfile);
        new_lines = read_lines(newfile);
    }
    auto t_read_end = Clock::now();

    if (old_lines.empty() && new_lines.empty()) {
        fprintf(stderr, "Error: both files empty or unreadable\n");
        return 1;
    }

    /* If indent_aware, build normalized copies of the lines for the line-level
     * diff. The indices returned by compute_line_diff are the same (since
     * normalization doesn't change line count), so we can use them to access
     * the ORIGINAL (non-normalized) lines when building hunk text. */
    vector<string> old_norm, new_norm;
    if (do_indent_aware) {
        old_norm.reserve(old_lines.size());
        new_norm.reserve(new_lines.size());
        for (auto& l : old_lines) old_norm.push_back(normalize_indent(l));
        for (auto& l : new_lines) new_norm.push_back(normalize_indent(l));
    }
    const vector<string>& line_a = do_indent_aware ? old_norm : old_lines;
    const vector<string>& line_b = do_indent_aware ? new_norm : new_lines;

    auto t_diff_start = Clock::now();
    auto lops = compute_line_diff(line_a, line_b, algorithm);

    vector<Hunk> hunks;
    int old_pos = 1;
    for (int i = 0; i < (int)lops.size(); i++) {
        if (lops[i].type == OP_KEEP) {
            old_pos = lops[i].a_idx + 2;
        } else {
            int start = i;
            while (i < (int)lops.size() && lops[i].type != OP_KEEP) i++;
            int end = i;
            i--;

            Hunk h;
            h.target_line = old_pos;
            h.deleted_count = 0;
            h.inserted_count = 0;
            h.is_end_insert = 0;
            h.is_end_delete = 0;

            string old_text, new_text;
            for (int k = start; k < end; k++) {
                if (lops[k].type == OP_DELETE) {
                    if (h.deleted_count > 0) old_text += '\n';
                    old_text += old_lines[lops[k].a_idx];
                    h.deleted_count++;
                    old_pos = lops[k].a_idx + 2;
                } else if (lops[k].type == OP_INSERT) {
                    if (h.inserted_count > 0) new_text += '\n';
                    new_text += new_lines[lops[k].b_idx];
                    h.inserted_count++;
                }
            }

            if (h.deleted_count == 0) {
                old_text.clear();
                if (old_lines.empty()) {
                    /* no separator needed */
                } else if (h.target_line > (int)old_lines.size()) {
                    new_text = "\n" + new_text;
                    h.is_end_insert = 1;
                } else {
                    new_text += "\n";
                }
            } else if (h.inserted_count == 0) {
                new_text.clear();
                if (h.target_line + h.deleted_count - 1 >= (int)old_lines.size()) {
                    old_text = "\n" + old_text;
                    h.is_end_delete = 1;
                } else {
                    old_text += "\n";
                }
            }

            h.char_ops = do_word_diff ? word_diff(old_text, new_text) : char_diff(old_text, new_text);
            if (do_semantic) {
                h.char_ops = semantic_cleanup(move(h.char_ops));
            }
            if (do_optimize) {
                h.char_ops = optimize_sequence(move(h.char_ops));
            }
            if (do_l2r) {
                h.char_ops = left_to_right(move(h.char_ops));
            }
            hunks.push_back(move(h));
        }
    }
    auto t_diff_end = Clock::now();

    auto t_write_start = Clock::now();
    ofstream out(outfile, ios::binary);
    if (!out) { fprintf(stderr, "Cannot write %s\n", outfile.c_str()); return 1; }
    out << "# diffvim precomputed diff v1\n";
    out << "# algorithm " << algorithm << "\n";
    out << "# semantic_cleanup " << (do_semantic ? 1 : 0) << "\n";
    out << "# word_diff " << (do_word_diff ? 1 : 0) << "\n";
    out << "# indent_aware " << (do_indent_aware ? 1 : 0) << "\n";
    out << "# optimize_sequence " << (do_optimize ? 1 : 0) << "\n";
    out << "# left_to_right " << (do_l2r ? 1 : 0) << "\n";
    out << "# hunk_count " << hunks.size() << "\n";
    for (auto& h : hunks) {
        out << "HUNK " << h.target_line << " " << h.deleted_count << " "
            << h.inserted_count << " " << h.is_end_insert << " " << h.is_end_delete << "\n";
        for (auto& op : h.char_ops) {
            const char* type = op.type == OP_KEEP ? "keep" :
                               op.type == OP_DELETE ? "delete" : "insert";
            out << type << " " << op.code << "\n";
        }
    }
    out.close();
    auto t_write_end = Clock::now();

    fprintf(stderr, "compute: %.2f ms (read %.2f + diff %.2f + write %.2f)\n",
            ms_diff(t_start, t_write_end),
            ms_diff(t_read_start, t_read_end),
            ms_diff(t_diff_start, t_diff_end),
            ms_diff(t_write_start, t_write_end));
    fprintf(stderr, "startup: %.2f ms\n", ms_diff(t_start, t_read_start));
    fprintf(stderr, "hunks: %zu, lines: %zu -> %zu\n",
            hunks.size(), old_lines.size(), new_lines.size());
    return 0;
}
