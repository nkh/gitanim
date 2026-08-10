# diffvim — Animate Code Diffs in Vim

Animate a code diff as if a human were typing it. Open the old file in vim,
watch the cursor glide between change locations with smooth ease-in-out
acceleration, and see only the actually-changed characters deleted and
re-typed — surrounding text is never touched.

---

## Table of Contents

- [What It Does](#what-it-does)
- [Quick Start](#quick-start)
- [Three Implementations](#three-implementations)
- [Controls](#controls)
- [Options](#options)
- [Configuration](#configuration)
- [Examples](#examples)
- [Plugin Mode](#plugin-mode)
- [Git Replay](#git-replay)
- [Testing](#testing)
- [Project Structure](#project-structure)
- [Known Limitations](#known-limitations)
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
5. **User control** — at any moment the user can pause, skip, go back,
   change speed, or quit; the animation responds immediately

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

---

## Three Implementations

| Feature | `diffvim` | `diffvim-tmux` | `diffvim.pl` |
|---------|-----------|----------------|--------------|
| Language | Bash + Vimscript | Bash | Perl |
| Vim communication | Native (timer) | tmux send-keys | tmux send-keys |
| Race conditions | No | Yes | Yes |
| Parser pluggability | No | No | Yes (2 parsers) |
| Dependencies | Vim only | tmux, diff, sed, awk | tmux, diff |
| Best for | Quick use, no deps | Bash scripting | Parser research |

---

## Controls

During animation (in vim normal mode):

| Key       | Action                                      |
| --------- | ------------------------------------------- |
| `Space`   | Pause / resume the animation                |
| `n`       | Skip current hunk (apply instantly)         |
| `b`       | Back to previous hunk (revert and restart)  |
| `q`       | Stop animation (leave buffer for editing)   |
| `+`       | Speed up (x1.5)                             |
| `-`       | Slow down (x0.67)                           |
| `=`       | Reset speed to 1.0x                         |
| `?`       | Show help *(diffvim only)*                  |

A progress bar is shown in the status line: `hunk 3/7 (42%)`

---

## Options

All three implementations support these options:

```
--speed N                Speed multiplier: 0.5=half, 2=double, 5=5x
--output FILE            Write result to FILE after animation, then quit
--context N              Fold unchanged regions >2N lines, keep N context
--max-hunk-chars N       Skip char-by-char for hunks > N changed chars
--max-word-chars N       Type words <= N chars instantly, pause after
--word-pause-ms N        Pause after instant word (default: 150)
--scroll zz|zt|zb|none   Scroll cursor to center/top/bottom/none
--multi                  Animate multiple old:new file pairs
--replay                 Animate git history for given file(s)
--from REV               Git rev to start replay from (default: HEAD~5)
--to REV                 Git rev to end replay at (default: HEAD)
--help, -h               Show help
```

`diffvim.pl` also supports:
```
--parser perl|diff2html  Diff parser (default: perl)
```

---

## Configuration

Timing can be tuned via environment variables:

| Variable                    | Default | Description                              |
| --------------------------- | ------- | ---------------------------------------- |
| `DIFFVIM_TICK_MS`           | `16`    | Animation frame interval (~60fps)        |
| `DIFFVIM_TYPE_DELAY_MS`     | `35`    | Delay between typed characters (ms)      |
| `DIFFVIM_DELETE_DELAY_MS`   | `25`    | Delay between deleted characters (ms)    |
| `DIFFVIM_MOVE_MIN_MS`       | `200`   | Minimum cursor-glide duration (ms)       |
| `DIFFVIM_MOVE_MAX_MS`       | `1400`  | Maximum cursor-glide duration (ms)       |
| `DIFFVIM_MOVE_MS_PER_UNIT`  | `6`     | Milliseconds per unit of glide distance  |
| `DIFFVIM_HUNK_PAUSE_MS`     | `180`   | Pause between hunks (ms)                 |
| `DIFFVIM_WORD_PAUSE_MS`     | `150`   | Pause after instant word (ms)            |
| `DIFFVIM_SPEED`             | `1.0`   | Speed multiplier (same as --speed)       |

Example — slow down for a presentation:

```bash
DIFFVIM_TYPE_DELAY_MS=100 \
DIFFVIM_MOVE_MAX_MS=3000 \
./diffvim old.py new.py
```

Or use `--speed`:

```bash
./diffvim --speed 0.5 old.py new.py    # half speed
./diffvim --speed 3 old.py new.py      # 3x speed
```

---

## Examples

### Basic animation

```bash
./diffvim old.py new.py
```

### Slow down for a presentation

```bash
./diffvim --speed 0.5 old.py new.py
```

### Center cursor during animation

```bash
./diffvim --scroll zz old.py new.py
```

### Skip large hunks, type short words instantly

```bash
./diffvim --max-hunk-chars 200 --max-word-chars 5 old.py new.py
```

### Write result to a file and quit

```bash
./diffvim --output result.py old.py new.py
```

### Multi-file animation

```bash
./diffvim --multi old1.py:new1.py old2.py:new2.py
```

### Replay git history

```bash
# Last 5 commits of src/main.py
./diffvim --replay src/main.py

# Specific commit range
./diffvim --replay src/main.py --from v1.0 --to HEAD

# Multiple files
./diffvim --replay src/main.py src/utils.py
```

### Animate a git diff

```bash
git show HEAD:file.py > /tmp/old.py
./diffvim /tmp/old.py file.py
```

### Use the diff2html parser

```bash
perl diffvim.pl --parser diff2html old.py new.py
```

---

## Plugin Mode

Run diffvim inside an existing vim session via the `:Diffvim` command:

```vim
" In vim:
:Diffvim old.py new.py
:Diffvim old.py new.py tabnew    " open in a new tab
:Diffvim old.py new.py vsplit    " open in a vertical split
```

Install the plugin by copying `plugin/diffvim.vim` to `~/.vim/plugin/` or
adding to your package manager:

```vim
" vim-plug
Plug 'nkh/gitanim', {'rtp': 'plugin/'}
```

---

## Git Replay

The `--replay` flag animates a file's git history. For each commit in the
range, it extracts the old version and animates the transformation to the
next commit, ending with the working copy.

```bash
# Animate last 5 commits of a file
./diffvim --replay src/main.py

# Animate a specific range
./diffvim --replay src/main.py --from v1.0 --to HEAD

# Multiple files
./diffvim --replay src/main.py src/utils.py
```

The animation transitions between commits with a brief message showing the
commit hash and file name.

---

## Testing

### Parser tests

```bash
perl tests/test_parsers.pl
```

Tests both parsers (Perl and diff2html) with 9 test cases each (18 total).

### Feature tests

```bash
perl tests/test_features.pl
```

Tests all new features: --speed, --output, --max-hunk-chars, --max-word-chars,
--scroll, --multi, --replay, --help, plugin, man page (52 assertions).

### Manual testing

```bash
# Quick test
echo 'hello' > /tmp/old.txt
echo 'hello there' > /tmp/new.txt
./diffvim /tmp/old.txt /tmp/new.txt
```

---

## Project Structure

```
gitanim/
├── diffvim                       # Bash + Vimscript (no tmux needed)
├── diffvim-tmux                  # Bash + tmux
├── diffvim.pl                    # Perl + tmux (pluggable parsers)
├── diffvim.1                     # Man page
├── DiffVim/
│   └── Parser/
│       ├── Perl.pm               # Pure-Perl LCS diff parser
│       └── Diff2Html.pm          # diff2html CLI-based parser
├── plugin/
│   └── diffvim.vim              # :Diffvim command for plugin mode
├── tests/
│   ├── test_parsers.pl           # Parser tests (18 assertions)
│   ├── test_features.pl          # Feature tests (52 assertions)
│   └── test_e2e_perl.pl          # End-to-end tests
├── docs/                         # Detailed documentation
│   ├── ARCHITECTURE.md
│   ├── CONTROLS.md
│   ├── CONFIGURATION.md
│   ├── PARSERS.md
│   └── TESTING.md
├── examples/
│   ├── old.py                    # Sample old file
│   └── new.py                    # Sample new file
├── README.md
├── CHANGELOG.md
├── LICENSE
└── IMPROVEMENTS.md               # 100 planned improvements
```

---

## Known Limitations

1. **Trailing newline changes** — if the only difference is a trailing
   newline, the animation may not handle it correctly.

2. **`diffvim-tmux` / `diffvim.pl` race conditions** — when Ex commands
   are sent to vim via `tmux send-keys` faster than vim processes them,
   command text can leak into normal mode. The `diffvim` implementation
   doesn't have this issue.

3. **Large files** — the LCS DP table is O(N×M) in memory. For very
   large files (>10,000 lines), use `--max-hunk-chars` to skip large
   hunks.

4. **Binary files** — not detected; will produce garbage char ops.

5. **Non-UTF-8 encodings** — files are read as raw bytes.

---

## License

MIT License. See [`LICENSE`](LICENSE) for details.
