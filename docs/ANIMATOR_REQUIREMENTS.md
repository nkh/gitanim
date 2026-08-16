# diffvim-animator: Standalone Animation Application

## Requirements Specification & Architecture Design

**Document version:** 1.0
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

### 1.2 Proposed Solution

A **standalone terminal application** (`diffvim-animator`) that:

- Reads a precomputed diff file (produced by `diffvim-compute-{c,cpp,rust,go}`)
- Displays the old file content in a terminal
- Animates the transformation into the new file by applying char ops
- Does NOT depend on vim, tmux, or any editor
- Supports all the same options as the current diffvim (--op-order,
  --delete-pacing, --insert-pacing, --pacing, --highlight, etc.)

### 1.3 Key Advantage

A standalone application has a **virtual text buffer** that it fully
controls. It can:
- Keep deleted lines in the buffer as "ghost lines" (invisible but
  maintaining line numbers)
- Move the cursor freely without buffer manipulation overhead
- Render only what changed (incremental redraw)
- Support any terminal, not just vim

---

## 2. Language Comparison

### 2.1 Bash

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★☆☆ | `tput`, ANSI escape sequences; no curses |
| Text buffer | ★☆☆☆☆ | No arrays of strings; everything is external commands |
| Performance | ★☆☆☆☆ | Subprocess spawning for every operation |
| Unicode | ★★☆☆☆ | Depends on `wc -m`, `printf`; fragile |
| Timing | ★★☆☆☆ | `sleep` only; no sub-millisecond precision |
| Maintainability | ★★☆☆☆ | Hard to structure complex logic |
| Dependencies | ★★★★★ | None (bash 4+ is everywhere) |

**Verdict:** Not suitable as the primary implementation. Bash is fine for
the launcher script but cannot handle a virtual text buffer, precise
timing, or efficient terminal rendering.

### 2.2 Perl

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★☆☆ | `Term::ANSIScreen`, raw escape sequences |
| Text buffer | ★★★★☆ | Native arrays, `@lines`; easy to manipulate |
| Performance | ★★★☆☆ | Interpreted, but fast enough for text ops |
| Unicode | ★★★☆☆ | `use utf8`, `Encode` module; manual handling |
| Timing | ★★★★☆ | `Time::HiRes` for sub-millisecond precision |
| Maintainability | ★★★☆☆ | Verbose but structured; CPAN ecosystem |
| Dependencies | ★★★★☆ | Perl 5.10+ is nearly universal on Unix |

**Verdict:** Good candidate. Perl has native text manipulation, good
timing control, and is widely available. The main drawback is Unicode
complexity and the lack of a built-in curses library (requires CPAN
modules for full-screen terminal control).

### 2.3 Go

| Aspect | Rating | Notes |
|--------|--------|-------|
| Terminal control | ★★★★★ | `github.com/charmbracelet/bubbletea`, `tcell`, `termbox` |
| Text buffer | ★★★★★ | Native `[]string`, `strings.Builder`; fast |
| Performance | ★★★★★ | Compiled, concurrent, sub-millisecond timing |
| Unicode | ★★★★★ | Native UTF-8 support, `runes` |
| Timing | ★★★★★ | `time.Timer`, `time.After`, channel-based |
| Maintainability | ★★★★★ | Strongly typed, gofmt, excellent tooling |
| Dependencies | ★★★☆☆ | Requires Go toolchain to build; produces static binary |

**Verdict:** Best candidate. Go has native UTF-8, excellent terminal
libraries, compiled performance, and produces a single static binary.
The main drawback is requiring Go to build, but the binary has zero
runtime dependencies.

### 2.4 Speed Impact Analysis

| Operation | Bash | Perl | Go |
|-----------|------|------|----|
| Read 1000-line file | ~50ms (`cat`) | ~5ms | ~1ms |
| Apply 100 char ops | ~500ms (subprocess per op) | ~10ms | ~0.1ms |
| Full screen redraw (80x24) | ~100ms (multiple `echo`) | ~20ms | ~1ms |
| Incremental redraw | N/A (no diff support) | ~5ms | ~0.5ms |
| Unicode char width | ~5ms (`wc -m` subprocess) | ~0.5ms | ~0.01ms |
| Timer precision | 10ms (`sleep 0.01`) | 1ms (`Time::HiRes`) | 0.1ms (`time.After`) |

**Conclusion:** Go is 10-100x faster than Perl and 100-1000x faster than
bash for animation-critical operations. For a 60fps animation (16ms per
frame), Go can do the rendering in <1ms, leaving 15ms for the animation
delay. Perl can do it in ~5ms, which is acceptable. Bash cannot achieve
60fps.

### 2.5 Recommendation

**Primary implementation: Go** — best performance, best terminal support,
native UTF-8, single binary distribution.

**Fallback implementation: Perl** — for systems without Go, Perl provides
acceptable performance and is universally available.

**Bash: launcher only** — a thin wrapper that finds the right binary and
passes options through.

---

## 3. Requirements

### 3.1 Functional Requirements

#### FR-1: Input Handling

- **FR-1.1:** The application SHALL accept a precomputed diff file
  (produced by `diffvim-compute-{c,cpp,rust,go}`) as input.
- **FR-1.2:** The application SHALL accept two file paths (old, new) and
  compute the diff inline using a bundled or external compute tool.
- **FR-1.3:** The application SHALL accept a unified diff file (`--diff`)
  as input.
- **FR-1.4:** The application SHALL support multi-file animation
  (`--multi old1:new1 old2:new2 ...`).
- **FR-1.5:** The application SHALL support git history replay
  (`--git-rev REV..REV <file>`).

#### FR-2: Virtual Text Buffer

- **FR-2.1:** The application SHALL maintain an in-memory virtual text
  buffer representing the file being animated.
- **FR-2.2:** The buffer SHALL support lines as arrays of Unicode
  characters (runes), not bytes.
- **FR-2.3:** The buffer SHALL support "ghost lines" — lines that have
  been deleted but whose line numbers are preserved to avoid pulling
  subsequent lines up.
- **FR-2.4:** The buffer SHALL support a logical cursor position
  (line, column) that can exceed the line length (for end-of-line
  insertions).
- **FR-2.5:** The buffer SHALL track a line offset to map logical
  (diff) line numbers to physical (buffer) line numbers.

#### FR-3: Animation Operations

- **FR-3.1:** The application SHALL apply char ops (keep, delete, insert)
  to the virtual buffer.
- **FR-3.2:** For `keep` ops: advance the cursor (no buffer change).
- **FR-3.3:** For `delete` ops: remove the character at the cursor
  position. For `\n` deletes: mark the line as a ghost line and move
  the cursor to the next line (DO NOT remove the line from the buffer).
- **FR-3.4:** For `insert` ops: insert the character at the cursor
  position and advance. For `\n` inserts: split the line at the cursor.
- **FR-3.5:** The application SHALL support all unified option selectors:
  - `--op-order` (6 modes)
  - `--delete-pacing` (6 modes)
  - `--insert-pacing` (3 modes)
  - `--pacing` (4 modes)
  - `--highlight` (4 modes)
- **FR-3.6:** The application SHALL support `--delete-speed`,
  `--delete-threshold`, `--insert-speed` tuning parameters.

#### FR-4: Terminal Rendering

- **FR-4.1:** The application SHALL render the virtual buffer to the
  terminal using ANSI escape sequences.
- **FR-4.2:** The application SHALL use incremental rendering — only
  redraw lines that changed since the last frame.
- **FR-4.3:** The application SHALL support cursor positioning via
  ANSI escape sequences (`\033[<line>;<col>H`).
- **FR-4.4:** The application SHALL support color via ANSI escape
  sequences (256-color and truecolor).
- **FR-4.5:** The application SHALL handle terminal resize events
  (SIGWINCH) and re-render.
- **FR-4.6:** The application SHALL support scroll position
  (`--scroll zz|zt|zb|none`).
- **FR-4.7:** The application SHALL support syntax highlighting via
  external highlighters (e.g., `bat`, `highlight`) or built-in regex
  patterns for common languages.

#### FR-5: Cursor Animation

- **FR-5.1:** The application SHALL animate the cursor gliding between
  change locations with ease-in-out cubic acceleration.
- **FR-5.2:** The cursor glide SHALL be computed mathematically (not
  via timer callbacks) and rendered at the display refresh rate.
- **FR-5.3:** The cursor SHALL be visible during the glide, showing the
  path from the previous position to the target.
- **FR-5.4:** The glide duration SHALL be computed as:
  `min(move_min_ms, min(move_max_ms, distance * move_ms_per_unit))`
  divided by the speed multiplier.

#### FR-6: User Interaction

- **FR-6.1:** The application SHALL support keyboard input during
  animation (non-blocking):
  - `Space` — pause/resume
  - `n` — skip current hunk (apply instantly)
  - `b` — back to previous hunk (revert)
  - `q` — stop animation
  - `+` / `-` — speed up / slow down
  - `=` — reset speed
  - `?` — show help overlay
  - `]` / `[` — next/previous file (multi-file mode)
- **FR-6.2:** The application SHALL support `--step-mode` (Space advances
  one op at a time).
- **FR-6.3:** The application SHALL read input via raw terminal mode
  (no Enter required, no echo).

#### FR-7: Output

- **FR-7.1:** After animation, the application SHALL leave the terminal
  in a clean state (cursor visible, normal colors).
- **FR-7.2:** The application SHALL support `--output FILE` to write the
  result to a file.
- **FR-7.3:** The application SHALL support `--dry-run` to print diff
  info without animating.
- **FR-7.4:** The application SHALL support `--log-mode 1|2` to generate
  a log file showing the operations.
- **FR-7.5:** The application SHALL support `--keep-dirty` (no-op in
  standalone mode, but accepted for compatibility).

#### FR-8: Post-Processing Pipeline

- **FR-8.1:** The application SHALL apply the same post-processing
  pipeline as the current diffvim:
  - `--op-order` (natural, optimize, left-to-right, end-first,
    end-first-smart, overwrite)
  - `--semantic-cleanup`
  - `--indent-aware`
- **FR-8.2:** The post-processing SHALL be applied to the char ops
  BEFORE animation begins (not during).

#### FR-9: Highlighting

- **FR-9.1:** `--highlight none` — no highlighting.
- **FR-9.2:** `--highlight inline` — paint freshly typed chars green,
  deleted chars red, fade after N ms.
- **FR-9.3:** `--highlight word` — highlight the word at the cursor
  before it changes.
- **FR-9.4:** `--highlight hunk` — highlight the entire hunk region
  before animating it.
- **FR-9.5:** `--dim-unchanged` — reduce brightness of unchanged lines.

#### FR-10: Deletion Pacing

- **FR-10.1:** `--delete-pacing char` — one char per frame.
- **FR-10.2:** `--delete-pacing rapid-eol` — rapid shot at end of line.
- **FR-10.3:** `--delete-pacing rapid-identical` — accelerate identical
  char runs.
- **FR-10.4:** `--delete-pacing accel` — accelerate through long runs.
- **FR-10.5:** `--delete-pacing word` — word-by-word with acceleration
  (default). First 3 non-space chars slow, then words with accelerating
  delay, then rest rapid. Spaces deleted instantly.
- **FR-10.6:** `--delete-pacing instant` — all strategies enabled.
- **FR-10.7:** For `\n` deletes: mark line as ghost, move cursor to next
  line. DO NOT pull next line up.

#### FR-11: Insertion Pacing

- **FR-11.1:** `--insert-pacing char` — one char per frame (default).
- **FR-11.2:** `--insert-pacing word` — batch short words (<=8 chars).
- **FR-11.3:** `--insert-pacing accel` — accelerate char-by-char inserts.

#### FR-12: Timing

- **FR-12.1:** `--pacing uniform` — fixed delays.
- **FR-12.2:** `--pacing adaptive` — slow down in complex regions.
- **FR-12.3:** `--pacing gaussian` — add human-like jitter.
- **FR-12.4:** `--pacing review` — pause every N lines in large hunks.

### 3.2 Non-Functional Requirements

#### NFR-1: Performance

- **NFR-1.1:** The application SHALL achieve at least 30fps (33ms per
  frame) for files up to 1000 lines.
- **NFR-1.2:** The application SHALL achieve at least 60fps (16ms per
  frame) for files up to 100 lines.
- **NFR-1.3:** Startup time (from launch to first frame) SHALL be under
  100ms for files up to 1000 lines.
- **NFR-1.4:** Memory usage SHALL be under 50MB for files up to 10,000
  lines.

#### NFR-2: Portability

- **NFR-2.1:** The application SHALL run on any POSIX terminal (Linux,
  macOS, BSD).
- **NFR-2.2:** The application SHALL work in any terminal that supports
  ANSI escape sequences (virtually all modern terminals).
- **NFR-2.3:** The Go binary SHALL be statically linked (no shared
  library dependencies).
- **NFR-2.4:** The Perl implementation SHALL require only core modules
  (no CPAN dependencies).

#### NFR-3: Compatibility

- **NFR-3.1:** The application SHALL accept the same precomputed diff
  format as the current diffvim.
- **NFR-3.2:** The application SHALL support the same CLI options as the
  current diffvim (unified selectors).
- **NFR-3.3:** The application SHALL produce the same final output as
  the current diffvim (the buffer content after animation matches the
  new file).

#### NFR-4: Testability

- **NFR-4.1:** The virtual buffer SHALL be testable independently of
  the terminal renderer.
- **NFR-4.2:** The animation engine SHALL be testable in synchronous
  mode (no timers, no terminal) — apply all ops and check the final
  buffer.
- **NFR-4.3:** The terminal renderer SHALL be testable via a mock
  terminal (capture output, compare with expected).

---

## 4. Architecture

### 4.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    diffvim-animator                          │
│                                                             │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │  Input Layer  │──▶│  Diff Loader │──▶│  Post-Proc   │    │
│  │               │   │              │   │  Pipeline    │    │
│  │ - file paths  │   │ - parse diff │   │ - op-order   │    │
│  │ - precomputed │   │ - build hunks│   │ - semantic   │    │
│  │ - --diff      │   │              │   │ - indent     │    │
│  │ - --multi     │   │              │   │              │    │
│  └──────────────┘   └──────────────┘   └──────┬───────┘    │
│                                                │            │
│                                                ▼            │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │  Terminal     │◀──│  Renderer    │◀──│  Animation   │    │
│  │  Output       │   │              │   │  Engine      │    │
│  │               │   │ - incremental │   │              │    │
│  │ - ANSI escape │   │   redraw     │   │ - char ops   │    │
│  │ - cursor pos  │   │ - colors     │   │ - cursor glide│   │
│  │ - colors      │   │ - scroll     │   │ - pacing     │    │
│  └──────────────┘   └──────────────┘   └──────┬───────┘    │
│                                                │            │
│                                                ▼            │
│                                       ┌──────────────┐      │
│                                       │  Virtual     │      │
│                                       │  Buffer      │      │
│                                       │              │      │
│                                       │ - lines[]    │      │
│                                       │ - ghost[]    │      │
│                                       │ - cursor     │      │
│                                       │ - line_offset│      │
│                                       └──────────────┘      │
│                                                             │
│  ┌──────────────┐                    ┌──────────────┐       │
│  │  Input       │                    │  Timing      │       │
│  │  Handler     │                    │  Controller  │       │
│  │              │                    │              │       │
│  │ - raw mode   │                    │ - frame rate │       │
│  │ - non-blocking│                   │ - delays     │       │
│  │ - key events │                    │ - speed mult │       │
│  └──────────────┘                    └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Component Descriptions

#### 4.2.1 Input Layer

Parses CLI arguments, identifies the input mode (two-file, precomputed,
unified diff, multi-file, git replay), and loads the old file content
into the virtual buffer.

#### 4.2.2 Diff Loader

Reads the precomputed diff file (or computes one inline by calling an
external compute tool), parses the char ops, and builds hunk structures.

#### 4.2.3 Post-Processing Pipeline

Applies the op-order, semantic-cleanup, indent-aware, and other
post-processing passes to the char ops before animation begins. This is
identical to the current diffvim's post-processing but runs in the
application, not in the compute tool.

#### 4.2.4 Virtual Buffer

The core innovation. An in-memory representation of the file being
animated:

```go
type VirtualBuffer struct {
    lines      []string    // visible line content
    ghostLines []bool      // true = line is deleted (ghost), don't render
    cursorLine int         // logical cursor line (0-indexed)
    cursorCol  int         // logical cursor column (can exceed line length)
    lineOffset int         // offset for multi-hunk tracking
    width      int         // terminal width
    height     int         // terminal height
}
```

**Key operations:**
- `KeepChar(ch)` — advance cursor
- `DeleteChar()` — remove char at cursor
- `DeleteNewline()` — mark current line as ghost, move cursor to next line
- `InsertChar(ch)` — insert char at cursor
- `InsertNewline()` — split line at cursor
- `Render()` — output only changed lines since last render

**Ghost lines:** When a `\n` is deleted, the line is marked as ghost.
Ghost lines are not rendered (they appear as blank space or are skipped
entirely), but they maintain line numbering so subsequent lines don't
shift up. At the end of the animation, ghost lines are removed for the
final output.

#### 4.2.5 Animation Engine

Walks the char ops and applies them to the virtual buffer with timing:
- Handles all pacing modes (word, accel, rapid-eol, etc.)
- Computes cursor glide between hunks
- Manages AWD (adaptive word delete) state machine
- Calls the renderer after each frame

#### 4.2.6 Renderer

Converts the virtual buffer to terminal output:
- Incremental rendering: only output lines that changed
- ANSI escape sequences for cursor positioning and colors
- Scroll management (zz, zt, zb, none)
- Syntax highlighting (optional, via external highlighter or regex)

#### 4.2.7 Terminal Output

Raw ANSI escape sequence output to stdout. No curses dependency.

#### 4.2.8 Input Handler

Reads keyboard input in raw terminal mode (non-blocking):
- Sets terminal to raw mode on startup (no echo, no line buffering)
- Restores terminal on exit
- Reads single bytes without blocking

#### 4.2.9 Timing Controller

Manages frame timing and delays:
- Uses high-resolution timers (Go: `time.Timer`, Perl: `Time::HiRes`)
- Supports speed multiplier
- Supports Gaussian jitter
- Frame rate: 60fps target, 30fps minimum

### 4.3 Data Flow

```
1. Parse CLI args → determine input mode
2. Load old file → populate virtual buffer
3. Load/compute diff → build hunks with char ops
4. Apply post-processing → reorder/cleanup ops
5. For each hunk:
   a. Glide cursor to target line (animated)
   b. For each char op:
      - Apply op to virtual buffer
      - Render changed lines to terminal
      - Wait for delay (based on pacing mode)
      - Check for user input (non-blocking)
   c. Pause between hunks
6. Animation complete → cleanup ghost lines → write output if needed
7. Restore terminal → exit
```

### 4.4 Ghost Line Implementation

The key innovation that solves the `\n` merge problem:

```
Buffer state after deleting line 2 ("line2\n"):

Before:              After DeleteNewline():
line1                line1
line2  ← cursor      [GHOST]  ← cursor was here, moved to line 3
line3                line3  ← cursor now here
line4                line4
line5                line5

Rendering:           Terminal shows:
line1                line1
                     (blank line — ghost not rendered, or rendered as ~)
line3                line3
line4                line4
line5                line5
```

The cursor moves to line 3 and continues deleting `line3` there. The
ghost line maintains the line numbering so nothing shifts up.

**At animation end:** Remove all ghost lines and write the final buffer.
The result matches the expected new file.

---

## 5. CLI Interface

### 5.1 Usage

```
diffvim-animator [options] <oldfile> <newfile>
diffvim-animator [options] --multi <old1:new1> <old2:new2> ...
diffvim-animator [options] --git-rev REV..REV <file>
diffvim-animator [options] --precomputed FILE <oldfile> <newfile>
diffvim-animator [options] --diff FILE
```

### 5.2 Options

Identical to the current diffvim's unified options:

```
CORE:
  --speed N (-s)           Speed multiplier
  --output FILE (-o)       Write result to FILE
  --context N (-c)         Fold unchanged regions
  --scroll zz|zt|zb|none   Cursor scroll position
  --multi (-m)             Multi-file mode
  --git-rev REV..REV (-R)  Git history replay
  --dry-run (-d)           Print diff without animating
  --tool c|cpp|rust|go     Use external compute tool
  --precomputed FILE       Use precomputed diff
  --preset NAME (-p)       Apply preset
  --version, -V
  --help, -h

DIFF ALGORITHM:
  --algorithm lcs|myers|patience (-a)
  --semantic-cleanup (-S)
  --indent-aware (-i)
  --word-diff (-w)

OP ORDER:
  --op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite

DELETION PACING:
  --delete-pacing char|rapid-eol|rapid-identical|accel|word|instant
  --delete-speed slow|normal|fast|instant
  --delete-threshold N

INSERTION PACING:
  --insert-pacing char|word|accel
  --insert-speed slow|normal|fast

TIMING:
  --pacing uniform|adaptive|gaussian|review

HIGHLIGHTING:
  --highlight none|inline|word|hunk
  --highlight-color COLOR
  --highlight-duration-ms N
  --dim-unchanged (-D)
  --dim-unchanged-pct N
```

---

## 6. Testing Strategy

### 6.1 Unit Tests

- **Virtual buffer tests:** Apply char ops to the buffer, verify the
  final content matches the expected new file. Test ghost lines, cursor
  positioning, Unicode handling.
- **Post-processing tests:** Apply each op-order mode, verify the ops
  are reordered correctly.
- **Pacing tests:** Verify AWD state machine transitions, word boundary
  detection, acceleration curves.

### 6.2 Integration Tests

- **Round-trip tests:** For each example file pair, compute the diff,
  apply all ops, verify the buffer matches the new file.
- **Rendering tests:** Capture terminal output, compare with expected
  escape sequences.
- **Input tests:** Simulate key presses, verify pause/resume/skip/quit.

### 6.3 Performance Tests

- **Frame rate:** Measure FPS for files of 100, 1000, 10000 lines.
- **Startup time:** Measure time from launch to first frame.
- **Memory:** Measure peak memory usage.

---

## 7. Documentation Skeleton

### 7.1 Files to Create

```
diffvim-animator/
├── README.md                    # Overview, install, quick start
├── CHANGELOG.md                 # Version history
├── LICENSE                      # Artistic 2.0 / GPL 3.0 (dual)
├── Makefile                     # Build Go and/or Perl variants
│
├── go/                          # Go implementation (primary)
│   ├── main.go                  # Entry point, CLI parsing
│   ├── buffer.go                # Virtual buffer with ghost lines
│   ├── engine.go                # Animation engine
│   ├── renderer.go              # Terminal renderer
│   ├── input.go                 # Keyboard input handler
│   ├── timing.go                # Timing controller
│   ├── postprocess.go           # Post-processing pipeline
│   ├── pacing.go                # Deletion/insertion pacing logic
│   ├── highlight.go             # Highlight modes
│   ├── diff.go                  # Diff file loader
│   ├── presets.go               # Preset definitions
│   └── go.mod                   # Go module definition
│
├── perl/                        # Perl implementation (fallback)
│   ├── animator.pl              # Entry point
│   ├── Buffer.pm                # Virtual buffer
│   ├── Engine.pm                # Animation engine
│   ├── Renderer.pm              # Terminal renderer
│   ├── Input.pm                 # Keyboard input
│   ├── Timing.pm                # Timing controller
│   ├── PostProcess.pm           # Post-processing
│   ├── Pacing.pm                # Pacing logic
│   └── Highlight.pm            # Highlight modes
│
├── man/
│   ├── diffvim-animator.1       # Manpage
│   └── diffvim-animator.1.html  # HTML manpage
│
├── completion/
│   ├── diffvim-animator.bash    # Bash completion
│   ├── diffvim-animator.fish    # Fish completion
│   └── _diffvim-animator        # Zsh completion
│
├── tests/
│   ├── test_buffer.pl           # Virtual buffer unit tests
│   ├── test_engine.pl           # Animation engine tests
│   ├── test_renderer.pl         # Renderer tests
│   ├── test_postprocess.pl      # Post-processing tests
│   ├── test_pacing.pl           # Pacing mode tests
│   ├── test_roundtrip.pl        # Round-trip correctness tests
│   └── test_performance.pl      # Performance benchmarks
│
└── docs/
    ├── ARCHITECTURE.md          # Architecture deep-dive
    ├── BUFFER_MODEL.md          # Virtual buffer & ghost lines
    ├── PACING.md                # Pacing modes reference
    ├── RENDERING.md             # Terminal rendering guide
    ├── REQUIREMENTS.md          # This document
    └── MIGRATION.md             # Migrating from vim-based diffvim
```

### 7.2 Documentation Content

#### README.md
- What it is (1 paragraph)
- Why it exists (the `\n` merge problem, vim dependency)
- Installation (build from source, or download binary)
- Quick start (3 examples)
- Options reference (link to manpage)
- Comparison with vim-based diffvim
- License

#### ARCHITECTURE.md
- High-level diagram
- Component descriptions
- Data flow
- Ghost line implementation
- Threading model (Go: goroutines for input + timer + render)

#### BUFFER_MODEL.md
- Virtual buffer data structure
- Ghost line concept
- Why ghost lines solve the `\n` merge problem
- Cursor tracking (logical vs physical position)
- Line offset for multi-hunk animation

#### PACING.md
- All pacing modes with visual diagrams
- AWD state machine (phase 0→1→2→3)
- How spaces are handled in phase 1
- Acceleration curves

#### RENDERING.md
- ANSI escape sequences used
- Incremental rendering algorithm
- Scroll management
- Color support (256-color, truecolor)
- Syntax highlighting integration

#### MIGRATION.md
- How to migrate from vim-based diffvim
- Option mapping (all options are identical)
- Behavioral differences (ghost lines, no `:q`)
- Performance comparison

---

## 8. Build and Distribution

### 8.1 Go Build

```bash
cd go && go build -o ../bin/diffvim-animator .
```

Produces a single static binary (~5-10MB) with no runtime dependencies.

### 8.2 Perl Distribution

```bash
# No build needed — just run directly
perl perl/animator.pl [options] old.py new.py
```

### 8.3 Installation

```bash
# Go binary
sudo cp bin/diffvim-animator /usr/local/bin/
sudo cp man/diffvim-animator.1 /usr/local/share/man/man1/

# Perl
sudo cp perl/animator.pl /usr/local/bin/diffvim-animator
sudo cp -r perl/lib/* /usr/local/lib/perl5/
```

---

## 9. Migration Path

### 9.1 Phase 1: Implement Go version

- Implement the virtual buffer with ghost lines
- Implement the animation engine with all pacing modes
- Implement the terminal renderer
- Port all post-processing logic from the vimscript engine
- Test against all 42 example file pairs

### 9.2 Phase 2: Integration

- Add `--animator` flag to the bash `diffvim` script that launches
  the standalone animator instead of vim
- Keep the vim-based engine as the default (backwards compat)
- Document the migration path

### 9.3 Phase 3: Make animator the default

- Change the bash `diffvim` script to use the animator by default
- Add `--vim` flag to fall back to the vim-based engine
- Update all documentation

---

## 10. Open Questions

1. **Syntax highlighting:** Should we bundle a highlighter (e.g., a
   minimal regex-based one) or depend on an external tool (`bat`,
   `highlight`)? Bundling adds complexity; external adds a dependency.

2. **Perl terminal library:** Should we use `Term::ANSIScreen` (CPAN)
   or raw escape sequences? Raw is more portable but more code.

3. **Input handling in Perl:** `Term::ReadKey` is not core. Should we
   use `select()` on STDIN with raw mode via `stty`, or require
   `Term::ReadKey`?

4. **Go terminal library:** Should we use `tcell`, `termbox`, or raw
   escape sequences? Raw is zero-dependency but requires handling
   terminal capabilities manually.

5. **Ghost line rendering:** Should ghost lines be rendered as blank
   lines, `~` (like vim), or skipped entirely (lines below shift up
   visually but not logically)?

---

## 11. Conclusion

The standalone animation application solves the fundamental limitation
of the vim buffer model (the `\n` merge problem) by using a virtual
text buffer with ghost lines. Go is the recommended implementation
language due to its performance, terminal library ecosystem, and
single-binary distribution. Perl is a viable fallback for systems
without Go.

The application maintains full compatibility with the existing diffvim
CLI options and precomputed diff format, ensuring a smooth migration
path.
