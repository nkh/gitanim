# diffvim-animator-c: Standalone Animation Application

## Requirements Specification & Architecture Design

**Document version:** 2.0
**Date:** 2026-08-17
**Status:** Analysis and design only — no implementation

---

## 1. Executive Summary

### 1.1 Problem Statement

The current diffvim animation engine is embedded inside vim. This creates
fundamental limitations that cannot be fixed within the vim buffer model:

1. **The `\n` merge problem:** When a whole line is deleted, vim's buffer
   model requires deleting the line, which pulls the next line up. There is
   no way to "skip" a line in vim without deleting it. This makes multi-line
   deletion animations look terrible — each deleted line's content gets
   pulled onto the previous line before being deleted.

2. **Vim-only audience:** The animation requires vim, excluding developers
   who use other editors. A standalone terminal application would work for
   everyone.

3. **Timer-based architecture:** The vimscript engine uses `timer_start()`
   which is difficult to test, debug, and control. Race conditions between
   timer callbacks and user input are common.

4. **Buffer manipulation overhead:** Each char op requires `setline()`,
   `getline()`, cursor positioning, and `redraw` — expensive operations
   that limit animation smoothness.

5. **Pacing logic embedded in the viewer:** The vimscript engine contains
   both the animation rendering AND the pacing logic (AWD state machine,
   rapid-EOL, word batching, etc.). This makes the engine complex,
   hard to test, and tightly coupled. Pacing should be computed
   *before* the animator runs, producing a flat op stream with timing
   information that the animator simply plays back.

### 1.2 Proposed Solution

A **standalone terminal application** (`diffvim-animator-c`) that:

- Reads a **timed op stream** — a sequence of char ops with pre-computed
  timing, pacing, and grouping information produced by external tools
- Displays the old file content in a terminal
- Animates the transformation by playing back the op stream
- Does NOT depend on vim, tmux, or any editor
- Is a **simple playback engine** — all complex logic (diff computation,
  post-processing, pacing) is done by separate tools *before* the
  animator runs

### 1.3 Key Architectural Principle: Separation of Concerns

The current diffvim crams everything into one vimscript engine:
diff computation, post-processing, pacing decisions, animation rendering,
user input, and buffer management.

The new architecture separates these into independent stages, each
implemented as a separate tool that can be piped together:

```
compute    →    post-process    →    pace    →    animate
(diff)          (op-order)          (timing)     (display)
```

Each stage reads from stdin and writes to stdout, enabling:
- Independent testing of each stage
- Mixing implementations (e.g., C++ compute + Perl post-process + C animator)
- Using the animator without animation (headless mode) for testing
- Adding new post-processing or pacing tools without touching the animator

### 1.4 Key Advantage: Virtual Buffer

A standalone application has a **virtual text buffer** that it fully
controls. It can:
- Move the cursor freely without buffer manipulation overhead
- Render only what changed (incremental redraw)
- Support any terminal, not just vim

---

## 2. Architecture: Pipeline of Independent Tools

### 2.1 Pipeline Overview

```
┌─────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│  diffvim-   │     │  diffvim-     │     │  diffvim-    │     │  diffvim-    │
│  compute    │────▶│  postprocess  │────▶│  pace        │────▶│  animator    │
│             │     │               │     │              │     │              │
│ Computes    │     │ Reorders ops  │     │ Adds timing  │     │ Plays back   │
│ char ops    │     │ (op-order,    │     │ and pacing   │     │ ops with     │
│ (patience     │     │ semantic,     │     │ (AWD, word   │     │ cursor glide │
│ Patience)   │     │ indent, etc.) │     │ batching,    │     │ and rendering│
│             │     │               │     │ delays)      │     │              │
│ C++         │     │ Perl / C      │     │ Perl / C     │     │ Perl / C     │
│ (Perl       │     │               │     │              │     │              │
│ fallback)   │     │               │     │              │     │              │
└─────────────┘     └───────────────┘     └──────────────┘     └──────────────┘
     Exists              New tool              New tool            New tool
```

### 2.2 Data Flow

```
old.py + new.py
       │
       ▼
┌──────────────────┐
│ diffvim-compute   │  (existing: C++ with Perl fallback)
│                   │
│ Input: old, new   │
│ Output: raw ops   │  Format: HUNK / keep / delete / insert
│ (char-level patience)  │
└────────┬──────────┘
         │  raw ops (no timing, no ordering)
         ▼
┌──────────────────┐
│ diffvim-postprocess│  (new: Perl / C)
│                   │
│ Input: raw ops    │  Flags: --op-order, --semantic-cleanup,
│ Output: ordered   │          --indent-aware, --overwrite
│         ops       │
│                   │
│ Reorders ops      │  Can be multiple piped commands:
│ within lines      │    postprocess --op-order optimize |
│ + (line, col)     │    postprocess --semantic-cleanup |
│ positions         │    postprocess --left-to-right
│                   │
│ Owns cursor       │  (Since the Phase C refactor, postprocess
│ positioning so    │   also emits per-op (line, col) positions
│ the animator is   │   so the animator is scroll-safe.)
│ scroll-safe       │
└────────┬──────────┘
         │  ordered ops (correct sequence, no timing)
         ▼
┌──────────────────┐
│ diffvim-pace      │  (new: Perl / C)
│                   │
│ Input: ordered    │  Flags: --delete-pacing, --delete-speed,
│         ops       │          --insert-pacing, --pacing,
│ Output: timed     │          --delete-threshold
│         ops       │
│                   │
│ Adds timing info  │  Expands the op stream:
│ and pacing        │    - Groups chars into word batches
│ instructions      │    - Adds delay annotations
│                   │    - Inserts snapshot markers
│                   │
│ Output format:    │
│   op keep 97      │    (apply op, wait 50ms)
│   delay 50        │
│   op delete 108   │    (apply op, wait 40ms)
│   delay 40        │
│   batch_delete 10 │    (delete 10 chars instantly)
│   delay 15        │
│   snapshot        │    (write buffer to file — for testing)
│   newline_delete  │    (delete the `\n`)
│   delay 100       │
│                   │
│ Note: cursor      │  (Since the Phase C refactor, pace no
│ positions are    │   longer emits glide ops. Each op carries
│ owned by         │   its own (line, col) — produced by
│ postprocess      │   postprocess and passed through here.)
└────────┬──────────┘
         │  timed ops (ready to play back)
         ▼
┌──────────────────┐
│ diffvim-animator-c  │  (new: Perl / C)
│                   │
│ Input: timed ops  │  Flags: --speed, --scroll, --highlight,
│         + old file│          --dim-unchanged, --no-display
│                   │
│ Plays back the    │  The animator is SIMPLE:
│ timed op stream   │    - Read op
│                   │    - Set cursor to op's (line, col)
│                   │    - Apply to virtual buffer
│                   │    - Render (or skip if --no-display)
│                   │    - Wait the specified delay
│                   │    - Check for user input
│                   │    - Repeat
│                   │
│ Supports:         │
│   --no-display    │    Process all ops, modify buffer,
│                   │    don't render. For testing.
│   --snapshot FILE │    Write internal buffer to FILE.
│                   │    Can appear in the op stream too.
│   --output FILE   │    Write final buffer to FILE.
└──────────────────┘
```

### 2.3 Why This Separation Matters

**The animator becomes simple.** It doesn't need to know about:
- Diff algorithms (Patience)
- Post-processing (op ordering, semantic cleanup)
- Pacing decisions (when to batch words, when to accelerate)
- AWD state machine
- Lookahead functions

It just reads a flat stream of instructions and plays them back. This
makes it:
- Easy to implement in any language
- Easy to test (feed it a known op stream, check the output)
- Fast (no complex logic per frame)
- Replaceable (swap Perl for C without touching the other tools)

**Pacing is pre-computed.** The pacing tool analyzes the entire op stream
beforehand and produces a timed op stream. This means:
- The pacing tool can look ahead arbitrarily (no limited lookahead window)
- The animator doesn't need any lookahead logic
- Pacing decisions are deterministic and testable
- The same timed op stream produces identical animations in Perl and C

**Post-processing is piped.** Multiple post-processing passes can be
chained:
```bash
diffvim-compute-cpp old.py new.py |
  diffvim-postprocess --op-order optimize |
  diffvim-postprocess --semantic-cleanup |
  diffvim-pace --delete-pacing word --pacing gaussian |
  diffvim-animator-c old.py
```

Each postprocess invocation reads ops from stdin, applies one
transformation, and writes ops to stdout. This allows:
- Independent testing of each pass
- Mixing languages (Perl postprocess + Go animator)
- Adding new passes without modifying existing tools

---

## 3. Language Comparison

### 3.1 Implementation Languages

Three languages are considered for the new tools (postprocess, pace,
animator). **Bash is excluded** — it cannot handle the data structures,
timing, or terminal control required.

#### 3.1.1 Perl

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★★☆ | `Term::ReadKey`, `Term::ANSIScreen`, raw escapes |
| Text buffer | ★★★★☆ | Native arrays, easy string manipulation |
| Performance | ★★★☆☆ | Interpreted, but fast enough for text ops |
| Unicode | ★★★☆☆ | `use utf8`, `Encode` module; manual handling |
| Timing | ★★★★☆ | `Time::HiRes` for sub-millisecond precision |
| Maintainability | ★★★☆☆ | Verbose but structured; CPAN ecosystem |
| Dependencies | ★★★★☆ | Perl 5.10+ core; non-core modules allowed |

**Non-core modules allowed:** The Perl implementation MAY use non-core
CPAN modules if they provide significant functionality:
- `Term::ReadKey` — raw terminal input (non-blocking key reads)
- `Term::ANSIScreen` — screen manipulation, cursor positioning
- `Text::Tabs` — tab expansion for rendering
- `Unicode::GCString` — Unicode-aware string width (display width)

**Verdict:** Good candidate. Perl excels at text processing (ideal for
postprocess and pace tools). For the animator, `Term::ReadKey` +
`Term::ANSIScreen` provide the terminal control needed.

#### 3.1.2 C

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★☆☆ | Raw escape sequences; no curses needed |
| Text buffer | ★★★☆☆ | Manual memory management; `wchar_t` or UTF-8 |
| Performance | ★★★★★ | Fastest possible; sub-microsecond timing |
| Unicode | ★★☆☆☆ | Manual UTF-8 handling; no native support |
| Timing | ★★★★★ | `clock_gettime`, `nanosleep`; nanosecond precision |
| Maintainability | ★★☆☆☆ | Verbose, manual memory, no built-in strings |
| Dependencies | ★★★★★ | Zero runtime dependencies; static binary |

**Verdict:** Best performance, but highest implementation cost. Ideal
for the pace tool (computation-heavy, no terminal I/O). For the
animator, the terminal control and Unicode handling add significant
complexity. The C implementation is valuable for embedded/CI
environments where Perl and Go aren't available.

#### 3.1.3 Go

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★★★ | `tcell`, `bubbletea`, `termbox`; or raw escapes |
| Text buffer | ★★★★★ | Native `[]string`, `strings.Builder`; fast |
| Performance | ★★★★★ | Compiled, concurrent, sub-millisecond timing |
| Unicode | ★★★★★ | Native UTF-8 support, `runes` |
| Timing | ★★★★★ | `time.Timer`, `time.After`, channel-based |
| Maintainability | ★★★★★ | Strongly typed, gofmt, excellent tooling |
| Dependencies | ★★★☆☆ | Requires Go toolchain to build; static binary |

**Verdict:** Best overall candidate for the animator. Native UTF-8,
excellent terminal libraries, compiled performance, single binary.
For postprocess and pace, Go is also excellent but the build step
is a minor friction.

### 3.2 Speed Impact Analysis

| Operation | Perl | C | Go |
|-----------|------|---|----|
| Read 1000-line file | ~5ms | ~0.5ms | ~1ms |
| Apply 100 char ops | ~10ms | ~0.01ms | ~0.1ms |
| Full screen redraw (80x24) | ~20ms | ~1ms | ~1ms |
| Incremental redraw | ~5ms | ~0.5ms | ~0.5ms |
| Unicode char width | ~0.5ms | ~0.01ms | ~0.01ms |
| Timer precision | 1ms (`Time::HiRes`) | 0.001ms (`nanosleep`) | 0.1ms (`time.After`) |
| Process 10,000 ops (no display) | ~50ms | ~1ms | ~5ms |

**For the animator (display-critical):** Go and C can achieve 60fps
easily. Perl can achieve 30-60fps (acceptable). All three are viable.

**For the pace tool (computation-only, no display):** All three are
fast enough. The pacing computation is O(N) in the number of ops, and
even Perl processes 10,000 ops in ~50ms.

**For the postprocess tool (computation-only):** Same as pace — all
three are fast enough.

### 3.3 Recommendation

| Tool | Primary | Alternative |
|------|---------|-------------|
| diffvim-compute | C++ (exists) | Perl fallback (`compute_builtin.pl`) |
| diffvim-postprocess | C | Perl |
| diffvim-pace | C | Perl |
| diffvim-animator-c | C | Perl |

**C++ for compute:** The compute tool is the heaviest CPU work. C++
provides the fastest compute and smallest binary.

**Perl for postprocess and pace:** These are text-processing tools
that benefit from Perl's string manipulation. They don't need terminal
control or high-performance rendering. Perl's `Time::HiRes` is
sufficient for timing computation.

**C for the animator:** The animator needs terminal control, high-
performance rendering, Unicode handling, and non-blocking input. C is
the default animator implementation; Perl is the fallback.

(Both Perl and C implementations of postprocess, pace, and animator
exist. The historical Go implementations were removed in the Phase A
refactor.)

---

## 4. Timed Op Stream Format

### 4.1 Design

The timed op stream is the interface between the pace tool and the
animator. It extends the current precomputed diff format with timing
and pacing instructions.

### 4.2 Op Types

| Op | Arguments | Description |
|----|-----------|-------------|
| `op` | `<type> <line> <col> <code>` | Apply a char op at (line, col) |
| `delay` | `<ms>` | Wait N milliseconds |
| `batch_delete` | `<line> <col> <count>` | Delete N chars at (line, col) instantly |
| `batch_insert` | `<line> <col> <codes...>` | Insert N chars at (line, col) instantly |
| `newline_delete` | `<line>` | Delete the newline (join current line with next), move cursor down |
| `newline_insert` | `<line> <col>` | Split line at cursor, move cursor to new line |
| `highlight` | `<mode> <line> <col> <len>` | Apply highlight |
| `clear_highlight` | `<id>` | Clear a specific highlight |
| `dim` | `<line> <pct>` | Dim a line |
| `snapshot` | `<file>` | Write internal buffer to file (for testing) |
| `scroll` | `<mode>` | Set scroll position (zz/zt/zb/none) |
| `pause` | | Pause until user presses Space |
| `hunk_start` | `<del_count> <ins_count>` | Mark hunk beginning |
| `hunk_end` | | Mark hunk end |
| `file_start` | `<old_path> <new_path>` | Multi-file: start new file |
| `done` | | Animation complete |

> **Note (Phase C refactor):** every op now carries its own 1-indexed
> `(line, col)`. The old `removed (per-op positioning)` op is gone — the
> animator just sets the cursor to the position carried by the next op
> before applying it. The format is TSV (tab-separated).

### 4.3 Example

```
# timed op stream v2
# format: TSV, every op carries (line, col) — 1-indexed
# generated by: diffvim-pace --delete-pacing word --pacing gaussian
# delete_threshold 3
file_start\told.py\tnew.py
hunk_start\t1\t1
op\tdelete\t2\t1\t112
delay\t80
op\tdelete\t2\t1\t114
delay\t80
op\tdelete\t2\t1\t105
delay\t80
batch_delete\t2\t1\t17
delay\t15
batch_delete\t2\t1\t7
delay\t15
newline_delete\t2
delay\t100
hunk_end
snapshot\t/tmp/test_snapshot.txt
done
```

(Pre-Phase-C, this was space-separated and required a `glide 2:1` op
before each hunk. Since Phase C, every op carries its own position, so
the glide op is unnecessary.)

### 4.4 Snapshot Op

The `snapshot` op writes the current internal buffer state to a file.
This is used for:
- **Testing:** Verify the buffer state at any point during animation
- **Debugging:** Inspect the buffer mid-animation
- **CI:** Run the animator with `--no-display`, insert snapshots at
  key points, compare buffer states with expected output

The snapshot file contains the raw buffer content. This allows
round-trip testing: snapshot after all ops should match the new file.

---

## 5. Requirements

### 5.1 Functional Requirements

#### FR-1: The Animator (diffvim-animator-c)

**FR-1.1:** The animator SHALL read a timed op stream from stdin or
a file.

**FR-1.2:** The animator SHALL load the old file into a virtual text
buffer at startup.

**FR-1.3:** The animator SHALL maintain a virtual text buffer with:
- Lines as arrays of Unicode characters (runes/code points)
- Logical cursor position (line, column) that can exceed line length
- Line offset tracking for multi-hunk animation

**FR-1.4:** The animator SHALL process each op in the stream:
- `op`: Set cursor to the op's `(line, col)`, then apply the char operation to the buffer
- `delay`: Wait the specified time (divided by speed multiplier)
- `batch_delete`/`batch_insert`: Set cursor to the op's `(line, col)`, then apply multiple chars in one frame
- `newline_delete`: Delete the newline (join current line with next), move cursor to next line
- `newline_insert`: Split line at cursor
- `highlight`/`clear_highlight`/`dim`: Apply visual effects
- `snapshot`: Write buffer to file
- `pause`: Wait for user input

**FR-1.5:** The animator SHALL support `--no-display` mode:
- Process all ops and modify the internal buffer
- Do NOT render to the terminal
- Do NOT read keyboard input
- Process `snapshot` ops (write buffer to file)
- Used for testing and CI

**FR-1.6:** The animator SHALL support `--snapshot FILE`:
- Write the internal buffer to FILE at the end of processing
- Also, `snapshot` ops in the stream write to their specified files

**FR-1.7:** The animator SHALL support `--output FILE`:
- Write the final buffer to FILE

**FR-1.8:** The animator SHALL support `--speed N`:
- Multiply all delays by 1/N
- Does not affect op processing, only timing

**FR-1.9:** The animator SHALL support terminal rendering with:
- ANSI escape sequences for cursor positioning and colors
- Incremental rendering (only redraw changed lines)
- Scroll management (`--scroll zz|zt|zb|none`)
- Terminal resize handling (SIGWINCH)

**FR-1.10:** The animator SHALL support keyboard input (non-blocking):
- Space (pause/resume), n (skip), b (back), q (quit)
- + / - / = (speed control)
- ] / [ (multi-file navigation)

**FR-1.11:** The animator SHALL support `--dry-run`:
- Print op stream summary without processing

#### FR-2: The Post-Processing Tool (diffvim-postprocess)

**FR-2.1:** The postprocess tool SHALL read char ops from stdin and
write transformed ops to stdout.

**FR-2.2:** The postprocess tool SHALL support these flags:
- `--op-order MODE`: Reorder ops within each line
- `--semantic-cleanup`: Merge canceling delete/insert pairs
- `--indent-aware`: Handle indent-only changes
- `--overwrite`: Transform delete+insert into in-place overwrite

**FR-2.3:** Multiple postprocess invocations SHALL be chainable via
pipes:
```bash
diffvim-compute-cpp old.py new.py |
  diffvim-postprocess --op-order optimize |
  diffvim-postprocess --semantic-cleanup
```

**FR-2.4:** The postprocess tool SHALL be implemented in Perl and C.
Both SHALL produce identical output. (The historical Go version was
removed in the refactor.)

**FR-2.5:** The postprocess tool SHALL be testable independently:
- Feed it known input ops
- Compare output ops with expected
- No terminal, no animation, no timing

#### FR-3: The Pacing Tool (diffvim-pace)

**FR-3.1:** The pace tool SHALL read ordered char ops from stdin and
write a timed op stream to stdout.

**FR-3.2:** The pace tool SHALL support these flags:
- `--delete-pacing MODE`: Deletion strategy (char/rapid-eol/rapid-identical/accel/word/instant)
- `--delete-speed MODE`: Deletion speed (slow/normal/fast/instant)
- `--delete-threshold N`: Min chars for rapid/word modes
- `--insert-pacing MODE`: Insertion strategy (char/word/accel)
- `--insert-speed MODE`: Insertion speed
- `--pacing MODE`: Timing mode (uniform/adaptive/gaussian/review)
- `--snapshot FILE`: Insert a snapshot op at the end

**FR-3.3:** The pace tool SHALL analyze the entire op stream before
producing output, enabling:
- Unlimited lookahead (no windowed lookahead like the vimscript engine)
- Pre-computed AWD state machine transitions
- Pre-computed cursor glide targets between hunks
- Pre-computed word boundaries for word batching

**FR-3.4:** The pace tool SHALL expand the op stream:
- Group consecutive delete chars into `batch_delete` ops
- Group consecutive insert chars into `batch_insert` ops
- Insert `delay` ops between operations
- Insert `glide` ops before each hunk
- Insert `newline_delete` / `newline_insert` for \n ops
- Insert `highlight` / `clear_highlight` ops as needed
- Insert `snapshot` ops at hunk boundaries (if requested)

**FR-3.5:** The pace tool SHALL be implemented in Perl and C.
All three SHALL produce identical timed op streams.

**FR-3.6:** The pace tool SHALL be testable independently:
- Feed it known input ops
- Compare output timed op stream with expected
- No terminal, no animation

#### FR-4: Virtual Text Buffer

**FR-4.1:** The buffer SHALL support lines as arrays of Unicode
characters (not bytes).

**FR-4.2:** The cursor SHALL be able to move to any line (for
positioning during animation).

**FR-4.3:** The buffer SHALL support split (insert \n) and merge
(delete \n) operations that keep the buffer state consistent with the
op stream.

### 5.2 Non-Functional Requirements

#### NFR-1: Performance

- The animator SHALL achieve 60fps for files up to 1000 lines (Go/C)
- The animator SHALL achieve 30fps for files up to 1000 lines (C++)
- The pace tool SHALL process 10,000 ops in under 100ms
- The postprocess tool SHALL process 10,000 ops in under 50ms
- `--no-display` mode SHALL process 10,000 ops in under 50ms

#### NFR-2: Portability

- Go binary: statically linked, zero runtime deps
- Perl: requires Perl 5.10+; non-core CPAN modules allowed
- C binary: statically linked, zero runtime deps
- All three SHALL run on Linux, macOS, BSD

#### NFR-3: Compatibility

- The timed op stream format SHALL be language-agnostic
- The same timed op stream SHALL produce identical animations in
  Perl and C
- The precomputed diff format (from compute tools) SHALL be unchanged

#### NFR-4: Testability

- Each tool SHALL be testable independently via stdin/stdout
- The animator's `--no-display` + `snapshot` mode SHALL enable
  round-trip testing without a terminal
- The pace and postprocess tools SHALL be pure functions
  (input → output, no side effects)

---

## 6. CLI Interface

### 6.1 Full Pipeline

```bash
# Full pipeline with separate tools
diffvim-compute-cpp old.py new.py |
  diffvim-postprocess --op-order optimize --semantic-cleanup |
  diffvim-pace --delete-pacing word --pacing gaussian |
  diffvim-animator-c --speed 1.0 --scroll zz old.py

# Or with a wrapper script that builds the pipeline (no --tool flag
# needed anymore — diffvim-pipeline auto-selects the C++ compute tool
# and falls back to Perl when it's missing)
diffvim-pipeline --op-order optimize --delete-pacing word old.py new.py
```

### 6.2 Animator Options

```
diffvim-animator-c [options] <oldfile>
diffvim-animator-c [options] --multi <old1:new1> <old2:new2> ...

Input:
  <oldfile>                The file to animate (loaded into buffer)
  --timed-ops FILE         Read timed op stream from FILE (default: stdin)

Display:
  --no-display             Process ops without rendering (for testing)
  --speed N                Speed multiplier (default: 1.0)
  --scroll zz|zt|zb|none   Cursor scroll position (default: zz)
  --highlight MODE         Highlight mode (from timed op stream)
  --dim-unchanged          Dim unchanged lines (from timed op stream)

Output:
  --output FILE            Write final buffer to FILE
  --snapshot FILE          Write buffer to FILE at end of processing
  --dry-run                Print op stream summary without processing

Interaction:
  --step-mode              Space advances one op at a time
  --no-input               Don't read keyboard input (for CI)

Multi-file:
  --multi                  Multi-file mode

Other:
  --version, -V
  --help, -h
```

### 6.3 Postprocess Options

```
diffvim-postprocess [options]  < raw_ops  > ordered_ops

  --op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite
  --semantic-cleanup
  --indent-aware
  --overwrite
```

### 6.4 Pace Options

```
diffvim-pace [options]  < ordered_ops  > timed_ops

  --delete-pacing char|rapid-eol|rapid-identical|accel|word|instant
  --delete-speed slow|normal|fast|instant
  --delete-threshold N
  --insert-pacing char|word|accel
  --insert-speed slow|normal|fast
  --pacing uniform|adaptive|gaussian|review
  --snapshot FILE          Insert a snapshot op at the end
  --scroll zz|zt|zb|none   Add scroll ops to the stream
  --highlight MODE         Add highlight ops to the stream
  --dim-unchanged          Add dim ops to the stream
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

Each tool is tested independently:

- **Postprocess tests:** Feed known raw ops, verify ordered output.
  Test each mode independently and in combination.
- **Pace tests:** Feed known ordered ops, verify timed op stream.
  Test each pacing mode, verify delays, batch sizes, glide targets.
- **Animator buffer tests:** Feed known timed ops with `--no-display`,
  verify buffer state via snapshots.
- **Animator render tests:** Feed known timed ops, capture terminal
  output, compare with expected ANSI sequences.

### 7.2 Integration Tests

- **Round-trip tests:** For each example file pair:
  1. Compute diff
  2. Postprocess
  3. Pace
  4. Animate with `--no-display --snapshot /tmp/result.txt`
  5. Compare /tmp/result.txt with the expected new file
- **Pipeline tests:** Verify that piping the tools together produces
  the same result as running them with intermediate files.

### 7.3 Cross-Language Tests

- Run the same timed op stream through Perl and C animators
- Compare snapshot outputs — they must be identical
- Compare terminal output — they must be visually identical (allowing
  for terminal-specific differences)

---

## 8. Documentation Skeleton

```
diffvim-animator-c/
├── README.md                    # Overview, install, quick start
├── CHANGELOG.md
├── LICENSE                      # Artistic 2.0 / GPL 3.0 (dual)
├── Makefile                     # Build all variants
│
├── go/                          # Go implementations
│   ├── animator/main.go         # Animator (terminal display)
│   ├── postprocess/main.go      # Post-processing tool
│   ├── pace/main.go             # Pacing tool
│   └── go.mod
│
├── perl/                        # Perl implementations
│   ├── animator.pl              # Animator
│   ├── postprocess.pl           # Post-processing tool
│   ├── pace.pl                  # Pacing tool
│   └── lib/
│       ├── Buffer.pm            # Virtual buffer
│       ├── Renderer.pm          # Terminal renderer
│       └── Input.pm             # Keyboard input
│
├── c/                           # C implementations
│   ├── animator.c               # Animator
│   ├── postprocess.c            # Post-processing tool
│   ├── pace.c                   # Pacing tool
│   ├── buffer.h / buffer.c      # Virtual buffer
│   ├── renderer.h / renderer.c  # Terminal renderer
│   └── Makefile
│
├── man/
│   ├── diffvim-animator-c.1
│   ├── diffvim-postprocess.1
│   └── diffvim-pace.1
│
├── completion/
│   ├── diffvim-animator-c.bash
│   ├── diffvim-animator-c.fish
│   └── _diffvim-animator-c
│
├── tests/
│   ├── test_postprocess.pl      # Postprocess unit tests
│   ├── test_pace.pl             # Pace unit tests
│   ├── test_buffer.pl           # Buffer unit tests
│   ├── test_animator.pl         # Animator integration tests
│   ├── test_roundtrip.pl        # Round-trip correctness
│   ├── test_cross_language.pl   # Perl vs C vs Go parity
│   └── test_performance.pl      # Benchmarks
│
└── docs/
    ├── ARCHITECTURE.md          # Pipeline architecture
    ├── TIMED_OP_FORMAT.md       # Timed op stream format spec
    ├── BUFFER_MODEL.md          # Virtual buffer
    ├── PACING.md                # Pacing algorithm reference
    ├── RENDERING.md             # Terminal rendering guide
    ├── TESTING.md               # Testing strategy
    └── MIGRATION.md             # Migrating from vim-based diffvim
```

---

## 9. Migration Path

### 9.1 Phase 1: Implement postprocess and pace tools

- Implement `diffvim-postprocess` in Perl (primary), C, Go
- Implement `diffvim-pace` in Perl (primary), C, Go
- Test independently with known op streams
- Verify they produce identical output across languages

### 9.2 Phase 2: Implement the animator

- Implement the virtual buffer (C primary, Perl fallback)
- Implement the terminal renderer (C primary, Perl fallback)
- Implement `--no-display` + `snapshot` mode for testing
- Test with timed op streams from Phase 1

### 9.3 Phase 3: Integration

- Add `--animator` flag to the bash `diffvim` wrapper that builds
  the pipeline: compute | postprocess | pace | animator
- Keep vim-based engine as default (backwards compat)
- Update documentation

### 9.4 Phase 4: Make animator the default

- Change `diffvim` to use the animator by default
- Add `--vim` flag to fall back to the vim-based engine
- Deprecate the vimscript engine

---

## 10. Open Questions

1. **Timed op stream format:** Should it be text-based (human-readable,
   easy to debug) or binary (faster to parse, more compact)? Text is
   recommended for v1; binary can be added later.

2. **Go terminal library:** Raw ANSI escapes (zero dependency) vs
   `tcell`/`bubbletea` (richer but adds dependency)? Raw is recommended
   for v1; the animator's rendering needs are simple enough.

3. **C Unicode handling:** Use `wchar_t` (platform-dependent) or
   manual UTF-8 (more portable but more code)? Manual UTF-8 is
   recommended for portability.

4. **Perl non-core modules:** Which CPAN modules to require?
   `Term::ReadKey` (input) and `Term::ANSIScreen` (rendering) are
   recommended. Both are widely available.

5. **Back button:** The current vim engine supports `b` (back to
   previous hunk) via snapshot/restore. Should the animator support
   this? It would require the pace tool to insert `snapshot` ops at
   hunk boundaries, and the animator to restore from snapshots.
