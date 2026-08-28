# ad

**Standalone terminal animation for code diffs — no vim required.**

ad is a pipeline of independent tools that animate code
diffs in any terminal. It replaces the vim-based diffvim engine with a
simpler, faster, more correct architecture.

---

## Table of Contents

1. [Overview](#1-overview)
2. [Installation](#2-installation)
3. [Quick Start](#3-quick-start)
4. [Pipeline Architecture](#4-pipeline-architecture)
5. [Tools](#5-tools)
6. [Timed Op Stream Format](#6-timed-op-stream-format)
7. [The `\n` Problem — Pending Phase F](#7-the-n-problem--pending-phase-f)
8. [Syntax Coloring](#8-syntax-coloring)
9. [Options Reference](#9-options-reference)
10. [Language Implementations](#10-language-implementations)
11. [Testing](#11-testing)
12. [Comparison with vim-based diffvim](#12-comparison-with-vim-based-diffvim)
13. [Migration Path](#13-migration-path)

---

## 1. Overview

The ad pipeline consists of 4 stages:

```
compute → postprocess → pace → animator
```

Each stage is a separate tool that reads from stdin and writes to stdout.
This separation means:

- Each tool is independently testable
- Tools can be mixed across languages (Perl postprocess + C animator)
- The animator is simple — just plays back a pre-computed op stream
- All complex logic (diff, op ordering, pacing) runs before animation

### Key Features

- **No vim dependency** — works in any terminal
- **Per-op positioning** — every op carries its own `(line, col)`; the
  animator has no `glide` handler
- **Syntax coloring** — via external highlighters (`bat`, `highlight`)
- **Two languages** — Perl and C implementations of every tool
- **Cross-language parity** — both implementations produce identical output
- **`--no-display` mode** — process ops without rendering (for testing/CI)
- **Snapshot ops** — write the buffer to a file at any point during animation

> **Phase A–C refactor note.** The Go implementations of postprocess /
> pace / animator were removed; only Perl and C remain. The compute
> stage has a single C++ tool (`bin/ad_compute`) with a
> pure-Perl fallback (`compute/perl/compute_builtin.pl`).

---

## 2. Installation

### Build All Tools

```bash
# C animator tools
cc -O2 -o bin/ad_postprocess animator/c/postprocess.c
cc -O2 -o bin/ad_layer_pace animator/c/ad_layer_pace.c
cc -O2 -o bin/ad-c animator/c/ad.c

# C++ compute tool (used by the pipeline)
make -C compute

# Perl tools need no build
```

### Install

```bash
sudo cp animator/bin/diffvim-* /usr/local/bin/
sudo cp animator/ad_pipeline /usr/local/bin/
```

### Prerequisites

- **Compute tool:** `bin/ad_compute` (built by `make -C compute`).
  Falls back to `compute/perl/compute_builtin.pl` when the C++ binary
  is missing.
- **Perl tools:** Perl 5.10+ (core modules only)
- **C tools:** Any C compiler (cc/gcc/clang)
- **Syntax coloring (optional):** `bat`, `highlight`, or any ANSI-capable highlighter

---

## 3. Quick Start

### Using ad_pipeline (recommended)

```bash
# Basic animation
animator/ad_pipeline old.py new.py

# With word-by-word deletion and syntax coloring
animator/ad_pipeline \
  --pace-delete-pacing word \
  --syntax 'bat --color=always' \
  old.py new.py

# Testing mode (no display, write result to file)
animator/ad_pipeline \
  --animator-no-display \
  --animator-snapshot result.txt \
  old.py new.py
```

### Manual Pipeline

```bash
# Compute the diff
bin/ad_compute old.py new.py /tmp/raw.txt

# Post-process (reorder ops + add per-op (line, col) positions)
perl layers/perl/postprocess.pl --op-order optimize < /tmp/raw.txt > /tmp/post.txt

# Add timing and pacing (passes positions through)
perl layers/perl/ad_layer_pace.pl --delete-pacing word < /tmp/post.txt > /tmp/timed.txt

# Animate
bin/ad-c --syntax 'bat --color=always' old.py < /tmp/timed.txt
```

---

## 4. Pipeline Architecture

```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  diffvim-   │     │  diffvim-     │     │  diffvim-    │     │  diffvim-    │
│  compute    │────▶│  postprocess  │────▶│  pace        │────▶│  animator    │
│             │     │               │     │              │     │              │
│ Computes    │     │ Reorders ops  │     │ Adds timing  │     │ Plays back   │
│ char ops    │     │ + per-op      │     │ + batching   │     │ ops with     │
│ (Patience or     │     │ (line, col)   │     │ (AWD, word   │     │ cursor set  │
│ Patience)   │     │ positioning   │     │ batches)     │     │ per op      │
│             │     │               │     │              │     │              │
│ C++         │     │ Perl / C      │     │ Perl / C     │     │ Perl / C     │
│ (Perl       │     │               │     │              │     │              │
│ fallback)   │     │               │     │              │     │              │
└─────────────┘     └───────────────┘     └──────────────┘     └──────────────┘
     Exists              New tool              New tool            New tool
```

### Option Routing

`ad_pipeline` routes options by prefix:

| Prefix | Stage | Example |
|--------|-------|---------|
| `--compute-*` | compute | `--compute-algorithm patience` |
| `--postprocess-*` | postprocess | `--postprocess-op-order optimize` |
| `--pace-*` | pace | `--pace-delete-pacing word` |
| `--animator-*` | animator | `--animator-no-display` |
| (none) | animator | `--speed 2.0`, `--syntax 'bat ...'` |

> The historical `--tool (removed)` flag (which selected the compute
> language) was removed in the refactor — only the C++ tool remains,
> with a Perl fallback.

---

## 5. Tools

### ad_postprocess

**Purpose:** Reorders char ops within each line for human readability,
and emits a `(line, col)` for every op so the animator is scroll-safe.

**Languages:** Perl, C (both produce identical output)

**Options:**
- `--op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite` (default: optimize)
- `--semantic-cleanup` — Merge canceling delete/insert pairs
- `--indent-aware` — Handle indent-only changes
- `--overwrite` — Transform delete+insert into in-place overwrite

**Piping:** Multiple invocations can be chained:
```bash
postprocess --op-order optimize | postprocess --semantic-cleanup
```

### ad_layer_pace

**Purpose:** Adds timing and batching to the positioned op stream from
postprocess. Passes the per-op `(line, col)` through untouched — pace
owns ONLY delays and batching now (cursor positioning moved to
postprocess in the Phase C refactor).

**Languages:** Perl, C (both produce identical output)

**Options:**
- `--delete-pacing char|rapid-eol|rapid-identical|accel|word|instant` (default: word)
- `--delete-speed slow|normal|fast|instant` (default: normal)
- `--delete-threshold N` (default: 3)
- `--insert-pacing char|word|accel` (default: char)
- `--insert-speed slow|normal|fast` (default: normal)
- `--pacing uniform|adaptive|gaussian|review` (default: uniform)
- `--snapshot FILE` — Insert a snapshot op at the end

**AWD (Adaptive Word Delete) for `--delete-pacing word`:**
```
Phase 1: Skip spaces instantly (not counted toward threshold)
Phase 2: Delete first 3 non-space chars slowly (80ms each)
Phase 3: Delete words with acceleration (80ms → 15ms per word)
Phase 4: Delete remaining chars instantly (rapid shot)
Phase 5: Delete \n (join lines)
```

### ad

**Purpose:** Reads a TSV timed op stream and animates the transformation
in a terminal. Each op carries its own `(line, col)` — the animator just
sets the cursor before applying each op. No `glide` handler.

**Languages:** C (primary), Perl (fallback)

**Options:**
- `--no-display` — Process ops without rendering (for testing)
- `--speed N` — Speed multiplier (default: 1.0)
- `--output FILE` — Write final buffer to FILE
- `--snapshot FILE` — Write buffer to FILE at end
- `--scroll zz|zt|zb|none` — Cursor scroll position (default: zz)
- `--syntax CMD` — External syntax highlighter command
- `--help, -h` — Show help

### ad_pipeline

**Purpose:** Runs all 4 stages with prefixed option routing. Defaults
to the C++ compute tool + C animator; falls back to Perl when binaries
are missing.

```bash
ad_pipeline [options] <oldfile> <newfile>
```

---

## 6. Timed Op Stream Format

The pace tool produces a TSV stream that the animator reads (v2 format,
introduced in the Phase C refactor):

```
# timed op stream v2
# format: TSV, every op carries (line, col) — 1-indexed
# generated by: ad_layer_pace --delete-pacing word --pacing gaussian
# delete_threshold 3
file_start	old.py	new.py
hunk_start	1	1
op	delete	2	1	112
delay	80
op	delete	2	1	114
delay	80
batch_delete	2	1	4
delay	15
newline_delete	2
delay	40
snapshot	/tmp/check.txt
hunk_end
done
```

### Op Types

| Op | Arguments | Description |
|----|-----------|-------------|
| `op` | `<type> <line> <col> <code>` | Apply a char op at `(line, col)` |
| `delay` | `<ms>` | Wait N milliseconds |
| `batch_delete` | `<line> <col> <count>` | Delete N chars at `(line, col)` instantly |
| `batch_insert` | `<line> <col> <codes...>` | Insert multiple chars at `(line, col)` instantly |
| `newline_delete` | `<line>` | Delete `\n` at end of `<line>` (join with next) |
| `newline_insert` | `<line> <col>` | Insert `\n` at `(line, col)` (split line) |
| `snapshot` | `<file>` | Write buffer to file |
| `hunk_start` | `<del> <ins>` | Mark hunk beginning |
| `hunk_end` | | Mark hunk end |
| `done` | | Animation complete |

> **v1 → v2 change.** The old v1 format was space-separated and emitted
> `removed (per-op positioning)` ops between hunks. In v2, every op carries its
> own 1-indexed `(line, col)` and the `glide` op is gone — the animator
> just sets the cursor to the position carried by the next op before
> applying it.

---

## 7. The `\n` Problem — Pending Phase F

### The Problem

When a `\n` is deleted and the current line still has content (keep
characters), joining the current line with the next line pulls the next
line's content up onto the current line during animation. This looks
terrible — the viewer sees the next line's text suddenly appear on the
current line.

### Current behavior

The animator mechanically joins lines when it encounters a `\n` delete.
This is correct (the final buffer matches the new file), but the
intermediate visual is jarring.

The "deferred join" mechanism that previously attempted to fix this
was reverted (see commit `410cfdb` / NEXT_SESSION.md). It broke mixed
delete+insert sequences on large files because the buffer retained
extra `\n`s, causing subsequent inserts to land on wrong lines.

### Pending fix (Phase F)

The correct fix belongs in **postprocess**, not in the animator. The
postprocessor should detect the `keep X, delete \n, keep Y` pattern
(a line join) and transform it into a sequence that animates naturally
(e.g., delete the entire second line, then re-insert it as new content).

NOT YET IMPLEMENTED — see `docs/PIPELINE.md` for the design discussion.

---

## 8. Syntax Coloring

The animator supports syntax coloring via external highlighters:

```bash
# Using bat
ad_pipeline --syntax 'bat --color=always' old.py new.py

# Using highlight
ad_pipeline --syntax 'highlight -O ansi' old.py new.py

# Using pygments
ad_pipeline --syntax 'pygmentize' old.py new.py
```

The animator writes the buffer to a temp file, runs the highlighter on
it, and displays the colored output. The cursor is positioned after
the colored text. If the highlighter fails, the animator falls back to
plain rendering.

---

## 9. Options Reference

### ad_pipeline Options

| Option | Stage | Description |
|--------|-------|-------------|
| `--compute-algorithm patience\|patience` | compute | Diff algorithm (Myers removed) |
| `--postprocess-op-order MODE` | postprocess | Op reordering mode |
| `--postprocess-semantic-cleanup` | postprocess | Merge canceling ops |
| `--postprocess-indent-aware` | postprocess | Handle indent changes |
| `--pace-delete-pacing MODE` | pace | Deletion strategy |
| `--pace-delete-speed MODE` | pace | Deletion speed |
| `--pace-delete-threshold N` | pace | Min chars for rapid/word |
| `--pace-insert-pacing MODE` | pace | Insertion strategy |
| `--pace-insert-speed MODE` | pace | Insertion speed |
| `--pace-pacing MODE` | pace | Timing mode |
| `--animator-no-display` | animator | Process without rendering |
| `--animator-snapshot FILE` | animator | Write buffer to FILE |
| `--animator-output FILE` | animator | Write final buffer to FILE |
| `--animator-speed N` | animator | Speed multiplier |
| `--animator-syntax CMD` | animator | External syntax highlighter |
| `--no-display` | animator | (shorthand) Process without rendering |
| `--speed N` | animator | (shorthand) Speed multiplier |
| `--output FILE` | animator | (shorthand) Write final buffer |
| `--snapshot FILE` | animator | (shorthand) Write buffer to FILE |
| `--syntax CMD` | animator | (shorthand) Syntax highlighter |
| `--help, -h` | all | Show help |

---

## 10. Language Implementations

Both Perl and C have complete implementations of all three animator
tools. The compute stage is C++ with a Perl fallback.

### Implementation Status

| Tool | Perl | C |
|------|------|---|
| postprocess | ✅ ~380 lines | ✅ ~170 lines |
| pace | ✅ ~310 lines | ✅ ~210 lines |
| animator | ✅ ~175 lines | ✅ ~200 lines |
| (compute) | ✅ `compute_builtin.pl` (~90 lines, fallback) | C++ `ad_compute.cpp` |

### Cross-Language Parity

All implementations produce **byte-for-byte identical output**:
- Postprocess: C == Perl (verified by cross-language parity tests)
- Pace: C == Perl (verified across all 4 delete-pacing modes)
- Animator: both produce correct round-trip results (verified by round-trip tests)
- Compute: C++ == Perl fallback (verified on `tests/tests/examples/01_small_python`)

### Performance

| Tool | Perl | C |
|------|------|---|
| postprocess (68K ops) | ~147ms | ~14ms |
| pace (68K ops) | ~124ms | ~15ms |
| animator startup | ~20ms | <1ms |

---

## 11. Testing

### Test Suite

| Test File | Assertions | What It Tests |
|-----------|-----------|---------------|
| `test_all_animators.pl` | round-trip | C and Perl animators produce identical output |
| `test_cross_language.pl` | 14+ | Postprocess + pace parity (byte-for-byte) |
| `test_newline_fix.pl` | 7 | `\n` merge handling verification |
| `test_roundtrip.pl` | 15 | Perl animator round-trip |
| `test_roundtrip_verify.pl` | 30 | C animator round-trip |

### Running Tests

```bash
# All animator round-trip tests
perl animator/tests/test_all_animators.pl

# Cross-language parity
perl animator/tests/test_cross_language.pl

# \n merge handling
perl animator/tests/test_newline_fix.pl
```

### Test Cases

The round-trip test covers: simple insert/delete, mid-line replace,
whole-line delete/insert, multi-line delete/insert, identical files,
empty old/new files, Python functions, indent changes, Unicode,
multiple hunks, and identical char runs.

### `--no-display` Mode

The animator's `--no-display` mode processes all ops without rendering,
writing the buffer to a file via `--snapshot`. This enables round-trip
testing without a terminal.

---

## 12. Comparison with vim-based diffvim

| Aspect | diffvim (vim) | animator (standalone) |
|--------|---------------|----------------------|
| `\n` delete | Mechanical join (Phase F pending) | ✅ Same behavior |
| Dependencies | vim 8+ | ✅ None (C static binary) |
| Architecture | Monolithic (4,500 lines) | ✅ Pipeline (4 tools) |
| Testability | Hard (timer-based) | ✅ Easy (stdin/stdout, `--no-display`) |
| Performance | Slow (vim overhead) | ✅ 10-100x faster |
| Syntax coloring | vim syntax files | ✅ External highlighters (`bat`, etc.) |
| Lines of code | ~4,500 (vimscript) | ✅ ~1,000 (total across tools) |
| Languages | Vimscript only | ✅ Perl, C (animator); C++ (compute) |

---

## 13. Migration Path

### Phase 1: Both systems coexist (current)

```bash
# Current (vim-based)
diffvim old.py new.py

# New (standalone)
ad_pipeline old.py new.py
```

### Phase 2: Wrapper integration

Add `--animator` flag to the bash `diffvim` wrapper:

```bash
diffvim --animator old.py new.py
```

### Phase 3: Animator becomes default

```bash
diffvim old.py new.py        # uses animator
diffvim --vim old.py new.py  # falls back to vim
```
