# Options Analysis: Redundancy, Grouping, and Improvement Opportunities

## Overview

This document analyzes all ad_vim options for redundancy, grouping
opportunities, and potential improvements. It is a professional analysis
— no code changes are proposed, only observations and recommendations.

---

## 1. Redundant Options

### 1.1 `--word-diff` vs `--word-accel` vs `--max-word-chars`

**Current state:** Three options control word-level behavior:
- `--word-diff`: Changes the diff algorithm to word-token level + batches
  word runs as instant ops
- `--word-accel`: Char-by-char word insert/delete with acceleration
  (slow start, fast end, pause)
- `--max-word-chars N`: If a word is <= N chars, type instantly + pause

**Redundancy:** `--word-diff` and `--max-word-chars` overlap. If
`--word-diff` batches word runs as instant ops, `--max-word-chars` is
redundant (all words are already instant). If `--word-accel` is on,
it provides a middle ground between char-by-char and instant.

**Recommendation:** These should be **mutually exclusive modes** with
a single `--word-mode` option:
- `--word-mode char` (default): char by char
- `--word-mode accel`: char by char with acceleration + end pause
- `--word-mode instant`: whole word instantly + pause
- `--word-mode threshold N`: words <= N chars instant, longer = char by char

### 1.2 `--accel-delete` vs `--adaptive-word-delete`

**Current state:** Two options for multi-line deletion:
- `--accel-delete`: Block-based (3-line blocks) with triangle accel/decel
- `--adaptive-word-delete`: Word-by-word (few chars → words → rest) with
  acceleration

**Redundancy:** Both handle the same use case (multi-line deletion)
with different strategies. Having both on simultaneously would conflict
(both try to handle the same delete run).

**Recommendation:** Merge into `--delete-mode`:
- `--delete-mode char` (default): char by char
- `--delete-mode block`: block-based with accel (current `--accel-delete`)
- `--delete-mode word`: word-by-word with accel (current `--adaptive-word-delete`)
- `--delete-mode instant`: whole hunk instantly

### 1.3 `--hunk-pause-ms` vs `--pause-after-lines` vs `--line-change-pause-ms`

**Current state:** Three different pause points:
- `--hunk-pause-ms`: pause between hunks
- `--pause-after-lines N`: pause every N lines in large hunks
- `--line-change-pause-ms`: pause when crossing a line boundary

**Redundancy:** `--line-change-pause-ms` pauses at EVERY line boundary,
while `--pause-after-lines` pauses every N lines. If both are on, the
user gets a pause at every line boundary PLUS an extra pause every N
lines. This is confusing.

**Recommendation:** Group into `--pause-mode`:
- `--pause-mode none`: no pauses
- `--pause-mode hunk`: pause between hunks only (current `--hunk-pause-ms`)
- `--pause-mode line`: pause at each line boundary (current `--line-change-pause-ms`)
- `--pause-mode periodic N`: pause every N lines (current `--pause-after-lines`)

### 1.4 `[REMOVED: --semantic-cleanup]` vs `--optimize-sequence`

**Current state:** Two post-processing passes:
- `[REMOVED: --semantic-cleanup]`: Merge canceling del+ins pairs (del 'a' + ins 'a' → keep 'a')
- `--optimize-sequence`: Consolidate interleaved del/ins (del a, ins x, del b → del a, del b, ins x)

**Redundancy:** Both clean up the char op sequence. `[REMOVED: --semantic-cleanup]`
is a special case of `--optimize-sequence` (canceling pairs are a subset
of interleaved pairs). If `--optimize-sequence` is on (default), most
canceling pairs are already handled.

**Recommendation:** Merge into a single `--optimize` flag with levels:
- `--optimize none`: no optimization
- `--optimize basic`: semantic cleanup only
- `--optimize full` (default): semantic cleanup + sequence consolidation

---

## 2. Options That Should Be Grouped

### 2.1 All highlight options

**Current state:** Separate flags:
- `--highlight-hunk`, `--highlight-word`, `--highlight-inline`
- `--highlight-color`, `--highlight-duration-ms`, `--highlight-min-chars`
- `--highlight-word-color`, `--highlight-word-duration-ms`, `--highlight-word-min-chars`
- `--highlight-inline-duration-ms`
- `--dim-unchanged`, `--dim-unchanged-pct`

**Recommendation:** Group under a `--highlight` meta-option:
- `--highlight all`: enable all highlight types
- `--highlight hunk,word,inline`: select specific types
- `--highlight none`: disable all
- Duration/color options become shared: `--highlight-duration-ms 300`
  applies to all active highlight types

### 2.2 All timing options

**Current state:** 15+ separate delay/pause options:
- `--type-delay-ms`, `--delete-delay-ms`, `--tick-ms`
- `--hunk-pause-ms`, `--word-pause-ms`, `--word-end-pause-ms`
- `--line-change-pause-ms`, `--pause-after-ms`
- `--pause-before-delete-ms`, `--pause-after-delete-ms`
- `--accel-delete-start-ms`, `--accel-delete-min-ms`
- `--adaptive-word-delete-start-ms`, `--adaptive-word-delete-min-ms`
- `--move-min-ms`, `--move-max-ms`

**Recommendation:** Introduce a `--speed-profile` option:
- `--speed-profile slow`: all delays × 2
- `--speed-profile normal`: defaults
- `--speed-profile fast`: all delays × 0.5
- `--speed-profile custom`: individual options override

This would let users set a general speed without tuning 15 individual
delays.

### 2.3 All deletion acceleration options

**Current state:** Separate options for each deletion mode:
- `--accel-delete`, `--accel-delete-start-ms`, `--accel-delete-min-ms`,
  `--accel-delete-accel`
- `--adaptive-word-delete`, `--adaptive-word-delete-start-chars`,
  `-start-ms`, `-min-ms`, `-accel`, `-word-pause-ms`
- `--rapid-identical-chars`, `--rapid-identical-min`, `--rapid-identical-accel`
- `--rapid-eol-delete`, `--rapid-eol-delay-ms`, `--rapid-eol-min-chars`
- `--block-delete-size`, `--pause-before-delete-ms`, `--pause-after-delete-ms`

**Recommendation:** Group under `--delete-profile`:
- `--delete-profile char`: char by char (default)
- `--delete-profile block N`: block-based with N lines per block
- `--delete-profile word`: word-by-word
- `--delete-profile rapid`: all rapid modes on (EOL + identical + block)
- `--delete-profile custom`: individual options

### 2.4 All external compute options

**Current state:** `--precomputed`, `--auto-precompute`, `--compute-tool`

**Recommendation:** Merge into:
- `--compute auto`: auto-run compute tool (current `--auto-precompute`)
- `--compute file PATH`: use precomputed file (current `--precomputed`)
- `--compute inline`: compute in vimscript (default)
- `--compute-tool c|cpp|rust|go`: sub-option for `--compute auto`

> **Update (Phase A–C refactor):** This was overtaken by events. The
> `--tool` / `--compute-tool` flags were **removed entirely** (along with
> the C, Rust, and Go compute variants — only the C++ tool remains).
> `--auto-precompute` was also removed; ad_vim now always searches for
> `bin/ad_compute` automatically and falls back to the
> in-vim Patience if missing. Only `--precomputed FILE` remains as the
> low-level escape hatch. See the [Unreleased] entry in `CHANGELOG.md`.

---

## 3. Options That Could Be Replaced

### 3.1 `--keep-dirty` → replace with `--buffer-modified on|off`

**Current state:** `--keep-dirty` is a boolean that leaves the buffer
modified. The inverse (default) is `:set nomodified`.

**Recommendation:** Replace with `--buffer-modified on|off` (default:
off). More explicit and extensible.

### 3.2 `--no-vimrc` → replace with `--vimrc user|isolated`

**Current state:** `--no-vimrc` is a boolean that skips loading user vimrc.

**Recommendation:** Replace with `--vimrc user` (default) or
`--vimrc isolated`. More explicit.

### 3.3 `--startup-pause` → replace with `--startup verbose|silent`

**Current state:** `--startup-pause` shows config + help before starting.

**Recommendation:** Replace with `--startup verbose` or `--startup silent`
(default). Could also support `--startup minimal` (just the hunk count).

### 3.4 `--overwrite` → could be a sub-mode of `--word-mode`

**Current state:** `--overwrite` transforms del+ins pairs into overwrite
operations.

**Recommendation:** Make it `--word-mode overwrite` — it's fundamentally
a word-replacement strategy, not a separate feature.

### 3.5 `--delete-end-first` → could be part of `--optimize-sequence`

**Current state:** `--delete-end-first` reorders ops to delete EOL before
inserting.

**Recommendation:** This is a post-processing pass. It could be a
sub-option of `--optimize`: `--optimize full,eol-first`.

---

## 4. Missing Options

### 4.1 `--scroll-smooth on|off`

Currently, smooth scrolling during typing (the new ScrollStep phase)
is always on when the cursor jumps > 3 lines. There should be an option
to disable it: `--scroll-smooth off` for instant jumps.

### 4.2 `--scroll-threshold N`

The current threshold for triggering smooth scroll during typing is
hardcoded to 3 lines. It should be configurable.

### 4.3 `--log-scroll on|off`

The scroll debug log (`config var: SCROLL_DEBUG`) is an env var only.
It should be a CLI option: `--log-scroll /tmp/scroll.log`.

### 4.4 `--word-accel-threshold N`

The word-accel mode uses a hardcoded "first 3 chars slow" threshold.
It should be configurable.

---

## 5. Naming Inconsistencies

### 5.1 `--highlight-inline` vs `--inline-highlight`

The option was renamed from `--inline-highlight` to `--highlight-inline`
for consistency, but the env var is still `config var: HIGHLIGHT_INLINE` and
the config key is `inline_highlight`. Should be fully consistent.

### 5.2 `--rapid-eol-delete` vs `--rapid-identical-chars`

Both use "rapid" but `--rapid-eol-delete` is default-on while
`--rapid-identical-chars` is default-off. The naming doesn't convey
the default state.

### 5.3 Mixed `--no-*` and `--*-off` patterns

Some options use `--no-X` to disable (`--no-optimize-sequence`,
`--no-left-to-right`, `--no-rapid-eol-delete`), while others use
separate flags. This should be standardized.

---

## 6. Summary

| Category | Current Options | Recommendation |
|----------|----------------|----------------|
| Word modes | 3 overlapping | Merge into `--word-mode` |
| Delete modes | 2 overlapping | Merge into `--delete-mode` |
| Pauses | 3 overlapping | Merge into `--pause-mode` |
| Optimization | 2 overlapping | Merge into `--optimize` levels |
| Highlights | 10+ separate | Group under `--highlight` |
| Timing | 15+ separate | Add `--speed-profile` |
| Compute | 3 separate | Merge into `--compute` |
| Naming | Inconsistent | Standardize `--no-X` pattern |

**Bottom line:** The current 60+ CLI options could be reduced to ~25
core options with sub-modes, while maintaining full backward compatibility
via env vars and aliases. This would make the tool significantly easier
to use and configure.
