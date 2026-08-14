// diffvim-compute.rs — External diff computer for diffvim (Rust version).
//
// Reads two files, computes line-level + char-level diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Supports three line-diff algorithms (lcs, myers, patience) selected
// via --algorithm or DIFFVIM_ALGORITHM, and optional semantic cleanup
// of char-level diffs via --semantic-cleanup or DIFFVIM_SEMANTIC_CLEANUP.
//
// Build: make rust
// Usage: diffvim-compute-rust <oldfile> <newfile> <outputfile>
//                            [--algorithm lcs|myers|patience] [--semantic-cleanup]
//
// Timing is printed to stderr.

use std::env;
use std::fs;
use std::io::Read;
use std::io::Write;
use std::time::Instant;

#[derive(Clone, Copy, PartialEq)]
enum OpType { Keep, Delete, Insert }

#[derive(Clone)]
struct LineOp { typ: OpType, a_idx: usize, b_idx: usize }
#[derive(Clone)]
struct CharOp { typ: OpType, code: u32 }  // Unicode code point

struct Hunk {
    target_line: usize,
    deleted_count: usize,
    inserted_count: usize,
    is_end_insert: bool,
    is_end_delete: bool,
    char_ops: Vec<CharOp>,
}

fn read_lines(path: &str) -> Vec<String> {
    let content = match fs::read_to_string(path) { Ok(c) => c, Err(_) => return vec![] };
    let mut lines = Vec::new();
    let mut start = 0;
    let bytes = content.as_bytes();
    for i in 0..=bytes.len() {
        if i == bytes.len() || bytes[i] == b'\n' {
            let len = i - start;
            // If at end of buffer and last char was newline, don't emit
            // trailing empty line — matches vim's readfile().
            if i == bytes.len() && len == 0 && !lines.is_empty() { break; }
            lines.push(content[start..i].to_string());
            start = i + 1;
        }
    }
    lines
}

/* Read an entire file (or stdin if path is "-") into a String.
 * Returns Err on file open error. */
fn read_file_or_stdin(path: &str) -> Result<String, String> {
    if path == "-" {
        let mut s = String::new();
        std::io::stdin().read_to_string(&mut s).map_err(|e| e.to_string())?;
        Ok(s)
    } else {
        fs::read_to_string(path).map_err(|e| e.to_string())
    }
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
 * Returns Ok((old_lines, new_lines)) on success, Err on read error. */
fn parse_unified_diff(path: &str) -> Result<(Vec<String>, Vec<String>), String> {
    let content = read_file_or_stdin(path)?;
    let bytes = content.as_bytes();
    let mut old_lines: Vec<String> = Vec::new();
    let mut new_lines: Vec<String> = Vec::new();
    let mut start = 0;
    for i in 0..=bytes.len() {
        if i == bytes.len() || bytes[i] == b'\n' {
            let len = i - start;
            /* Skip a trailing empty line (matches vim's readfile()). */
            if i == bytes.len() && len == 0 { break; }

            if len == 0 {
                /* Empty line in the diff = empty context line in both files. */
                old_lines.push(String::new());
                new_lines.push(String::new());
            } else if len >= 3 && &bytes[start..start + 3] == b"---" {
                /* old file header — ignore */
            } else if len >= 3 && &bytes[start..start + 3] == b"+++" {
                /* new file header — ignore */
            } else if len >= 2 && &bytes[start..start + 2] == b"@@" {
                /* hunk header — ignore */
            } else if bytes[start] == b'\\' {
                /* metadata — ignore */
            } else if bytes[start] == b'-' {
                /* delete line — strip leading '-' */
                old_lines.push(content[start + 1..i].to_string());
            } else if bytes[start] == b'+' {
                /* insert line — strip leading '+' */
                new_lines.push(content[start + 1..i].to_string());
            } else if bytes[start] == b' ' {
                /* context line — strip leading ' ', present in both */
                let s = content[start + 1..i].to_string();
                old_lines.push(s.clone());
                new_lines.push(s);
            }
            /* else: unrecognized line (e.g. "diff --git") — skip */

            start = i + 1;
        }
    }
    Ok((old_lines, new_lines))
}

/* Line-level LCS diff over a sub-range [a_start,a_end) x [b_start,b_end).
 * Produces ops with ABSOLUTE indices into a/b. */
fn line_diff_range(a: &[String], a_start: usize, a_end: usize,
                    b: &[String], b_start: usize, b_end: usize) -> Vec<LineOp> {
    let na = a_end - a_start;
    let nb = b_end - b_start;
    let mut dp = vec![vec![0usize; nb + 1]; na + 1];
    for i in 1..=na {
        for j in 1..=nb {
            if a[a_start + i - 1] == b[b_start + j - 1] {
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                dp[i][j] = dp[i-1][j].max(dp[i][j-1]);
            }
        }
    }
    let mut ops = Vec::new();
    let mut i = na;
    let mut j = nb;
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && a[a_start + i - 1] == b[b_start + j - 1] {
            ops.push(LineOp { typ: OpType::Keep, a_idx: a_start + i - 1, b_idx: b_start + j - 1 });
            i -= 1; j -= 1;
        } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
            ops.push(LineOp { typ: OpType::Insert, a_idx: 0, b_idx: b_start + j - 1 });
            j -= 1;
        } else {
            ops.push(LineOp { typ: OpType::Delete, a_idx: a_start + i - 1, b_idx: 0 });
            i -= 1;
        }
    }
    ops.reverse();
    ops
}

fn line_diff(a: &[String], b: &[String]) -> Vec<LineOp> {
    line_diff_range(a, 0, a.len(), b, 0, b.len())
}

/* --- Myers diff algorithm (O(ND)) --- */
/* Faster than LCS for small diffs. Falls back to LCS for very large N+M. */
fn myers_diff(a: &[String], b: &[String]) -> Vec<LineOp> {
    let na = a.len();
    let nb = b.len();
    if na + nb > 200000 {
        return line_diff(a, b);
    }
    let max = (na + nb) as i64;
    let na_i = na as i64;
    let nb_i = nb as i64;
    /* v indexed by (k + max); k ranges over [-max, max]. */
    let mut v: Vec<i64> = vec![0; (2 * max + 1) as usize];
    let idx = |k: i64| -> usize { (k + max) as usize };
    /* trace stores a copy of v at the start of each depth d. */
    let mut trace: Vec<Vec<i64>> = Vec::with_capacity((max + 1) as usize);

    for d in 0..=max {
        trace.push(v.clone());
        let mut k = -d;
        while k <= d {
            let x;
            if k == -d || (k != d && v[idx(k-1)] < v[idx(k+1)]) {
                x = v[idx(k+1)];
            } else {
                x = v[idx(k-1)] + 1;
            }
            let mut y = x - k;
            let mut xm = x;
            while xm < na_i && y < nb_i && a[xm as usize] == b[y as usize] {
                xm += 1;
                y += 1;
            }
            v[idx(k)] = xm;
            if xm >= na_i && y >= nb_i {
                /* Backtrack from (xm, y) at depth d. */
                let mut ops: Vec<LineOp> = Vec::with_capacity((d + na_i + nb_i) as usize);
                let mut cx = na_i;
                let mut cy = nb_i;
                for dd in (1..=d).rev() {
                    let vp = &trace[dd as usize];
                    let tv = |kk: i64| -> i64 { vp[idx(kk)] };
                    let kk = cx - cy;
                    let prev_x: i64;
                    let prev_y: i64;
                    let from_below: bool;
                    if kk == -dd {
                        from_below = true;
                    } else if kk == dd {
                        from_below = false;
                    } else {
                        from_below = tv(kk-1) < tv(kk+1);
                    }
                    if from_below {
                        prev_x = tv(kk+1);
                        prev_y = prev_x - (kk + 1);
                    } else {
                        prev_x = tv(kk-1) + 1;
                        prev_y = prev_x - (kk - 1);
                    }
                    /* Emit diagonal keeps from (cx,cy) back to (prev_x, prev_y). */
                    while cx > prev_x && cy > prev_y {
                        ops.push(LineOp {
                            typ: OpType::Keep,
                            a_idx: (cx - 1) as usize,
                            b_idx: (cy - 1) as usize,
                        });
                        cx -= 1;
                        cy -= 1;
                    }
                    /* The single non-diagonal step. */
                    if from_below {
                        ops.push(LineOp {
                            typ: OpType::Insert,
                            a_idx: 0,
                            b_idx: (cy - 1) as usize,
                        });
                        cy -= 1;
                    } else {
                        ops.push(LineOp {
                            typ: OpType::Delete,
                            a_idx: (cx - 1) as usize,
                            b_idx: 0,
                        });
                        cx -= 1;
                    }
                }
                /* Handle any diagonal keeps at the very start (depth 0). */
                while cx > 0 && cy > 0 {
                    ops.push(LineOp {
                        typ: OpType::Keep,
                        a_idx: (cx - 1) as usize,
                        b_idx: (cy - 1) as usize,
                    });
                    cx -= 1;
                    cy -= 1;
                }
                ops.reverse();
                return ops;
            }
            k += 2;
        }
    }
    /* Fallback */
    line_diff(a, b)
}

/* --- Patience diff algorithm --- */
/* Anchors on unique common lines, then recurses on the gaps. */

/* Find unique common lines between a[a_start..a_end) and b[b_start..b_end).
 * Returns matching (a_idx, b_idx) pairs (in increasing a_idx order, then
 * filtered to the LIS of b_idx) via out_a_idx / out_b_idx.
 * Returns the count. */
fn find_patience_anchors(a: &[String], a_start: usize, a_end: usize,
                          b: &[String], b_start: usize, b_end: usize,
                          out_a_idx: &mut Vec<usize>, out_b_idx: &mut Vec<usize>) -> usize {
    out_a_idx.clear();
    out_b_idx.clear();
    for i in a_start..a_end {
        /* Check if a[i] appears exactly once in a[a_start..a_end). */
        let mut a_count = 0usize;
        for k in a_start..a_end {
            if a[i] == a[k] { a_count += 1; }
        }
        if a_count != 1 { continue; }
        /* Find the unique match in b[b_start..b_end). */
        let mut b_match: usize = 0;
        let mut b_count = 0usize;
        for k in b_start..b_end {
            if a[i] == b[k] {
                b_match = k;
                b_count += 1;
            }
        }
        if b_count == 1 {
            out_a_idx.push(i);
            out_b_idx.push(b_match);
        }
    }
    let count = out_a_idx.len();
    if count <= 1 { return count; }
    /* LIS of b_idx via patience sorting. */
    let mut lis_prev: Vec<i64> = vec![0; count];
    let mut lis_tail_idx: Vec<usize> = vec![0; count];
    let mut lis_len: usize = 0;
    for i in 0..count {
        let mut lo: usize = 0;
        let mut hi: usize = lis_len;
        while lo < hi {
            let mid = (lo + hi) / 2;
            if out_b_idx[lis_tail_idx[mid]] < out_b_idx[i] {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        lis_prev[i] = if lo > 0 { lis_tail_idx[lo - 1] as i64 } else { -1 };
        if lo == lis_len {
            lis_tail_idx[lis_len] = i;
            lis_len += 1;
        } else {
            lis_tail_idx[lo] = i;
        }
    }
    /* Reconstruct LIS. */
    let mut keep_a: Vec<usize> = vec![0; lis_len];
    let mut keep_b: Vec<usize> = vec![0; lis_len];
    let mut idx_i: i64 = lis_tail_idx[lis_len - 1] as i64;
    for i in (0..lis_len).rev() {
        let u = idx_i as usize;
        keep_a[i] = out_a_idx[u];
        keep_b[i] = out_b_idx[u];
        idx_i = lis_prev[u];
    }
    *out_a_idx = keep_a;
    *out_b_idx = keep_b;
    lis_len
}

fn patience_diff_range(a: &[String], a_start: usize, a_end: usize,
                        b: &[String], b_start: usize, b_end: usize) -> Vec<LineOp> {
    let na = a_end - a_start;
    let nb = b_end - b_start;
    let mut ops: Vec<LineOp> = Vec::new();

    if na == 0 && nb == 0 {
        return ops;
    }
    if na == 0 {
        for j in 0..nb {
            ops.push(LineOp { typ: OpType::Insert, a_idx: 0, b_idx: b_start + j });
        }
        return ops;
    }
    if nb == 0 {
        for i in 0..na {
            ops.push(LineOp { typ: OpType::Delete, a_idx: a_start + i, b_idx: 0 });
        }
        return ops;
    }

    /* Find patience anchors. */
    let mut anchor_a: Vec<usize> = Vec::new();
    let mut anchor_b: Vec<usize> = Vec::new();
    let n_anchors = find_patience_anchors(a, a_start, a_end, b, b_start, b_end,
                                           &mut anchor_a, &mut anchor_b);

    if n_anchors == 0 {
        /* No unique common lines — fall back to LCS for this range. */
        return line_diff_range(a, a_start, a_end, b, b_start, b_end);
    }

    /* Diff the gaps between anchors. */
    let mut prev_a = a_start;
    let mut prev_b = b_start;
    for k in 0..=n_anchors {
        let cur_a = if k < n_anchors { anchor_a[k] } else { a_end };
        let cur_b = if k < n_anchors { anchor_b[k] } else { b_end };
        if cur_a > prev_a || cur_b > prev_b {
            let sub_ops = patience_diff_range(a, prev_a, cur_a, b, prev_b, cur_b);
            ops.extend(sub_ops);
        }
        if k < n_anchors {
            ops.push(LineOp { typ: OpType::Keep, a_idx: anchor_a[k], b_idx: anchor_b[k] });
            prev_a = anchor_a[k] + 1;
            prev_b = anchor_b[k] + 1;
        }
    }
    ops
}

fn patience_diff(a: &[String], b: &[String]) -> Vec<LineOp> {
    patience_diff_range(a, 0, a.len(), b, 0, b.len())
}

/* --- Diff dispatcher --- */
fn compute_line_diff(a: &[String], b: &[String], algorithm: &str) -> Vec<LineOp> {
    match algorithm {
        "myers" => myers_diff(a, b),
        "patience" => patience_diff(a, b),
        _ => line_diff(a, b),
    }
}

fn char_diff(a: &str, b: &str) -> Vec<CharOp> {
    // Use Unicode code points (not bytes) for char-level diff.
    // This matches vim's split(str, '\zs') behavior.
    let ac: Vec<u32> = a.chars().map(|c| c as u32).collect();
    let bc: Vec<u32> = b.chars().map(|c| c as u32).collect();
    let na = ac.len();
    let nb = bc.len();
    let mut dp = vec![vec![0usize; nb + 1]; na + 1];
    for i in 1..=na {
        for j in 1..=nb {
            if ac[i-1] == bc[j-1] {
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                dp[i][j] = dp[i-1][j].max(dp[i][j-1]);
            }
        }
    }
    let mut ops = Vec::new();
    let mut i = na;
    let mut j = nb;
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && ac[i-1] == bc[j-1] {
            ops.push(CharOp { typ: OpType::Keep, code: ac[i-1] });
            i -= 1; j -= 1;
        } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
            ops.push(CharOp { typ: OpType::Insert, code: bc[j-1] });
            j -= 1;
        } else {
            ops.push(CharOp { typ: OpType::Delete, code: ac[i-1] });
            i -= 1;
        }
    }
    ops.reverse();
    ops
}

/* --- Semantic cleanup: merge adjacent delete+insert pairs that cancel --- */
fn semantic_cleanup(ops: Vec<CharOp>) -> Vec<CharOp> {
    if ops.len() < 2 { return ops; }
    let mut out: Vec<CharOp> = Vec::with_capacity(ops.len());
    let mut i = 0;
    while i < ops.len() {
        if i + 1 < ops.len() {
            /* delete X followed by insert X -> keep X */
            if ops[i].typ == OpType::Delete && ops[i+1].typ == OpType::Insert && ops[i].code == ops[i+1].code {
                out.push(CharOp { typ: OpType::Keep, code: ops[i].code });
                i += 2;
                continue;
            }
            /* insert X followed by delete X -> keep X */
            if ops[i].typ == OpType::Insert && ops[i+1].typ == OpType::Delete && ops[i].code == ops[i+1].code {
                out.push(CharOp { typ: OpType::Keep, code: ops[i].code });
                i += 2;
                continue;
            }
        }
        out.push(ops[i].clone());
        i += 1;
    }
    out
}

/* --- Op-sequence optimization: consolidate interleaved del/ins --- */
fn optimize_sequence(ops: Vec<CharOp>) -> Vec<CharOp> {
    if ops.len() < 4 { return ops; }
    let mut out: Vec<CharOp> = Vec::with_capacity(ops.len());
    let mut i = 0;
    while i < ops.len() {
        if ops[i].typ != OpType::Keep && ops[i].code != 10 {
            while i < ops.len() {
                if ops[i].typ == OpType::Keep { break; }
                if ops[i].code == 10 { break; }
                out.push(ops[i].clone());
                i += 1;
            }
        } else {
            out.push(ops[i].clone());
            i += 1;
        }
    }
    out
}

/* --- Left-to-right: sort ops within each line by type --- */
fn left_to_right(ops: Vec<CharOp>) -> Vec<CharOp> {
    if ops.len() < 2 { return ops; }
    let mut out: Vec<CharOp> = Vec::with_capacity(ops.len());
    let mut i = 0;
    while i < ops.len() {
        let line_start = i;
        while i < ops.len() && ops[i].code != 10 { i += 1; }
        let line_end = i;
        for k in line_start..line_end {
            if ops[k].typ == OpType::Keep { out.push(ops[k].clone()); }
        }
        for k in line_start..line_end {
            if ops[k].typ == OpType::Delete { out.push(ops[k].clone()); }
        }
        for k in line_start..line_end {
            if ops[k].typ == OpType::Insert { out.push(ops[k].clone()); }
        }
        if i < ops.len() { out.push(ops[i].clone()); i += 1; }
    }
    out
}

/* --- Word-level diff --- */
/* Splits text into tokens (maximal runs of non-whitespace + maximal runs of
 * whitespace), runs LCS at the token level, then expands each token to
 * individual char ops. Produces more natural typing patterns than char-level
 * LCS because consecutive chars within a word are grouped.
 *
 * Matches vimscript s:WordDiff + s:SplitWords. */

fn is_ws_byte(c: u8) -> bool {
    /* Vim's \s matches [ \t\n\r\f\v] */
    c == b' ' || c == b'\t' || c == b'\n' || c == b'\r' || c == 0x0B || c == 0x0C
}

/* Token: byte offset + length into the source string. */
#[derive(Clone, Copy)]
struct Token { start: usize, len: usize }

/* Split text into tokens: maximal runs of whitespace OR maximal runs of
 * non-whitespace. E.g. "hello world" -> ["hello", " ", "world"]. */
fn split_words(text: &str) -> Vec<Token> {
    let bytes = text.as_bytes();
    let len = bytes.len();
    let mut toks: Vec<Token> = Vec::new();
    let mut i = 0;
    while i < len {
        let start = i;
        if is_ws_byte(bytes[i]) {
            while i < len && is_ws_byte(bytes[i]) { i += 1; }
        } else {
            while i < len && !is_ws_byte(bytes[i]) { i += 1; }
        }
        toks.push(Token { start, len: i - start });
    }
    toks
}

fn token_eq(a: &[u8], ta: &Token, b: &[u8], tb: &Token) -> bool {
    ta.len == tb.len && a[ta.start..ta.start + ta.len] == b[tb.start..tb.start + tb.len]
}

fn word_diff(a: &str, b: &str) -> Vec<CharOp> {
    let ab = a.as_bytes();
    let bb = b.as_bytes();
    let ta = split_words(a);
    let tb = split_words(b);
    let na = ta.len();
    let nb = tb.len();

    /* LCS at token level */
    let mut dp = vec![vec![0usize; nb + 1]; na + 1];
    for i in 1..=na {
        for j in 1..=nb {
            if token_eq(ab, &ta[i-1], bb, &tb[j-1]) {
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                dp[i][j] = dp[i-1][j].max(dp[i][j-1]);
            }
        }
    }

    /* Backtrack at token level, collecting (type, is_a, tok_idx) in reverse. */
    #[derive(Clone, Copy)]
    struct TokenOp { typ: OpType, is_a: bool, tok_idx: usize }
    let mut tops: Vec<TokenOp> = Vec::with_capacity(na + nb);
    let mut i = na;
    let mut j = nb;
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && token_eq(ab, &ta[i-1], bb, &tb[j-1]) {
            tops.push(TokenOp { typ: OpType::Keep, is_a: true, tok_idx: i - 1 });
            i -= 1; j -= 1;
        } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
            tops.push(TokenOp { typ: OpType::Insert, is_a: false, tok_idx: j - 1 });
            j -= 1;
        } else {
            tops.push(TokenOp { typ: OpType::Delete, is_a: true, tok_idx: i - 1 });
            i -= 1;
        }
    }
    /* Reverse token ops so chars within each token are in forward order. */
    tops.reverse();

    /* Expand each token to char ops (Unicode code points).
     * We decode the token's byte slice as UTF-8. Rust's str::chars() does
     * the right thing for valid UTF-8; for invalid bytes we fall back to
     * the raw byte value, matching the C implementation. */
    let mut ops: Vec<CharOp> = Vec::with_capacity(a.len() + b.len());
    for top in &tops {
        let text_bytes = if top.is_a { ab } else { bb };
        let tok = if top.is_a { &ta[top.tok_idx] } else { &tb[top.tok_idx] };
        let slice = &text_bytes[tok.start..tok.start + tok.len];
        /* Decode UTF-8 code points from the slice. For invalid sequences,
         * emit the raw byte as a code point (matching C's utf8_decode). */
        let mut pos = 0;
        while pos < slice.len() {
            let c = slice[pos];
            let (cp, advance) = if c < 0x80 {
                (c as u32, 1)
            } else if (c & 0xE0) == 0xC0 && pos + 1 < slice.len() && (slice[pos+1] & 0xC0) == 0x80 {
                (((c as u32 & 0x1F) << 6) | (slice[pos+1] as u32 & 0x3F), 2)
            } else if (c & 0xF0) == 0xE0 && pos + 2 < slice.len()
                && (slice[pos+1] & 0xC0) == 0x80 && (slice[pos+2] & 0xC0) == 0x80 {
                (((c as u32 & 0x0F) << 12) | ((slice[pos+1] as u32 & 0x3F) << 6) | (slice[pos+2] as u32 & 0x3F), 3)
            } else if (c & 0xF8) == 0xF0 && pos + 3 < slice.len()
                && (slice[pos+1] & 0xC0) == 0x80 && (slice[pos+2] & 0xC0) == 0x80 && (slice[pos+3] & 0xC0) == 0x80 {
                (((c as u32 & 0x07) << 18) | ((slice[pos+1] as u32 & 0x3F) << 12)
                 | ((slice[pos+2] as u32 & 0x3F) << 6) | (slice[pos+3] as u32 & 0x3F), 4)
            } else {
                (c as u32, 1)  /* invalid, treat as single byte */
            };
            ops.push(CharOp { typ: top.typ, code: cp });
            pos += advance;
        }
    }
    ops
}

/* Strip leading whitespace (spaces and tabs) from a line.
 * Used by --indent-aware so lines that differ only in indentation are
 * treated as "keep" at the line level. */
fn normalize_indent(line: &str) -> String {
    let start = line.bytes().position(|b| b != b' ' && b != b'\t').unwrap_or(line.len());
    line[start..].to_string()
}

fn main() {
    let t_start = Instant::now();
    let args: Vec<String> = env::args().collect();

    let mut algorithm = env::var("DIFFVIM_ALGORITHM").unwrap_or_default();
    if algorithm.is_empty() { algorithm = "lcs".to_string(); }
    let mut do_semantic = env::var("DIFFVIM_SEMANTIC_CLEANUP")
        .map(|v| v.starts_with('1'))
        .unwrap_or(false);
    let mut do_word_diff = env::var("DIFFVIM_WORD_DIFF")
        .map(|v| v.starts_with('1'))
        .unwrap_or(false);
    let mut do_indent_aware = env::var("DIFFVIM_INDENT_AWARE")
        .map(|v| v.starts_with('1'))
        .unwrap_or(false);
    let mut do_optimize = env::var("DIFFVIM_OPTIMIZE_SEQUENCE")
        .map(|v| !v.starts_with('0'))
        .unwrap_or(true);  /* default on */
    let mut do_l2r = env::var("DIFFVIM_LEFT_TO_RIGHT")
        .map(|v| v.starts_with('1'))
        .unwrap_or(false);

    /* Parse args:
     *   Two-file mode: <oldfile> <newfile> <outputfile> [options]
     *   Diff mode:     --diff <patchfile> <outputfile> [options]
     * Options: --algorithm lcs|myers|patience, --semantic-cleanup,
     *          --word-diff, --indent-aware. May appear in any position. */
    let mut diff_mode = false;
    let mut positionals: Vec<String> = Vec::new();
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--algorithm" && i + 1 < args.len() {
            algorithm = args[i + 1].clone();
            i += 2;
        } else if args[i] == "--semantic-cleanup" {
            do_semantic = true;
            i += 1;
        } else if args[i] == "--word-diff" {
            do_word_diff = true;
            i += 1;
        } else if args[i] == "--indent-aware" {
            do_indent_aware = true;
            i += 1;
        } else if args[i] == "--optimize-sequence" {
            do_optimize = true;
            i += 1;
        } else if args[i] == "--no-optimize-sequence" {
            do_optimize = false;
            i += 1;
        } else if args[i] == "--left-to-right" {
            do_l2r = true;
            i += 1;
        } else if args[i] == "--diff" {
            diff_mode = true;
            i += 1;
        } else {
            positionals.push(args[i].clone());
            i += 1;
        }
    }

    let t_read_start = Instant::now();
    let (old_lines, new_lines, outfile) = if diff_mode {
        if positionals.len() < 2 {
            eprintln!("Usage: {} --diff <patchfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]", args[0]);
            eprintln!("   or: {} --diff - <outputfile> [options]   (read diff from stdin)", args[0]);
            std::process::exit(1);
        }
        let diff_file = positionals[0].clone();
        let outfile = positionals[1].clone();
        let (old, new) = match parse_unified_diff(&diff_file) {
            Ok(pair) => pair,
            Err(e) => {
                eprintln!("Error: cannot read diff file {}: {}", diff_file, e);
                std::process::exit(1);
            }
        };
        (old, new, outfile)
    } else {
        if positionals.len() < 3 {
            eprintln!("Usage: {} <oldfile> <newfile> <outputfile> [--algorithm lcs|myers|patience] [--semantic-cleanup] [--word-diff] [--indent-aware]", args[0]);
            eprintln!("   or: {} --diff <patchfile> <outputfile> [options]", args[0]);
            std::process::exit(1);
        }
        let oldfile = positionals[0].clone();
        let newfile = positionals[1].clone();
        let outfile = positionals[2].clone();
        let old = read_lines(&oldfile);
        let new = read_lines(&newfile);
        (old, new, outfile)
    };

    let t_read_end = Instant::now();

    if old_lines.is_empty() && new_lines.is_empty() {
        eprintln!("Error: both files empty or unreadable");
        std::process::exit(1);
    }

    /* If indent_aware, build normalized copies of the lines for the line-level
     * diff. The indices returned by compute_line_diff are the same (since
     * normalization doesn't change line count), so we can use them to access
     * the ORIGINAL (non-normalized) lines when building hunk text. */
    let old_norm: Vec<String>;
    let new_norm: Vec<String>;
    let (line_a, line_b): (Vec<String>, Vec<String>) = if do_indent_aware {
        old_norm = old_lines.iter().map(|l| normalize_indent(l)).collect();
        new_norm = new_lines.iter().map(|l| normalize_indent(l)).collect();
        (old_norm, new_norm)
    } else {
        (old_lines.clone(), new_lines.clone())
    };

    let t_diff_start = Instant::now();
    let lops = compute_line_diff(&line_a, &line_b, &algorithm);

    let mut hunks: Vec<Hunk> = Vec::new();
    let mut old_pos: usize = 1;
    let mut i = 0;
    while i < lops.len() {
        if lops[i].typ == OpType::Keep {
            old_pos = lops[i].a_idx + 2;
            i += 1;
        } else {
            let start = i;
            while i < lops.len() && lops[i].typ != OpType::Keep { i += 1; }
            let end = i;

            let mut h = Hunk {
                target_line: old_pos,
                deleted_count: 0,
                inserted_count: 0,
                is_end_insert: false,
                is_end_delete: false,
                char_ops: Vec::new(),
            };
            let mut old_text = String::new();
            let mut new_text = String::new();
            for k in start..end {
                match lops[k].typ {
                    OpType::Delete => {
                        if h.deleted_count > 0 { old_text.push('\n'); }
                        old_text.push_str(&old_lines[lops[k].a_idx]);
                        h.deleted_count += 1;
                        old_pos = lops[k].a_idx + 2;
                    }
                    OpType::Insert => {
                        if h.inserted_count > 0 { new_text.push('\n'); }
                        new_text.push_str(&new_lines[lops[k].b_idx]);
                        h.inserted_count += 1;
                    }
                    _ => {}
                }
            }
            if h.deleted_count == 0 {
                old_text.clear();
                if old_lines.is_empty() {
                    /* no separator */
                } else if h.target_line > old_lines.len() {
                    new_text = format!("\n{}", new_text);
                    h.is_end_insert = true;
                } else {
                    new_text.push('\n');
                }
            } else if h.inserted_count == 0 {
                new_text.clear();
                if h.target_line + h.deleted_count - 1 >= old_lines.len() {
                    old_text = format!("\n{}", old_text);
                    h.is_end_delete = true;
                } else {
                    old_text.push('\n');
                }
            }
            h.char_ops = if do_word_diff { word_diff(&old_text, &new_text) } else { char_diff(&old_text, &new_text) };
            if do_semantic {
                h.char_ops = semantic_cleanup(h.char_ops);
            }
            if do_optimize {
                h.char_ops = optimize_sequence(h.char_ops);
            }
            if do_l2r {
                h.char_ops = left_to_right(h.char_ops);
            }
            hunks.push(h);
        }
    }
    let t_diff_end = Instant::now();

    let t_write_start = Instant::now();
    let mut out = match fs::File::create(&outfile) {
        Ok(f) => f,
        Err(e) => { eprintln!("Cannot write {}: {}", outfile, e); std::process::exit(1); }
    };
    writeln!(out, "# diffvim precomputed diff v1").unwrap();
    writeln!(out, "# algorithm {}", algorithm).unwrap();
    writeln!(out, "# semantic_cleanup {}", if do_semantic { 1 } else { 0 }).unwrap();
    writeln!(out, "# word_diff {}", if do_word_diff { 1 } else { 0 }).unwrap();
    writeln!(out, "# indent_aware {}", if do_indent_aware { 1 } else { 0 }).unwrap();
    writeln!(out, "# optimize_sequence {}", if do_optimize { 1 } else { 0 }).unwrap();
    writeln!(out, "# left_to_right {}", if do_l2r { 1 } else { 0 }).unwrap();
    writeln!(out, "# hunk_count {}", hunks.len()).unwrap();
    for h in &hunks {
        write!(out, "HUNK {} {} {} {} {}\n",
               h.target_line, h.deleted_count, h.inserted_count,
               if h.is_end_insert { 1 } else { 0 },
               if h.is_end_delete { 1 } else { 0 }).unwrap();
        for op in &h.char_ops {
            let typ = match op.typ {
                OpType::Keep => "keep",
                OpType::Delete => "delete",
                OpType::Insert => "insert",
            };
            writeln!(out, "{} {}", typ, op.code).unwrap();
        }
    }
    let t_write_end = Instant::now();

    eprintln!("compute: {:.2} ms (read {:.2} + diff {:.2} + write {:.2})",
              t_start.elapsed().as_secs_f64() * 1000.0,
              (t_read_end - t_read_start).as_secs_f64() * 1000.0,
              (t_diff_end - t_diff_start).as_secs_f64() * 1000.0,
              (t_write_end - t_write_start).as_secs_f64() * 1000.0);
    eprintln!("startup: {:.2} ms",
              t_read_start.duration_since(t_start).as_secs_f64() * 1000.0);
    eprintln!("hunks: {}, lines: {} -> {}",
              hunks.len(), old_lines.len(), new_lines.len());
}
