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
- [Plugin Mode](#plugin-mode)
- [Configuration](#configuration)
- [Examples](#examples)
- [Git Integration](#git-integration)
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
   change speed, undo/redo, or quit

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

### Plugin Mode (inside existing vim)

```vim
:Diffvim old.py new.py
:Diffvim old.py new.py tabnew
```

---

## Three Implementations

| Feature | `diffvim` | `diffvim-tmux` | `diffvim.pl` |
|---------|-----------|----------------|--------------|
| Language | Bash + Vimscript | Bash | Perl |
| Vim communication | Native (timer) | tmux send-keys | tmux send-keys |
| Race conditions | No | Yes | Yes |
| Parser pluggability | No | No | Yes (2 parsers) |
| Dependencies | Vim only | tmux, diff, sed, awk | Perl, tmux, diff |
| Best for | Quick use, no deps | Bash scripting | Parser research |

---

## Controls

During animation (in vim normal mode):

| Key | Action |
|-----|--------|
| `Space` | Pause / resume (or advance one op in `--step-mode`) |
| `n` | Skip current hunk (apply instantly) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation (leave buffer for editing) |
| `+` | Speed up (x1.5) |
| `-` | Slow down (x0.67) |
| `=` | Reset speed to 1.0x |
| `u` | Undo last hunk |
| `Ctrl-r` | Redo hunk |
| `B` | Go back one char op |
| `N` | Skip to next file (multi-file mode) |
| `Ctrl-B` | Go back to beginning |
| `Ctrl-N` | Skip to end |
| `?` | Toggle full-screen help overlay |

A progress bar is shown: `hunk 3/7 (42%) | speed 2.3x | PAUSED`

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
--git-rev REV..REV       Animate a git commit range
--no-tmux                Run vim directly in terminal (no tmux)
--dry-run                Print diff ops without launching vim
--sign-column            Show +/- signs in vim's sign column
--git-blame              Show git blame for changed lines
--step-mode              Space advances one char op at a time
--max-line-len N         Warn threshold for long lines (default: 10000)
--adaptive-timing        Auto-slow for complex hunks, speed up for simple
--word-diff              Use word-level diff (groups changes by word)
--version, -V            Print version and dependency info
--help, -h               Show help
```

`diffvim.pl` also supports `--parser perl|diff2html`.

---

## Plugin Mode

Run diffvim inside an existing vim session via the `:Diffvim` command:

```vim
:Diffvim old.py new.py
:Diffvim old.py new.py tabnew      " open in a new tab
:Diffvim old.py new.py vsplit      " open in a vertical split
```

Install the plugin by copying `plugin/` and `autoload/` to your vim runtimepath:

```bash
cp -r plugin autoload ~/.vim/
```

Or with vim-plug:
```vim
Plug 'nkh/gitanim', {'rtp': '.'}
```

The plugin uses vim's native `timer_start()` — no tmux or external process needed.

---

## Configuration

Timing can be tuned via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `DIFFVIM_TICK_MS` | `16` | Animation frame interval (~60fps) |
| `DIFFVIM_TYPE_DELAY_MS` | `35` | Delay between typed characters (ms) |
| `DIFFVIM_DELETE_DELAY_MS` | `25` | Delay between deleted characters (ms) |
| `DIFFVIM_MOVE_MIN_MS` | `200` | Minimum cursor-glide duration (ms) |
| `DIFFVIM_MOVE_MAX_MS` | `1400` | Maximum cursor-glide duration (ms) |
| `DIFFVIM_MOVE_MS_PER_UNIT` | `6` | Milliseconds per unit of glide distance |
| `DIFFVIM_HUNK_PAUSE_MS` | `180` | Pause between hunks (ms) |
| `DIFFVIM_WORD_PAUSE_MS` | `150` | Pause after instant word (ms) |
| `DIFFVIM_SPEED` | `1.0` | Speed multiplier (same as --speed) |
| `DIFFVIM_MAX_LINE_LEN` | `10000` | Warn threshold for long lines |

See [docs/src/configuration.md](docs/src/configuration.md) for presets.

---

## Examples

The repo includes example file pairs in `examples/`:

```bash
# Small Python (f-string conversion)
./diffvim examples/01_small_python/old.py examples/01_small_python/new.py

# Large Python (class refactoring, 76→123 lines)
./diffvim examples/02_large_python/old.py examples/02_large_python/new.py

# JSON config, shell script, Go code, TypeScript, text prose
ls examples/
```

### Common usage

```bash
# Slow down for a presentation
./diffvim --speed 0.5 --scroll zz old.py new.py

# Type short words instantly
./diffvim --max-word-chars 5 old.py new.py

# Write result to file and quit
./diffvim --output result.py old.py new.py

# Dry run (print diff without launching vim)
perl diffvim.pl --dry-run old.py new.py

# Multi-file animation
./diffvim --multi old1.py:new1.py old2.py:new2.py
```

---

## Git Integration

### Replay git history

```bash
# Last 5 commits of a file
./diffvim --replay src/main.py

# Specific commit range
./diffvim --replay src/main.py --from v1.0 --to HEAD

# Using --git-rev syntax
./diffvim --git-rev HEAD~3..HEAD src/main.py

# Multiple files
./diffvim --replay src/main.py src/utils.py
```

### Git blame

```bash
./diffvim --git-blame old.py new.py
```

---

## Testing

```bash
# Parser tests (18 assertions)
perl tests/test_parsers.pl

# Feature tests (52 assertions)
perl tests/test_features.pl

# Integration tests (62 assertions)
perl tests/test_integration.pl
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
├── autoload/
│   └── diffvim/
│       └── engine.vim           # Standalone engine (sourced by plugin)
├── completion/
│   ├── diffvim.bash             # Bash completion
│   ├── _diffvim                 # Zsh completion
│   └── diffvim.fish             # Fish completion
├── tests/
│   ├── test_parsers.pl           # Parser tests (18 assertions)
│   ├── test_features.pl          # Feature tests (52 assertions)
│   ├── test_integration.pl       # Integration tests (62 assertions)
│   └── test_e2e_perl.pl          # End-to-end tmux tests
├── docs/
│   └── src/                      # mdbook documentation
├── examples/                     # 7 example file pairs
├── README.md
├── CHANGELOG.md
├── LICENSE
└── IMPROVEMENTS.md               # 100 improvements (39 implemented)
```

---

## Known Limitations

1. **Trailing newline changes** — may not animate correctly
2. **`diffvim-tmux` / `diffvim.pl` race conditions** — Ex command text can
   leak into normal mode (use `diffvim` to avoid this)
3. **Large files** — LCS DP table is O(N×M) memory; use `--max-hunk-chars`
4. **Binary files** — detected and refused (not animated)
5. **Non-UTF-8 encodings** — files are read as raw bytes

---

## License

MIT License. See [`LICENSE`](LICENSE) for details.
