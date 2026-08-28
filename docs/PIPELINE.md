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

**Tool:** `bin/ad_compute` — the C++ implementation
(`compute/cpp/ad_compute.cpp`). When the C++ binary is missing,
`ad_pipeline` falls back to the pure-Perl
`compute/perl/compute_builtin.pl` (a wrapper around
`DiffVim::Parser::Perl::parse_diff`). Both paths emit the same op-stream
format.

**Algorithms:** two line-diff algorithms are supported:

1. **Patience** — dynamic programming,
   O(N×M) time and memory. Produces minimal diffs. Default.

2. **Patience** — uses anchor lines (unique longest matches) to divide
   and conquer. Produces more human-readable diffs for code with
   structural markers. Same algorithm.

Myers was removed in the refactor: it OOMs on 15K-line files (O(N×M)
memory in our implementation) and produces the same op count as Patience.

**Timing (15K-line synthetic file, 549KB → 718KB):**

| Algorithm | C++ (ms) | Ops produced |
|-----------|----------|--------------|
| Patience  | 1687     | 1,034,143    |

(Patience and Myers were removed in the refactor — Patience is the only algorithm.)

**Op format:**
```
# diffvim precomputed diff v1
# algorithm patience
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

**Tools:** `bin/ad_postprocess` (C, Perl)

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

## Stage 3: Pace

**Input:** positioned char ops from postprocess (TSV, per-op `(line, col)`)
**Output:** timed op stream (ops with delays and batch operations)

**Tools:** `bin/ad_layer_pace` (C, Perl)

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
# generated by: ad_layer_pace ...
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

Note: the old v1 format (space-separated, with `removed (per-op positioning)` ops
between hunks) has been removed. Every op now carries its own `(line, col)`,
so a separate glide op is unnecessary — the animator just sets the
cursor to the position carried by the next op before applying it.

## Stage 4: Animate

**Input:** timed op stream (TSV, per-op positions, typed delays)
**Output:** visual animation in terminal (or saved buffer file)

**Tools:**
- `diffvim` (vimscript, run inside vim) — uses the external pipeline
  (compute → postprocess → pace) and reads the resulting timed op stream.
  The vimscript engine is now a ~200-line timed-op-stream reader. It
  uses incremental rendering (`redraw`, not `redraw!`) to avoid flashing.
- `bin/ad` (C) — default standalone animator
  with incremental rendering (tracks previous screen state, only
  redraws changed lines). Supports syntax coloring via `--colormap-old`
  and `--colormap-new`.
- `animator/perl/ad.pl` (Perl) — Perl fallback

**How it works:**

The animator maintains a virtual buffer (list of lines) and a cursor
(line, col). It reads the TSV timed op stream and processes each op:

1. **op keep/delete/insert** — `set_cursor(line, col)`, then modify the
   buffer at that position
2. **batch_delete/batch_insert** — `set_cursor(line, col)`, then apply
   multiple ops at once
3. **newline_delete** — remove `\n` (joins current line with next)
4. **newline_insert** — split the current line at the cursor
5. **delay** — sleep for N ms (scaled by `--speed`). Delays are typed
   (`delay\t<type>\t<ms>`) enabling future per-type dynamic pacing.
6. **snapshot** — write the current buffer to a file
7. **done** — animation complete

**Anti-flash rendering:**
- **Vimscript**: uses `redraw` (incremental) not `redraw!` (full clear).
  Only renders at delay boundaries. `keep` ops don't render.
- **C**: tracks `prev_lines` array and only redraws lines whose content
  or cursor state changed. Uses per-line clear (`\033[<line>;1H\033[2K`)
  instead of full-screen clear (`\033[2J`).

**Syntax coloring:**
The pipeline runs `diffvim-colorize` in parallel with the processing
stages. Color maps (ANSI-colored lines) are passed to the animator via
`--colormap-old`/`--colormap-new`. Unmodified lines are rendered with
syntax colors; modified lines fall back to plain text (progressive
decoloring).

## Controls (during animation)

| Key | Action |
|-----|--------|
| `Space` | Pause / resume |
| `q` | Stop animation |
| `+` | Speed up (×1.5) |
| `-` | Slow down (÷1.5) |

## Current State

### What works:
- **42/42 examples pass** MD5 verification with the C animator
- Cross-language parity: C and Perl postprocess/pace produce identical output
- Syntax coloring via `diffvim-colorize` (vim/pygmentize backends)
- Streaming mode (`--stream`) in postprocess for true Unix pipes
- `--transform NAME` flags in postprocess for composable transformations
- Typed delays for future per-type dynamic pacing
- No flashing (incremental rendering in both vimscript and C animators)

## File Structure

```
gitanim/
├── diffvim                  # bash launcher + embedded vimscript engine
├── diffvim.pl               # Perl launcher
├── diffvim-tmux             # tmux variant
├── compute/
│   ├── cpp/                 # C++ Patience diff (the only compute impl)
│   ├── perl/                # Pure-Perl fallback (byte-identical to C++)
│   └── bin/ad_compute
├── animator/
│   ├── c/                   # C source (animator.c, pace.c, postprocess.c)
│   ├── perl/                # Perl source (animator.pl, pace.pl, postprocess.pl, colorize.pl)
│   ├── bin/                 # compiled C binaries
│   ├── ad_pipeline     # runs all 4 stages + parallel coloring
│   └── tests/               # animator-specific tests
├── tests/tests/examples/                # 42 file pairs (old/new) for testing
├── tests/                   # vimscript engine tests
├── tests/verify_md5.sh   # MD5 round-trip verification script
└── docs/                    # documentation (including DEVELOPER_GUIDE.md)
```
