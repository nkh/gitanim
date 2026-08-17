# diffvim-animator

**Standalone terminal animation for code diffs — no vim required.**

diffvim-animator is a pipeline of independent tools that animate code
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
7. [The `\n` Problem — Solved](#7-the-n-problem--solved)
8. [Syntax Coloring](#8-syntax-coloring)
9. [Options Reference](#9-options-reference)
10. [Language Implementations](#10-language-implementations)
11. [Testing](#11-testing)
12. [Comparison with vim-based diffvim](#12-comparison-with-vim-based-diffvim)
13. [Migration Path](#13-migration-path)

---

## 1. Overview

The diffvim-animator pipeline consists of 4 stages:

```
compute → postprocess → pace → animator
```

Each stage is a separate tool that reads from stdin and writes to stdout.
This separation means:

- Each tool is independently testable
- Tools can be mixed across languages (Perl postprocess + Go animator)
- The animator is simple — just plays back a pre-computed op stream
- All complex logic (diff, op ordering, pacing) runs before animation

### Key Features

- **No vim dependency** — works in any terminal
- **Correct `\n` handling** — deferred line joins prevent content pull-up
- **Syntax coloring** — via external highlighters (`bat`, `highlight`)
- **Three languages** — Perl, C, and Go implementations of every tool
- **Cross-language parity** — all implementations produce identical output
- **`--no-display` mode** — process ops without rendering (for testing/CI)
- **Snapshot ops** — write the buffer to a file at any point during animation

---

## 2. Installation

### Build All Tools

```bash
# C tools
cc -O2 -o animator/bin/diffvim-postprocess animator/c/postprocess.c
cc -O2 -o animator/bin/diffvim-pace animator/c/pace.c
cc -O2 -o animator/bin/diffvim-animator-c animator/c/animator.c

# Go tools
go build -o animator/bin/diffvim-postprocess-go animator/go/postprocess.go
go build -o animator/bin/diffvim-pace-go animator/go/pace.go
go build -o animator/bin/diffvim-animator animator/go/animator.go

# Perl tools need no build
```

### Install

```bash
sudo cp animator/bin/diffvim-* /usr/local/bin/
sudo cp animator/diffvim-pipeline /usr/local/bin/
```

### Prerequisites

- **Compute tool:** One of `diffvim-compute-{c,cpp,rust,go}` (already built in `compute/bin/`)
- **Perl tools:** Perl 5.10+ (core modules only)
- **Go tools:** Go 1.21+ (to build; runtime has no dependencies)
- **C tools:** Any C compiler (cc/gcc/clang)
- **Syntax coloring (optional):** `bat`, `highlight`, or any ANSI-capable highlighter

---

## 3. Quick Start

### Using diffvim-pipeline (recommended)

```bash
# Basic animation
animator/diffvim-pipeline old.py new.py

# With word-by-word deletion and syntax coloring
animator/diffvim-pipeline \
  --pace-delete-pacing word \
  --syntax 'bat --color=always' \
  old.py new.py

# Testing mode (no display, write result to file)
animator/diffvim-pipeline \
  --animator-no-display \
  --animator-snapshot result.txt \
  old.py new.py
```

### Manual Pipeline

```bash
# Compute the diff
compute/bin/diffvim-compute-c old.py new.py /tmp/raw.txt

# Post-process (reorder ops)
perl animator/perl/postprocess.pl --op-order optimize < /tmp/raw.txt > /tmp/post.txt

# Add timing and pacing
perl animator/perl/pace.pl --delete-pacing word < /tmp/post.txt > /tmp/timed.txt

# Animate
animator/bin/diffvim-animator --syntax 'bat --color=always' old.py < /tmp/timed.txt
```

---

## 4. Pipeline Architecture

```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  diffvim-   │     │  diffvim-     │     │  diffvim-    │     │  diffvim-    │
│  compute    │────▶│  postprocess  │────▶│  pace        │────▶│  animator    │
│             │     │               │     │              │     │              │
│ Computes    │     │ Reorders ops  │     │ Adds timing  │     │ Plays back   │
│ char ops    │     │ (op-order,    │     │ and pacing   │     │ ops with     │
│ (LCS/Myers/ │     │ semantic,     │     │ (AWD, word   │     │ cursor glide │
│ Patience)   │     │ indent, etc.) │     │ batching,    │     │ and rendering│
│             │     │               │     │ delays)      │     │              │
│ C/C++/Rust/ │     │ Perl / C / Go │     │ Perl / C / Go│     │ Perl / C / Go│
│ Go          │     │               │     │              │     │              │
└─────────────┘     └───────────────┘     └──────────────┘     └──────────────┘
     Exists              New tool            New tool           New tool
```

### Option Routing

`diffvim-pipeline` routes options by prefix:

| Prefix | Stage | Example |
|--------|-------|---------|
| `--compute-*` | compute | `--compute-algorithm patience` |
| `--postprocess-*` | postprocess | `--postprocess-op-order optimize` |
| `--pace-*` | pace | `--pace-delete-pacing word` |
| `--animator-*` | animator | `--animator-no-display` |
| (none) | animator | `--speed 2.0`, `--syntax 'bat ...'` |
| `--tool` | compute | `--tool rust` (selects compute language) |

---

## 5. Tools

### diffvim-postprocess

**Purpose:** Reorders char ops within each line for human readability.

**Languages:** Perl, C, Go (all produce identical output)

**Options:**
- `--op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite` (default: optimize)
- `--semantic-cleanup` — Merge canceling delete/insert pairs
- `--indent-aware` — Handle indent-only changes
- `--overwrite` — Transform delete+insert into in-place overwrite

**Piping:** Multiple invocations can be chained:
```bash
postprocess --op-order optimize | postprocess --semantic-cleanup
```

### diffvim-pace

**Purpose:** Transforms ordered ops into a timed op stream with pre-computed delays, batch operations, and cursor glide targets.

**Languages:** Perl, C, Go (all produce identical output)

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
Phase 5: Delete \n (deferred join if line has content)
```

### diffvim-animator

**Purpose:** Reads a timed op stream and animates the transformation in a terminal.

**Languages:** Go (primary), Perl, C

**Options:**
- `--no-display` — Process ops without rendering (for testing)
- `--speed N` — Speed multiplier (default: 1.0)
- `--output FILE` — Write final buffer to FILE
- `--snapshot FILE` — Write buffer to FILE at end
- `--scroll zz|zt|zb|none` — Cursor scroll position (default: zz)
- `--syntax CMD` — External syntax highlighter command
- `--help, -h` — Show help

### diffvim-pipeline

**Purpose:** Runs all 4 stages with prefixed option routing.

```bash
diffvim-pipeline [options] <oldfile> <newfile>
```

---

## 6. Timed Op Stream Format

The pace tool produces a text-based stream that the animator reads:

```
# timed op stream v1
hunk_start 2 1 1
glide 2:1
delay 480
op keep 32
delay 1
op insert 102
delay 50
batch_delete 4
delay 15
newline_delete
delay 40
snapshot /tmp/check.txt
hunk_end
done
```

### Op Types

| Op | Arguments | Description |
|----|-----------|-------------|
| `op` | `<type> <code>` | Apply a char op (keep/delete/insert) |
| `delay` | `<ms>` | Wait N milliseconds |
| `batch_delete` | `<count>` | Delete N chars at cursor instantly |
| `batch_insert` | `<codes...>` | Insert multiple chars instantly |
| `glide` | `<line>:<col>` | Move cursor to position |
| `newline_delete` | | Delete \n (join lines, may be deferred) |
| `newline_insert` | | Insert \n (split line) |
| `snapshot` | `<file>` | Write buffer to file |
| `hunk_start` | `<line> <del> <ins>` | Mark hunk beginning |
| `hunk_end` | | Mark hunk end |
| `done` | | Animation complete |

---

## 7. The `\n` Problem — Solved

### The Problem

When a newline is deleted and the current line still has content (keep
characters), joining the current line with the next line pulls the next
line's content up onto the current line during animation. This looks
terrible — the viewer sees the next line's text suddenly appear on the
current line.

### The Solution: Deferred Line Joins

When deleting a `\n`:

1. **If the current line is EMPTY** (all content already deleted):
   Join immediately. This just removes the empty line — the next line's
   content takes its place. No visual issue because there's no content
   to be "pulled up".

2. **If the current line has CONTENT** (keep characters before the deletes):
   DON'T join. Just move the cursor to the next line. Defer the join
   until the end of the animation. This prevents the next line's content
   from being pulled up during animation.

At the end of the animation (or when writing a snapshot), all deferred
joins are applied in reverse line order (so joins don't shift line
numbers). The final buffer is correct — matches the expected new file.

### Implementation

| Component | Implementation |
|-----------|---------------|
| diffvim (vimscript) | `s:deferred_joins` list, `s:ApplyDeferredJoins()` called in `StartNextHunk` and `Quit` |
| animator (Go) | `VirtualBuffer.deferredJoins` slice, `ApplyDeferredJoins()` called on snapshot/done |
| animator (Perl) | `@deferred_joins` array, `apply_deferred_joins()` called on snapshot/done |
| animator (C) | `deferred_joins[]` array, `apply_deferred_joins()` called on snapshot/done |

---

## 8. Syntax Coloring

The animator supports syntax coloring via external highlighters:

```bash
# Using bat
diffvim-pipeline --syntax 'bat --color=always' old.py new.py

# Using highlight
diffvim-pipeline --syntax 'highlight -O ansi' old.py new.py

# Using pygments
diffvim-pipeline --syntax 'pygmentize' old.py new.py
```

The animator writes the buffer to a temp file, runs the highlighter on
it, and displays the colored output. The cursor is positioned after
the colored text. If the highlighter fails, the animator falls back to
plain rendering.

---

## 9. Options Reference

### diffvim-pipeline Options

| Option | Stage | Description |
|--------|-------|-------------|
| `--tool c\|cpp\|rust\|go` | compute | Select compute tool language |
| `--compute-algorithm lcs\|myers\|patience` | compute | Diff algorithm |
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

All three languages have complete implementations of all three tools.

### Implementation Status

| Tool | Perl | C | Go |
|------|------|---|-----|
| postprocess | ✅ 379 lines | ✅ 168 lines | ✅ 170 lines |
| pace | ✅ 310 lines | ✅ 210 lines | ✅ 342 lines |
| animator | ✅ 175 lines | ✅ 200 lines | ✅ 500 lines |

### Cross-Language Parity

All implementations produce **byte-for-byte identical output**:
- Postprocess: C == Perl == Go (verified by 30 parity tests)
- Pace: C == Perl == Go (verified by 8 parity tests)
- Animator: all 3 produce correct round-trip results (verified by 45 tests)

### Performance

| Tool | Perl | C | Go |
|------|------|---|-----|
| postprocess (68K ops) | 147ms | 14ms | ~15ms |
| pace (68K ops) | 124ms | 15ms | ~15ms |
| animator startup | ~20ms | <1ms | ~5ms |

---

## 11. Testing

### Test Suite

| Test File | Assertions | What It Tests |
|-----------|-----------|---------------|
| `test_all_animators.pl` | 45 | 15 cases × 3 animators (round-trip) |
| `test_cross_language.pl` | 38 | Postprocess + pace parity (byte-for-byte) |
| `test_newline_fix.pl` | 8 | `\n` merge bug verification |
| **Total** | **91** | **All pass** |

### Running Tests

```bash
# All animator round-trip tests
perl animator/tests/test_all_animators.pl

# Cross-language parity
perl animator/tests/test_cross_language.pl

# \n merge bug verification
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
| `\n` delete | Deferred join (fixed) | ✅ Same fix |
| Dependencies | vim 8+ | ✅ None (Go static binary) |
| Architecture | Monolithic (4,500 lines) | ✅ Pipeline (4 tools) |
| Testability | Hard (timer-based) | ✅ Easy (stdin/stdout, `--no-display`) |
| Performance | Slow (vim overhead) | ✅ 10-100x faster |
| Syntax coloring | vim syntax files | ✅ External highlighters (`bat`, etc.) |
| Lines of code | ~4,500 (vimscript) | ✅ ~1,500 (total across tools) |
| Languages | Vimscript only | ✅ Perl, C, Go |

---

## 13. Migration Path

### Phase 1: Both systems coexist (current)

```bash
# Current (vim-based)
diffvim old.py new.py

# New (standalone)
diffvim-pipeline old.py new.py
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
