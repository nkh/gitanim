# Restoring old features — analysis and implementation plan

## Context

The refactoring replaced the 3064-line vimscript engine (73 functions)
with an 11-function timed op stream reader. The pipeline (compute →
postprocess → pace) now handles diff computation, op ordering, and
delay insertion. The vimscript only animates.

This document analyzes what needs to be done to restore every old
feature, categorized by where the implementation belongs.

## Current architecture

```
bash launcher
  ├── parses all options
  ├── exports ~95 config var: * env vars
  ├── runs pipeline: compute → postprocess → pace
  └── launches vim with timed op stream reader
      └── reads $config var: TIMED_OPS, $config var: SPEED, $config var: SYNC
          (ignores all other env vars)
```

## Feature categories

### Category A: Pipeline options (need postprocess/pace changes)

These features belong in the pipeline stages. The bash launcher
already passes them, but the C/Perl tools don't fully implement them.

#### A1. `--delete-speed slow|normal|fast|instant`
**Current state**: Pace reads `--delete-speed` and adjusts `delete_delay`
and AWD timing. **WORKS** but only affects `word` pacing mode.
**Action**: Verify `slow` mode works (doubles delays). ✅ Already works.

#### A2. `--insert-speed slow|normal|fast`
**Current state**: Pace reads `--insert-speed` and adjusts `char_delay`.
**WORKS**.
**Action**: None needed. ✅ Already works.

#### A3. `--pacing uniform|adaptive|gaussian|review`
**Current state**: Exported as `config var: PACING` but pace doesn't read it.
**Needed**: Implement pacing modes in pace:
- `uniform` (default): fixed delays (current behavior)
- `adaptive`: speed up for long runs of same-type ops, slow down at transitions
- `gaussian`: add random jitter (±N%) to each delay for human-like typing
- `review`: long pauses between hunks, slow typing
**Action**: Add `--pacing` flag to pace.c, implement 4 modes.
**Effort**: ~2 hours.

#### A4. `--gaussian-jitter` / `--gaussian-jitter-pct N`
**Current state**: Exported but pace doesn't read it.
**Needed**: Add random jitter to delays. Subset of `--pacing gaussian`.
**Action**: Implement as part of A3.
**Effort**: Included in A3.

#### A5. `--pause-after-lines N` / `--pause-after-threshold N` / `--pause-after-ms N`
**Current state**: Exported but pace doesn't read it.
**Needed**: After every N changed lines, insert a pause of N ms.
**Action**: Add to pace.c — count changed lines, insert extra delay.
**Effort**: ~1 hour.

#### A6. `--accel-delete` / related env vars
**Current state**: Exported but pace doesn't read it.
**Needed**: Accelerated multi-line deletion — delete first lines slowly,
accelerate, then decelerate. Different from AWD (which is within a single
line's deletes).
**Action**: Add to pace.c — detect multi-line delete runs, apply
acceleration curve.
**Effort**: ~2 hours.

#### A7. `--rapid-eol-delete` / `--rapid-identical-chars`
**Current state**: Exported but pace doesn't read them.
**Needed**: 
- `rapid-eol`: delete trailing chars rapidly (80ms initial, accelerate)
- `rapid-identical`: delete runs of identical chars rapidly
**Action**: Add as delete-pacing modes in pace.c.
**Effort**: ~2 hours each.

#### A8. `--block-delete-size N` / `--pause-before-delete-ms` / `--pause-after-delete-ms`
**Current state**: Exported but pace doesn't read them.
**Needed**: Pause before/after delete blocks, group deletes into blocks.
**Action**: Add to pace.c.
**Effort**: ~1 hour.

#### A9. `--overwrite` / `[REMOVED: --op-order] overwrite`
**Current state**: Postprocess has `--overwrite` flag but it's a no-op
(just calls optimize_line).
**Needed**: Transform delete+insert into in-place overwrite ops.
**Action**: Implement in postprocess — when delete 'a' is immediately
followed by insert 'b' at the same position, replace with a single
"overwrite" concept (delete 'a', insert 'b' with no delay between them).
**Effort**: ~3 hours. Requires a new op type or pace handling.

#### A10. `[REMOVED: --op-order] left-to-right|end-first|end-first-smart`
**Current state**: Postprocess only implements `natural` and `optimize`.
**Needed**: 
- `left-to-right`: sort keeps, then deletes, then inserts (per line)
- `end-first`: trailing deletes before inserts
- `end-first-smart`: end-first with grouping
**Action**: Implement in postprocess.c `reorder_line()`.
**Effort**: ~2 hours each.

### Category B: Vimscript engine features (need vim APIs)

These features need vim-specific APIs that can't be done in the
pipeline. They must be implemented in the vimscript timed reader.

#### B1. `--context N` (fold unchanged regions)
**Current state**: Exported but timed reader ignores it.
**Needed**: After animation, fold regions >2N lines that are unchanged,
keeping N lines of context around each hunk.
**Action**: Add to timed reader — after animation completes, execute
vim fold commands. The pipeline already marks hunks; the reader can
fold between HUNK_END markers.
**Effort**: ~2 hours.

#### B2. `--sign-column` (show +/- signs)
**Current state**: Exported but timed reader ignores it.
**Needed**: Place signs in the vim sign column for each changed line.
**Action**: Add to timed reader — use `sign place` for each changed
line during animation.
**Effort**: ~1 hour.

#### B3. `--git-blame` (echo blame info)
**Current state**: Exported but timed reader ignores it.
**Needed**: For each hunk target line, echo git blame info.
**Action**: Add to timed reader — call `git blame` for the target
line, echo the result.
**Effort**: ~1 hour.

#### B4. `--step-mode` (space advances one op)
**Current state**: Exported but timed reader ignores it.
**Needed**: Start paused, space advances one op at a time.
**Action**: Add to timed reader — start with `timed_paused=1`, map
Space to process one op then pause again.
**Effort**: ~1 hour.

#### B5. `--highlight inline` (highlight changed chars)
**Current state**: Exported but timed reader ignores it.
**Needed**: After each delete/insert, highlight the changed char with
a matchadd (green for insert, red for delete), fade after N ms.
**Action**: Add to timed reader — use `matchadd()` with a timer to
clear after duration.
**Effort**: ~3 hours.

#### B6. `--highlight word` (highlight changed words)
**Current state**: Exported but timed reader ignores it.
**Needed**: Highlight the entire changed word, not just one char.
**Action**: Add to timed reader — detect word boundaries, use
`matchadd()` for the word span.
**Effort**: ~3 hours.

#### B7. `--highlight hunk` (highlight entire hunk)
**Current state**: Exported but timed reader ignores it.
**Needed**: Highlight the entire hunk region.
**Action**: Add to timed reader — use `matchadd()` for hunk span.
**Effort**: ~1 hour.

#### B8. `--dim-unchanged` / `--dim-unchanged-pct N`
**Current state**: Exported but timed reader ignores it.
**Needed**: Dim unchanged lines to draw attention to changes.
**Action**: Add to timed reader — use `matchadd()` with a dim
foreground color on unchanged lines.
**Effort**: ~2 hours.

#### B9. `--fold-unchanged`
**Current state**: Exported but timed reader ignores it.
**Needed**: Fold unchanged regions (similar to --context but during
animation).
**Action**: Add to timed reader — use vim fold commands.
**Effort**: ~2 hours.

#### B10. `--theme dark|light|high-contrast`
**Current state**: Exported but timed reader ignores it.
**Needed**: Set color scheme for highlights.
**Action**: Add to timed reader — set vim highlight groups based on
theme.
**Effort**: ~1 hour.

#### B11. `--startup-pause` / `--startup-feedback`
**Current state**: Exported but timed reader ignores it.
**Needed**: Show config + help before starting; show progress during
compute.
**Action**: Add to bash launcher (before vim starts) and timed reader
(during animation).
**Effort**: ~1 hour.

#### B12. `--max-hunk-chars N` (apply large hunks instantly)
**Current state**: Exported but timed reader ignores it.
**Needed**: If a hunk has >N changed chars, skip animation for that
hunk (apply instantly).
**Action**: Add to timed reader — count chars per hunk, if >N, apply
all ops without delays.
**Effort**: ~1 hour.

#### B13. `--scroll zz|zt|zb|none`
**Current state**: Exported but timed reader always uses `zz`.
**Needed**: Support `zt` (top), `zb` (bottom), `none` (no scroll).
**Action**: Read `config var: SCROLL` in TimedPlaceCursor, use appropriate
vim scroll command.
**Effort**: ~30 minutes.

### Category C: Bash launcher features (handled in bash)

#### C1. `--log-mode` / `--log-file` / `--no-log-timing`
**Current state**: Not implemented.
**Needed**: Generate a log file without starting vim.
**Action**: Add to bash launcher — run pipeline, write log, exit.
**Effort**: ~1 hour.

#### C2. `--debug`
**Current state**: Not implemented.
**Needed**: Verbose logging to /tmp/diffvim-debug.log.
**Action**: Add to bash launcher — set `-x`, redirect to log file.
**Effort**: ~30 minutes.

#### C3. `--max-line-len N`
**Current state**: Exported but not used.
**Needed**: Warn on lines longer than N characters.
**Action**: Add to bash launcher — check old/new files, warn.
**Effort**: ~30 minutes.

#### C4. `--preset NAME`
**Current state**: Parsed and applies preset combinations.
**Needed**: Verify presets work with current pipeline.
**Action**: Test each preset, fix any that reference removed features.
**Effort**: ~1 hour.

### Category D: Already working

These options work correctly in the current architecture:

- `--speed N` ✅ (fixed in last commit)
- `--output FILE` ✅
- `--sync` ✅
- `--dry-run` ✅
- `--no-vimrc` ✅
- `--keep-dirty` ✅ (fixed in last commit)
- `[REMOVED: --semantic-cleanup]` ✅
- `[REMOVED: --indent-aware]` ✅
- `--word-diff` ✅
- `--delete-pacing char|word|instant` ✅
- `--insert-pacing char|word` ✅
- `--delete-speed slow|normal|fast|instant` ✅
- `--insert-speed slow|normal|fast` ✅
- `--algorithm patience|lcs` ✅
- `--left-to-right` ✅ (new implementation)
- Keyboard: q/Space/p/n/+/-/=? ✅

## Implementation priority

### Phase 1: Quick wins (vimscript, ~8 hours total)

These are small changes to the timed reader that restore commonly
used features:

1. B13: `--scroll` (30 min)
2. B12: `--max-hunk-chars` (1 hour)
3. B4: `--step-mode` (1 hour)
4. B2: `--sign-column` (1 hour)
5. B3: `--git-blame` (1 hour)
6. B11: `--startup-pause` (1 hour)
7. B1: `--context` (2 hours)
8. B10: `--theme` (1 hour)

### Phase 2: Pacing improvements (~8 hours total)

1. A3: `--pacing` modes (2 hours)
2. A5: `--pause-after-lines` (1 hour)
3. A6: `--accel-delete` (2 hours)
4. A7: `--rapid-eol-delete` (2 hours)
5. A8: `--block-delete` (1 hour)

### Phase 3: Highlight features (~10 hours total)

1. B5: `--highlight inline` (3 hours)
2. B6: `--highlight word` (3 hours)
3. B7: `--highlight hunk` (1 hour)
4. B8: `--dim-unchanged` (2 hours)
5. B9: `--fold-unchanged` (1 hour)

### Phase 4: Advanced pipeline (~8 hours total)

1. A9: `--overwrite` (3 hours)
2. A10: `[REMOVED: --op-order] left-to-right|end-first|end-first-smart` (3 hours)
3. C1: `--log-mode` (1 hour)
4. C2: `--debug` (30 min)
5. C3: `--max-line-len` (30 min)

### Phase 5: Remaining

1. C4: `--preset` verification (1 hour)
2. A4: `--gaussian-jitter` (included in A3)
3. Testing all combinations (~4 hours)

## Total estimated effort

- Phase 1: ~8 hours (quick vimscript wins)
- Phase 2: ~8 hours (pacing)
- Phase 3: ~10 hours (highlighting)
- Phase 4: ~8 hours (advanced pipeline)
- Phase 5: ~5 hours (cleanup + testing)
- **Total: ~39 hours**

## Key design decisions

### Should features be in the pipeline or vimscript?

**Rule**: if the feature affects WHAT ops are produced (ordering,
grouping, transforms), it belongs in the pipeline. If it affects HOW
ops are displayed (highlighting, folding, signs), it belongs in
vimscript.

### Should pace support all timing modes?

Yes. The pace stage should handle all timing-related options:
- `--pacing` (mode selector)
- `--delete-pacing` (delete strategy)
- `--insert-pacing` (insert strategy)
- `--gaussian-jitter` (randomization)
- `--accel-delete` (multi-line acceleration)
- `--pause-after-lines` (periodic pauses)

### Should the timed reader read more env vars?

Yes. Currently it only reads 3. It should read:
- `config var: SCROLL` (for scroll mode)
- `config var: MAX_HUNK_CHARS` (for instant-apply threshold)
- `config var: STEP_MODE` (for step mode)
- `config var: SIGN_COLUMN` (for sign placement)
- `config var: GIT_BLAME` (for blame echo)
- `config var: HIGHLIGHT` + related (for highlighting)
- `config var: DIM_UNCHANGED` (for dimming)
- `config var: THEME` (for color scheme)
- `config var: CONTEXT` (for folding)
- `config var: FOLD_UNCHANGED` (for folding)
- `config var: STARTUP_PAUSE` (for startup)
- `config var: LANGUAGE` (for filetype)

### New op types needed?

For `--overwrite`, we may need a new op type `overwrite` that
combines delete+insert in one step. Alternatively, pace can emit
delete+insert with zero delay between them.

For `--highlight`, the timed reader can use `matchadd()` — no new op
type needed. The highlight is applied after each op based on the
op type and position.

## Validation needed from user

1. Is the priority order correct? (Quick wins → pacing → highlighting → pipeline)
2. Should `--overwrite` use a new op type or zero-delay delete+insert?
3. Should `--highlight` be in the pipeline (marking ops) or vimscript
   (applying matchadd)?
4. Should we implement `--log-mode` (generate log without vim)?
5. Are there features that should be REMOVED instead of restored?
6. Is ~39 hours of effort acceptable, or should we prioritize a subset?
