# Environment Variable Analysis

The `ad` toolkit currently uses **107 distinct `AD_*` environment variables**. This document categorizes them, identifies which are removable, and proposes a plan to reduce the count dramatically.

## Summary

| Category | Count | Recommendation |
|----------|-------|----------------|
| **Active and needed** | 28 | KEEP |
| **Obsolete (options removed)** | 8 | DELETE (already non-functional) |
| **Vimscript-only (never set by user)** | 35 | Convert to internal variables |
| **Perl launcher only (duplicate of bash)** | 12 | Delete Perl launcher or align |
| **Redundant duplicates** | 9 | Consolidate |
| **Debug/internal** | 8 | Keep but namespace as `AD_DEBUG_*` |
| **Test-only** | 7 | Move to test fixtures |
| **Total** | 107 | → ~30 after cleanup |

## Goal

Reduce from 107 to ~30 user-facing env vars. The remaining 30 should be:
- Documented in `docs/src/configuration.md`
- Have clear, non-overlapping purposes
- Use the `AD_` prefix consistently
- Be settable via config file (`~/.config/ad/config`) OR env var OR CLI flag

The principle: **environment variables are for things the user might want to set. Internal state should be plain variables, not env vars.**

---

## Category 1: Obsolete — DELETE (8 vars)

These reference options that were removed in earlier refactors. The env vars are still declared in `diff_engine/cpp/compute.cpp` and `apps/vim/autoload_diffvim/engine.vim` but the code that reads them is gone.

```
AD_SEMANTIC_CLEANUP    — option removed (commit 6c2f56d)
AD_INDENT_AWARE        — option removed (commit 6c2f56d)
AD_OP_ORDER            — option removed (commit 6c2f56d)
AD_OPTIMIZE_SEQUENCE   — header-only; compute always optimizes now
AD_WORD_DIFF           — option removed
AD_LANGUAGE            — unused
AD_NO_STARTUP_PAUSE    — replaced by --startup-pause flag
AD_TRACE_DECISIONS     — commented out in C source
```

**Action:** Delete all references. Search-and-replace.

---

## Category 2: Vimscript-only internal state — CONVERT (35 vars)

These are exported by the bash launcher (`apps/vim/ad_vim`) so the vimscript engine (`apps/vim/autoload_diffvim/engine.vim`) can read them via `$VAR`. But the user never sets them — they're computed from CLI flags.

The bash launcher does:

```bash
export AD_DELETE_PACING=word
export AD_INSERT_PACING=char
# ... 50 more
```

Then vimscript reads:

```vim
let s:delete_pacing = $AD_DELETE_PACING
```

This is wrong. Internal state should be passed via a single channel (a temp file or a single env var holding JSON), not 50 separate env vars.

```
AD_ACCEL_DELETE                  AD_GAUSSIAN_JITTER
AD_ACCEL_DELETE_ACCEL            AD_GAUSSIAN_JITTER_PCT
AD_ACCEL_DELETE_MIN_MS           AD_HIGHLIGHT_COLOR
AD_ACCEL_DELETE_START_MS         AD_HIGHLIGHT_DURATION_MS
AD_ADAPTIVE_TIMING               AD_HIGHLIGHT_MIN_CHARS
AD_BLOCK_DELETE_SIZE             AD_HIGHLIGHT_WORD
AD_DELETE_PACING                 AD_HIGHLIGHT_WORD_COLOR
AD_DELETE_SPEED                  AD_HIGHLIGHT_WORD_DURATION_MS
AD_DELETE_THRESHOLD              AD_HIGHLIGHT_WORD_MIN_CHARS
AD_DIM_UNCHANGED                 AD_INLINE_HIGHLIGHT
AD_DIM_UNCHANGED_PCT             AD_INLINE_HIGHLIGHT_DURATION_MS
AD_DISTANCE_FAST_MULT           AD_MOVE_MAX_MS
AD_DISTANCE_SLOW_MULT            AD_MOVE_MIN_MS
AD_DISTANCE_SPEED                AD_MOVE_MS_PER_UNIT
AD_DISTANCE_THRESHOLD            AD_PACING
AD_FLASH_HIGHLIGHT_MS            AD_PAUSE_AFTER_DELETE_MS
AD_FLASH_PAUSE_MS                AD_PAUSE_AFTER_LINES
AD_FOLD_UNCHANGED                AD_PAUSE_AFTER_MS
AD_GIT_BLAME                     AD_PAUSE_AFTER_THRESHOLD
AD_PAUSE_BEFORE_DELETE_MS        AD_RAPID_EOL_DELETE
AD_SIGN_COLUMN                   AD_WORD_END_PAUSE_MS
AD_INSERT_PACING                 (etc.)
AD_INSERT_SPEED
```

**Action:** Replace the 50 exports with a single temp file written by bash and read by vimscript. Or pass them via the existing `$DIFFVIM_TIMED_OPS` channel. **Removes 35+ env vars from the user-visible namespace.**

---

## Category 3: Perl launcher duplicates — DELETE or ALIGN (12 vars)

`apps/vim/ad_vim.pl` is a Perl parallel launcher that duplicates the bash launcher. It reads the same env vars but with its own defaults. Either:

- **Option A (recommended):** Delete `ad_vim.pl`. The bash launcher is the canonical entry point; the Perl duplicate adds maintenance burden without value.
- **Option B:** Keep `ad_vim.pl` but make it read from the same config file as the bash launcher.

```
AD_ADAPTIVE_WORD_DELETE           AD_RAPID_EOL_MIN_CHARS
AD_ADAPTIVE_WORD_DELETE_ACCEL     AD_RAPID_IDENTICAL_ACCEL
AD_ADAPTIVE_WORD_DELETE_MIN_MS    AD_RAPID_IDENTICAL_CHARS
AD_ADAPTIVE_WORD_DELETE_START_CHARS  AD_RAPID_IDENTICAL_MIN
AD_ADAPTIVE_WORD_DELETE_START_MS  AD_SCROLL_DEBUG
AD_ADAPTIVE_WORD_DELETE_WORD_PAUSE_MS  AD_TUNE_WORKDIR
AD_MAX_WORD_CHARS
```

These are all referenced only in `apps/vim/autoload_diffvim/engine.vim` or `apps/vim/ad_vim.pl`. The bash launcher doesn't use them.

---

## Category 4: Redundant duplicates — CONSOLIDATE (9 vars)

Multiple env vars that control the same thing:

```
AD_DELETE_END_FIRST              ← feature flag
AD_DELETE_END_FIRST_DELAY_MS     ← timing
AD_DELETE_END_FIRST_HIGHLIGHT_MS ← timing
AD_DELETE_END_FIRST_SMART        ← mode

AD_HIGHLIGHT                     ← mode (none/inline/word/hunk)
AD_HIGHLIGHT_HUNK                ← subset of AD_HIGHLIGHT=hunk
AD_HIGHLIGHT_WORD                ← subset of AD_HIGHLIGHT=word
AD_HIGHLIGHT_WORD_COLOR          ← word-specific
AD_HIGHLIGHT_WORD_DURATION_MS    ← word-specific
AD_HIGHLIGHT_WORD_MIN_CHARS      ← word-specific
AD_INLINE_HIGHLIGHT              ← subset of AD_HIGHLIGHT=inline
AD_INLINE_HIGHLIGHT_DURATION_MS ← inline-specific
```

**Action:** Collapse `AD_HIGHLIGHT_HUNK`, `AD_HIGHLIGHT_WORD`, `AD_INLINE_HIGHLIGHT` into `AD_HIGHLIGHT=none|inline|word|hunk`. Collapse `AD_DELETE_END_FIRST_*` into a single `AD_DELETE_END_FIRST` config that takes a mode.

---

## Category 5: Debug/internal — KEEP but namespace (8 vars)

These are legitimate internal env vars used for debugging. Keep them but ensure they all use the `AD_DEBUG_*` prefix.

```
AD_DEBUG_LAYERS                  ← already correct
AD_DUMP_INPUT                    ← rename to AD_DEBUG_DUMP_INPUT
AD_DUMP_OUTPUT                   ← rename to AD_DEBUG_DUMP_OUTPUT
AD_DUMP_CHANGES                  ← rename to AD_DEBUG_DUMP_CHANGES
AD_OLD_FILE                      ← rename to AD_DEBUG_OLD_FILE (or AD_INTERNAL_OLD_FILE)
AD_TIMED_OPS                     ← rename to AD_INTERNAL_TIMED_OPS
AD_CONFIG_LOADED                 ← rename to AD_INTERNAL_CONFIG_LOADED
AD_COMPUTE_TOOL                  ← rename to AD_INTERNAL_COMPUTE_BIN
```

---

## Category 6: Test-only — MOVE to test fixtures (7 vars)

These are only referenced in test scripts, not in production code. They should be test fixtures, not env vars.

```
AD_PRECOMPUTED                   ← test helper
AD_SCROLL                        ← test variant
AD_HUNK_PAUSE_MS                 ← test variant
AD_TYPE_DELAY_MS                 ← test variant
AD_DELETE_DELAY_MS               ← test variant
AD_WORD_PAUSE_MS                 ← test variant
AD_TICK_MS                       ← test variant
```

**Action:** Replace with explicit CLI flags in test scripts.

---

## Category 7: Active and needed — KEEP (28 vars)

These are the vars that genuinely belong in the user-facing namespace. They control user-visible behavior and are documented in `docs/src/configuration.md`:

### Pacing (5)
```
AD_DELETE_PACING        ← char|word|instant|rapid-eol|rapid-identical|accel|flash
AD_INSERT_PACING         ← char|word|accel
AD_PACING                ← uniform|adaptive|gaussian|review
AD_DELETE_SPEED          ← slow|normal|fast|instant
AD_INSERT_SPEED         ← slow|normal|fast
```

### Layer chain (3)
```
AD_INDENT_LAST              ← 0|1 (enables ad_layer_indent_last)
AD_OVERWRITE_MODE           ← 0|1 (enables ad_layer_overwrite)
AD_LINE_DELETE_IN_PLACE     ← 0|1 (enables ad_layer_line_delete_in_place)
```

### Animation behavior (5)
```
AD_LEFT_TO_RIGHT        ← 0|1 (diff mode)
AD_SPEED                ← float (speed multiplier)
AD_SCROLL               ← zz|zt|zb|none
AD_MAX_LINE_LEN         ← integer
AD_MAX_HUNK_CHARS       ← integer (0 = no limit)
```

### Cursor movement (5)
```
AD_CURSOR_GLIDE_MS              ← integer (ms; 0 disables)
AD_CURSOR_GLIDE_SHOW_INTERMEDIATE ← 0|1
AD_DISTANCE_SPEED                ← adaptive|off
AD_DISTANCE_THRESHOLD            ← integer (lines)
AD_DISTANCE_FAST_MULT            ← float
AD_DISTANCE_SLOW_MULT            ← float
```

### Decoration (4)
```
AD_HIGHLIGHT_MODE           ← none|inline|word|hunk (rename from AD_HIGHLIGHT)
AD_HIGHLIGHT_DURATION_MS    ← integer (ms)
AD_DIM_UNCHANGED            ← 0|1
AD_DIM_UNCHANGED_PCT        ← integer (0-100)
AD_CONTEXT_LINES            ← integer (lines of context)
AD_FOLD_UNCHANGED           ← 0|1
AD_SIGN_COLUMN              ← 0|1
AD_GIT_BLAME                ← 0|1
```

### Output (3)
```
AD_OUTPUT                ← file path
AD_SNAPSHOT              ← file path (rename from AD_SNAPSHOT if exists)
AD_KEEP_DIRTY            ← 0|1
```

### Misc (3)
```
AD_THEME                 ← dark|light|high-contrast
AD_LOG_MODE             ← mode
AD_LOG_FILE             ← file path
```

---

## Proposed reduction plan

| Phase | Action | Vars removed |
|-------|--------|-------------|
| 1 | Delete obsolete (Category 1) | 8 |
| 2 | Convert vimscript-internal to temp file (Category 2) | 35 |
| 3 | Delete Perl launcher duplicates (Category 3) | 12 |
| 4 | Consolidate redundant duplicates (Category 4) | 9 |
| 5 | Namespace debug vars (Category 5) | 0 (renames) |
| 6 | Move test-only to fixtures (Category 6) | 7 |
| **Total** | | **71 vars removed** |

Final count: **107 → 36 env vars** (28 user-facing + 8 debug-namespaced).

---

## Implementation order

1. **Phase A (low risk):** Delete Category 1 (obsolete). They're already non-functional.
2. **Phase B (medium risk):** Consolidate Category 4 (redundant). Update tests.
3. **Phase C (high risk):** Convert Category 2 (vimscript-internal). Requires rewriting how bash passes state to vimscript — significant change to `apps/vim/ad_vim` and `apps/vim/autoload_diffvim/engine.vim`.
4. **Phase D (low risk):** Namespace Category 5 (debug). Pure renames.
5. **Phase E (low risk):** Move Category 6 (test-only) to fixtures.
6. **Phase F (decision):** Delete or align Category 3 (Perl launcher).

---

## Open questions

#Q1 Delete `apps/vim/ad_vim.pl`?

The Perl launcher duplicates the bash one. It exists for environments without bash, but those are rare today. Deleting it removes 12 env vars and significant maintenance burden.

#Q2 How should bash pass state to vimscript?

Options:
- (a) Single temp file with `key=value` lines, sourced by vimscript.
- (b) JSON env var (`AD_CONFIG='{"delete_pacing":"word",...}'`).
- (c) Vimscript reads the config file directly (like bash does).

Option (c) is cleanest — both bash and vimscript source the same `~/.config/ad/config`, and CLI flags override per-invocation. No env vars needed for internal state.

#Q3 Keep `AD_HIGHLIGHT` or rename to `AD_HIGHLIGHT_MODE`?

The current name is ambiguous (mode vs. color vs. duration). `AD_HIGHLIGHT_MODE` is clearer but breaks backward compat. Recommendation: rename, accept the break.

---

## Inventory (full list)

For reference, the complete list of 107 `AD_*` env vars found in the codebase:

```
AD_ACCEL_DELETE
AD_ACCEL_DELETE_ACCEL
AD_ACCEL_DELETE_MIN_MS
AD_ACCEL_DELETE_START_MS
AD_ADAPTIVE_ACCEL
AD_ADAPTIVE_MAX_MS
AD_ADAPTIVE_MODE
AD_ADAPTIVE_PAUSE_LINES
AD_ADAPTIVE_PAUSE_MS
AD_ADAPTIVE_START_MS
AD_ADAPTIVE_TIMING
AD_ADAPTIVE_WORD_DELETE
AD_ADAPTIVE_WORD_DELETE_ACCEL
AD_ADAPTIVE_WORD_DELETE_MIN_MS
AD_ADAPTIVE_WORD_DELETE_START_CHARS
AD_ADAPTIVE_WORD_DELETE_START_MS
AD_ADAPTIVE_WORD_DELETE_WORD_PAUSE_MS
AD_BLOCK_DELETE_SIZE
AD_COMPUTE_TOOL
AD_CONFIG_LOADED
AD_CONTEXT
AD_DEBUG_LAYERS
AD_DELETE_DELAY_MS
AD_DELETE_END_FIRST
AD_DELETE_END_FIRST_DELAY_MS
AD_DELETE_END_FIRST_HIGHLIGHT_MS
AD_DELETE_END_FIRST_SMART
AD_DELETE_PACING
AD_DELETE_SPEED
AD_DELETE_THRESHOLD
AD_DIM_UNCHANGED
AD_DIM_UNCHANGED_PCT
AD_DUMP_CHANGES
AD_DUMP_INPUT
AD_DUMP_OUTPUT
AD_FOLD_UNCHANGED
AD_GAUSSIAN_JITTER
AD_GAUSSIAN_JITTER_PCT
AD_GIT_BLAME
AD_HIGHLIGHT
AD_HIGHLIGHT_COLOR
AD_HIGHLIGHT_DURATION_MS
AD_HIGHLIGHT_HUNK
AD_HIGHLIGHT_MIN_CHARS
AD_HIGHLIGHT_WORD
AD_HIGHLIGHT_WORD_COLOR
AD_HIGHLIGHT_WORD_DURATION_MS
AD_HIGHLIGHT_WORD_MIN_CHARS
AD_HUNK_PAUSE_MS
AD_INDENT_AWARE
AD_INDENT_LAST
AD_INLINE_HIGHLIGHT
AD_INLINE_HIGHLIGHT_DURATION_MS
AD_INSERT_PACING
AD_INSERT_SPEED
AD_KEEP_DIRTY
AD_LANGUAGE
AD_LAYER_COMMON_H
AD_LAYER_MAX_LINE
AD_LAYER_STANDALONE
AD_LAYER_TYPE_LEN
AD_LEFT_TO_RIGHT
AD_LINE_CHANGE_PAUSE_MS
AD_LINE_DELETE_IN_PLACE
AD_LOG_FILE
AD_LOG_MODE
AD_MAX_HUNK_CHARS
AD_MAX_LINE_LEN
AD_MAX_WORD_CHARS
AD_MOVE_MAX_MS
AD_MOVE_MIN_MS
AD_MOVE_MS_PER_UNIT
AD_NO_STARTUP_PAUSE
AD_NO_VIMRC
AD_OLD_FILE
AD_OP_ORDER
AD_OPTIMIZE_SEQUENCE
AD_OUTPUT
AD_OVERWRITE_MODE
AD_PACING
AD_PAUSE_AFTER_DELETE_MS
AD_PAUSE_AFTER_LINES
AD_PAUSE_AFTER_MS
AD_PAUSE_AFTER_THRESHOLD
AD_PAUSE_BEFORE_DELETE_MS
AD_PRECOMPUTED
AD_RAPID_EOL_DELETE
AD_RAPID_EOL_DELAY_MS
AD_RAPID_EOL_MIN_CHARS
AD_RAPID_IDENTICAL_ACCEL
AD_RAPID_IDENTICAL_CHARS
AD_RAPID_IDENTICAL_MIN
AD_RAPID_EOL_MIN_CHARS
AD_SCROLL
AD_SCROLL_DEBUG
AD_SEMANTIC_CLEANUP
AD_SIGN_COLUMN
AD_SPEED
AD_STARTUP_FEEDBACK
AD_STARTUP_PAUSE
AD_THEME
AD_TICK_MS
AD_TIMED_OPS
AD_TRACE_DECISIONS
AD_TUNE_WORKDIR
AD_TYPE_DELAY_MS
AD_WORD_ACCEL
AD_WORD_ACCEL_DELETE_PCT
AD_WORD_DIFF
AD_WORD_END_PAUSE_MS
AD_WORD_PAUSE_MS
```
