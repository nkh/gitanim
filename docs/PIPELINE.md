# diffvim Pipeline Architecture

## Overview

diffvim animates a code diff — the transformation of an old file into a
new file — as if a human were typing it in real time. The pipeline has
four stages: compute, postprocess, pace, animate. Each stage transforms
the data closer to what the viewer sees on screen.

## Stage 1: Compute (diff)

**Input:** old file + new file
**Output:** ordered list of char-level ops (keep/delete/insert) grouped
into hunks.

**Tool:** `compute/bin/diffvim-compute-cpp` — the C++ implementation
(`compute/cpp/diffvim-compute.cpp`). When the C++ binary is missing,
`diffvim-pipeline` falls back to the pure-Perl
`compute/perl/compute_builtin.pl` (a wrapper around
`DiffVim::Parser::Perl::parse_diff`). Both paths emit the same op-stream
format.

**Algorithms:** two line-diff algorithms are supported:

1. **LCS** (Longest Common Subsequence) — dynamic programming,
   O(N×M) time and memory. Produces minimal diffs. Default.

2. **Patience** — uses anchor lines (unique longest matches) to divide
   and conquer. Produces more human-readable diffs for code with
   structural markers. Similar performance to LCS.

Myers was removed in the refactor: it OOMs on 15K-line files (O(N×M)
memory in our implementation) and produces the same op count as LCS.

**Timing (15K-line synthetic file, 549KB → 718KB):**

| Algorithm | C++ (ms) | Ops produced |
|-----------|----------|--------------|
| LCS       | 1585     | 1,034,143    |
| Patience  | 1687     | 1,034,143    |

LCS and Patience produce identical op counts on this file.

**Op format:**
```
# diffvim precomputed diff v1
# algorithm lcs
# hunk_count N
HUNK <target_line> <del_count> <ins_count> <is_end_insert> <is_end_delete>
keep <char_code>
delete <char_code>
insert <char_code>
...
```

Each hunk targets a specific line in the old file. `is_end_insert` and
`is_end_delete` flag hunks that append to or truncate the end of the file.
Char codes are Unicode code points (10 = newline).

## Stage 2: Postprocess

**Input:** raw char ops from compute
**Output:** reordered/transformed char ops, each carrying a `(line, col)`
position

**Tools:** `animator/bin/diffvim-postprocess` (C, Perl)

**Purpose:** the raw diff ops are mathematically correct but visually
poor. A diff might say "delete all of line A, then insert all of line B"
when the human-readable change is "replace word X with word Y in line A".
Postprocess transforms the ops to look natural — and, since the Phase C
refactor, also owns cursor positioning so the animator is scroll-safe.

**Current transformations:**

1. **Op ordering** (`--postprocess-op-order`): reorders ops within a
   hunk. Modes: natural, optimize (default — consolidates delete/insert
   runs), left-to-right (sorts by column), end-first (deletes trailing
   content first), end-first-smart, overwrite.

2. **Semantic cleanup** (`--postprocess-semantic-cleanup`): merges
   adjacent delete+insert pairs that cancel out (e.g., delete 'a'
   insert 'a' → keep 'a'), reducing typing noise.

3. **Line grouping**: ensures ops within a hunk are grouped by line so
   the animator processes them in a sensible order.

4. **Per-op (line, col) positioning**: walks each hunk's ops,
   simulates the cursor position, and emits a `(line, col)` for every
   op (1-indexed). Tracks `line_offset` (cumulative
   `newline_inserts − newline_deletes` from previous hunks) across the
   whole file so each op targets the right *current* buffer line. This
   is what lets the animator be position-less and scroll-safe.

**THE GHOST LINE PROBLEM — UNRESOLVED (Phase F):**

When the diff algorithm produces a sequence like:
```
keep "foo"
delete \n
keep "bar"
```
(joining two lines into "foobar"), the animator mechanically joins the
lines. Visually, "bar" jumps up onto the "foo" line — this looks bad.

The correct fix belongs in **postprocess**, not in the animator. The
postprocessor should detect this pattern (a `\n` delete between two
`keep` runs) and transform it into a sequence that animates naturally.
This is pending (Phase F).

Possible postprocess transformations (NOT YET IMPLEMENTED):

- **Split into delete+insert**: transform `keep "foo", delete \n, keep
  "bar"` into `keep "foo\n", delete "bar", insert "bar"` — i.e., delete
  the entire second line and re-insert it as new content. The `\n` is
  preserved with the keep, and the second line is deleted then re-inserted
  in place. Visually: "bar" disappears and reappears on the same line.

- **Defer the join**: the postprocessor reorders ops so all char deletes
  on a line happen before the `\n` delete. Then the `\n` delete can use
  the "remove empty line" path (the line is already empty by then).

The postprocessor currently does NOT do this. It passes the raw diff
ops through (with optional reordering and per-op positioning). This is
the core unresolved issue.

## Stage 3: Pace

**Input:** positioned char ops from postprocess (TSV, per-op `(line, col)`)
**Output:** timed op stream (ops with delays and batch operations)

**Tools:** `animator/bin/diffvim-pace` (C, Perl)

**Purpose:** add timing and batching so the animation feels human. A
human doesn't type at uniform speed — they pause between words, delete
in bursts, and move the cursor with variable speed.

Since the Phase C refactor, pace owns ONLY delays and batching.
Cursor positioning (the `(line, col)` per op) is owned by postprocess;
pace passes positions through untouched.

**What pace adds:**

1. **Delays**: each op gets a delay (in ms) after it. Types:
   - `delay 1` — minimal (keep chars, fast scroll past)
   - `delay 50` — normal typing speed
   - `delay 250` — hunk pause (between hunks)

2. **Batch operations**: consecutive same-type ops get batched:
   - `batch_delete <line> <col> <count>` — delete N chars at once
     (rapid deletion)
   - `batch_insert <line> <col> <code1> <code2> ... <codeN>` — insert a
     word at once

3. **Delete pacing** (`--pace-delete-pacing`): strategy for deletions:
   - `char` — one char at a time
   - `rapid-eol` — fast delete at end of line
   - `word` (default) — AWD: spaces instant, 3 chars slow, then word
     batches with acceleration
   - `instant` — delete everything at once

4. **Insert pacing** (`--pace-insert-pacing`): `char` (default) or
   `word` (batch short words).

**Timed op format (v2 — TSV, per-op positioning):**
```
# timed op stream v2
# format: TSV, every op carries (line, col) — 1-indexed
# generated by: diffvim-pace ...
# delete_threshold 3
hunk_start\t<del_count>\t<ins_count>
op\tkeep|delete|insert\t<line>\t<col>\t<code>
batch_delete\t<line>\t<col>\t<count>
batch_insert\t<line>\t<col>\t<code1>\t<code2>\t...
newline_delete\t<line>
newline_insert\t<line>\t<col>
delay\t<ms>
hunk_end
done
```

Note: the old v1 format (space-separated, with `glide <line>:<col>` ops
between hunks) has been removed. Every op now carries its own `(line, col)`,
so a separate glide op is unnecessary — the animator just sets the
cursor to the position carried by the next op before applying it.

## Stage 4: Animate

**Input:** timed op stream (TSV, per-op positions)
**Output:** visual animation in terminal (or saved buffer file)

**Tools:**
- `diffvim` (vimscript, run inside vim) — the original, uses vim's
  buffer manipulation and timer-based animation
- `animator/bin/diffvim-animator-c` (C++) — default standalone animator
- `animator/perl/animator.pl` (C++) — Perl fallback

(The Go animator was removed in the refactor.)

**How it works:**

The animator maintains a virtual buffer (list of lines) and a cursor
(line, col). It reads the TSV timed op stream and processes each op:

1. **op keep/delete/insert** — set cursor to the op's `(line, col)`,
   then modify the buffer at that position, advance the cursor
2. **batch_delete/batch_insert** — set cursor to the op's `(line, col)`,
   then apply multiple ops at once
3. **newline_delete** — join current line with next (removes the `\n`)
4. **newline_insert** — split the current line at the cursor (inserts
   a `\n`)
5. **delay** — sleep for N ms (scaled by `--speed`)
6. **snapshot** — write the current buffer to a file
7. **done** — animation complete

Because every op carries its own position, the animator has no `glide`
handler — it just sets the cursor before each op. When the target line
is beyond the buffer end (the end-insert case), the cursor goes to the
END of the last line so subsequent inserts append correctly.

**The `\n` delete problem:**

When the animator encounters `newline_delete` (or `delete` with code
10), it must remove the `\n` between the current line and the next.
There are two cases:

1. **Current line is empty** (all content already deleted): remove the
   empty line entirely. The line vanishes.

2. **Current line has content**: JOIN the current line with the next.
   This is the only correct behavior because the diff algorithm
   produced a `\n` delete op, meaning the `\n` must be removed from the
   buffer. Not removing it leaves an extra line that subsequent ops
   don't expect.

The "ghost line" visual issue (where joining pulls the next line's
content up onto the current line) is real, but the fix belongs in
**postprocess** (transform the ops before they reach the animator),
not in the animator (which must mechanically apply what it's given).

## The vimscript engine (diffvim)

The `diffvim` bash script launches vim with an embedded vimscript
engine. The engine:

1. **BuildHunks()** — reads the old file, computes or loads precomputed
   ops, builds hunk data structures. For each hunk, it computes
   `old_text` and `new_text` (the deleted and inserted content), then
   runs a char-level diff on those texts to produce `char_ops`.

2. **StartAnimation()** — sets up the timer, positions cursor at first
   hunk.

3. **StartNextHunk()** — positions cursor at hunk target (adjusted by
   the cumulative inserted - deleted lines from previous hunks).

4. **ProcessCharOp()** — processes one char op per timer tick. Applies
   the op to the buffer, advances cursor, schedules next tick. Handles
   AWD (adaptive word delete), rapid-eol, word acceleration, and other
   pacing modes.

**Controls:** Space (pause), n (skip hunk), b (back), q (quit), +/-
(speed), = (reset speed).

## Current State and Known Issues

### What works:
- diffvim-pipeline (C animator): **42/42 examples pass** MD5
  verification
- diffvim (vimscript, synchronous): 32/42 pass (10 large-file timeouts
  due to O(N²) in ProcessCharOp on 28K+ ops)
- Cross-language parity: the C++ compute tool, plus C and Perl
  postprocess/pace, produce identical output

### What doesn't work:

1. **Ghost line problem** — the core visual issue. When a `\n` delete
   joins two lines, the next line's content visually jumps up. This
   needs a postprocess fix (transform the ops), not an animator fix.
   Pending Phase F.

2. **Large-file performance** — vimscript engine is O(N²) on large op
   lists. 28K ops (33_large_python) takes 11+ seconds; 68K ops
   (42_large_huge_python) times out at 30s. The standalone C animator
   handles these fine (< 1 second).

3. **Pause/resume cursor drift** — in interactive diffvim, if the user
   pauses and scrolls, the cursor position (`s:cur_l`, `s:cur_c`) is not
   re-validated against the actual buffer position after resume. Ops
   then apply at the wrong place. (Reported but not reproduced
   headlessly.)

## File Structure

```
gitanim/
├── diffvim                  # bash + vimscript launcher (main tool)
├── diffvim.pl               # Perl alternative
├── diffvim-tmux             # tmux variant
├── compute/
│   ├── cpp/                 # C++ compute source (the only compute impl)
│   ├── perl/                # Pure-Perl fallback wrapper
│   └── bin/diffvim-compute-cpp
├── animator/
│   ├── bin/                 # compiled animator + pace + postprocess (C only)
│   ├── perl/                # Perl source (animator.pl, pace.pl, postprocess.pl)
│   ├── c/                   # C source (animator.c, pace.c, postprocess.c)
│   ├── diffvim-pipeline     # runs all 4 stages (C-preferred, Perl fallback)
│   └── tests/               # animator-specific tests
├── examples/                # 42 file pairs (old/new) for testing
├── tests/                   # vimscript engine tests
├── scripts/verify_md5.sh   # MD5 round-trip verification script
└── docs/                    # documentation
```
