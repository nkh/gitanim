// diffvim-compute.cpp — External diff computer for diffvim (C++ version).
//
// Reads two files, computes line-level + char-level LCS diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Build: make cpp
// Usage: diffvim-compute-cpp <oldfile> <newfile> <outputfile>
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

vector<LineOp> line_diff(const vector<string>& a, const vector<string>& b) {
    int na = a.size(), nb = b.size();
    vector<vector<int>> dp(na + 1, vector<int>(nb + 1, 0));
    for (int i = 1; i <= na; i++)
        for (int j = 1; j <= nb; j++)
            dp[i][j] = (a[i-1] == b[j-1]) ? dp[i-1][j-1] + 1
                       : max(dp[i-1][j], dp[i][j-1]);
    vector<LineOp> ops;
    int i = na, j = nb;
    while (i > 0 || j > 0) {
        if (i > 0 && j > 0 && a[i-1] == b[j-1]) {
            ops.push_back({OP_KEEP, i-1, j-1}); i--; j--;
        } else if (j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j])) {
            ops.push_back({OP_INSERT, -1, j-1}); j--;
        } else {
            ops.push_back({OP_DELETE, i-1, -1}); i--;
        }
    }
    reverse(ops.begin(), ops.end());
    return ops;
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

int main(int argc, char** argv) {
    auto t_start = Clock::now();
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <oldfile> <newfile> <outputfile>\n", argv[0]);
        return 1;
    }

    auto t_read_start = Clock::now();
    auto old_lines = read_lines(argv[1]);
    auto new_lines = read_lines(argv[2]);
    auto t_read_end = Clock::now();

    auto t_diff_start = Clock::now();
    auto lops = line_diff(old_lines, new_lines);

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

            h.char_ops = char_diff(old_text, new_text);
            hunks.push_back(move(h));
        }
    }
    auto t_diff_end = Clock::now();

    auto t_write_start = Clock::now();
    ofstream out(argv[3], ios::binary);
    if (!out) { fprintf(stderr, "Cannot write %s\n", argv[3]); return 1; }
    out << "# diffvim precomputed diff v1\n";
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
