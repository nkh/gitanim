# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] — 2026-08-10

### Added — 11 new features

#### #13 `:Diffvim` plugin command
- Created `plugin/diffvim.vim` that defines a `:Diffvim` command for
  running the animation inside an existing vim session (no tmux needed).
- Usage: `:Diffvim oldfile newfile` or `:Diffvim oldfile newfile tabnew`
- The plugin reads config from `g:diffvim` in vimrc.

#### #37 `--scroll zz|zt|zb|none` cursor positioning
- During animation, the cursor can be kept centered (`zz`), at top (`zt`),
  at bottom (`zb`), or left to default behavior (`none`).
- Implemented in the vimscript engine's `s:DvPlace()` function.
- Available in all three implementations.

#### #38 `+`/`-`/`=` variable speed keys
- During animation, press `+` to speed up (x1.5), `-` to slow down (x0.67),
  `=` to reset to 1.0x.
- Runtime speed adjustment is applied to all timing values (tick, type,
  delete, move, hunk pause).
- Speed is shown in the progress message: `hunk 3/7 (42%) | speed 2.3x`

#### #39 Progress bar in status line
- The animation shows `hunk N/M (X%)` in the vim message line.
- Updated after each hunk, skip, back, and pause toggle.
- Also shows PAUSED indicator and speed multiplier when applicable.

#### #43 `--speed N` flag
- Speed multiplier: 0.5 = half speed, 2 = double speed, 5 = 5x speed.
- All timing delays are divided by the multiplier at startup.
- Can also be set via `DIFFVIM_SPEED` environment variable.
- Available in all three implementations.

#### #50 `--output FILE` flag
- After the animation completes, write the buffer to FILE and quit vim.
- Also works with `q` (quit) — the buffer is written before stopping.
- Useful for scripted use where the result should be saved without
  manual intervention.

#### #54 Multi-file animation (`--multi`)
- Animate diffs across multiple files: `--multi old1:new1 old2:new2 ...`
- Between files, shows a "next file" message.
- State (hunk index, cursor, line offset) is reset between file pairs.

#### #55 `--context N` flag
- Fold unchanged regions longer than 2*N lines, keeping N lines of context
  around each hunk.
- Makes large-file diffs easier to follow by hiding unchanged regions.
- Default: 0 (no folding).

#### #60-1 `--max-hunk-chars N` limit
- If a hunk has more than N changed characters, skip the char-by-char
  animation and apply the entire hunk instantly.
- Useful for large changes that would take too long to animate.
- Shows a message: "hunk 3 has 250 changed chars (> 200), applying instantly"

#### #60 `--max-word-chars N` word batching
- If a contiguous sequence of changed characters forms a word (non-space
  chars terminated by a space/newline) and the word length <= N, type the
  entire word instantly, then pause.
- Makes the animation feel more natural — short words are typed as units.
- Pause duration configurable via `--word-pause-ms` (default: 150ms).
- Available in all three implementations.

#### #86 Comprehensive man page
- Created `diffvim.1` in roff/man format.
- Documents all flags, env vars, controls, and architecture with examples.
- Install: `cp diffvim.1 /usr/local/share/man/man1/ && man diffvim`

#### #98 `--replay` from git history
- Animate a file's git history: `--replay FILE [--from REV] [--to REV]`
- For each commit in the range, extracts the old version and animates the
  transformation to the next commit, ending with the working copy.
- Multiple files: `--replay FILE1 FILE2`
- Default range: HEAD~5..HEAD
- Available in all three implementations (diffvim-tmux and diffvim.pl
  support `--from`/`--to` flags; diffvim uses env vars for the range).

### Changed
- All three scripts now share the same CLI option syntax (`--speed`,
  `--output`, `--scroll`, etc.).
- The `diffvim` bash launcher now parses options with a while-loop instead
  of simple positional `$1`/`$2`.
- The vimscript engine reads new env vars: `DIFFVIM_SCROLL`,
  `DIFFVIM_MAX_HUNK_CHARS`, `DIFFVIM_MAX_WORD_CHARS`, `DIFFVIM_OUTPUT`,
  `DIFFVIM_CONTEXT`.
- Updated README with comprehensive documentation of all new features.

### Fixed
- Removed broken `Algorithm::Diff` integration that caused "Argument isn't
  numeric" warnings (in v1.0.1).
- Fixed `diffvim-tmux` error messages going to stderr only (now go to
  stdout with install hints).
- Fixed `diffvim` bash launcher typo where `DIFFVIM_HUNK_PAUSE_MS` export
  was glued to `OLD=` assignment.

### Tests
- Added `tests/test_features.pl` with 52 assertions covering all new features.
- All 18 parser tests still pass.
- Test coverage: CLI option parsing, help output, feature flags, plugin
  file, man page content.

---

## [1.0.1] — 2026-08-09

### Fixed
- Removed broken `Algorithm::Diff` integration in `DiffVim/Parser/Perl.pm`
  that caused "Argument isn't numeric in array or hash lookup" warnings.
- Improved `diffvim-tmux` error messages (now go to stdout with install hints).
- Made `diffvim.pl` and `diffvim-tmux` executable.

---

## [1.0.0] — 2026-08-09

### Added
- Three implementations: `diffvim` (Bash+Vimscript), `diffvim-tmux` (Bash+tmux),
  `diffvim.pl` (Perl+tmux).
- Two diff parsers: `DiffVim::Parser::Perl` (pure-Perl LCS) and
  `DiffVim::Parser::Diff2Html` (diff2html CLI).
- Ease-in-out cubic cursor glide.
- Char-level LCS diff (only changed characters are touched).
- User controls: Space (pause), n (skip), b (back), q (quit).
- Snapshot-based "back" control.
- 7 environment variables for timing control.
- Comprehensive documentation: README, ARCHITECTURE, PARSERS, CONTROLS,
  CONFIGURATION, TESTING.
- 18 parser tests (9 cases × 2 parsers).
- 100 planned improvements documented in IMPROVEMENTS.md.
