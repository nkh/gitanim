# ad_vim — Requirements Specification

**Document version:** 2.0
**Date:** 2026-08-17
**Status:** Requirements document for the application as it exists now
**Scope:** Complete specification of diffvim's current functionality,
architecture, interfaces, and documentation structure.

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Overview](#2-system-overview)
3. [Functional Requirements](#3-functional-requirements)
4. [Non-Functional Requirements](#4-non-functional-requirements)
5. [Interface Specifications](#5-interface-specifications)
6. [Architecture](#6-architecture)
7. [Data Formats](#7-data-formats)
8. [Option Reference](#8-option-reference)
9. [Test Specification](#9-test-specification)
10. [Documentation Skeleton](#10-documentation-skeleton)
11. [Known Limitations](#11-known-limitations)
12. [Glossary](#12-glossary)

---

## 1. Executive Summary

### 1.1 What ad_vim Is

ad_vim is a command-line tool that animates code diffs in vim as if a
human were typing them. Given two versions of a file, ad_vim opens the
old version in vim and animates the transformation into the new version
character by character, with the cursor gliding smoothly between change
locations.

### 1.2 Current State

| Metric | Value |
|--------|-------|
| Main script (bash + vimscript) | 4,517 lines |
| Perl implementation | 1,970 lines |
| tmux implementation | 1,673 lines |
| External compute tools | 1 (C++) — Perl fallback when binary missing |
| Vimscript engine functions | 73 |
| CLI options (unified) | ~40 |
| Environment variables | 114 |
| Config dict entries | 168 |
| Example file pairs | 42 (15+ languages) |
| Test files | 33 |
| Test assertions | 410+ |
| Documentation files | 37 |
| Manpages | 5 |
| Shell completions | 3 (bash, fish, zsh) |
| Presets | 4 (fast-delete, review, demo, ai-code) |

### 1.3 Three Implementations

| Implementation | Language | Vim Communication | Dependencies |
|----------------|----------|-------------------|--------------|
| `diffvim` | Bash + Vimscript | Native (`timer_start`) | Vim 8+ only |
| `ad_tmux` | Bash + tmux | `tmux send-keys` | tmux, vim, diff, sed, awk |
| `ad_vim.pl` | Perl + tmux | `tmux send-keys` | Perl 5.10+, tmux, diff |

The primary implementation is `diffvim` (bash + vimscript). It is the
only one that has no race conditions (single-process, timer-driven) and
the only one that supports all unified option selectors.

### 1.4 External Compute Tool

A single native compute tool (C++) pre-computes diffs 10-100x faster
than the in-vim patience. When `bin/ad_compute` is missing,
`diffvim` falls back to the embedded vimscript patience and `ad_pipeline`
falls back to `compute/perl/compute_builtin.pl`. Used via `--precomputed FILE`
or automatically (no `--tool` flag needed).

---

## 2. System Overview

### 2.1 Pipeline

```
INPUT                    PROCESSING                     OUTPUT
──────                   ───────────                    ──────

<oldfile> <newfile>  →   1. Parse CLI args          →   vim display
--precomputed FILE       2. Load old file into vim       (animated)
--diff FILE              3. Compute/load diff
--multi pairs            4. Post-process ops
--git-rev REV..REV       5. Animate in vim
                         6. User interacts
                         7. Write output / quit
```

### 2.2 Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         ad_vim (bash)                           │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐       │
│  │ CLI      │  │ Config   │  │ Preset   │  │ Compute  │       │
│  │ Parser   │  │ Resolver │  │ Expander │  │ Tool     │       │
│  │          │  │          │  │          │  │ Launcher │       │
│  │ 40+ opts │  │ 5 unified│  │ 4 presets│  │ (auto)   │       │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘       │
│       │              │              │              │             │
│       └──────────────┴──────────────┴──────────────┘             │
│                              │                                   │
│                              ▼                                   │
│                    ┌─────────────────┐                          │
│                    │  Environment    │                          │
│                    │  Variables      │                          │
│                    │  (114 exports)  │                          │
│                    └────────┬────────┘                          │
│                             │                                   │
│                             ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    vim (vimscript engine)                │    │
│  │                                                         │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │    │
│  │  │ Config   │  │ Diff     │  │ Post-    │  │ Animation│ │    │
│  │  │ Dict     │  │ Engine   │  │ Process  │  │ Engine   │ │    │
│  │  │          │  │          │  │          │  │          │ │    │
│  │  │ 168      │  │ Line patience │  │ 6 passes │  │ Timer    │ │    │
│  │  │ entries  │  │ Char patience │  │          │  │ driven   │ │    │
│  │  │          │  │ Hunks    │  │          │  │          │ │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │    │
│  │                                                         │    │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌─────────┐ │    │
│  │  │ Buffer   │  │ Cursor   │  │ Render   │  │ Input   │ │    │
│  │  │ Manip.   │  │ Glide    │  │ (redraw) │  │ Handler │ │    │
│  │  │          │  │          │  │          │  │          │ │    │
│  │  │ setline  │  │ ease-out │  │ sign col │  │ normal  │ │    │
│  │  │ getline  │  │ cubic    │  │ highlight│  │ mode    │ │    │
│  │  │ cursor   │  │          │  │ dim      │  │ mappings│ │    │
│  │  └──────────┘  └──────────┘  └──────────┘  └─────────┘ │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              External Compute Tools                     │    │
│  │                                                         │    │
│  │  ┌─────┐  ┌──────┐  ┌──────┐  ┌─────┐                  │    │
│  │  │  C  │  │ C++  │  │ Rust │  │ Go  │                  │    │
│  │  └─────┘  └──────┘  └──────┘  └─────┘                  │    │
│  │                                                         │    │
│  │  All produce identical output (294 parity tests pass)   │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Functional Requirements

### FR-1: Input Modes

#### FR-1.1: Two-File Mode (Primary)

The application SHALL accept two file paths as positional arguments:

```
ad_vim [options] <oldfile> <newfile>
```

The old file is opened in vim; the new file is the animation target.
The diff is computed either inline (vimscript patience) or externally
(`bin/ad_compute`, searched for automatically).

**Acceptance criteria:**
- Both files must exist and be readable.
- If either file is missing, print an error and exit 1.
- File types are auto-detected from extension for syntax highlighting.

#### FR-1.2: Precomputed Diff Mode

```
ad_vim --precomputed FILE <oldfile> <newfile>
```

The application SHALL accept a precomputed diff file (produced by
`ad_compute`) and skip the in-vim patience computation. When the
C++ binary is on `$PATH` (or in `bin/ad_compute `, `/usr/local/bin/`, or
`~/.local/bin/`), ad_vim pre-computes automatically; otherwise it
falls back to the in-vim patience with a warning on stderr. (The `--tool`
flag was removed in the refactor — only the C++ compute tool remains.)

**Acceptance criteria:**
- The precomputed file must be in the ad_vim diff format (see §7.1).
- If the file is missing or invalid, fall back to inline computation
  with a warning on stderr.

#### FR-1.3: Unified Diff Input

```
ad_vim --diff FILE
ad_vim --diff - < file.diff
```

The application SHALL accept a unified diff file as input. The diff is
parsed to extract old and new content, then the animation proceeds as
in two-file mode.

#### FR-1.4: Multi-File Mode

```
ad_vim --multi <old1:new1> <old2:new2> ...
```

The application SHALL animate multiple file pairs sequentially. After
finishing one file, the animation transitions to the next. The status
line shows "file 2/3: src/parser.rs".

**Acceptance criteria:**
- Each argument must be in `old:new` format (colon-separated).
- Press `]` to advance to the next file, `[` to go back.
- Each file gets its own animation pass with its own diff.

#### FR-1.5: Git History Replay

```
ad_vim --replay <file>
ad_vim --git-rev REV..REV <file> [<file> ...]
```

The application SHALL animate a file's git history. For each commit in
the range, the application extracts the file content at both revs and
animates the diff. The status line shows the commit hash and message.

**Acceptance criteria:**
- Requires `git` in PATH.
- Default range: `HEAD~5..HEAD`.
- `--git-rev` is shorthand for `--replay` with a specific rev range.
- Multiple files can be replayed simultaneously.

### FR-2: Diff Computation

#### FR-2.1: Line-Level Diff

The application SHALL compute a line-level diff using one of two
algorithms:

| Algorithm | Time Complexity | Use Case |
|-----------|----------------|----------|
| Patience (only) | O(N×M) | Anchored on unique lines |
| Patience | O(N×M) | More human-readable hunks (anchors on unique lines) |

Selected via `--algorithm patience`. (Myers was removed: it OOMs
on 15K-line files and produces the same op count as patience.)

#### FR-2.2: Char-Level Diff

Within each hunk (a group of consecutive changed lines), the application
SHALL compute a char-level patience diff. Only the actually-changed characters
are touched — surrounding text is never rewritten.

**Acceptance criteria:**
- The char-level diff operates on Unicode code points, not bytes.
- The result is a sequence of `{op: 'keep'|'delete'|'insert', code: int}`
  operations.
- For `--word-diff`, the char-level diff uses word tokens instead of
  individual characters.

#### FR-2.3: Hunk Grouping

The application SHALL group consecutive non-keep line ops into hunks.
Each hunk has:
- `target_line`: the line number in the old file where the cursor should
  be positioned
- `char_ops`: the ordered list of char-level operations
- `deleted_count`, `inserted_count`: line-level counts
- `is_end_insert`, `is_end_delete`: flags for end-of-file edge cases
- `old_text`, `new_text`: the original and target text for the hunk

#### FR-2.4: External Compute Tools

The application SHALL support four external compute tools (C, C++,
Rust, Go) that produce byte-for-byte identical output. These tools
implement the same algorithms (Patience) and post-processing
(semantic-cleanup, word-diff, indent-aware, optimize-sequence,
left-to-right) as the vimscript engine, but compiled to native code.

**Performance comparison (1000-line Python file):**
| Tool | Compute time |
|------|-------------|
| vimscript patience | ~3500 ms |
| C | 11 ms |
| C++ | 12 ms |
| Rust | 13 ms |
| Go | 14 ms |

### FR-3: Post-Processing Pipeline

The application SHALL apply post-processing passes to the char ops
before animation begins. The passes are applied in order:

#### FR-3.1: Semantic Cleanup (`--semantic-cleanup`)

Merges adjacent delete/insert pairs that cancel out (e.g., delete 'a'
followed by insert 'a' becomes keep 'a'). Reduces unnecessary typing.

#### FR-3.2: Op Order (`--op-order MODE`)

Controls how char ops within a line are ordered. Six modes:

| Mode | Description |
|------|-------------|
| `natural` | No post-processing (raw patience order) |
| `optimize` (default) | Deletes before inserts within a line |
| `left-to-right` | Keeps, then deletes, then inserts per line |
| `end-first` | Trailing deletes before inserts |
| `end-first-smart` | Trailing deletes + word batching |
| `overwrite` | In-place replacement instead of delete+insert |

**Implementation:** The `--op-order` resolution block in the bash
launcher maps the mode to individual variables (`OPTIMIZE_SEQUENCE`,
`LEFT_TO_RIGHT`, `DELETE_END_FIRST`, `DELETE_END_FIRST_SMART`,
`OVERWRITE_MODE`), which the vimscript engine reads.

#### FR-3.3: Indent-Aware (`--indent-aware`)

Normalizes indentation before the line-level diff, so lines that differ
only in indentation are treated as "keep" at the line level. The char
diff then handles the indent change.

### FR-4: Animation Engine

#### FR-4.1: Timer-Driven Animation

The application SHALL use vim's `timer_start()` function for async
animation. A timer callback (`s:Tick`) is called every `tick_ms`
(default 16ms, ~60fps). Each callback advances the animation by one step.

**Acceptance criteria:**
- Only one timer is active at a time (`s:state.active_timer`).
- `ScheduleNext(delay_ms)` stops the current timer and starts a new one.
- The timer is stopped when the animation completes or the user presses
  `q`.

#### FR-4.2: Cursor Glide

The application SHALL animate the cursor gliding between change locations
with ease-in-out cubic acceleration.

**Glide duration formula:**
```
duration = max(move_min_ms, min(move_max_ms, distance * move_ms_per_unit))
```

Default values:
- `move_min_ms`: 250ms
- `move_max_ms`: 1600ms
- `move_ms_per_unit`: 6ms per unit (lines weighted 80x more than columns)

**Acceptance criteria:**
- The glide is smooth (no teleporting).
- The cursor is visible during the glide.
- The glide is divided into steps: the animation engine computes the
  intermediate cursor position at each tick.

#### FR-4.3: Character Operations

The application SHALL process char ops one at a time via
`ProcessCharOp()`. For each op:

| Op | Action | Delay |
|----|--------|-------|
| `keep` | Advance cursor | 1ms (or line-change pause) |
| `delete` | Remove char at cursor | `delete_delay_ms` (40ms default) |
| `insert` | Insert char at cursor, advance | `type_delay_ms` (50ms default) |

**Special handling:**
- `keep \n`: Move cursor to next line, reset column to 1.
- `delete \n`: Mark line as empty (move cursor to next line, do NOT
  delete the line from the buffer — this avoids pulling the next line
  up).
- `insert \n`: Split the line at the cursor position.

#### FR-4.4: Deletion Pacing (`--delete-pacing MODE`)

The application SHALL support six deletion strategies:

| Mode | Description |
|------|-------------|
| `char` | One char per timer tick (no acceleration) |
| `rapid-eol` | Rapid shot at end of line (non-newline chars only) |
| `rapid-identical` | Accelerate identical char runs (---, ===) |
| `accel` | Accelerate through long runs (slow→fast→slow) |
| `word` (default) | Word-by-word with acceleration |
| `instant` | All strategies enabled (fastest) |

**AWD (Adaptive Word Delete) state machine for `word` mode:**

```
Phase 1: Delete first N non-space chars slowly (80ms each)
         Spaces are deleted instantly (not counted toward N)
         N = adaptive_word_delete_start_chars (default: 3)
             ↓ (after N non-space chars deleted)
Phase 2: Delete words instantly, one per timer tick
         Word = contiguous non-space chars until space/newline
         Delay accelerates: 80ms → 15ms per word
             ↓ (no more words on this line)
Phase 3: Delete remaining chars instantly (all at once)
             ↓ (line is empty)
Newline: Move cursor to next line (DON'T delete the empty line)
             ↓ (reset to Phase 1 for next line)
```

**Acceptance criteria:**
- The threshold for triggering AWD is `adaptive_word_delete_threshold`
  (default: 3). If a delete run has fewer than 3 non-space chars, AWD
  is not triggered.
- `--delete-speed fast` halves all delete delays.
- `--delete-speed instant` sets all delete delays to 1ms.
- `--delete-threshold N` overrides the trigger threshold.

#### FR-4.5: Insertion Pacing (`--insert-pacing MODE`)

| Mode | Description |
|------|-------------|
| `char` (default) | One char per timer tick |
| `word` | Batch short words (≤8 chars) instantly, pause after |
| `accel` | Accelerate char-by-char inserts (slow→fast→pause) |

#### FR-4.6: Timing Modes (`--pacing MODE`)

| Mode | Description |
|------|-------------|
| `uniform` (default) | Fixed delays, no jitter |
| `adaptive` | Slow down in complex regions (±10 op window) |
| `gaussian` | Add human-like timing jitter (±20%) |
| `review` | Pause every 5 lines in large hunks (threshold: 20 lines) |

#### FR-4.7: Highlighting (`--highlight MODE`)

| Mode | Description |
|------|-------------|
| `none` (default) | No highlighting |
| `inline` | Paint freshly typed chars green, deleted chars red (200ms fade) |
| `word` | Highlight the word at cursor before each change |
| `hunk` | Highlight the entire hunk region before animating it |

**Additional highlighting options:**
- `--highlight-color COLOR`: Vim highlight group (default: DiffChange)
- `--highlight-duration-ms N`: Duration in ms (default: 1000)
- `--dim-unchanged`: Dim unchanged anchor lines (default opacity: 60%)
- `--dim-unchanged-pct N`: Dimming percentage 0-100
- `--sign-column`: Show +/- signs in vim's sign column

### FR-5: User Interaction

#### FR-5.1: Keyboard Controls

During the animation, the following keys are active in vim normal mode:

| Key | Action |
|-----|--------|
| `Space` | Pause / resume animation |
| `n` | Skip current hunk (apply instantly, move to next) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation (leave buffer in current state) |
| `+` | Speed up (×1.5) |
| `-` | Slow down (÷1.5) |
| `=` | Reset speed to 1.0× |
| `?` | Show in-vim help overlay |

**Multi-file mode:**
| Key | Action |
|-----|--------|
| `]` | Next file |
| `[` | Previous file |

**Git replay mode:**
| Key | Action |
|-----|--------|
| `)` | Next commit |
| `(` | Previous commit |

#### FR-5.2: Step Mode (`--step-mode`)

Space advances one char op at a time instead of toggling pause/resume.
The animation starts paused.

#### FR-5.3: Pause After Animation

By default, after the animation completes, the buffer is marked as
not-modified so `:q` quits cleanly. Use `--keep-dirty` to leave the
buffer modified (then `:q!` is required).

### FR-6: Presets

The application SHALL support four named presets:

| Preset | Options Applied |
|--------|----------------|
| `fast-delete` | `--delete-pacing word --delete-speed fast --op-order optimize --semantic-cleanup` |
| `review` | `--pacing review --highlight hunk --dim-unchanged --op-order left-to-right --semantic-cleanup` |
| `demo` | `--pacing gaussian --speed 0.7 --highlight inline` |
| `ai-code` | `--op-order end-first-smart --highlight inline --pacing adaptive --semantic-cleanup` |

Plus `custom` which reads options from the `AD_PRESET_CUSTOM`
environment variable.

### FR-7: Output

#### FR-7.1: Buffer State After Animation

After the animation completes (or the user presses `q`), the buffer
contains the result of applying all char ops. The buffer is a normal
vim buffer and can be edited, saved, or quit.

#### FR-7.2: Write to File (`--output FILE`)

Write the buffer content to FILE after the animation, then quit vim
automatically.

#### FR-7.3: Dry Run (`--dry-run`)

Print the diff hunks without launching vim. Shows each hunk's target
line, deleted/inserted counts, and char op summary.

#### FR-7.4: Log Mode (`--log-mode 1|2`)

Generate a log file without starting vim:
- Mode 1: One line per hunk showing the original line with markers at
  deleted char positions.
- Mode 2: Three lines per char op (current line, marker, result).

#### FR-7.5: Log File (`--log-file FILE`)

Write the log to FILE (default: `diffvim.log`).

### FR-8: Viewport Control

#### FR-8.1: Scroll Position (`--scroll MODE`)

| Mode | Description |
|------|-------------|
| `zz` (default) | Center cursor on screen |
| `zt` | Top-align cursor |
| `zb` | Bottom-align cursor |
| `none` | No automatic scrolling |

#### FR-8.2: Context Folding (`--context N`)

Fold unchanged regions longer than 2×N lines, keeping N lines of context
around each hunk. `--context 0` folds all unchanged regions.

### FR-9: Git Integration

#### FR-9.1: Git Blame (`--git-blame`)

Show git blame for the target line of each hunk. Blame is pre-computed
at startup (batch) to avoid per-hunk latency.

#### FR-9.2: Sign Column (`--sign-column`)

Show `+`/`-` signs in vim's sign column at hunk locations during the
animation.

### FR-10: Syntax Highlighting

The application SHALL use the user's vimrc colors by default (no
`-u NONE`). The `--no-vimrc` flag isolates vim from the user's
configuration. Syntax highlighting is detected from the file extension
and loaded via `runtime syntax/<filetype>.vim`.

---

## 4. Non-Functional Requirements

### NFR-1: Performance

| Metric | Requirement |
|--------|-------------|
| Startup time (small file, <100 lines) | < 500ms |
| Startup time (large file, >1000 lines, inline patience) | < 5s |
| Startup time (large file, with C++ compute) | < 200ms |
| Animation frame rate | 60fps (16ms per tick) |
| Char op processing | < 1ms per op (excluding delay) |
| Cursor glide rendering | < 5ms per frame |
| Memory usage (10,000-line file) | < 100MB |

### NFR-2: Portability

| Requirement | Details |
|-------------|---------|
| Operating systems | Linux, macOS, BSD (any POSIX system) |
| Vim version | 8.0+ with `+timers` and `+float` features |
| Bash version | 4.0+ (associative arrays) |
| Perl version | 5.10+ (for `ad_vim.pl`) |
| tmux version | 3.0+ (for `ad_tmux` and `ad_vim.pl`) |
| External tools | `diff` (required), `git` (optional), `sed`/`awk` (for tmux) |

### NFR-3: Correctness

- Applying all char ops to the old file SHALL produce exactly the new
  file (round-trip property).
- The C++ compute tool and the Perl fallback (`compute/perl/compute_builtin.pl`)
  SHALL produce byte-for-byte identical output.
- The final buffer after animation SHALL match the new file (with the
  exception of empty lines left by `\n` deletes — see §11).

### NFR-4: Backward Compatibility

- Old CLI flags are rejected with "Unknown option" errors (no silent
  acceptance).
- The precomputed diff format is versioned (`# diffvim precomputed diff v1`).
- Environment variables use the `DIFFVIM_` prefix consistently.

---

## 5. Interface Specifications

### 5.1 CLI Interface

```
Usage: ad_vim [options] <oldfile> <newfile>
       ad_vim [options] --multi(-m) <old1:new1> <old2:new2> ...
       ad_vim [options] --replay(-r) <file>
       ad_vim [options] --git-rev(-R) REV..REV <file> [<file> ...]
```

**Short options:** `-s` (speed), `-o` (output), `-c` (context), `-m`
(multi), `-r` (replay), `-d` (dry-run), `-w` (word-diff), `-a`
(algorithm), `-S` (semantic-cleanup), `-i` (indent-aware), `-g`
(git-blame), `-R` (git-rev), `-p` (preset), `-N` (no-vimrc), `-F`
(startup-feedback), `-D` (dim-unchanged), `-t` (theme), `-V` (version),
`-h` (help).

### 5.2 Environment Variables

All options can be set via `DIFFVIM_<OPTION_NAME>` environment variables.
The bash launcher reads env vars as defaults, CLI options override them,
and the resolution blocks map unified selectors to individual variables
before exporting them to vim.

**Key env vars:**
- `DIFFVIM_OP_ORDER`, `DIFFVIM_DELETE_PACING`, `DIFFVIM_DELETE_SPEED`,
  `DIFFVIM_DELETE_THRESHOLD`, `DIFFVIM_INSERT_PACING`,
  `DIFFVIM_INSERT_SPEED`, `DIFFVIM_PACING`, `DIFFVIM_HIGHLIGHT`
- `AD_TICK_MS`, `AD_TYPE_DELAY_MS`, `AD_DELETE_DELAY_MS`,
  `AD_MOVE_MIN_MS`, `AD_MOVE_MAX_MS`, `AD_HUNK_PAUSE_MS`
- `AD_PRESET` (default preset to apply)

### 5.3 Precomputed Diff Format

```
# diffvim precomputed diff v1
# algorithm patience
# semantic_cleanup 0
# word_diff 0
# indent_aware 0
# optimize_sequence 1
# left_to_right 0
# hunk_count N
HUNK <target_line> <deleted_count> <inserted_count> <is_end_insert> <is_end_delete>
keep <code>
delete <code>
insert <code>
HUNK ...
```

Where `<code>` is the Unicode code point of the character (e.g., 97 for
'a', 10 for newline).

### 5.4 Vimscript Config Dictionary

The vimscript engine reads configuration from a `g:diffvim` dictionary
with 168 entries. The dictionary is populated from environment variables
in the bash launcher, then sourced by vim.

---

## 6. Architecture

### 6.1 Bash Launcher

The bash launcher (`diffvim`) handles:
1. CLI argument parsing (40+ options with validation)
2. Preset expansion (4 presets)
3. Speed multiplier application (scales all timing env vars)
4. Unified selector resolution (5 blocks: op-order, delete-pacing,
   insert-pacing, pacing, highlight)
5. Environment variable export (114 exports)
6. External compute tool invocation (auto; no `--tool` flag)
7. Vimscript generation (embedded heredoc)
8. Vim launch (`exec vim`)

**Key design decision:** All resolution blocks run BEFORE the export
block, so the env vars exported to vim reflect the resolved values.

### 6.2 Vimscript Engine

The vimscript engine (embedded in the bash script as a heredoc) handles:
1. Config dictionary initialization (168 entries from env vars)
2. Diff computation (Patience at line and char level)
3. Post-processing pipeline (6 passes)
4. Hunk building and grouping
5. Animation state machine (idle → moving → typing → idle)
6. Cursor glide (ease-in-out cubic)
7. Buffer manipulation (setline, cursor, delete, insert)
8. User input (normal-mode mappings)
9. Rendering (redraw, sign column, highlighting, dimming)
10. Snapshot/restore (for back button)

**73 functions** organized into:
- Diff functions (7): LineDiff, CharDiff, WordDiff, SemanticCleanup,
  NormalizeIndent, BuildHunks, LoadPrecomputed
- Post-processing (5): OverwriteTransform, DeleteEndFirst,
  OptimizeSequence, LeftToRight, SortLineOps
- Cursor/buffer (8): PlaceCursor, CharToByte, InsertCharAtCursor,
  DeleteCharAtCursor, DeleteNewlineAtCursor, AdvanceForKeepChar
- Animation (10): ScheduleNext, Tick, StartNextHunk, ProcessCharOp,
  ApplyHunkInstantly, MoveStep, ScrollStep, StartSmoothScroll
- Lookahead (5): LookaheadEOLDelete, LookaheadSameTypeRun,
  LookaheadIdenticalChars, LookaheadWordLength, LookaheadMultiLineDelete
- Pacing (3): ProcessBlockDelete, ProcessAdaptiveWordDelete,
  ComputeAccelDeleteDelay
- Highlight (7): InlineHighlight, ClearInlineHighlight, SetupDimUnchanged,
  ClearDimUnchanged, HighlightHunk, ClearHighlight, HighlightCurrentWord
- Input (8): TogglePause, SkipCurrent, Back, Quit, ShowHelp, SpeedUp,
  SlowDown, ResetSpeed
- Multi-file (3): SetFilePairs, NextFile, PrevFile
- Utility (10): SaveSnapshot, RestoreSnapshot, GaussianJitter,
  ComputeComplexity, ShowStartupFeedback, PlaceSign, LoadBlameCache,
  ShowGitBlame, SetupSyntax, DetectFiletype, ShowConfig, StartAnimation

### 6.3 External Compute Tool

A single implementation (C++) of the same algorithm:

1. **Line-level diff:** Patience dynamic programming
2. **Hunk grouping:** Group consecutive non-keep ops
3. **Char-level patience:** Within each hunk, compute minimal char ops
4. **Post-processing:** semantic-cleanup, word-diff, indent-aware,
   optimize-sequence, left-to-right

When the C++ binary is missing, the pipeline falls back to the pure-Perl
`compute/perl/compute_builtin.pl` wrapper (which calls
`DiffVim::Parser::Perl::parse_diff`); both paths produce byte-for-byte
identical output. (The historical C, Rust, and Go variants were
removed in the refactor.)

### 6.4 Resolution Pipeline

```
CLI args
    │
    ▼
┌──────────────┐
│ Arg Parser   │  40+ options, validation, short forms
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Preset       │  fast-delete, review, demo, ai-code, custom
│ Expander     │  Sets shell variables (DELETE_PACING, PACING, etc.)
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Speed        │  Scales all timing env vars by 1/speed_mult
│ Multiplier   │
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────────────┐
│ Resolution Blocks (5, in order):             │
│                                              │
│ 1. --op-order      → OPTIMIZE_SEQUENCE,      │
│                      LEFT_TO_RIGHT,           │
│                      DELETE_END_FIRST,        │
│                      DELETE_END_FIRST_SMART,  │
│                      OVERWRITE_MODE           │
│                                              │
│ 2. --delete-pacing → RAPID_EOL_DELETE,       │
│                      RAPID_IDENTICAL_CHARS,   │
│                      ACCEL_DELETE,            │
│                      ADAPTIVE_WORD_DELETE     │
│                                              │
│ 3. --delete-speed  → Scales DELETE_DELAY_MS, │
│                      ACCEL_DELETE_*_MS,       │
│                      ADAPTIVE_WORD_DELETE_*_MS│
│                                              │
│ 4. --insert-pacing → MAX_WORD_CHARS,         │
│                      WORD_ACCEL               │
│                                              │
│ 5. --pacing        → ADAPTIVE_TIMING,        │
│                      ADAPTIVE_MODE,           │
│                      GAUSSIAN_JITTER,         │
│                      PAUSE_AFTER_LINES        │
│                                              │
│ 6. --highlight     → HIGHLIGHT_WORD,          │
│                      HIGHLIGHT_HUNK,          │
│                      INLINE_HIGHLIGHT         │
└──────────────────────────────────────────────┘
       │
       ▼
┌──────────────┐
│ Export Block │  114 env var exports to vim
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Vimscript    │  4,500 lines, 73 functions
│ Engine       │  Reads env vars into g:diffvim dict (168 entries)
└──────────────┘
```

---

## 7. Data Formats

### 7.1 Precomputed Diff File Format

```
# diffvim precomputed diff v1
# algorithm <patience>
# semantic_cleanup <0|1>
# word_diff <0|1>
# indent_aware <0|1>
# optimize_sequence <0|1>
# left_to_right <0|1>
# hunk_count <N>
HUNK <target_line> <deleted_count> <inserted_count> <is_end_insert> <is_end_delete>
<op> <code>
<op> <code>
...
HUNK <target_line> ...
...
```

- `<op>` is `keep`, `delete`, or `insert`
- `<code>` is the Unicode code point (integer)
- `target_line` is 1-indexed in the old file
- `is_end_insert` / `is_end_delete` are 0 or 1

### 7.2 Log File Format

**Mode 1 (markers):**
```
# timing: type=50ms delete=40ms hunk_pause=250ms
HUNK 2 (del=1 ins=1)
    print("Hello, " + name)
         ████████████████████████ ← deleted positions
    print(f"Hello, {name}!")
         ████████████████████████ ← inserted positions
```

**Mode 2 (progressive, 3 lines per op):**
```
# timing: type=50ms delete=40ms hunk_pause=250ms
HUNK 2 (del=1 ins=1)
    print("Hello, " + name)
              ↑
    print(f"Hello, " + name)
    print("Hello, " + name)
               ↑
    print(f"Hello, " + name)
...
```

### 7.3 Config Dictionary Structure

```vim
let g:diffvim = {
    \ 'tick_ms':            str2nr($AD_TICK_MS),
    \ 'type_delay_ms':      str2nr($AD_TYPE_DELAY_MS),
    \ 'delete_delay_ms':    str2nr($AD_DELETE_DELAY_MS),
    \ 'move_min_ms':        str2nr($AD_MOVE_MIN_MS),
    \ 'move_max_ms':        str2nr($AD_MOVE_MAX_MS),
    \ 'move_ms_per_unit':   str2nr($AD_MOVE_MS_PER_UNIT),
    \ 'hunk_pause_ms':      str2nr($AD_HUNK_PAUSE_MS),
    \ 'speed':              str2nr($DIFFVIM_SPEED),
    \ 'scroll':             $DIFFVIM_SCROLL,
    \ 'op_order':           $DIFFVIM_OP_ORDER,
    \ 'delete_pacing':      $DIFFVIM_DELETE_PACING,
    \ 'insert_pacing':      $DIFFVIM_INSERT_PACING,
    \ 'pacing':             $DIFFVIM_PACING,
    \ 'highlight':          $DIFFVIM_HIGHLIGHT,
    \ ... (168 total entries)
\ }
```

---

## 8. Option Reference

### 8.1 Complete Option Table

| Option | Short | Takes Value | Default | Description |
|--------|-------|-------------|---------|-------------|
| `--speed` | `-s` | N | 1.0 | Speed multiplier |
| `--output` | `-o` | FILE | — | Write result to FILE |
| `--context` | `-c` | N | 0 | Context lines around hunks |
| `--max-hunk-chars` | | N | 0 | Skip char-by-char for large hunks |
| `--scroll` | | MODE | zz | Cursor scroll position |
| `--multi` | `-m` | | — | Multi-file mode |
| `--replay` | `-r` | | — | Git history replay |
| `--git-rev` | `-R` | REV..REV | — | Git commit range |
| `--version` | `-V` | | — | Print version |
| `--dry-run` | `-d` | | — | Print diff without animating |
| `--word-diff` | `-w` | | — | Word-level diff |
| `--step-mode` | | | — | Step through one op at a time |
| `--no-startup-pause` | | | — | Skip startup delay |
| `--language` | | LANG | auto | Vim filetype |
| `--sign-column` | | | — | Show +/- signs |
| `--git-blame` | `-g` | | — | Show git blame |
| `--max-line-len` | | N | 0 | Warn on long lines |
| `--keep-dirty` | | | — | Leave buffer modified |
| `--no-vimrc` | `-N` | | — | Isolated vim |
| `--precomputed` | | FILE | — | Use precomputed diff |
| `--startup-pause` | | | — | Show config before starting |
| `--startup-feedback` | `-F` | | — | Show progress during computation |
| `--algorithm` | `-a` | patience\|patience | patience | Diff algorithm |
| `--semantic-cleanup` | `-S` | | — | Merge canceling ops |
| `--indent-aware` | `-i` | | — | Handle indent-only changes |
| `--op-order` | | MODE | optimize | Op reordering mode |
| `--delete-pacing` | | MODE | word | Deletion strategy |
| `--delete-speed` | | MODE | normal | Deletion speed |
| `--delete-threshold` | | N | 3 | Min chars for rapid/word |
| `--insert-pacing` | | MODE | char | Insertion strategy |
| `--insert-speed` | | MODE | normal | Insertion speed |
| `--pacing` | | MODE | uniform | Timing mode |
| `--highlight` | | MODE | none | Highlight mode |
| `--highlight-color` | | COLOR | DiffChange | Highlight group |
| `--highlight-duration-ms` | | N | 1000 | Highlight duration |
| `--dim-unchanged` | `-D` | | — | Dim unchanged lines |
| `--dim-unchanged-pct` | | N | 60 | Dimming percentage |
| `--theme` | `-t` | MODE | — | Color theme |
| `--preset` | `-p` | NAME | — | Apply preset |
| `--log-mode` | | 1\|2 | — | Generate log file |
| `--log-file` | | FILE | diffvim.log | Log file path |
| `--no-log-timing` | | | — | Disable timing in log |
| `--diff` | | FILE | — | Unified diff input |
| `--debug` | | | — | Verbose logging |
| `--help` | `-h` | | — | Show help |

---

## 9. Test Specification

### 9.1 Test Suite Inventory

| Test File | Assertions | What It Tests |
|-----------|-----------|---------------|
| `test_correctness.pl` | 91 | Round-trip: apply ops → matches new file |
| `test_features.pl` | 52 | CLI options, help text, manpage |
| `test_compositions.pl` | 172 | All 2-way, 3-way, 4-way, 5-way option combos |
| `test_op_order.pl` | 20 | `--op-order` all 6 modes + old flags rejected |
| `test_delete_pacing.pl` | 28 | `--delete-pacing` all 6 modes + old flags rejected |
| `test_insert_pacing.pl` | 23 | `--insert-pacing` all 3 modes + old flags rejected |
| `test_pacing.pl` | 27 | `--pacing` all 4 modes + old flags rejected |
| `test_highlight.pl` | 29 | `--highlight` all 4 modes + old flags rejected |
| `test_highlight_resolution.pl` | 12 | Resolution blocks before exports |
| `test_viewport.pl` | 22 | `--context`, `--scroll`, `--fold-unchanged` rejected |
| `test_input_source.pl` | 14 | `--from`/`--to`/`--auto-precompute` rejected |
| `test_rapid_eol.pl` | 20 | Rapid EOL delete correctness |
| `test_overwrite_deletefirst.pl` | 8 | Overwrite + delete-end-first |
| `test_engine_features.pl` | 12 | Engine feature flags |
| `test_new_features.pl` | 9 | New feature integration |
| `test_semantic_cleanup.pl` | 21 | Semantic cleanup + help |
| `test_parsers.pl` | 9 | Perl parser correctness |
| `test_precomputed.pl` | 32 | Precomputed diff loading |
| `test_vim_correctness.pl` | 42 | Real vim execution (bypasses ProcessCharOp) |
| `test_diff_input.pl` | 9 | `--diff` unified diff input |
| `test_comprehensive.pl` | 24 | Comprehensive integration |
| `test_highlight_hunk.pl` | 18 | Hunk highlighting |
| `test_highlight_word.pl` | 20 | Word highlighting |
| Compute parity | 14 | C++ == Perl fallback produce identical output |

**Total: 410+ ad_vim assertions + 14 compute parity = 424+**

### 9.2 Test Categories

1. **Correctness tests:** Apply char ops to old file, verify result
   matches new file. Pure Perl (no vim).
2. **Feature tests:** Verify CLI options are accepted, help text is
   correct, manpage exists.
3. **Composition tests:** Every 2-way combination of the 6 unified
   selectors, plus 3-way, 4-way, 5-way combos.
4. **Rejection tests:** Old flags are rejected with "Unknown option".
5. **Resolution tests:** Resolution blocks are before export blocks
   (line-number verification).
6. **Vim execution tests:** Run the actual vim engine, write buffer,
   compare with expected.
7. **Compute parity tests:** The C++ compute tool and the Perl
   fallback produce identical output across the example pairs and
   the option combinations.

### 9.3 Known Test Gaps

- `test_vim_correctness.pl` bypasses `ProcessCharOp` — it directly calls
  `DeleteCharAtCursor`/`InsertCharAtCursor` in a loop. This means AWD,
  rapid-EOL, and all pacing logic are NOT tested by this suite.
- `test_vim_engine.pl` attempts to test `ProcessCharOp` synchronously
  but has issues with the timer-based architecture in `vim -es` mode.
- No test currently verifies that the `\n` delete behavior (moving cursor
  to next line instead of pulling up) produces correct visual output.

---

## 10. Documentation Skeleton

### 10.1 Current Documentation Structure

```
gitanim/
├── README.md                        # Main README (518 lines)
├── CHANGELOG.md                     # Version history (495 lines)
├── LICENSE                          # Artistic 2.0 / GPL 3.0 (dual)
├── IMPROVEMENTS.md                  # 100 improvement ideas
│
├── ad_vim                          # Main script (4,517 lines)
├── ad_vim.1                        # Root manpage (copy of man/ad_vim.1)
├── ad_tmux                     # tmux implementation
├── ad_vim.pl                       # Perl implementation
├── ad_compare                  # Diff algorithm benchmark
├── ad_jogger                   # Test-case exerciser
├── jq_filter                        # difft JSON → text format
├── difft_json_to_lcs                # Text format → Patience string
├── set_config                       # Timing env var defaults
│
├── DiffVim/
│   └── Parser/
│       └── Perl.pm                  # Pure-Perl Patience diff parser
│
├── plugin/
│   └── diffvim.vim                  # :Diffvim vim plugin
├── autoload/
│   └── diffvim/
│       └── engine.vim              # Standalone engine (sourced by plugin)
│
├── completion/
│   ├── ad_vim.bash                # Bash completion
│   ├── __ad_vim                    # Zsh completion
│   └── ad_vim.fish                # Fish completion
│
├── compute/
│   ├── cpp/ad_compute.cpp     # C++ (only compute implementation)
│   ├── perl/compute_builtin.pl     # Pure-Perl fallback wrapper
│   ├── Makefile                    # Build the C++ binary
│   ├── README.md                   # Compute tool docs
│   └── PARALLELISM.md              # Parallelism analysis
│
├── man/
│   ├── ad_vim.1                   # Main manpage
│   ├── ad_tmux.1              # tmux variant manpage
│   ├── ad_compare.1           # Compare tool manpage
│   ├── ad_jogger.1            # Jogger tool manpage
│   └── ad_compute.1           # Compute tools manpage
│
├── packaging/
│   └── diffvim.rb                  # Homebrew formula
│
├── tests/                          # 33 test files (410+ assertions)
│   ├── test_correctness.pl
│   ├── test_features.pl
│   ├── test_compositions.pl
│   ├── test_op_order.pl
│   ├── test_delete_pacing.pl
│   ├── test_insert_pacing.pl
│   ├── test_pacing.pl
│   ├── test_highlight.pl
│   ├── test_highlight_resolution.pl
│   ├── test_viewport.pl
│   ├── test_input_source.pl
│   ├── test_rapid_eol.pl
│   ├── test_overwrite_deletefirst.pl
│   ├── test_engine_features.pl
│   ├── test_new_features.pl
│   ├── test_semantic_cleanup.pl
│   ├── test_parsers.pl
│   ├── test_precomputed.pl
│   ├── test_vim_correctness.pl
│   ├── test_vim_engine.pl
│   ├── test_awd_correctness.pl
│   ├── test_diff_input.pl
│   ├── test_comprehensive.pl
│   ├── test_highlight_hunk.pl
│   ├── test_highlight_word.pl
│   ├── test_integration.pl
│   ├── test_timer_engine.pl
│   ├── test_benchmark.pl
│   ├── test_commit_picker.pl
│   ├── test_fold_theme_debug.pl
│   ├── test_parser_compare.pl
│   └── test_e2e_perl.pl
│
├── tests/tests/examples/                       # 42 example file pairs (15+ languages)
│   ├── 01_small_python/
│   ├── 02_large_python/
│   ├── ...
│   └── 42_large_huge_python/
│
└── docs/
    ├── VISUAL_GUIDE.md             # ASCII art visual explanation
    ├── ADOPTION_GUIDE.md           # Team onboarding guide
    ├── ARCHITECTURE.md             # Architecture deep-dive
    ├── OPTION_ANALYSIS.md          # Option analysis & refactoring proposal
    ├── ANIMATOR_REQUIREMENTS.md    # Future standalone app requirements
    ├── AI_CODE_DIFFING.md          # 100 ideas for AI-generated code
    ├── FOLLOW_IMPROVEMENTS.md      # 50 UX followability improvements
    ├── OPTION_COMBINATIONS.md      # 100+ option combination examples
    ├── USER_REQUESTS.md            # Complete feature-request log (124 items)
    ├── PARSERS.md                  # Diff parser reference
    ├── POST_PROCESSING.md          # Post-processing pipeline reference
    ├── PARALLEL_COMPUTE.md         # Parallel compute architecture
    ├── MULTI_FILE.md               # Multi-file animation guide
    ├── TESTING.md                  # Test suite documentation
    ├── CONFIGURATION.md            # Configuration reference
    ├── CONTROLS.md                 # Keyboard controls reference
    ├── DIFF_STUDY.md               # Diff comparison study
    ├── NON_CHAR_OPTIONS.md         # Non-char-level options
    ├── OPTIONS_OVERVIEW.md         # Options overview
    ├── OPTIONS_ANALYSIS.md         # Options analysis
    ├── presentation.html           # One-page HTML overview
    │
    └── src/                        # mdBook documentation
        ├── SUMMARY.md              # Table of contents
        ├── introduction.md
        ├── installation.md
        ├── quick-start.md
        ├── options.md              # Complete option reference
        ├── controls.md             # Keyboard controls
        ├── configuration.md        # Env vars and config
        ├── examples.md             # Usage examples
        ├── presets.md              # Preset reference
        ├── architecture.md         # Architecture (mdBook version)
        ├── parsers.md              # Parser reference (mdBook)
        ├── plugin.md               # Vim plugin mode
        ├── compute.md              # External compute tools
        ├── manpages.md             # Manpage installation
        ├── git-integration.md      # Git replay and blame
        ├── testing.md              # Test documentation
        └── completion.md           # Shell completion
```

### 10.2 Documentation Content Requirements

Each documentation file SHALL cover:

| Document | Required Content |
|----------|-----------------|
| README.md | Project overview, installation, quick start, options table, examples, project structure, license |
| VISUAL_GUIDE.md | ASCII art diagrams of the pipeline, hunk anatomy, cursor glide, post-processing, presets, controls |
| ADOPTION_GUIDE.md | Why adoption is hard, presets as on-ramp, external compute, editor integration, workshop plan, 30-day checklist |
| ARCHITECTURE.md | Three implementations comparison, data flow, vimscript engine functions, compute tools |
| OPTION_ANALYSIS.md | 10 base operations, overlap analysis, refactoring proposal |
| CHANGELOG.md | All versions with Added/Changed/Removed/Deprecated sections |
| man/ad_vim.1 | SYNOPSIS, DESCRIPTION, OPTIONS (all), CONTROLS, ENVIRONMENT VARIABLES, EXAMPLES, FILES, SEE ALSO |
| docs/src/options.md | Every option with description, default, examples, env var equivalent |

---

## 11. Known Limitations

### 11.1 The `\n` Merge Problem

**Description:** When a whole line is deleted (including its newline),
the vim buffer model requires either deleting the line (which pulls the
next line up) or leaving an empty line. The current implementation
chooses to leave the empty line and move the cursor to the next line.
This means:
- The animation looks correct (cursor moves down, next line is deleted
  in place).
- The final buffer may contain extra empty lines where whole lines were
  deleted.
- This is a fundamental limitation of the vim buffer model.

**Workaround:** Use `--output FILE` to write the result (which is
correct because the char ops produce the correct content; only the
visual buffer has empty lines).

**Future fix:** The standalone animation application (see
`ANIMATOR_REQUIREMENTS.md`) solves this with a virtual text buffer
that it fully controls.

### 11.2 Timer-Based Architecture

The vimscript engine uses `timer_start()` for async animation. This
means:
- Only one timer can be active at a time.
- Timer callbacks are non-preemptible (vim is single-threaded).
- Testing the animation engine synchronously is difficult (requires
  overriding `ScheduleNext` to be a no-op).
- Long-running operations in a timer callback block vim.

### 11.3 No Engine Test Coverage

`test_vim_correctness.pl` bypasses `ProcessCharOp` entirely — it
directly calls `DeleteCharAtCursor`/`InsertCharAtCursor` in a loop.
This means:
- AWD (adaptive word delete) is not tested by the main test suite.
- Rapid-EOL is not tested.
- All pacing logic is not tested.
- The only way to test these is via manual visual inspection or the
  experimental `test_vim_engine.pl` (which has issues with timer-based
  architecture in `vim -es` mode).

### 11.4 Vim Dependency

The animation requires vim 8+ with `+timers` and `+float`. This excludes:
- Developers who use other editors (VS Code, Sublime, Emacs, etc.)
- CI/CD pipelines that don't have vim installed
- Headless environments without a terminal

### 11.5 ad_vim.pl and ad_tmux Lag Behind

The Perl and tmux implementations do not support the unified option
selectors. They still use the old individual flags. Only the bash
`diffvim` has the full unified option system.

---

## 12. Glossary

| Term | Definition |
|------|-----------|
| **AWD** | Adaptive Word Delete — the state machine that deletes chars→words→rapid with acceleration |
| **Char op** | A single character operation: keep, delete, or insert |
| **Hunk** | A group of consecutive non-keep line operations |
| **Patience** | The diff algorithm used for diff computation |
| **removed Myers diff** | REMOVED — OOM on large files, same op count as patience |
| **Patience diff** | Diff algorithm that anchors on unique lines for more human-readable hunks |
| **Op order** | The ordering of char ops within a line (natural, optimize, left-to-right, etc.) |
| **Pacing** | The timing strategy for the animation (uniform, adaptive, gaussian, review) |
| **Precomputed diff** | A diff file produced by an external compute tool, loaded via `--precomputed` |
| **Resolution block** | A bash code block that maps a unified selector (e.g., `--op-order`) to individual variables |
| **Semantic cleanup** | Post-processing pass that merges adjacent delete/insert pairs that cancel out |
| **Unified selector** | A single CLI option that replaces multiple individual flags (e.g., `--op-order` replaces `--optimize-sequence`, `--left-to-right`, etc.) |
