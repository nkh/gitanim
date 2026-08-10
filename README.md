# diffvim — Animate Code Diffs in Vim

Animate a code diff as if a human were typing it. Open the old file in vim,
watch the cursor glide between change locations with smooth ease-in-out
acceleration, and see only the actually-changed characters deleted and
re-typed — surrounding text is never touched.

![diffvim demo flow](docs/images/flow.txt)

---

## Table of Contents

- [What It Does](#what-it-does)
- [Quick Start](#quick-start)
- [Three Implementations](#three-implementations)
- [Controls](#controls)
- [Configuration](#configuration)
- [Requirements](#requirements)
- [Installation](#installation)
- [Examples](#examples)
- [How It Works](#how-it-works)
- [Diff Parsers](#diff-parsers)
- [Project Structure](#project-structure)
- [Testing](#testing)
- [Known Limitations](#known-limitations)
- [Roadmap — 100 Improvements](#roadmap--100-improvements)
- [License](#license)

---

## What It Does

Given two versions of a file, `diffvim` opens the **old** version in vim and
animates the transformation into the **new** version character by character:

1. **Diff** — computes a line-level diff, groups changes into hunks
2. **Char-diff** — within each hunk, computes a char-level LCS diff so only
   the actually-changed characters are touched (no whole-line rewrites)
3. **Glide** — the cursor glides between change locations with an ease-in-out
   cubic curve (slow start → fast middle → slow end)
4. **Type / Delete** — changed characters are deleted and re-typed with
   small natural delays; unchanged characters are skipped instantly
5. **User control** — at any moment the user can pause, skip, go back, or
   quit; the animation responds immediately without blocking

After the animation completes (or the user stops it), the buffer is a normal
vim buffer — you can `:w`, `:wq`, edit further, etc.

---

## Quick Start

```bash
# Simplest usage — bash + vim (no tmux needed)
./diffvim old.py new.py

# Bash + tmux + vim
./diffvim-tmux old.py new.py

# Perl + tmux + vim (with pluggable parsers)
perl diffvim.pl old.py new.py
perl diffvim.pl --parser diff2html old.py new.py
```

Controls during animation (in vim normal mode):

| Key       | Action                                      |
| --------- | ------------------------------------------- |
| `Space`   | Pause / resume the animation                |
| `n`       | Skip current hunk (apply instantly)         |
| `b`       | Back to previous hunk (revert and restart)  |
| `q`       | Stop animation (leave buffer for editing)   |
| `?`       | Show help *(diffvim only)*                  |

---

## Three Implementations

This project contains three independent implementations of the same concept:

### 1. `diffvim` — Bash + Vimscript (self-contained)

- **Language:** Bash (launcher) + Vimscript (engine)
- **Architecture:** The bash script generates a vimscript file and launches
  vim with it. Vim's `timer_start()` drives the animation asynchronously,
  so user input is never blocked.
- **Best for:** Quick single-file animations without extra dependencies.
- **Requires:** Vim 8+ with `+timers` and `+float`. No Python, no tmux.

### 2. `diffvim-tmux` — Bash + tmux + Vim

- **Language:** Bash
- **Architecture:** Bash is the orchestrator. Vim runs in a tmux pane.
  Bash sends Ex commands to vim via `tmux send-keys`. Vim normal-mode
  mappings write user commands (p/n/b/q) to a FIFO. Bash reads the FIFO
  non-blocking between animation steps.
- **Best for:** When you want bash to control the animation loop (e.g.,
  for scripting, logging, or integration with other tools).
- **Requires:** Bash 4+, tmux 3+, Vim 8+, `diff`, `sed`, `awk`.

### 3. `diffvim.pl` — Perl + tmux + Vim (with pluggable parsers)

- **Language:** Perl 5
- **Architecture:** Same tmux+FIFO approach as `diffvim-tmux`, but written
  in Perl with a modular parser architecture. Two parsers are available:
  - **`DiffVim::Parser::Perl`** — pure-Perl LCS diff (no external deps
    beyond Perl core; uses `Algorithm::Diff` if installed)
  - **`DiffVim::Parser::Diff2Html`** — shells out to the `diff2html` CLI
    with `-f json` for line-level parsing, then computes char-level LCS
    in Perl
- **Best for:** When you want parser pluggability, better data structures,
  or prefer Perl over Bash.
- **Requires:** Perl 5.10+, tmux 3+, Vim 8+, `diff`.
- **Optional:** `diff2html-cli` (`npm install -g diff2html-cli`) for the
  diff2html parser.

---

## Controls

All three implementations share the same user controls (except `?` help is
diffvim-only):

| Key       | Action                                                              |
| --------- | ------------------------------------------------------------------ |
| `Space`   | **Pause / resume.** Toggles the animation. While paused, a message is displayed. |
| `n`       | **Skip.** Applies the current hunk instantly (no char-by-char animation) and moves to the next. |
| `b`       | **Back.** Reverts to the snapshot taken before the current hunk and restarts it. |
| `q`       | **Quit.** Stops the animation. The buffer is left in its current state for editing. |
| `?`       | **Help.** Shows the current hunk index and available keys *(diffvim only)*. |

Controls are active at any moment during the animation — even mid-typing.
The animation loop checks for user input between every animation step.

---

## Configuration

All implementations read timing configuration from environment variables:

| Variable                    | Default | Description                              |
| --------------------------- | ------- | ---------------------------------------- |
| `DIFFVIM_TICK_MS`           | `16`    | Animation frame interval (~60fps)        |
| `DIFFVIM_TYPE_DELAY_MS`     | `35`    | Delay between typed characters           |
| `DIFFVIM_DELETE_DELAY_MS`   | `25`    | Delay between deleted characters         |
| `DIFFVIM_MOVE_MIN_MS`       | `200`   | Minimum cursor-glide duration            |
| `DIFFVIM_MOVE_MAX_MS`       | `1400`  | Maximum cursor-glide duration            |
| `DIFFVIM_MOVE_MS_PER_UNIT`  | `6`     | Milliseconds per unit of glide distance  |
| `DIFFVIM_HUNK_PAUSE_MS`     | `180`   | Pause between hunks                      |

Example — slow down the animation for a presentation:

```bash
DIFFVIM_TYPE_DELAY_MS=80 \
DIFFVIM_DELETE_DELAY_MS=60 \
DIFFVIM_MOVE_MAX_MS=3000 \
./diffvim old.py new.py
```

Example — speed it up for a quick review:

```bash
DIFFVIM_TYPE_DELAY_MS=10 \
DIFFVIM_DELETE_DELAY_MS=10 \
DIFFVIM_MOVE_MIN_MS=50 \
DIFFVIM_MOVE_MAX_MS=300 \
./diffvim old.py new.py
```

The `diffvim` (Vimscript) implementation also supports a `g:diffvim`
dictionary in your vimrc for persistent configuration:

```vim
let g:diffvim = {
    \ 'type_delay_ms': 50,
    \ 'delete_delay_ms': 30,
    \ 'move_min_ms': 300,
    \ 'move_max_ms': 2000,
    \ }
```

---

## Requirements

### `diffvim` (Bash + Vimscript)

| Dependency | Version | Notes                                  |
| ---------- | ------- | -------------------------------------- |
| Vim        | 8+      | Must be compiled with `+timers` and `+float` |
| Bash       | 4+      | For the launcher script                |

### `diffvim-tmux` (Bash + tmux)

| Dependency | Version | Notes                                  |
| ---------- | ------- | -------------------------------------- |
| Bash       | 4+      | Associative arrays, `read -ra`         |
| tmux       | 3+      | For pane management and `send-keys`    |
| Vim        | 8+      | Any build (no special features needed) |
| diff       | any     | GNU diff or compatible                 |
| sed        | any     | For char-level diff splitting          |
| awk        | any     | For easing curve computation           |

### `diffvim.pl` (Perl + tmux)

| Dependency       | Version  | Notes                                           |
| ---------------- | -------- | ------------------------------------------------ |
| Perl             | 5.10+    | `//` operator, `use utf8`                       |
| tmux             | 3+       | For pane management                             |
| Vim              | 8+       | Any build                                       |
| diff             | any      | For unified diff generation                     |
| JSON::PP         | any      | Core module since Perl 5.14 (bundled)           |
| Algorithm::Diff  | optional | Speeds up line-level diff if installed          |
| diff2html-cli    | optional | Only for `--parser diff2html` mode              |

---

## Installation

### Option A: Manual (all implementations)

```bash
# Clone or copy the project
cp diffvim /usr/local/bin/              # or ~/.local/bin
cp diffvim-tmux /usr/local/bin/
chmod +x /usr/local/bin/diffvim /usr/local/bin/diffvim-tmux

# For the Perl implementation:
cp diffvim.pl /usr/local/bin/
cp -r DiffVim /usr/local/lib/perl5/     # or set PERL5LIB
```

### Option B: Perl module installation (diffvim.pl only)

```bash
# If packaged as a CPAN module:
perl Makefile.PL
make
make test
make install
```

### Option C: diff2html CLI (for the diff2html parser)

```bash
npm install -g diff2html-cli
# Verify:
diff2html --version
```

### Verify installation

```bash
diffvim --help          # or: diffvim with no args
diffvim-tmux            # prints usage
perl diffvim.pl --help
```

---

## Examples

### Animate a git diff

```bash
# Extract the old version from git
git show HEAD:src/main.py > /tmp/old_main.py

# Animate the transformation
diffvim /tmp/old_main.py src/main.py
```

### Animate two files side by side

```bash
# Create test files
cat > /tmp/old.py <<'EOF'
def greet(name):
    print("Hello, " + name)
    return None
EOF

cat > /tmp/new.py <<'EOF'
def greet(name):
    print(f"Hello, {name}!")
    return None
EOF

# Animate
./diffvim /tmp/old.py /tmp/new.py
```

### Use the diff2html parser

```bash
# Install diff2html CLI first
npm install -g diff2html-cli

# Run with the diff2html parser
perl diffvim.pl --parser diff2html /tmp/old.py /tmp/new.py
```

### Slow down for a presentation

```bash
DIFFVIM_TYPE_DELAY_MS=100 \
DIFFVIM_MOVE_MAX_MS=3000 \
DIFFVIM_HUNK_PAUSE_MS=500 \
./diffvim old.py new.py
```

---

## How It Works

### Diff Computation (two-level LCS)

All implementations use a two-level diff:

1. **Line-level diff** — identifies which lines changed (using LCS
   dynamic programming or `diff -u`)
2. **Hunk grouping** — consecutive changed lines are grouped into a
   single "hunk"
3. **Char-level diff** — within each hunk, the old text and new text
   are compared character-by-character using LCS, producing a sequence
   of `keep` / `delete` / `insert` operations

This means only the **actually-changed characters** are deleted and
re-typed. If a line changes from `print("Hello")` to `print("Hi")`,
only `Hello` is deleted and `Hi` is typed — the `print("` and `")`
parts are left untouched.

### Cursor Glide (ease-in-out cubic)

When moving between change locations, the cursor doesn't jump — it
glides with an ease-in-out cubic curve:

```
position(t) = start + (end - start) * ease(t)

ease(t) = 4t³                          for t < 0.5
        = 1 - ((-2t + 2)³ / 2)        for t ≥ 0.5
```

The glide duration is proportional to the distance (weighted: line
changes count more than column changes), clamped to
`[MOVE_MIN_MS, MOVE_MAX_MS]`.

### User Input (FIFO-based)

In the tmux-based implementations (`diffvim-tmux`, `diffvim.pl`), vim
normal-mode mappings write single-character commands to a named pipe
(FIFO):

```vim
nnoremap <buffer> <silent> <Space> :call writefile(['p'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> n       :call writefile(['n'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> b       :call writefile(['b'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> q       :call writefile(['q'], g:dv_ctrl, 'a')<CR>
```

The orchestrator (bash/perl) reads the FIFO non-blocking between
animation steps, so user input is processed within one tick (~16ms)
of being pressed.

The `diffvim` (Vimscript) implementation uses vim's `timer_start()`
for the animation loop, so user input is handled natively by vim's
normal-mode mappings without a FIFO.

### Snapshots (for the "back" control)

Before each hunk is animated, a snapshot of the buffer is saved (to
vimscript variables in `diffvim`, to temp files in the tmux-based
implementations). Pressing `b` restores the previous snapshot and
replays the hunk from the beginning.

---

## Diff Parsers

The Perl implementation (`diffvim.pl`) supports two interchangeable
parsers:

### `DiffVim::Parser::Perl` (default)

- Pure-Perl LCS diff
- No external dependencies beyond Perl core
- Uses `Algorithm::Diff` if installed (faster C implementation)
- Falls back to a built-in LCS DP algorithm otherwise

### `DiffVim::Parser::Diff2Html`

- Shells out to `diff2html -f json` for line-level parsing
- Computes char-level LCS in Perl (same algorithm as the Perl parser)
- Requires `diff2html-cli` (`npm install -g diff2html-cli`)
- Produces identical output to the Perl parser

Both parsers return the same data structure:

```perl
{
    hunks => [
        {
            target_line   => 2,          # 1-indexed line in old file
            char_ops      => [           # ordered char-level operations
                { op => 'keep',   code => 32 },   # keep space
                { op => 'insert', code => 102 },  # insert 'f'
                { op => 'delete', code => 34 },   # delete '"'
                ...
            ],
            deleted_count  => 1,
            inserted_count => 1,
            is_end_insert  => 0,
            is_end_delete  => 0,
            old_text       => '    print("Hello, " + name)',
            new_text       => '    print(f"Hello, {name}!")',
        },
    ],
    parser => 'perl',   # or 'diff2html'
}
```

---

## Project Structure

```
diffvim-project/
├── README.md                     # This file
├── LICENSE                       # MIT license
├── CHANGELOG.md                  # Version history
├── diffvim                       # Implementation 1: Bash + Vimscript
├── diffvim-tmux                  # Implementation 2: Bash + tmux
├── diffvim.pl                    # Implementation 3: Perl + tmux
├── DiffVim/                      # Perl modules for diffvim.pl
│   └── Parser/
│       ├── Perl.pm               #   Pure-Perl LCS diff parser
│       └── Diff2Html.pm          #   diff2html CLI-based parser
├── IMPROVEMENTS.md               # 100 planned improvements
├── docs/                         # Detailed documentation
│   ├── ARCHITECTURE.md           #   Architecture deep-dive
│   ├── PARSERS.md                #   Parser API reference
│   ├── CONTROLS.md               #   User controls reference
│   ├── CONFIGURATION.md          #   Configuration reference
│   └── TESTING.md                #   Testing guide
└── tests/                        # Test files (if any)
```

---

## Testing

### Parser tests (Perl)

The parser test suite verifies that both parsers produce correct output
for 9 test cases (18 assertions total — each parser is tested for each
case):

```bash
perl tests/test_parsers.pl
```

Expected output:

```
PASS (perl):      simple modification
PASS (diff2html): simple modification
PASS (perl):      multi-hunk python
PASS (diff2html): multi-hunk python
...
Results: 18 passed, 0 failed
```

Test cases cover:

- Simple single-line modifications
- Multi-hunk Python diffs (replace + insert)
- Pure insertion at start of file
- Pure deletion at end of file
- Identical files (no diff)
- Empty old file (pure insertion)
- Insertion at end of file
- Mid-line character insertion
- Deletion of middle lines

### End-to-end tests

End-to-end tests run the full animation in a tmux session and verify
the buffer matches the expected new file. These require tmux and vim to
be installed.

### Running tests manually

```bash
# Test the diffvim (Vimscript) implementation
cp tests/sample_old.py /tmp/old.py
cp tests/sample_new.py /tmp/new.py
./diffvim /tmp/old.py /tmp/new.py
# Watch the animation, then :q to quit

# Test the diffvim-tmux implementation
./diffvim-tmux /tmp/old.py /tmp/new.py

# Test the Perl implementation with both parsers
perl diffvim.pl --parser perl /tmp/old.py /tmp/new.py
perl diffvim.pl --parser diff2html /tmp/old.py /tmp/new.py
```

---

## Known Limitations

1. **Trailing newline changes** — if the only difference between old
   and new is a trailing newline, the diff may not be animated correctly
   (the char-level diff doesn't capture file-level newline differences).

2. **`diffvim-tmux` / `diffvim.pl` race conditions** — when Ex commands
   are sent to vim via `tmux send-keys` faster than vim can process
   them, command text can leak into normal mode and cause unexpected
   behavior. The `diffvim` (Vimscript) implementation doesn't have this
   issue because it uses `timer_start()` instead of `send-keys`. See
   improvement #1 in `IMPROVEMENTS.md`.

3. **Large files** — the LCS dynamic programming table is O(N×M) in
   memory. For very large files (tens of thousands of lines), this can
   consume significant memory. See improvement #70.

4. **Binary files** — binary files are not detected and will produce
   garbage char ops. See improvement #23.

5. **Non-UTF-8 encodings** — files are read as raw bytes. Non-UTF-8
   multi-byte characters may not be handled correctly. See improvement
   #71.

6. **No syntax awareness** — the diff is purely textual. It doesn't
   understand language syntax, so it may split tokens (e.g., delete half
   a string literal and re-type it). See improvement #91.

---

## Roadmap — 100 Improvements

See [`IMPROVEMENTS.md`](IMPROVEMENTS.md) for a detailed list of 100
planned improvements organized into seven categories:

1. Architecture & Communication (1–15)
2. Diff Parser (16–30)
3. Animation & Easing (31–45)
4. User Experience (46–60)
5. Robustness & Error Handling (61–75)
6. Testing & Quality (76–85)
7. Advanced Features (86–100)

Top priorities:

- **#1** — Replace `tmux send-keys` with a file-based command queue
- **#3** — Implement a proper ack/sync protocol
- **#4** — Batch char ops into a single Ex command
- **#16** — Use Myers diff algorithm for better performance
- **#91** — Syntax-aware diffing with Tree-sitter

---

## License

MIT License. See [`LICENSE`](LICENSE) for details.

---

## Acknowledgments

- [diff2html](https://github.com/rtfpessoa/diff2html) by rtfpessoa —
  used by the `Diff2Html` parser for line-level diff parsing
- [Algorithm::Diff](https://metacpan.org/pod/Algorithm::Diff) by
  chromatic — optional speedup for the Perl parser
- The Vim and tmux projects — without which this tool would not be
  possible
