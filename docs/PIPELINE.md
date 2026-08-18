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

**Tools:** `compute/bin/diffvim-compute-{c,cpp,rust,go}` — four
independent implementations in C, C++, Rust, and Go. All produce
byte-identical output (verified by 294 cross-language tests).

**Algorithms:** three diff algorithms are supported:

1. **LCS** (Longest Common Subsequence) — dynamic programming, O(N*M)
   time and memory. Produces minimal diffs. Default.

2. **Myers** (Myers diff) — O(N+D) time where D is the edit distance.
   Faster on small diffs but uses O(N*M) memory in our implementation.
   **Killed by OOM on 15K-line files.**

3. **Patience** (Patience diff) — uses anchor lines (unique longest
   matches) to divide and conquer. Produces more human-readable diffs
   for code with structural markers. Similar performance to LCS.

**Timing (15K-line synthetic file, 549KB → 718KB):**

| Algorithm | C (ms) | C++ (ms) | Rust (ms) | Go (ms) | Ops produced |
|-----------|--------|----------|-----------|---------|--------------|
| LCS       | 1679   | 1585     | 4797      | 2758    | 1,034,143    |
| Myers     | KILLED | KILLED   | KILLED    | KILLED  | —            |
| Patience  | 2307   | 1687     | 5332      | 3024    | 1,034,143    |

LCS and Patience produce identical op counts on this file. Myers is
eliminated for large files due to OOM.

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
**Output:** reordered/transformed char ops

**Tools:** `animator/bin/diffvim-postprocess` (Perl, C, Go)

**Purpose:** the raw diff ops are mathematically correct but visually
poor. A diff might say "delete all of line A, then insert all of line B"
when the human-readable change is "replace word X with word Y in line A".
Postprocess transforms the ops to look natural.

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

**THE GHOST LINE PROBLEM — UNRESOLVED:**

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
ops through (with optional reordering). This is the core unresolved
issue.

## Stage 3: Pace

**Input:** ordered char ops
**Output:** timed op stream (ops with delays and batch operations)

**Tools:** `animator/bin/diffvim-pace` (Perl, C, Go)

**Purpose:** add timing and batching so the animation feels human. A
human doesn't type at uniform speed — they pause between words, delete
in bursts, and move the cursor with variable speed.

**What pace adds:**

1. **Delays**: each op gets a delay (in ms) after it. Types:
   - `delay 1` — minimal (keep chars, fast scroll past)
   - `delay 50` — normal typing speed
   - `delay 250` — hunk pause (between hunks)
   - `delay 1440` — long glide (cursor movement between distant lines)

2. **Batch operations**: consecutive same-type ops get batched:
   - `batch_delete N` — delete N chars at once (for rapid deletion)
   - `batch_insert C1 C2 ... Cn` — insert a word at once

3. **Delete pacing** (`--pace-delete-pacing`): strategy for deletions:
   - `char` — one char at a time
   - `rapid-eol` — fast delete at end of line
   - `word` (default) — AWD: spaces instant, 3 chars slow, then word
     batches with acceleration
   - `instant` — delete everything at once

4. **Insert pacing** (`--pace-insert-pacing`): `char` (default) or
   `word` (batch short words).

5. **Cursor glide**: before each hunk, emits `glide <line>:<col>` to
   position the cursor. The delay is proportional to the distance.

6. **Line offset tracking**: pace tracks cumulative
   (newline_inserts - newline_deletes) from previous hunks and adds
   this offset to each glide target. Without this, glide targets refer
   to original line numbers, not current buffer positions — causing
   inserts to land on wrong lines.

**Timed op format:**
```
# timed op stream v1
hunk_start <target_line> <del_count> <ins_count>
glide <line>:<col>
delay <ms>
op keep|delete|insert <char_code>
delay <ms>
batch_delete <count>
batch_insert <code1> <code2> ...
newline_delete
newline_insert
hunk_end
done
```

## Stage 4: Animate

**Input:** timed op stream
**Output:** visual animation in terminal (or saved buffer file)

**Tools:**
- `diffvim` (vimscript, run inside vim) — the original, uses vim's
  buffer manipulation and timer-based animation
- `animator/bin/diffvim-animator` (Go) — standalone, renders to
  terminal with ANSI escapes
- `animator/bin/diffvim-animator-c` (C) — C version
- `animator/perl/animator.pl` (Perl) — Perl version

**How it works:**

The animator maintains a virtual buffer (list of lines) and a cursor
(line, col). It reads the timed op stream and processes each op:

1. **op keep/delete/insert** — modify the buffer at the cursor position,
   advance the cursor
2. **batch_delete/batch_insert** — apply multiple ops at once
3. **newline_delete** — join current line with next (removes the `\n`)
4. **newline_insert** — split the current line at the cursor (inserts
   a `\n`)
5. **glide** — move the cursor to a new position
6. **delay** — sleep for N ms (scaled by `--speed`)
7. **snapshot** — write the current buffer to a file
8. **done** — animation complete

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
   `line_offset` = cumulative inserted - deleted lines from previous
   hunks).

4. **ProcessCharOp()** — processes one char op per timer tick. Applies
   the op to the buffer, advances cursor, schedules next tick. Handles
   AWD (adaptive word delete), rapid-eol, word acceleration, and other
   pacing modes.

5. **line_offset** — after each hunk, `line_offset += (inserted_count -
   deleted_count)`. This is LINE counts (from the line-level diff), not
   char counts. Correct for tracking buffer line shifts.

**Controls:** Space (pause), n (skip hunk), b (back), q (quit), +/-
(speed), = (reset speed).

## Current State and Known Issues

### What works:
- diffvim-pipeline (Go animator): **42/42 examples pass** MD5
  verification
- diffvim (vimscript, synchronous): 32/42 pass (10 large-file timeouts
  due to O(N²) in ProcessCharOp on 28K+ ops)
- Cross-language parity: all 4 compute tools, all 3 postprocess/pace
  tools produce identical output

### What doesn't work:

1. **Ghost line problem** — the core visual issue. When a `\n` delete
   joins two lines, the next line's content visually jumps up. This
   needs a postprocess fix (transform the ops), not an animator fix.

2. **Large-file performance** — vimscript engine is O(N²) on large op
   lists. 28K ops (33_large_python) takes 11+ seconds; 68K ops
   (42_large_huge_python) times out at 30s. The Go animator handles
   these fine (< 1 second).

3. **Pause/resume cursor drift** — in interactive diffvim, if the user
   pauses and scrolls, the cursor position (`s:cur_l`, `s:cur_c`) is not
   re-validated against the actual buffer position after resume. Ops
   then apply at the wrong place. (Reported but not reproduced
   headlessly.)

4. **Myers algorithm** — OOM-killed on 15K-line files. The
   implementation uses O(N*M) memory. Should either be replaced with
   a linear-space Myers variant, or dropped for large files.

## File Structure

```
gitanim/
├── diffvim                  # bash + vimscript launcher (main tool)
├── diffvim.pl               # Perl alternative
├── diffvim-tmux             # tmux variant
├── compute/bin/             # 4 diff compute tools (C/C++/Rust/Go)
├── animator/
│   ├── bin/                 # compiled animator + pace + postprocess
│   ├── go/                  # Go source
│   ├── perl/                # Perl source
│   ├── c/                   # C source
│   ├── diffvim-pipeline     # runs all 4 stages
│   └── tests/               # animator-specific tests
├── examples/                # 42 file pairs (old/new) for testing
├── tests/                   # vimscript engine tests
├── scripts/verify_md5.sh   # MD5 round-trip verification script
└── docs/                    # documentation
```
