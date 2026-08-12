# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.4.1] — 2026-08-12

### Added — `--highlight-word` option

#### `--highlight-word`
Highlight the word at the cursor position before each delete or insert op
is applied. Finer-grained than `--highlight-hunk`: instead of highlighting
the whole hunk region (a line range), `--highlight-word` highlights just
the token (maximal run of non-whitespace chars) that is about to change.

- `--highlight-word` — enable word-level highlighting
- `--highlight-word-color COLOR` (default: `Search`) — vim highlight group
- `--highlight-word-duration-ms N` (default: 300) — how long the highlight
  stays visible
- `--highlight-word-min-chars N` (default: 2) — minimum word length to
  trigger highlighting

The engine uses `s:LookaheadSameTypeRun()` to count the upcoming contiguous
delete/insert ops, then `s:HighlightCurrentWord()` finds the maximal
non-whitespace run containing the cursor and applies `matchaddpos()` with
the configured color. The highlight auto-clears after the duration via a
timer.

Useful for following the animation on long lines where the eye needs help
locking onto the exact word being modified.

### Tests
- Added `tests/test_highlight_word.pl` — 20 assertions verifying that both
  `--highlight-word=on` and `--highlight-word=off` produce identical,
  correct output across 10 test cases (word replaces, trailing deletes,
  pure insertions, multi-word lines, etc.).
- All 469 assertions across 14 test suites pass.

---

## [1.4.0] — 2026-08-12

### Added — 4 new features

#### `--rapid-eol-delete` (default on)
When the cursor is at the end of the line and all the text after the cursor
is being deleted, apply those deletes in one rapid shot rather than one char
at a time. Trailing-line deletions now feel snappy instead of laborious.

- `--rapid-eol-delete` (default on)
- `--no-rapid-eol-delete` to disable
- `--rapid-eol-delay-ms N` (default 80) — single delay after the rapid run
- `--rapid-eol-min-chars N` (default 3) — minimum trailing chars to trigger

Logic: the engine looks ahead from a `delete` op. If the run extends to
end of line (next op is `keep \n`, or end of ops, or cursor is already
past end of line) and the run length is ≥ min_chars, all the deletes are
applied in a single batch followed by the rapid delay.

#### `--keep-dirty` (default off)
By default, after the animation completes (or the user presses `q`),
diffvim runs `:set nomodified` on the buffer so that `:q` quits cleanly
— no more need to type `:q!` every time. With `--keep-dirty`, the buffer
stays modified and `:q!` is required (useful when you want vim's normal
"unsaved changes" protection to remain active).

Also settable via `DIFFVIM_KEEP_DIRTY=1` environment variable.

#### Review mode for `n` key
`n` (SkipCurrent) now applies the next hunk and **pauses** for review,
instead of applying all remaining hunks and continuing. Press `n` again
for the next hunk, or `Space` to resume full-speed animation. This makes
it easy to step through a diff one hunk at a time.

#### `docs/FOLLOW_IMPROVEMENTS.md` — 50 UX improvements
A new document listing 50 concrete UX improvements that would help viewers
follow what's happening during patching. Organized into 5 categories:
visual cues, information display, timing & pacing, navigation & control,
and diff presentation. Each item is framed from the viewer's perspective.

### Changed
- Updated default timing values across all docs to match the implementation:
  `type_delay_ms=50`, `delete_delay_ms=40`, `move_min_ms=250`,
  `move_max_ms=1600`, `hunk_pause_ms=250`.
- `ShowConfig()` now also prints the rapid_eol and keep_dirty state.
- Startup echo shows which quit mode is active: `keep_dirty=off(:q)` or
  `keep_dirty=on(:q!)`.

### Fixed
- Documentation drift: README, man page, docs/src/options.md,
  docs/CONFIGURATION.md, and docs/CONTROLS.md all had stale defaults
  (e.g., `type_delay_ms=35` instead of `50`). All updated to match the
  actual implementation.
- README now lists 32 example pairs (was 7) and points to the new
  `FOLLOW_IMPROVEMENTS.md` document.

### Tests
- Added `tests/test_rapid_eol.pl` — 20 assertions verifying that both
  `--rapid-eol-delete=on` and `--rapid-eol-delete=off` produce identical,
  correct output across 10 test cases (trailing deletes, mid-line deletes,
  multi-line deletes, pure insertions, identical files, etc.).
- All 39 assertions in `tests/test_vim_correctness.pl` still pass.

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
