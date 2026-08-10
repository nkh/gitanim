# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- File-based command queue to eliminate tmux send-keys race conditions (#1)
- Myers diff algorithm for better performance on large files (#16)
- Syntax-aware diffing with Tree-sitter (#91)
- Neovim backend support (#7)

---

## [1.0.0] — 2026-08-09

### Added

#### Three implementations
- **`diffvim`** — Bash launcher + embedded Vimscript engine. Uses vim's
  `timer_start()` for async animation. No external dependencies beyond
  vim 8+. No race conditions.
- **`diffvim-tmux`** — Bash orchestrator + vim in a tmux pane. Bash
  sends Ex commands via `tmux send-keys`; vim sends user input via a
  FIFO. Requires bash 4+, tmux 3+, vim 8+.
- **`diffvim.pl`** — Perl orchestrator + vim in a tmux pane. Same
  architecture as `diffvim-tmux` but with pluggable parser modules.
  Requires Perl 5.10+, tmux 3+, vim 8+.

#### Two diff parsers (for `diffvim.pl`)
- **`DiffVim::Parser::Perl`** — Pure-Perl LCS diff (line + char level).
  Uses `Algorithm::Diff` if available, falls back to built-in LCS DP.
- **`DiffVim::Parser::Diff2Html`** — Shells out to `diff2html -f json`
  for line-level parsing, then computes char-level LCS in Perl.
  Requires `diff2html-cli` (`npm install -g diff2html-cli`).

#### Animation features
- Two-level LCS diff: line-level to identify hunks, char-level within
  each hunk so only changed characters are touched (no whole-line
  rewrites)
- Ease-in-out cubic cursor glide between change locations
- Distance-weighted glide duration (clamped to min/max)
- Character-by-character typing and deletion with configurable delays
- Snapshot-based "back" control (revert to previous hunk state)

#### User controls
- `Space` — pause / resume animation
- `n` — skip current hunk (apply instantly)
- `b` — back to previous hunk (revert and restart)
- `q` — stop animation (leave buffer for editing)
- `?` — show help (diffvim only)

#### Configuration
- 7 environment variables for timing control
  (`DIFFVIM_TICK_MS`, `DIFFVIM_TYPE_DELAY_MS`, etc.)
- Vimrc `g:diffvim` dictionary for persistent config (diffvim only)
- `--parser perl|diff2html` flag (diffvim.pl only)

#### Edge case handling
- Pure insertion at start/middle/end of file
- Pure deletion at start/middle/end of file
- Empty old file (insertion into empty buffer)
- Identical files (no animation, just open vim)
- Files without trailing newlines
- Multi-hunk diffs with mixed insert/delete

#### Documentation
- Comprehensive README with quick start, examples, and architecture overview
- `docs/ARCHITECTURE.md` — deep-dive into the three implementations
- `docs/PARSERS.md` — parser API reference and guide to writing custom parsers
- `docs/CONTROLS.md` — detailed user controls reference
- `docs/CONFIGURATION.md` — all configuration options with presets
- `docs/TESTING.md` — test suite documentation
- `IMPROVEMENTS.md` — 100 prioritized improvements organized into 7 categories

#### Tests
- `tests/test_parsers.pl` — 18 parser assertions (9 cases × 2 parsers)
  covering simple modifications, multi-hunk diffs, pure insertions/deletions,
  empty files, mid-line edits, and more
- `tests/test_e2e_perl.pl` — end-to-end test that runs the full animation
  in a tmux session and verifies the buffer matches the expected output

### Known Limitations
- **Trailing newline changes** — if the only difference is a trailing
  newline, the diff may not animate correctly
- **tmux send-keys race conditions** — `diffvim-tmux` and `diffvim.pl`
  can experience race conditions where Ex command text leaks into
  normal mode when commands are sent faster than vim processes them
- **Large files** — LCS DP table is O(N×M) memory; files >10,000 lines
  may consume significant memory
- **Binary files** — not detected; will produce garbage char ops
- **Non-UTF-8 encodings** — files are read as raw bytes
- **No syntax awareness** — diff is purely textual; may split tokens

---

## Version History Summary

| Version | Date       | Key Changes                                    |
| ------- | ---------- | ---------------------------------------------- |
| 1.0.0   | 2026-08-09 | Initial release with 3 implementations, 2 parsers, 100 improvements roadmap |
