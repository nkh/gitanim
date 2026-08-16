# diffvim — Animate Code Diffs in Vim

Animate a code diff as if a human were typing it. Open the old file in vim,
watch the cursor glide between change locations with smooth ease-in-out
acceleration, and see only the actually-changed characters deleted and
re-typed — surrounding text is never touched.

---

## Table of Contents

- [What It Does](#what-it-does)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Three Implementations](#three-implementations)
- [Controls](#controls)
- [Options](#options)
- [Buffer State After Animation](#buffer-state-after-animation)
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
vim buffer. By default diffvim marks the buffer as *not modified* so that
`:q` quits cleanly — you don't have to type `:q!`. Use `--keep-dirty` if you
want the buffer to remain modified (then `:q!` is required to quit).

---

## Installation

### Homebrew (macOS)

```bash
# From the repo (until published to a tap):
brew install ./packaging/diffvim.rb

# Or once published to a tap:
# brew tap nkh/gitanim
# brew install diffvim
```

This installs all three scripts (`diffvim`, `diffvim-tmux`, `diffvim.pl`),
the Perl modules, the vim plugin, the man page, and shell completions.

### Manual Installation

```bash
# Clone the repo
git clone https://github.com/nkh/gitanim.git
cd gitanim

# Make scripts executable
chmod +x diffvim diffvim-tmux diffvim.pl

# Install scripts to your PATH (choose one):
sudo cp diffvim diffvim-tmux diffvim.pl /usr/local/bin/
# or for current user only:
mkdir -p ~/.local/bin && cp diffvim diffvim-tmux diffvim.pl ~/.local/bin/

# Install Perl modules (for diffvim.pl):
sudo cp -r DiffVim /usr/local/lib/perl5/
# or:
export PERL5LIB="$(pwd):$PERL5LIB"

# Install the man pages:
sudo mkdir -p /usr/local/share/man/man1
sudo cp man/*.1 /usr/local/share/man/man1/
sudo mandb
man diffvim
man diffvim-compute

# Install shell completions (optional):
# Bash:
sudo cp completion/diffvim.bash /etc/bash_completion.d/diffvim
# Zsh:
sudo cp completion/_diffvim /usr/local/share/zsh/site-functions/
# Fish:
cp completion/diffvim.fish ~/.config/fish/completions/

# Install the vim plugin (for :Diffvim command):
cp -r plugin autoload ~/.vim/
```

### Prerequisites

| Dependency | Version | Required by |
|-----------|---------|-------------|
| Vim | 8+ with `+timers` `+float` | All implementations |
| Bash | 4+ | `diffvim`, `diffvim-tmux` |
| Perl | 5.10+ | `diffvim.pl` |
| tmux | 3+ | `diffvim-tmux`, `diffvim.pl` |
| diff | any | All |
| git | any | `--replay`, `--git-rev`, `--git-blame` |

### Verification

```bash
diffvim --version
diffvim-tmux --version
perl diffvim.pl --version
man diffvim
```

---

## Quick Start

```bash
# Simplest usage — bash + vim (no tmux needed)
./diffvim old.py new.py

# Bash + tmux + vim
./diffvim-tmux old.py new.py

# Perl + tmux + vim
perl diffvim.pl old.py new.py
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
| `n` | Skip current hunk (apply instantly, then pause for review) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation — by default `:q` then quits cleanly; use `--keep-dirty` to require `:q!` |
| `+` | Speed up (x1.5) |
| `-` | Slow down (x0.67) |
| `=` | Reset speed to 1.0x |
| `]` | Next file (multi-file mode) |
| `[` | Previous file (multi-file mode) |
| `?` | Show help

A progress bar is shown: `hunk 3/7 (42%) | speed 2.3x | PAUSED`

---

## Options

```
CORE OPTIONS:
  --speed N (-s)           Speed multiplier: 0.5=half, 2=double, 5=5x
  --output FILE (-o)       Write result to FILE after animation, then quit
  --context N (-c)         Fold unchanged regions >2N lines, keep N context
  --max-hunk-chars N       Skip char-by-char for hunks > N changed chars
  --scroll zz|zt|zb|none   Scroll cursor to center/top/bottom/none (default: zz)
  --multi (-m)             Animate multiple old:new file pairs
  --replay (-r)            Animate git history for given file(s)
  --git-rev REV..REV (-R)  Animate a git commit range
  --dry-run (-d)           Print diff ops without launching vim
  --word-diff (-w)         Use word-level diff (groups changes by word)
  --step-mode              Space advances one char op at a time
  --max-line-len N         Warn threshold for long lines (default: 10000)
  --sign-column            Show +/- signs in vim's sign column
  --git-blame (-g)         Show git blame for changed lines
  --keep-dirty             Leave buffer modified; require :q! to quit
  --no-vimrc (-N)          Don't load user's ~/.vimrc (isolated vim)
  --precomputed FILE       Use pre-computed diff from FILE
  --tool c|cpp|rust|go     Use external compute tool (10-100x faster for large files)
  --preset NAME (-p)       Apply named preset (fast-delete, review, demo, ai-code)
  --theme dark|light|high-contrast (-t)  Color scheme for highlights
  --version, -V            Print version
  --help, -h               Show help

DIFF ALGORITHM:
  --algorithm lcs|myers|patience (-a)  Line-level diff algorithm (default: lcs)
  --semantic-cleanup (-S)  Merge adjacent delete+insert pairs that cancel out
  --indent-aware (-i)      Normalize indentation before line diff
  --word-diff (-w)         Use word-level diff (groups changes by word tokens)

OP ORDER (post-processing):
  --op-order MODE          Op reordering: natural|optimize|left-to-right|
                           end-first|end-first-smart|overwrite (default: optimize)

DELETION PACING:
  --delete-pacing MODE     Deletion strategy: char|rapid-eol|rapid-identical|
                           accel|word|instant (default: word)
                           'word' does char→word→rapid progression with acceleration
  --delete-speed MODE      Deletion speed: slow|normal|fast|instant (default: normal)
  --delete-threshold N     Min chars to trigger rapid/word modes (default: 3)

INSERTION PACING:
  --insert-pacing MODE     Insertion strategy: char|word|accel (default: char)
  --insert-speed MODE      Insertion speed: slow|normal|fast (default: normal)

TIMING:
  --pacing MODE            Timing mode: uniform|adaptive|gaussian|review
                           (default: uniform)

HIGHLIGHTING:
  --highlight MODE         Highlight mode: none|inline|word|hunk (default: none)
  --highlight-color COLOR  Highlight group (default: DiffChange)
  --highlight-duration-ms N  Highlight duration in ms (default: 1000)
  --dim-unchanged (-D)     Dim unchanged anchor lines to draw eye to changes
  --dim-unchanged-pct N    Dimming percentage 0-100 (default: 60)
```

### Buffer State After Animation

By default, after the animation finishes (or you press `q` to stop it),
diffvim runs `:set nomodified` on the buffer. This means `:q` quits vim
without complaint — no need to type `:q!`.

If you want the buffer to stay modified (so vim's `:q` will refuse and
`:q!` will be required), pass `--keep-dirty`:

```bash
# Default: :q quits cleanly
./diffvim old.py new.py

# Keep buffer modified: :q! required to quit
./diffvim --keep-dirty old.py new.py
```

The startup config echo shows which mode is active:
`keep_dirty=off(:q)` or `keep_dirty=on(:q!)`.

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
| `DIFFVIM_TYPE_DELAY_MS` | `50` | Delay between typed characters (ms) |
| `DIFFVIM_DELETE_DELAY_MS` | `40` | Delay between deleted characters (ms) |
| `DIFFVIM_MOVE_MIN_MS` | `250` | Minimum cursor-glide duration (ms) |
| `DIFFVIM_MOVE_MAX_MS` | `1600` | Maximum cursor-glide duration (ms) |
| `DIFFVIM_MOVE_MS_PER_UNIT` | `6` | Milliseconds per unit of glide distance |
| `DIFFVIM_HUNK_PAUSE_MS` | `250` | Pause between hunks (ms) |
| `DIFFVIM_WORD_PAUSE_MS` | `150` | Pause after instant word (ms) |
| `DIFFVIM_RAPID_EOL_DELAY_MS` | `80` | Delay for rapid end-of-line deletion (ms) |
| `DIFFVIM_RAPID_EOL_MIN_CHARS` | `3` | Min trailing chars to trigger rapid EOL |
| `DIFFVIM_HIGHLIGHT_WORD_COLOR` | `Search` | Highlight group for `--highlight-word` |
| `DIFFVIM_HIGHLIGHT_WORD_DURATION_MS` | `300` | Word highlight duration in ms |
| `DIFFVIM_HIGHLIGHT_WORD_MIN_CHARS` | `2` | Min word length to highlight |
| `DIFFVIM_SPEED` | `1.0` | Speed multiplier (same as --speed) |
| `DIFFVIM_MAX_LINE_LEN` | `10000` | Warn threshold for long lines |
| `DIFFVIM_KEEP_DIRTY` | unset | Set to `1` to leave buffer modified (`:q!` required) |

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

# Keep buffer modified so :q! is required to quit
./diffvim --keep-dirty old.py new.py

# Use external Rust compute tool for large files (10-100x faster)
./diffvim --tool rust old.py new.py

# Word-by-word deletion with acceleration (default)
./diffvim --delete-pacing word old.py new.py

# Instant deletion for fastest review
./diffvim --delete-pacing instant --delete-speed fast old.py new.py

# Highlight the word at cursor before each change
./diffvim --highlight word old.py new.py

# Highlight the entire hunk before animating
./diffvim --highlight hunk old.py new.py
```

---

## Git Integration

### Replay git history

```bash
# Last 5 commits of a file
./diffvim --replay src/main.py

# Specific commit range using --git-rev syntax
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

# Authoritative vim correctness test (39 assertions)
perl tests/test_vim_correctness.pl

# Rapid end-of-line delete correctness (20 assertions)
perl tests/test_rapid_eol.pl
```

---

## Project Structure

```
gitanim/
├── diffvim                       # Bash + Vimscript (no tmux needed)
├── diffvim-tmux                  # Bash + tmux
├── diffvim.pl                    # Perl + tmux (pluggable parsers)
├── diffvim-compare               # Diff algorithm benchmark matrix
├── diffvim-jogger                # Test-case exerciser (25+ option combos)
├── jq_filter                     # difft JSON → HUNK/DEL/ADD/CTX text
├── difft_json_to_lcs             # HUNK/DEL/ADD/CTX → LCS string
├── set_config                    # Source-able timing env var defaults
├── DiffVim/
│   └── Parser/
│       └── Perl.pm               # Pure-Perl LCS diff parser
├── plugin/
│   └── diffvim.vim              # :Diffvim command for plugin mode
├── autoload/
│   └── diffvim/
│       └── engine.vim           # Standalone engine (sourced by plugin)
├── completion/
│   ├── diffvim.bash             # Bash completion
│   ├── _diffvim                 # Zsh completion
│   └── diffvim.fish             # Fish completion
├── compute/                     # External diff compute tools (4 langs)
│   ├── c/diffvim-compute.c      # C reference (1.4MB binary)
│   ├── cpp/diffvim-compute.cpp  # C++17 port
│   ├── rust/diffvim-compute.rs  # Rust port
│   ├── go/diffvim-compute.go    # Go port
│   └── Makefile                 # `make c|cpp|rust|go` or `make` (all)
├── man/                         # Manpages for every executable
│   ├── diffvim.1
│   ├── diffvim-tmux.1
│   ├── diffvim-compare.1
│   ├── diffvim-jogger.1
│   └── diffvim-compute.1
├── tests/                       # 378+ test assertions across 20+ files
├── docs/
│   ├── src/                     # mdBook documentation (15+ pages)
│   ├── presentation.html        # One-page HTML overview
│   ├── VISUAL_GUIDE.md          # Graphical ASCII-art walkthrough (NEW)
│   ├── ADOPTION_GUIDE.md        # Onboarding guide for teams (NEW)
│   ├── ARCHITECTURE.md          # Architecture deep-dive with diagrams
│   ├── POST_PROCESSING.md       # Post-processing pipeline reference
│   ├── AI_CODE_DIFFING.md       # 100 ideas for AI-generated code
│   ├── FOLLOW_IMPROVEMENTS.md   # 50 UX followability improvements
│   ├── OPTION_COMBINATIONS.md   # 100+ option combination examples
│   ├── USER_REQUESTS.md         # Complete feature-request log
│   └── ...                      # 16 docs in total
├── examples/                    # 42 example file pairs in 15+ languages
├── README.md
├── CHANGELOG.md
├── LICENSE                      # Artistic 2.0 / GPL 3.0 (dual)
└── IMPROVEMENTS.md              # 100 improvements (52 implemented)
```

### Where to Start Reading

| If you want to...                 | Read this                                              |
| --------------------------------- | ------------------------------------------------------ |
| Understand what diffvim does      | [`docs/VISUAL_GUIDE.md`](docs/VISUAL_GUIDE.md)        |
| Bring diffvim to your team        | [`docs/ADOPTION_GUIDE.md`](docs/ADOPTION_GUIDE.md)    |
| See the one-page HTML overview    | [`docs/presentation.html`](docs/presentation.html)    |
| Read the structured docs          | [`docs/src/SUMMARY.md`](docs/src/SUMMARY.md)          |
| Read a manpage                    | [`man/diffvim.1`](man/diffvim.1)                       |
| See every option combination      | [`docs/OPTION_COMBINATIONS.md`](docs/OPTION_COMBINATIONS.md) |

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

Dual-licensed under the Artistic License 2.0 and the GNU General Public
License v3.0. You may use this software under either license, at your
option. See [`LICENSE`](LICENSE) for details.
