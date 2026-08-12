// diffvim-compute.rs — External diff computer for diffvim (Rust version).
//
// Reads two files, computes line-level + char-level LCS diff, and writes
// the result in a format that `diffvim --precomputed FILE` can consume.
//
// Build: make rust
// Usage: diffvim-compute-rust <oldfile> <newfile> <outputfile>
//
// Timing is printed to stderr.

use std::env;
use std::fs;
use std::io::Write;
use std::time::Instant;

#[derive(Clone, Copy, PartialEq)]
enum OpType { Keep, Delete, Insert }

struct LineOp { typ: OpType, a_idx: usize, b_idx: usize }
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

fn line_diff(a: &[String], b: &[String]) -> Vec<LineOp> {
    let na = a.len();
    let nb = b.len();
    let mut dp = vec![vec![0usize; nb + 1]; na + 1];
    for i in 1..=na {
        for j in 1..=nb {
            if a[i-1] == b[j-1] {
                dp[i][j] = dp[i-1][j-1] + 1;
            } else {
                dp[i][j] = dp[i-1][j].max(dp[i][j-1]);
            }
        }
    }
    let mut ops = Vec::new();
    let mut i = na; let mut j = nb;
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && a[i-1] == b[j-1] {
            ops.push(LineOp { typ: OpType::Keep, a_idx: i-1, b_idx: j-1 });
            i -= 1; j -= 1;
        } else if j > 0 && (i == 0 || dp[i][j-1] >= dp[i-1][j]) {
            ops.push(LineOp { typ: OpType::Insert, a_idx: 0, b_idx: j-1 });
            j -= 1;
        } else {
            ops.push(LineOp { typ: OpType::Delete, a_idx: i-1, b_idx: 0 });
            i -= 1;
        }
    }
    ops.reverse();
    ops
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
    let mut i = na; let mut j = nb;
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

fn main() {
    let t_start = Instant::now();
    let args: Vec<String> = env::args().collect();
    if args.len() != 4 {
        eprintln!("Usage: {} <oldfile> <newfile> <outputfile>", args[0]);
        std::process::exit(1);
    }

    let t_read_start = Instant::now();
    let old_lines = read_lines(&args[1]);
    let new_lines = read_lines(&args[2]);
    let t_read_end = Instant::now();

    let t_diff_start = Instant::now();
    let lops = line_diff(&old_lines, &new_lines);

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
            h.char_ops = char_diff(&old_text, &new_text);
            hunks.push(h);
        }
    }
    let t_diff_end = Instant::now();

    let t_write_start = Instant::now();
    let mut out = match fs::File::create(&args[3]) {
        Ok(f) => f,
        Err(e) => { eprintln!("Cannot write {}: {}", args[3], e); std::process::exit(1); }
    };
    writeln!(out, "# diffvim precomputed diff v1").unwrap();
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
