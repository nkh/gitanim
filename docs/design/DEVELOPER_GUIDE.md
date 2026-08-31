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
7. [How ad_vim (vimscript) Works](#7-how-diffvim-vimscript-works)
8. [How ad_pipeline (standalone) Works](#8-how-ad_pipeline-standalone-works)
9. [The Coloring System](#9-the-coloring-system)
10. [Testing](#10-testing)
11. [Adding a New Language](#11-adding-a-new-language)
12. [Adding a New Postprocess Transform](#12-adding-a-new-postprocess-transform)
13. [Adding a New Pacing Mode](#13-adding-a-new-pacing-mode)
14. [Debugging Tips](#14-debugging-tips)
15. [Common Pitfalls](#15-common-pitfalls)
16. [Coding Conventions](#16-coding-conventions)

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
- **ad_pipeline** (standalone): Runs the full pipeline
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

---

## 3. Repository Layout

```
gitanim/
├── ad_vim                       # Bash launcher (loads vimscript engine)
├── ad_vim.pl                    # Perl launcher
├── ad_tmux                  # tmux variant
├── ad_compare               # Diff algorithm benchmark tool
├── ad_jogger                # Test-case exerciser
│
├── compute/
│   ├── cpp/ad_compute.cpp   # C++ Patience diff (the only compute tool)
│   ├── perl/compute_builtin.pl   # Perl fallback (byte-identical to C++)
│   ├── Makefile                  # `make` → builds ad_compute
│   └── bin/ad_compute   # Compiled binary
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
│   ├── ad_pipeline           # Bash script: runs all 4 stages
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
├── tests/tests/examples/                     # 42 example file pairs (old/new)
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
cc -O2 -o ../bin/ad animator.c
cc -O2 -o ../bin/ad_postprocess postprocess.c
cc -O2 -o ../bin/ad_layer_pace pace.c
cd ..

# Verify
./animator/ad_pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py
md5sum /tmp/out.txt tests/tests/examples/01_small_python/new.py
# Should match

# Run the full test suite
bash tests/verify_md5.sh
```

### Dependencies

- **C++17 compiler** (g++ 14+) — for the compute tool
- **C compiler** (gcc 14+) — for the animator tools
- **Perl 5** — for the Perl animator, postprocess, pace, colorize, and tests
- **vim 9** — for the vimscript animator (ad_vim)
- **pygmentize** (optional) — for syntax coloring via Pygments
- **fzf** (optional) — for `:DiffvimPick` commit picker

---

## 5. The Pipeline Stages

### Stage 1: Compute (`ad_compute`)

**Input:** old file + new file
**Output:** raw char-level ops (HUNK/keep/delete/insert format)

Uses the **Patience diff algorithm**: anchors on unique common lines,
recurses on the gaps, and falls back to LCS for ranges with no anchors.

```bash
ad_compute old.py new.py raw_ops.txt
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

### Stage 2: Postprocess (`ad_postprocess`)

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
ad_postprocess --transform op-order:optimize < raw_ops.txt > positioned_ops.txt
# Or streaming mode:
ad_postprocess --stream < raw_ops.txt > positioned_ops.txt
```

Output format (TSV):
```
hunk_start\t<del_count>\t<ins_count>
op\tkeep|delete|insert\t<line>\t<col>\t<char_code>
newline_delete\t<line>
newline_insert\t<line>\t<col>
```

### Stage 3: Pace (`ad_layer_pace`)

**Input:** positioned ops from postprocess
**Output:** timed op stream (ops + typed delays + batch operations)

Adds timing and batching. Does NOT modify any op — only adds delays and
batch operations around them.

```bash
ad_layer_pace --delete-pacing word --insert-pacing char < positioned_ops.txt > timed_ops.txt
```

Delay types: `type`, `keep`, `delete`, `hunk_pause`, `rapid_eol`,
`awd_start`, `awd_word`, `awd_space`, `word_insert`, `newline_delete`,
`newline_insert`.

### Stage 4: Animate (`ad` or `diffvim`)

**Input:** timed op stream
**Output:** visual animation in terminal (or vim)

The animator:
1. Loads the old file into a virtual buffer
2. Reads the timed op stream
3. For each op, calls `set_cursor(line, col)` then applies the op
4. Renders incrementally (only redraws changed lines)

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

## 7. How ad_vim (vimscript) Works

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

## 8. How ad_pipeline (standalone) Works

The `ad_pipeline` bash script:

1. Finds all tool binaries (C++ preferred, Perl fallback)
2. Starts coloring in **parallel** with the processing pipeline
3. Runs: `compute → postprocess → pace → animator`
4. Passes colormap files to the animator via `--colormap-old`/`--colormap-new`

```bash
ad_pipeline [options] <oldfile> <newfile>

# Options are routed by prefix:
#   --compute-*       → ad_compute
#   --postprocess-*   → ad_postprocess
#   --pace-*          → ad_layer_pace
#   --animator-*      → ad
#   (unprefixed)      → ad
```

### The C animator's incremental rendering

The C animator avoids flashing by:
- Tracking the previous screen state (`prev_lines` array)
- Only redrawing lines that changed (content or cursor position)
- Using `\033[<line>;1H\033[2K` (move + clear line) instead of `\033[2J` (clear screen)

---

## 9. The Coloring System

### ad_colorize tool

`animator/perl/colorize.pl` produces color map files — one ANSI-colored
line per source line.

**Backends:**
- **vim**: Uses vim's `synID()` per char — most accurate, requires vim
- **pygmentize**: Uses Pygments Python library — requires pygmentize
- **none**: Plain text, no coloring

Auto-detection: `vim > pygmentize > none`

```bash
ad_colorize [--backend vim|pygmentize|none] [--lang LANG] FILE OUTPUT
```

### How coloring integrates with the pipeline

The `ad_pipeline` script:
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

## 10. Testing

### MD5 round-trip verification

The primary test: animate old → new, save the final buffer, compare MD5
with the new file.

```bash
# Quick (parallel, 8 concurrent, ~2 minutes):
bash tests/verify_md5.sh

# Single example:
./animator/ad_pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py
md5sum /tmp/out.txt tests/tests/examples/01_small_python/new.py
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

1. Create `tests/tests/examples/NN_description/old.ext` and `new.ext`
2. Run `bash tests/verify_md5.sh` — the new example is automatically included
3. If the MD5 doesn't match, debug with:
   ```bash
   ./animator/ad_pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
       tests/tests/examples/NN_description/old.ext tests/tests/examples/NN_description/new.ext
   diff /tmp/out.txt tests/tests/examples/NN_description/new.ext
   ```

---

## 11. Adding a New Language

ad_vim auto-detects language from file extension. To add a new one:

1. **Add to the extension map** in:
   - `compute/cpp/ad_compute.cpp` (not needed — compute is language-agnostic)
   - `animator/perl/colorize.pl` — add to `%ext_map`
   - `diffvim` (vimscript) — add to the `setfiletype` if-chain

2. **Add example files**: Create `tests/tests/examples/NN_lang_name/old.ext` and `new.ext`

3. **Add completion** (optional): Add the extension to `completion/ad_vim.bash`
   in the `--language` completion.

---

## 12. Adding a New Postprocess Transform

1. **Implement the transform** in both:
   - `animator/c/postprocess.c` — add a function and wire it into `write_output()`
   - `layers/perl/postprocess.pl` — add a `sub` and call it in the transform loop

2. **Add to `--transform` parsing**:
   - In `apply_transform()` (C) or the `--transform` handler (Perl)
   - Add to `list_transforms()` / `--list-transforms` output

3. **Test**:
   ```bash
   ad_postprocess --transform your_transform < raw_ops.txt > out.txt
   ```

---

## 13. Adding a New Pacing Mode

1. **Add the mode** to `process_delete()` or `process_awd()` in:
   - `animator/c/pace.c`
   - `layers/perl/ad_layer_pace.pl`

2. **Add to validation**: Add to `%valid_dp` in Perl, and to the `--delete-pacing` help.

3. **Add a new delay type** if the mode produces different kinds of delays:
   - Add the type string to the `fprintf`/`printf` calls
   - Update the typed delay documentation

4. **Test**:
   ```bash
   ad_layer_pace --delete-pacing your_mode < positioned_ops.txt > timed_ops.txt
   ```

---

## 14. Debugging Tips

### Enable debug logging

```bash
# ad_vim launcher:
ad_vim --debug old.py new.py
# Writes to /tmp/diffvim-debug.log

# See the timed op stream:
WORKDIR=/tmp/ad_debug ad_vim --no-vimrc old.py new.py
# Stream is at /tmp/ad_debug/timed_ops.txt
```

### Run pipeline stages manually

```bash
# Stage 1: Compute
./bin/ad_compute old.py new.py /tmp/raw.txt

# Stage 2: Postprocess
./bin/ad_postprocess < /tmp/raw.txt > /tmp/post.txt

# Stage 3: Pace
./bin/ad_layer_pace < /tmp/post.txt > /tmp/timed.txt

# Stage 4: Animate
./bin/ad --no-display --speed 1000 --snapshot /tmp/out.txt old.py < /tmp/timed.txt
```

### Compare C vs Perl output

```bash
# Postprocess
diff <(./bin/ad_postprocess < /tmp/raw.txt) \
     <(perl layers/perl/postprocess.pl < /tmp/raw.txt)

# Pace
diff <(./bin/ad_layer_pace < /tmp/post.txt) \
     <(perl layers/perl/ad_layer_pace.pl < /tmp/post.txt)
```

### Use AddressSanitizer

If you suspect memory corruption:
```bash
cc -O0 -g -fsanitize=address -o /tmp/anim_asan animator/c/ad.c
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

## 15. Common Pitfalls

### "The animator produces wrong output on large files"

Likely a **buffer overflow**. The `line_modified` array (used for colormap
rendering) must grow dynamically — if it doesn't, writes past the end
corrupt adjacent heap memory. Use AddressSanitizer to find it.

### "The animation flashes horribly"

The animator is using `redraw!` (vimscript) or `\033[2J` (C) on every op.
These clear the entire screen. Use `redraw` (incremental) or only redraw
changed lines.

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

## 16. Coding Conventions

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
| `compute/cpp/ad_compute.cpp` | Patience diff algorithm (C++) |
| `animator/c/postprocess.c` | Op reordering + per-op positioning |
| `animator/c/pace.c` | Timing + batching |
| `animator/c/ad.c` | Terminal renderer with incremental display |
| `animator/perl/*.pl` | Perl mirrors of the C tools |
| `animator/perl/colorize.pl` | Syntax coloring (vim/pygmentize backends) |
| `animator/ad_pipeline` | Bash script wiring all 4 stages |
| `diffvim` | Bash launcher + embedded vimscript engine |
| `autoload/diffvim/engine.vim` | Standalone vimscript engine (for plugin mode) |
| `plugin/diffvim.vim` | Vim plugin (:Diffvim, :DiffvimPick) |
| `tests/verify_md5.sh` | Round-trip MD5 verification (42 examples) |
| `docs/PIPELINE.md` | Pipeline architecture reference |
| `docs/ARCHITECTURE_ANALYSIS.md` | Architecture analysis (historical) |
