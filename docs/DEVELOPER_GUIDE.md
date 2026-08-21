# Developer Guide / Onboarding Guide

This guide is for developers who want to understand, modify, or contribute
to the diffvim/gitanim project. It covers the architecture, codebase
layout, development workflow, and how to extend the project.

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Repository Layout](#3-repository-layout)
4. [Building from Source](#4-building-from-source)
5. [The Pipeline Stages](#5-the-pipeline-stages)
6. [The Timed Op Stream Format (v2 TSV)](#6-the-timed-op-stream-format-v2-tsv)
7. [How diffvim (vimscript) Works](#7-how-diffvim-vimscript-works)
8. [How diffvim-pipeline (standalone) Works](#8-how-diffvim-pipeline-standalone-works)
9. [The Coloring System](#9-the-coloring-system)
10. [Ghost-Line Fix](#10-ghost-line-fix)
11. [Testing](#11-testing)
12. [Adding a New Language](#12-adding-a-new-language)
13. [Adding a New Postprocess Transform](#13-adding-a-new-postprocess-transform)
14. [Adding a New Pacing Mode](#14-adding-a-new-pacing-mode)
15. [Debugging Tips](#15-debugging-tips)
16. [Common Pitfalls](#16-common-pitfalls)
17. [Coding Conventions](#17-coding-conventions)

---

## 1. Project Overview

**diffvim** animates a code diff — the transformation of an old file into
a new file — as if a human were typing it in real time. The animation
feels natural: the cursor glides between change locations, characters are
deleted and re-typed with small delays, and unchanged text is skipped
instantly.

The project has two modes:
- **diffvim** (vimscript): Opens the old file in vim and animates the
  transformation inside vim. Uses vim's syntax highlighting, buffer
  manipulation, and timer-based animation. Best for interactive use.
- **diffvim-pipeline** (standalone): Runs the full pipeline
  (compute → postprocess → pace → animate) as external executables.
  Renders to a terminal with ANSI escapes. Best for scripting and
  testing. Supports syntax coloring via external colorizers.

---

## 2. Architecture

```
┌──────────┐     ┌──────────────┐     ┌──────────┐     ┌──────────┐
│  Compute │ ──> │  Postprocess │ ──> │   Pace   │ ──> │ Animator │
│ (C++     │     │ (C / Perl)   │     │ (C/Perl) │     │(C/Perl/  │
│  Patience│     │ op ordering  │     │ delays + │     │ vim)     │
│  diff)   │     │ positioning  │     │ batching │     │          │
└──────────┘     └──────────────┘     └──────────┘     └──────────┘
     │                 │                   │                  │
     ▼                 ▼                   ▼                  ▼
  raw ops      positioned ops      timed op stream      rendered
  (HUNK/        (TSV with           (TSV with delays    animation
   keep/         per-op              + batch ops)        in terminal
   delete/       line,col)                               or vim
   insert)
```

### Key design principles

1. **Each stage is a separate executable.** They communicate via stdin/stdout
   pipes. Each can be tested independently.

2. **The timed op stream is the contract between stages.** It's a TSV format
   where every op carries its own (line, col) position. The animator is
   stateless w.r.t. positioning — it just applies ops at their given positions.

3. **Postprocess owns cursor positioning.** Pace only adds delays and batching.
   The animator doesn't track positions — every op tells it where to go.

4. **Typed delays.** Every delay has a type (`type`, `keep`, `delete`,
   `hunk_pause`, `awd_start`, `awd_word`, etc.) so the animator can
   dynamically scale delays per type at runtime.

5. **Ghost-line fix in the animator.** When deleting `\n` and the current
   line is already empty, remove the empty line instead of joining.

---

## 3. Repository Layout

```
gitanim/
├── diffvim                       # Bash launcher (loads vimscript engine)
├── diffvim.pl                    # Perl launcher
├── diffvim-tmux                  # tmux variant
├── diffvim-compare               # Diff algorithm benchmark tool
├── diffvim-jogger                # Test-case exerciser
│
├── compute/
│   ├── cpp/diffvim-compute.cpp   # C++ Patience diff (the only compute tool)
│   ├── perl/compute_builtin.pl   # Perl fallback (byte-identical to C++)
│   ├── Makefile                  # `make` → builds diffvim-compute-cpp
│   └── bin/diffvim-compute-cpp   # Compiled binary
│
├── animator/
│   ├── c/                         # C source
│   │   ├── animator.c             # Standalone terminal animator
│   │   ├── postprocess.c          # Op reordering + per-op positioning
│   │   └── pace.c                 # Timing + batching
│   ├── perl/                      # Perl source (mirrors C)
│   │   ├── animator.pl
│   │   ├── postprocess.pl
│   │   ├── pace.pl
│   │   └── colorize.pl            # Syntax coloring tool (vim/pygmentize)
│   ├── bin/                       # Compiled C binaries
│   ├── diffvim-pipeline           # Bash script: runs all 4 stages
│   ├── tests/                     # Animator-specific tests
│   └── docs/                      # Animator documentation
│
├── autoload/diffvim/engine.vim   # Vimscript engine (standalone, sourced by launcher)
├── plugin/diffvim.vim            # Vim plugin (:Diffvim, :DiffvimPick commands)
├── autoload/diffvim/             # Vimscript autoload
│
├── completion/                   # Shell completions (bash, fish, zsh)
├── man/                          # Manpages (roff)
├── docs/                         # Documentation
│   ├── src/                      # mdBook source
│   ├── PIPELINE.md               # Pipeline architecture
│   ├── DEVELOPER_GUIDE.md        # This file
│   └── ...
│
├── examples/                     # 42 example file pairs (old/new)
├── tests/                        # vimscript engine tests
├── tests/verify_md5.sh         # Round-trip MD5 verification
├── DiffVim/Parser/Perl.pm        # Pure-Perl Patience diff parser
└── packaging/diffvim.rb           # Homebrew formula
```

---

## 4. Building from Source

```bash
# Clone
git clone https://github.com/nkh/gitanim.git
cd gitanim

# Build C++ compute tool
make -C compute

# Build C animator tools
cd animator/c
cc -O2 -o ../bin/diffvim-animator-c animator.c
cc -O2 -o ../bin/diffvim-postprocess postprocess.c
cc -O2 -o ../bin/diffvim-pace pace.c
cd ..

# Verify
./animator/diffvim-pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    examples/01_small_python/old.py examples/01_small_python/new.py
md5sum /tmp/out.txt examples/01_small_python/new.py
# Should match

# Run the full test suite
bash tests/verify_md5.sh
```

### Dependencies

- **C++17 compiler** (g++ 14+) — for the compute tool
- **C compiler** (gcc 14+) — for the animator tools
- **Perl 5** — for the Perl animator, postprocess, pace, colorize, and tests
- **vim 9** — for the vimscript animator (diffvim)
- **pygmentize** (optional) — for syntax coloring via Pygments
- **fzf** (optional) — for `:DiffvimPick` commit picker

---

## 5. The Pipeline Stages

### Stage 1: Compute (`diffvim-compute-cpp`)

**Input:** old file + new file
**Output:** raw char-level ops (HUNK/keep/delete/insert format)

Uses the **Patience diff algorithm**: anchors on unique common lines,
recurses on the gaps, and falls back to LCS for ranges with no anchors.

```bash
diffvim-compute-cpp old.py new.py raw_ops.txt
```

Output format:
```
# diffvim precomputed diff v1
# algorithm patience
# hunk_count N
HUNK <target_line> <del_count> <ins_count> <is_end_insert> <is_end_delete>
keep <char_code>
delete <char_code>
insert <char_code>
```

### Stage 2: Postprocess (`diffvim-postprocess`)

**Input:** raw ops from compute
**Output:** positioned ops (TSV with per-op line, col)

Applies transformations:
- **Op ordering** (`--transform op-order:optimize`): deletes before inserts
  within each line group
- **Semantic cleanup** (`--transform semantic-cleanup`): merges adjacent
  delete+insert pairs that cancel out
- **Indent-aware** (`--transform indent-aware`): treats indent-only changes
  as keeps

Computes per-op `(line, col)` positions by simulating the cursor.

```bash
diffvim-postprocess --transform op-order:optimize < raw_ops.txt > positioned_ops.txt
# Or streaming mode:
diffvim-postprocess --stream < raw_ops.txt > positioned_ops.txt
```

Output format (TSV):
```
hunk_start\t<del_count>\t<ins_count>
op\tkeep|delete|insert\t<line>\t<col>\t<char_code>
newline_delete\t<line>
newline_insert\t<line>\t<col>
```

### Stage 3: Pace (`diffvim-pace`)

**Input:** positioned ops from postprocess
**Output:** timed op stream (ops + typed delays + batch operations)

Adds timing and batching. Does NOT modify any op — only adds delays and
batch operations around them.

```bash
diffvim-pace --delete-pacing word --insert-pacing char < positioned_ops.txt > timed_ops.txt
```

Delay types: `type`, `keep`, `delete`, `hunk_pause`, `rapid_eol`,
`awd_start`, `awd_word`, `awd_space`, `word_insert`, `newline_delete`,
`newline_insert`.

### Stage 4: Animate (`diffvim-animator-c` or `diffvim`)

**Input:** timed op stream
**Output:** visual animation in terminal (or vim)

The animator:
1. Loads the old file into a virtual buffer
2. Reads the timed op stream
3. For each op, calls `set_cursor(line, col)` then applies the op
4. Renders incrementally (only redraws changed lines)

**Ghost-line fix**: when `delete_char(10)` is called and the current
line is empty, removes the empty line instead of joining.

---

## 6. The Timed Op Stream Format (v2 TSV)

The timed op stream is a tab-separated values file:

```
# timed op stream v2
# format: TSV, every op carries (line, col) — 1-indexed
# delays are typed: delay\t<type>\t<ms>
# delete_threshold 3
hunk_start\t<del_count>\t<ins_count>
op\tkeep\t<line>\t<col>\t<char_code>
op\tdelete\t<line>\t<col>\t<char_code>
op\tinsert\t<line>\t<col>\t<char_code>
batch_delete\t<line>\t<col>\t<count>
batch_insert\t<line>\t<col>\t<code1>\t<code2>\t...
newline_delete\t<line>
newline_insert\t<line>\t<col>
delay\t<type>\t<ms>
hunk_end
done
```

Key points:
- **1-indexed** line and column numbers (vim-style)
- **char_code** is a Unicode code point (10 = newline)
- Every op carries its own position — the animator is stateless
- Delays are **typed** — enables future per-type dynamic pacing

---

## 7. How diffvim (vimscript) Works

The `diffvim` bash launcher:

1. Parses command-line options
2. Runs the external pipeline (compute → postprocess → pace) to produce
   a timed op stream file (`$DIFFVIM_TIMED_OPS`)
3. Launches vim with the old file
4. Sources the vimscript engine, which:
   a. Detects `$DIFFVIM_TIMED_OPS`
   b. Reads the timed op stream
   c. Applies ops to the vim buffer using `setline`/`append`/`delete`
   d. Renders using `redraw` (incremental, not `redraw!` which clears)
   e. Uses a single timer per delay (not a polling loop)

### Anti-flash rendering

The vimscript animator avoids flashing by:
- NOT calling `redraw!` (which clears the whole screen)
- Using `redraw` (which only updates changed lines)
- Only rendering at delay boundaries (not after every op)
- `keep` ops don't trigger rendering at all

### Key mappings (during animation)

| Key | Action |
|-----|--------|
| `Space` | Pause / resume |
| `q` | Stop animation |
| `+` | Speed up (×1.5) |
| `-` | Slow down (÷1.5) |

---

## 8. How diffvim-pipeline (standalone) Works

The `diffvim-pipeline` bash script:

1. Finds all tool binaries (C++ preferred, Perl fallback)
2. Starts coloring in **parallel** with the processing pipeline
3. Runs: `compute → postprocess → pace → animator`
4. Passes colormap files to the animator via `--colormap-old`/`--colormap-new`

```bash
diffvim-pipeline [options] <oldfile> <newfile>

# Options are routed by prefix:
#   --compute-*       → diffvim-compute-cpp
#   --postprocess-*   → diffvim-postprocess
#   --pace-*          → diffvim-pace
#   --animator-*      → diffvim-animator-c
#   (unprefixed)      → diffvim-animator-c
```

### The C animator's incremental rendering

The C animator avoids flashing by:
- Tracking the previous screen state (`prev_lines` array)
- Only redrawing lines that changed (content or cursor position)
- Using `\033[<line>;1H\033[2K` (move + clear line) instead of `\033[2J` (clear screen)

---

## 9. The Coloring System

### diffvim-colorize tool

`animator/perl/colorize.pl` produces color map files — one ANSI-colored
line per source line.

**Backends:**
- **vim**: Uses vim's `synID()` per char — most accurate, requires vim
- **pygmentize**: Uses Pygments Python library — requires pygmentize
- **none**: Plain text, no coloring

Auto-detection: `vim > pygmentize > none`

```bash
diffvim-colorize [--backend vim|pygmentize|none] [--lang LANG] FILE OUTPUT
```

### How coloring integrates with the pipeline

The `diffvim-pipeline` script:
1. Starts both colorizations (old + new) in the **background**
2. Concurrently runs compute → postprocess → pace
3. Waits for coloring to finish
4. Passes colormap files to the animator

The C animator:
- Renders unmodified lines using the colormap (syntax-highlighted)
- Modified lines fall back to plain text (progressive decoloring)
- `--colormap-old FILE`: colored version of the old file
- `--colormap-new FILE`: colored version of the new file (for inserts)

### Adding a new coloring backend

1. Add a new function `colorize_with_XXX()` in `colorize.pl`
2. Add it to the auto-detection in the `backend` logic
3. The function takes `($file, $lang, \@lines)` and returns `@colored_lines`
4. Each colored line should contain ANSI escape sequences (`\033[...m`)

---

## 10. Ghost-Line Fix

### The problem

When a diff produces:
```
keep "foo"
delete \n        ← joins line N with line N+1
delete "bar"     ← content of line N+1
```

The animator's `delete_char(10)` removes the `\n` between lines N and N+1,
**joining** them. Visually, line N+1's content ("bar") jumps up onto
line N — this looks bad.

### The fix (in the animator only)

When `delete_char(10)` is called:
- **If the current line is empty** (all content already deleted by
  preceding char deletes): **remove the empty line entirely**. The cursor
  stays at the same line index, which now points to what was the next line.
  No visual jump.
- **If the current line has content**: **join** it with the next line
  (original behavior — needed for mixed delete+insert sequences).

This fix is in:
- `animator/c/animator.c` — `delete_char()` function
- `animator/perl/animator.pl` — `delete_char()` function
- `diffvim` (vimscript) — `s:TimedDeleteChar()` function

No postprocess changes needed. No op reordering. No position tracking
changes. The postprocess already emits content deletes BEFORE the `\n`
delete (that's how `optimize_line` works), so the line is already empty
when the `\n` delete arrives.

---

## 11. Testing

### MD5 round-trip verification

The primary test: animate old → new, save the final buffer, compare MD5
with the new file.

```bash
# Quick (parallel, 8 concurrent, ~2 minutes):
bash tests/verify_md5.sh

# Single example:
./animator/diffvim-pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    examples/01_small_python/old.py examples/01_small_python/new.py
md5sum /tmp/out.txt examples/01_small_python/new.py
```

### Perl test suites

```bash
# Cross-language parity (C == Perl):
perl animator/tests/test_cross_language.pl

# Round-trip for all animators:
perl animator/tests/test_all_animators.pl

# Newline handling:
perl animator/tests/test_newline_fix.pl

# Op ordering:
perl tests/test_op_order.pl

# Delete pacing:
perl tests/test_delete_pacing.pl
```

### Adding a new test case

1. Create `examples/NN_description/old.ext` and `new.ext`
2. Run `bash tests/verify_md5.sh` — the new example is automatically included
3. If the MD5 doesn't match, debug with:
   ```bash
   ./animator/diffvim-pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
       examples/NN_description/old.ext examples/NN_description/new.ext
   diff /tmp/out.txt examples/NN_description/new.ext
   ```

---

## 12. Adding a New Language

diffvim auto-detects language from file extension. To add a new one:

1. **Add to the extension map** in:
   - `compute/cpp/diffvim-compute.cpp` (not needed — compute is language-agnostic)
   - `animator/perl/colorize.pl` — add to `%ext_map`
   - `diffvim` (vimscript) — add to the `setfiletype` if-chain

2. **Add example files**: Create `examples/NN_lang_name/old.ext` and `new.ext`

3. **Add completion** (optional): Add the extension to `completion/diffvim.bash`
   in the `--language` completion.

---

## 13. Adding a New Postprocess Transform

1. **Implement the transform** in both:
   - `animator/c/postprocess.c` — add a function and wire it into `write_output()`
   - `animator/perl/postprocess.pl` — add a `sub` and call it in the transform loop

2. **Add to `--transform` parsing**:
   - In `apply_transform()` (C) or the `--transform` handler (Perl)
   - Add to `list_transforms()` / `--list-transforms` output

3. **Test**:
   ```bash
   diffvim-postprocess --transform your_transform < raw_ops.txt > out.txt
   ```

---

## 14. Adding a New Pacing Mode

1. **Add the mode** to `process_delete()` or `process_awd()` in:
   - `animator/c/pace.c`
   - `animator/perl/pace.pl`

2. **Add to validation**: Add to `%valid_dp` in Perl, and to the `--delete-pacing` help.

3. **Add a new delay type** if the mode produces different kinds of delays:
   - Add the type string to the `fprintf`/`printf` calls
   - Update the typed delay documentation

4. **Test**:
   ```bash
   diffvim-pace --delete-pacing your_mode < positioned_ops.txt > timed_ops.txt
   ```

---

## 15. Debugging Tips

### Enable debug logging

```bash
# diffvim launcher:
diffvim --debug old.py new.py
# Writes to /tmp/diffvim-debug.log

# See the timed op stream:
WORKDIR=/tmp/dv_debug diffvim --no-vimrc old.py new.py
# Stream is at /tmp/dv_debug/timed_ops.txt
```

### Run pipeline stages manually

```bash
# Stage 1: Compute
./compute/bin/diffvim-compute-cpp old.py new.py /tmp/raw.txt

# Stage 2: Postprocess
./animator/bin/diffvim-postprocess < /tmp/raw.txt > /tmp/post.txt

# Stage 3: Pace
./animator/bin/diffvim-pace < /tmp/post.txt > /tmp/timed.txt

# Stage 4: Animate
./animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/out.txt old.py < /tmp/timed.txt
```

### Compare C vs Perl output

```bash
# Postprocess
diff <(./animator/bin/diffvim-postprocess < /tmp/raw.txt) \
     <(perl animator/perl/postprocess.pl < /tmp/raw.txt)

# Pace
diff <(./animator/bin/diffvim-pace < /tmp/post.txt) \
     <(perl animator/perl/pace.pl < /tmp/post.txt)
```

### Use AddressSanitizer

If you suspect memory corruption:
```bash
cc -O0 -g -fsanitize=address -o /tmp/anim_asan animator/c/animator.c
/tmp/anim_asan --no-display --speed 1000 --snapshot /tmp/out.txt old.py < /tmp/timed.txt
```

### Debug the vimscript engine

```bash
# Extract the engine and run it manually
vim -u NONE -N -n -es -V9 \
    -c 'let g:diffvim_new_file = "new.py"' \
    -c 'let g:diffvim = {"output_file": "/tmp/out.txt"}' \
    -c 'source /tmp/engine.vim' \
    old.py
```

---

## 16. Common Pitfalls

### "The animator produces wrong output on large files"

Likely a **buffer overflow**. The `line_modified` array (used for colormap
rendering) must grow dynamically — if it doesn't, writes past the end
corrupt adjacent heap memory. Use AddressSanitizer to find it.

### "The animation flashes horribly"

The animator is using `redraw!` (vimscript) or `\033[2J` (C) on every op.
These clear the entire screen. Use `redraw` (incremental) or only redraw
changed lines.

### "Cursor positions are wrong after ghost-line fix"

The ghost-line fix must ONLY be in the animator's `delete_char(10)`,
NOT in postprocess. The postprocess emits ops in the correct order
(content deletes before `\n` delete). The animator just needs to check
if the line is empty before deciding to join vs remove.

### "pace batches deletes across line boundaries"

The `process_delete()` function counts consecutive non-newline deletes.
If deletes span multiple lines (same col, different line), it batches
them all into one `batch_delete` targeting the first line. Fix: stop
counting when the line changes.

### "--stream mode emits wrong hunk_count"

In streaming mode, `hunk_count` is unknown (we haven't seen all hunks
yet). It's emitted as `-1`. Downstream tools (pace, animator) should
ignore this value — they process hunks as they arrive.

---

## 17. Coding Conventions

### C code
- Use `static` for all file-local functions and variables
- Dynamic arrays: `ensure_*_capacity()` pattern with doubling
- Always check `realloc` return value
- Use `fprintf(stderr, ...)` for error messages
- TSV output: use `\t` and `\n` explicitly

### Perl code
- `use strict; use warnings;` always
- `Getopt::Long` for argument parsing
- TSV output: use `\t` explicitly in strings

### Vimscript code
- Use `s:` prefix for script-local functions/variables
- Use `l:` prefix for function-local variables (but NOT `l:sid` — it's illegal!)
- Use `function!` (with `!`) for all function definitions
- Use `abort` on all function definitions
- Use `==#` (case-sensitive) for string comparisons

### Bash code
- `set -euo pipefail` at the top of scripts
- Quote all variable expansions: `"$var"`
- Use `[[ ]]` instead of `[ ]` for conditionals

### Documentation
- Update `CHANGELOG.md` for every change
- Update `docs/PIPELINE.md` when the pipeline format changes
- Update manpages when CLI options change
- Update completions when CLI options change

---

## Quick Reference: Key Files

| File | Purpose |
|------|---------|
| `compute/cpp/diffvim-compute.cpp` | Patience diff algorithm (C++) |
| `animator/c/postprocess.c` | Op reordering + per-op positioning |
| `animator/c/pace.c` | Timing + batching |
| `animator/c/animator.c` | Terminal renderer with incremental display |
| `animator/perl/*.pl` | Perl mirrors of the C tools |
| `animator/perl/colorize.pl` | Syntax coloring (vim/pygmentize backends) |
| `animator/diffvim-pipeline` | Bash script wiring all 4 stages |
| `diffvim` | Bash launcher + embedded vimscript engine |
| `autoload/diffvim/engine.vim` | Standalone vimscript engine (for plugin mode) |
| `plugin/diffvim.vim` | Vim plugin (:Diffvim, :DiffvimPick) |
| `tests/verify_md5.sh` | Round-trip MD5 verification (42 examples) |
| `docs/PIPELINE.md` | Pipeline architecture reference |
| `docs/GHOST_LINE_DESIGN.md` | Ghost-line fix design (historical) |
| `docs/ARCHITECTURE_ANALYSIS.md` | Architecture analysis (historical) |
