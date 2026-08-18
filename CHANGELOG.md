# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased] — 2026-08-18

### Fixed — ghost-line regression in diffvim

Commit 758c8c7 introduced a "deferred joins" mechanism to fix a
hallucinated "ghost line" visual problem. The mechanism was later
removed but the broken behavior remained in `DeleteCharAtCursor` and
`DeleteNewlineAtCursor`: when deleting a `\n`, if the current line had
content, the cursor was moved to the next line WITHOUT removing the
`\n` from the buffer. This caused the buffer state to diverge from
what subsequent ops expected, producing wrong output on 07_text_prose,
33_large_python, and others.

Fix: restored the original always-join behavior. When deleting a `\n`,
always JOIN the current line with the next (regardless of whether the
current line has content). The only exception is when the line is empty
(all content already deleted) — in that case, remove the empty line
entirely.

Verified: `test_vim_correctness.pl` passes 34/34 (was failing on
07_text_prose, 33_large_python). diffvim-pipeline passes 42/42.

### Fixed — same regression in Go/Perl/C animators

All 3 standalone animator implementations had the identical "don't join
if line has content" bug. Fixed `DeleteChar` and `NewlineDelete` in
Go, Perl, and C animators.

### Fixed — Go animator panics

- `InsertChar`: added defensive `cursorC` clamping to prevent
  `slice bounds out of range` panics from cursor drift.
- `BatchDelete`: added clamping before slicing.

### Fixed — pace line_offset bug

The pace stage was emitting glide targets using ORIGINAL line numbers,
not CURRENT buffer positions. After a previous hunk inserted/deleted
lines, all subsequent glide targets were off by the cumulative line
offset, causing inserts to land on wrong lines.

Fix: track `line_offset` (cumulative `newline_inserts -
newline_deletes` from previous hunks) and add it to each glide target.
Applied to pace.pl, pace.c, and pace.go.

Result: diffvim-pipeline went from 6/42 OK to 42/42 OK.

### Fixed — Go animator end_insert handling

When a hunk has `end_insert=1` (appending after last line), the Go
animator was clamping `cursorL` to the last line but leaving `cursorC`
at 0, causing inserts to PREPEND instead of APPEND.

Fix: when `cursorL >= len(lines)`, set `cursorC` to
`len(runes(last_line))` so subsequent inserts append after content.

### Added — verify_md5.sh script

`scripts/verify_md5.sh`: parallel round-trip MD5 verification script.
Tests diffvim (simple-loop + ProcessCharOp) and diffvim-pipeline
against all 42 example pairs. Runs 8 concurrent vim instances via
`xargs -P` for speed. Outputs MD5 comparison table.

### Added — PIPELINE.md documentation

`docs/PIPELINE.md`: 303-line prose document describing the full
pipeline (compute → postprocess → pace → animate), including timing
figures for all 3 diff algorithms on 15K-line files, and identification
of the ghost-line problem as a postprocess issue.

### Known issues — UNRESOLVED

1. **Ghost line problem**: when a `\n` delete joins two lines, the
   next line's content visually jumps up. The fix belongs in
   postprocess (transform the ops), not in the animator. NOT YET
   IMPLEMENTED.

2. **Large-file performance**: vimscript engine is O(N²) on large op
   lists. 28K ops (33_large_python) takes 11+ seconds; 68K ops
   (42_large_huge_python) times out at 30s.

3. **Myers algorithm**: OOM-killed on 15K-line files (O(N*M) memory).
   Should be replaced with linear-space Myers or dropped for large
   files.

4. **Pause/resume cursor drift**: in interactive diffvim, cursor
   position is not re-validated after pause/scroll/resume.

---

## [Unreleased] — 2026-08-16

### Removed — All old individual flags

All old individual flags that were replaced by unified selectors have
been removed. Only the unified selectors remain. This is a breaking
change — old flags are now rejected with "Unknown option" errors.

Removed flags (use the unified selector instead):
- --optimize-sequence / --no-optimize-sequence → --op-order
- --left-to-right / --no-left-to-right → --op-order left-to-right
- --delete-end-first → --op-order end-first
- --delete-end-first-smart → --op-order end-first-smart
- --overwrite → --op-order overwrite
- --rapid-eol-delete / --no-rapid-eol-delete → --delete-pacing
- --rapid-identical-chars → --delete-pacing rapid-identical
- --accel-delete → --delete-pacing accel
- --adaptive-word-delete → --delete-pacing word
- --max-word-chars → --insert-pacing word
- --word-accel → --insert-pacing accel
- --adaptive / --adaptive-timing → --pacing adaptive
- --gaussian-jitter → --pacing gaussian
- --pause-after-lines → --pacing review
- --highlight-word → --highlight word
- --highlight-hunk → --highlight hunk
- --highlight-inline → --highlight inline
- --fold-unchanged → --context 0

Removed sub-parameters (env vars still available for tuning):
- --rapid-eol-delay-ms, --rapid-eol-min-chars
- --rapid-identical-min, --rapid-identical-accel
- --accel-delete-start-ms, --accel-delete-min-ms, --accel-delete-accel
- --adaptive-word-delete-threshold, --adaptive-word-delete-start-chars,
  --adaptive-word-delete-start-ms, --adaptive-word-delete-min-ms,
  --adaptive-word-delete-accel, --adaptive-word-delete-word-pause-ms
- --delete-end-first-delay-ms, --delete-end-first-highlight-ms
- --word-accel-delete-pct, --word-end-pause-ms, --word-pause-ms
- --block-delete-size
- --pause-after-ms, --pause-before-delete-ms, --pause-after-delete-ms
- --adaptive-start-ms, --adaptive-max-ms, --adaptive-accel,
  --adaptive-pause-lines, --adaptive-pause-ms
- --gaussian-jitter-pct
- --line-change-pause-ms
- --highlight-word-color, --highlight-word-duration-ms,
  --highlight-word-min-chars, --highlight-inline-duration-ms,
  --highlight-min-chars

Removed short options (mapped to removed flags):
- -O (--overwrite), -L (--left-to-right), -W (--highlight-word),
  -H (--highlight-hunk), -I (--highlight-inline), -f (--fold-unchanged),
  -A (--adaptive-timing), -G (--gaussian-jitter)

Updated presets to use only unified options:
- fast-delete: --delete-pacing word --delete-speed fast --op-order optimize
- review: --pacing review --highlight hunk --dim-unchanged --op-order left-to-right
- demo: --pacing gaussian --speed 0.7 --highlight inline
- ai-code: --op-order end-first-smart --highlight inline --pacing adaptive

Updated all documentation:
- README.md: options table now shows only unified options
- man/diffvim.1: removed Animation Options and Utility Options sections,
  rewrote Environment Variables and Examples sections
- docs/src/options.md: completely rewritten with only unified options
- completion/diffvim.bash, .fish, _diffvim: rewritten with only unified options
- diffvim --help: rewritten with categorized sections (Core, Diff, Op Order,
  Deletion, Insertion, Timing, Highlighting)

Updated tests:
- All backwards-compat tests (which verified old flags still work) are
  now rejection tests (verify old flags are rejected with "Unknown option")
- test_features.pl: updated to check for unified options instead of old flags
- test_viewport.pl: updated to verify --fold-unchanged is rejected

### Added — Unified option selectors (Phases 2-7)

Six new unified selectors that replace ~30 individual flags.

- `--op-order MODE` — unified op reordering: `natural|optimize|left-to-right|end-first|end-first-smart|overwrite` (default: optimize). Replaces --optimize-sequence, --left-to-right, --delete-end-first, --delete-end-first-smart, --overwrite.
- `--delete-pacing MODE` — unified deletion strategy: `char|rapid-eol|rapid-identical|accel|word|instant` (default: rapid-eol). Replaces --rapid-eol-delete, --rapid-identical-chars, --accel-delete, --adaptive-word-delete.
- `--delete-speed MODE` — deletion speed: `slow|normal|fast|instant` (default: normal).
- `--delete-threshold N` — min chars to trigger rapid/word modes (default: 3).
- `--insert-pacing MODE` — unified insertion strategy: `char|word|accel` (default: char). Replaces --max-word-chars, --word-accel.
- `--insert-speed MODE` — insertion speed: `slow|normal|fast` (default: normal).
- `--pacing MODE` — unified timing mode: `uniform|adaptive|gaussian|review` (default: uniform). Replaces --adaptive, --adaptive-timing, --gaussian-jitter, --pause-after-lines.
- `--highlight MODE` — unified highlight mode: `none|inline|word|hunk` (default: none). Replaces --highlight-word, --highlight-hunk, --highlight-inline.

New test files: tests/test_op_order.pl (20), tests/test_delete_pacing.pl (29),
tests/test_insert_pacing.pl (23), tests/test_pacing.pl (27), tests/test_highlight.pl (29),
tests/test_viewport.pl (23), tests/test_input_source.pl (14) — 165 new assertions.

### Removed — diff2html dependency

The `diff2html-cli` Node.js dependency has been completely removed.

- Deleted `DiffVim/Parser/Diff2Html.pm` (the parser module).
- Removed `--parser diff2html` from `diffvim.pl` (only `--parser perl`
  is accepted now, and it's a no-op for backwards compatibility).
- Removed `--parser-compare` subcommand from `diffvim.pl`.
- Removed `diff2html` from the `--version` dependency list.
- Updated `tests/test_parsers.pl` to only test the Perl parser
  (was 18 assertions, now 9).
- Updated `tests/test_e2e_perl.pl` to only test the Perl parser
  (was 2 E2E tests, now 1).
- Updated `tests/test_comprehensive.pl` Test 20 to verify
  `--parser perl` is accepted instead of testing `--parser-compare`.
- Updated `tests/test_features.pl` Test 8 to expect "9 passed"
  instead of "18 passed".
- Updated completions (bash/fish/zsh) to only offer `perl` for
  `--parser`.
- Updated manpages, README, mdBook docs, Homebrew formula, and all
  documentation to remove diff2html references.
- The pure-Perl LCS parser was already the default and produces
  identical output to what diff2html produced — no functionality is
  lost.

This fixes the long-standing "FAIL: Parser tests pass" failure in
`tests/test_features.pl` that was caused by diff2html not being
installed.

### Removed — Input source options (Phase 8)

Removed 4 input-source options from the bash diffvim:
- `--from REV` — use `--git-rev REV..REV` instead
- `--to REV` — use `--git-rev REV..REV` instead
- `--auto-precompute` — use the compute tools directly with `--precomputed`
- `--compute-tool` — use the compute tools directly

`--git-rev REV..REV` already existed as a shorthand and now handles all
git replay use cases. `--precomputed FILE` is kept as the low-level
mechanism.

### Removed — diffvim-precomputed wrapper (Phase 9)

The `diffvim-precomputed` wrapper script and its manpage have been
removed. Users should now use the compute tools directly:

  # Before (removed):
  diffvim-precomputed --tool rust old.py new.py

  # After:
  compute/bin/diffvim-compute-rust old.py new.py /tmp/diff.txt
  diffvim --precomputed /tmp/diff.txt old.py new.py

### Added — Documentation overhaul

#### `-h` / `--help` on every executable
Every binary in the project now responds to `-h` and `--help` with a
full usage message, options, environment variables, examples, and
cross-references. Previously only `diffvim`, `diffvim-tmux`, and
`diffvim.pl` had it; now `diffvim-compare`, `diffvim-jogger`,
`diffvim-precomputed`, `jq_filter`, `difft_json_to_lcs`,
`set_config`, and all four `diffvim-compute-{c,cpp,rust,go}` variants
support it too.

#### Manpages for every executable
New `man/` directory with six manpages:
- `man/diffvim.1` (moved from repo root)
- `man/diffvim-tmux.1` (new)
- `man/diffvim-compare.1` (new)
- `man/diffvim-jogger.1` (new)
- `man/diffvim-precomputed.1` (new)
- `man/diffvim-compute.1` (new — covers all four language variants)

Install with `sudo cp man/*.1 /usr/local/share/man/man1/ && sudo mandb`.

#### Visual Guide
New `docs/VISUAL_GUIDE.md` — the canonical "explain diffvim in 5
minutes" reference with ASCII art. Covers the input → diff → hunks →
char ops → animation → output pipeline, the three implementations,
the post-processing pipeline, the cursor glide geometry, presets,
controls, multi-file, git replay, and end-to-end examples. 16
sections.

#### Adoption Guide
New `docs/ADOPTION_GUIDE.md` — concrete onboarding steps for teams:
why adoption is hard, presets as on-ramp, external compute as
default, editor + git integration, recording and sharing, shared
team config, a 45-minute workshop plan, measuring adoption, common
pushback (with answers), anti-patterns to avoid, and a 30-day
checklist.

#### mdBook expansion
- New `docs/src/presets.md` — the six built-in presets with usage
  examples, comparison table, and custom preset instructions.
- New `docs/src/compute.md` — the four external compute tools
  (C/C++/Rust/Go) with quick start, options, environment, output
  format, benchmark, and when to use each variant.
- New `docs/src/manpages.md` — how to install and read the manpages,
  plus the difference between `--help` and the manpages.
- Updated `docs/src/SUMMARY.md` to reference all 16 docs in `docs/`,
  plus the new pages.
- Updated `docs/src/introduction.md` with the new feature list
  (presets, external compute, post-processing pipeline) and a
  "Where to Go Next" section.

#### presentation.html expansion
Added five new sections to the one-page HTML overview:
- Six built-in presets (interactive card grid)
- Post-processing pipeline (visualized as ASCII flowchart)
- External compute tools (card grid for C/C++/Rust/Go + benchmark)
- Cursor glide geometry (ASCII ease-in-out chart)
- Documentation map (link grid to all major docs)

Also fixed the footer to reflect the current state (6 presets, 4
compute tools, 42 examples, 6 manpages, dual Artistic 2.0 / GPL 3.0
license).

### Changed
- `README.md` "Project Structure" section rewritten with the full
  file tree (now includes `compute/`, `man/`, and all new docs).
- `README.md` manpage install instructions updated to copy
  `man/*.1` instead of just `diffvim.1`.
- `README.md` new "Where to Start Reading" table linking to the
  visual guide, adoption guide, presentation, mdBook, manpages, and
  option combinations.
- `USER_REQUESTS.md` — added Session 16 (requests 119-124).

---

## [1.5.0] — 2026-08-13

### Added — 10 new features

#### Accelerated multi-line deletion (`--accel-delete`)
When consecutive lines are deleted, the deletion starts slow, accelerates
to a maximum speed, then decelerates near the end. Prevents large blocks
from vanishing in a single shot. Triangle profile with configurable start
delay, minimum delay (max speed), and acceleration factor.

- `--accel-delete` — enable
- `--accel-delete-start-ms N` (default 80) — initial delay per char
- `--accel-delete-min-ms N` (default 10) — minimum delay (max speed)
- `--accel-delete-accel N` (default 85) — acceleration factor 0-100

Good values for block sizes 2-100 lines: start=80ms, min=10ms, accel=85.

#### Overwrite mode (`--overwrite`)
When a word is deleted and a new word takes its place, the replacement is
done in-place (overwrite) instead of delete-all-then-insert-all. If the
replacement is shorter, overwrites then deletes the extra chars. If same
length, pure overwrite. If longer, overwrites then inserts the remainder.

#### Delete-end-first (`--delete-end-first`)
When a line has both inserts and end-of-line deletes, the end-of-line is
deleted first (with a short pause), then the inserts are applied. More
natural than "insert, then delete end".

- `--delete-end-first-delay-ms N` (default 100) — pause between delete and insert

#### Startup feedback (`--startup-feedback`)
Shows progress in the status line during diff computation ("computing
diff...", "N hunk(s) found"). Useful for large files where computation
takes seconds.

#### Inline char highlight (`--inline-highlight`)
Paints each freshly-typed char green (`DiffAdd`) and each freshly-deleted
char red (`DiffDelete`) for 200ms using `matchaddpos()`. Lets the eye
lock onto the exact change even on long lines.

- `--inline-highlight-duration-ms N` (default 200)

#### Gaussian jitter (`--gaussian-jitter`)
Varies per-char delay using a triangular distribution (approximation of
Gaussian) so typing feels human, not metronomic.

- `--gaussian-jitter-pct N` (default 20) — jitter percentage 0-100

#### Dim unchanged lines (`--dim-unchanged`)
Dims unchanged anchor lines (using a `diffvimDimUnchanged` highlight group)
so the eye is drawn to changed lines. Configurable dimming percentage.

- `--dim-unchanged-pct N` (default 60) — higher = more dim

#### Pause-after-N-lines (`--pause-after-lines`)
Auto-pauses every N lines in hunks larger than a threshold. Prevents the
viewer from losing context in very large hunks.

- `--pause-after-lines N` (default 0 = off)
- `--pause-after-threshold N` (default 50) — min hunk size to trigger
- `--pause-after-ms N` (default 500) — pause duration

### Added — 10 large example file pairs (200-1000 lines)
- `33_large_python` (208→393 lines) — Flask app refactor
- `34_large_javascript` (352→354) — React class → hooks
- `35_large_perl` (374→491) — Procedural → Moose OO
- `36_large_rust` (437→554) — Manual args → clap derive
- `37_large_go` (392→594) — Single handler → middleware chain
- `38_large_java` (518→604) — synchronized → CompletableFuture
- `39_large_typescript` (463→479) — any/callbacks → generics/async
- `40_large_csharp` (699→816) — God class → ECS pattern
- `41_large_ruby` (652→858) — Fat controller → service objects
- `42_large_huge_python` (1016→1221) — Monolith → typed classes

### Added — Documentation
- `docs/MULTI_FILE.md` — multi-file animation + external tools for multi-file
- `compute/PARALLELISM.md` — parallelism analysis + C OpenMP plan
- `docs/DIFF_STUDY.md` — human reading behavior research + recommended combos
- `diffvim-compare` — tool to generate all algorithm×option combinations

### Tests
- `tests/test_new_features.pl` (9 assertions) — new features correctness
- `tests/test_overwrite_deletefirst.pl` (8 assertions) — overwrite + delete-end-first
- All 160+ assertions across all test suites pass.

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
  `DiffVim::Parser::Diff2Html` (diff2html CLI). The diff2html parser
  was later removed in [Unreleased] — only the pure-Perl parser
  remains.
- Ease-in-out cubic cursor glide.
- Char-level LCS diff (only changed characters are touched).
- User controls: Space (pause), n (skip), b (back), q (quit).
- Snapshot-based "back" control.
- 7 environment variables for timing control.
- Comprehensive documentation: README, ARCHITECTURE, PARSERS, CONTROLS,
  CONFIGURATION, TESTING.
- 18 parser tests (9 cases × 2 parsers).
- 100 planned improvements documented in IMPROVEMENTS.md.
