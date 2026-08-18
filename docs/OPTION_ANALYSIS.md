# diffvim Option Analysis & Refactoring Proposal

**Date:** 2026-08-16
**Status:** Analysis and design only — no code changes proposed for
implementation yet.
**Scope:** All 95+ CLI options across `diffvim`, `diffvim-tmux`,
`diffvim.pl`, and the `diffvim-compute-cpp` tool.

> **Update (Phase A–C refactor):** Several of the proposals below were
> overtaken by events. The `--tool`/`--compute-tool` flags and the
> `--auto-precompute` flag were **removed** entirely (only the C++
> compute tool remains; diffvim searches for it automatically).
> `--algorithm myers` was also removed. See the [Unreleased] entry in
> `CHANGELOG.md` for the full list of changes.

---

## 1. Methodology

Every CLI option in the project was extracted from the `--help` output
and the argument-parsing code. Each option was then classified by the
**base operation** it controls — the fundamental thing the option
tweaks. Options that tweak the same base operation at different
granularities (e.g. enable flag + threshold + timing parameter) are
grouped together.

The goal is to find a small set of **orthogonal base operations** —
operations that don't overlap with each other — and then map every
current option onto exactly one base operation.

---

## 2. Current Option Inventory

**Total unique CLI options:** 95 (excluding `--help`/`--version`).

Grouped by current naming prefix:

| Prefix                     | Count | What it controls                         |
| -------------------------- | ----- | ---------------------------------------- |
| `--accel-delete*`          | 4     | Accelerated block deletion               |
| `--adaptive*`              | 6     | Adaptive timing & pacing                 |
| `--adaptive-word-delete*`  | 7     | Word-by-word deletion                    |
| `--algorithm`              | 1     | Diff algorithm                           |
| `--auto-precompute`        | 1     | Auto-compute externally                  |
| `--block-delete-size`      | 1     | Block deletion granularity               |
| `--compute-tool`           | 1     | External compute tool selection          |
| `--context`                | 1     | Context lines around hunks               |
| `--delete-end-first*`      | 4     | Trailing-delete reordering               |
| `--dim-unchanged*`         | 2     | Dim unchanged regions                    |
| `--dry-run`                | 1     | Print diff without animating             |
| `--fold-unchanged`         | 1     | Fold unchanged regions                   |
| `--from` / `--to`          | 2     | Git revision range                       |
| `--gaussian-jitter*`       | 2     | Human-like timing jitter                 |
| `--git-blame`              | 1     | Show git blame                           |
| `--git-rev`                | 1     | Git revision range shorthand             |
| `--highlight-*`            | 10    | Various highlighting modes               |
| `--indent-aware`           | 1     | Indent-aware diffing                     |
| `--keep-dirty`             | 1     | Buffer modified state after animation    |
| `--language`               | 1     | Language hint                            |
| `--left-to-right*`         | 2     | Left-to-right op ordering                |
| `--line-change-pause-ms`   | 1     | Pause at line boundaries                 |
| `--log-*`                  | 2     | Logging output                           |
| `--max-hunk-chars`         | 1     | Skip char-by-char for large hunks        |
| `--max-line-len`           | 1     | Warn on long lines                       |
| `--max-word-chars`         | 1     | Type short words instantly               |
| `--multi`                  | 1     | Multi-file mode                          |
| `--no-*`                   | 5     | Disable flags                            |
| `--optimize-sequence*`     | 2     | Op reordering                            |
| `--output`                 | 1     | Write result to file                     |
| `--overwrite`              | 1     | In-place overwrite mode                  |
| `--pause-after-*`          | 4     | Pauses after N lines / after delete      |
| `--pause-before-delete-ms` | 1     | Pause before delete                      |
| `--precomputed`            | 1     | Use precomputed diff file                |
| `--preset`                 | 1     | Named option bundle                      |
| `--rapid-eol-*`            | 3     | Rapid end-of-line deletion               |
| `--rapid-identical-*`      | 3     | Rapid identical-char deletion            |
| `--replay`                 | 1     | Git history replay                       |
| `--scroll`                 | 1     | Cursor scroll position                   |
| `--semantic-cleanup`       | 1     | Semantic cleanup                         |
| `--sign-column`            | 1     | Sign column +/- markers                  |
| `--speed`                  | 1     | Speed multiplier                         |
| `--startup-*`              | 2     | Startup feedback / pause                 |
| `--step-mode`              | 1     | Step-through mode                        |
| `--theme`                  | 1     | Color theme                              |
| `--word-accel*`            | 3     | Word acceleration                        |
| `--word-diff`              | 1     | Word-level diffing                       |
| `--word-end-pause-ms`      | 1     | Pause after word                         |
| `--word-pause-ms`          | 1     | Pause after instant word                 |

---

## 3. The 10 Base Operations

After cross-referencing every option against every other option, the
95 current options all tweak one of these 10 fundamental operations:

### Base Operation 1: DIFF ALGORITHM

**What it does:** Chooses which algorithm computes the line-level
and char-level diff.

**Current options mapping to this:**
- `--algorithm patience`
- `--word-diff` (changes char-level diff to token-level)
- `--indent-aware` (changes how indent-only changes are diffed)
- `--semantic-cleanup` (post-diff merge of adjacent del/ins pairs)
- `--language` (hints to the algorithm)

(Myers was removed: it OOMs on 15K-line files and produces the same
op count as LCS.)

**Problem:** `--word-diff` and `--indent-aware` are mixed concerns.
They change both the diff algorithm AND the animation (e.g.
`--word-diff` also batches word runs in the animator). Should be
split: algorithm options affect only the diff; animation options
affect only the animation.

---

### Base Operation 2: POST-PROCESSING (op reordering)

**What it does:** Reorders the raw char ops from the diff algorithm
to make the animation more readable.

**Current options mapping to this:**
- `--optimize-sequence` / `--no-optimize-sequence`
- `--left-to-right` / `--no-left-to-right`
- `--delete-end-first`
- `--delete-end-first-smart`
- `--delete-end-first-delay-ms`
- `--delete-end-first-highlight-ms`
- `--overwrite`

**Problem:** `--delete-end-first`, `--delete-end-first-smart`, and
`--overwrite` are three different post-processing strategies that
overlap in what they do (reorder ops on a line). They should be
**modes of a single `--op-order` option**:

```
--op-order natural        # raw LCS order (no post-processing)
--op-order optimize       # deletes before inserts (current default)
--op-order left-to-right  # keeps, then deletes, then inserts
--op-order end-first      # trailing deletes first
--op-order end-first-smart # trailing deletes first + word batching
--op-order overwrite      # in-place replacement
```

---

### Base Operation 3: DELETION PACING

**What it does:** Controls how fast deletes happen and whether they
accelerate.

**Current options mapping to this:**
- `--rapid-eol-delete` / `--no-rapid-eol-delete` / `--rapid-eol-delay-ms` / `--rapid-eol-min-chars`
- `--rapid-identical-chars` / `--rapid-identical-min` / `--rapid-identical-accel`
- `--accel-delete` / `--accel-delete-start-ms` / `--accel-delete-min-ms` / `--accel-delete-accel`
- `--adaptive-word-delete` (7 sub-options)
- `--block-delete-size`
- `--pause-before-delete-ms`
- `--pause-after-delete-ms`
- `--word-accel` / `--word-accel-delete-pct`

**Problem:** This is the most over-optioned area. There are **five
different acceleration/deletion strategies** (rapid-EOL,
rapid-identical, accel-delete, adaptive-word-delete, word-accel),
each with 3-7 sub-options. They overlap heavily — all of them
control "how fast to delete characters." Should be unified into a
single **deletion pacing policy**:

```
--delete-pacing char       # one char at a time (current default)
--delete-pacing rapid-eol  # rapid shot at end of line
--delete-pacing accel      # accelerate through long runs
--delete-pacing word       # word-by-word with acceleration
--delete-pacing instant    # delete everything at once
```

Plus tuning parameters:
```
--delete-speed slow|normal|fast|instant
--delete-threshold N       # min chars to trigger rapid/word mode
```

---

### Base Operation 4: INSERTION PACING

**What it does:** Controls how fast inserts happen.

**Current options mapping to this:**
- `--max-word-chars` (type short words instantly)
- `--word-pause-ms` (pause after instant word)
- `--word-end-pause-ms` (pause after completing a word)
- `--word-accel` (accelerate char-by-char inserts)

**Problem:** Four options for insertion pacing, overlapping with
`--word-accel` which also controls deletion. Should be unified:

```
--insert-pacing char       # one char at a time
--insert-pacing word       # batch short words
--insert-pacing accel      # accelerate through long inserts
```

---

### Base Operation 5: TIMING

**What it does:** Controls the raw timing of animation events.

**Current options mapping to this:**
- `--speed`
- `--adaptive` / `--adaptive-start-ms` / `--adaptive-max-ms` / `--adaptive-accel` / `--adaptive-pause-lines` / `--adaptive-pause-ms`
- `--adaptive-timing`
- `--line-change-pause-ms`
- `--gaussian-jitter` / `--gaussian-jitter-pct`
- `--startup-pause` / `--no-startup-pause`
- `--pause-after-lines` / `--pause-after-ms` / `--pause-after-threshold`

**Problem:** `--adaptive` (6 sub-options) and `--adaptive-timing`
are different things — one is about slowing down in complex regions,
the other is about line-count-based pausing. Both are "timing"
but they overlap conceptually. Should be unified:

```
--pacing uniform           # fixed delays
--pacing adaptive          # slow down in complex regions
--pacing gaussian          # add human-like jitter
--pacing review            # pause after each hunk
```

Plus base timing:
```
--speed N                  # global multiplier (keep)
--char-delay N             # ms per char (replaces type_delay_ms)
--hunk-pause N             # ms between hunks
--line-pause N             # ms at line boundaries
```

---

### Base Operation 6: HIGHLIGHTING

**What it does:** Visual cues to draw attention to changes.

**Current options mapping to this:**
- `--highlight-word` / `--highlight-word-color` / `--highlight-word-duration-ms` / `--highlight-word-min-chars`
- `--highlight-hunk`
- `--highlight-inline` / `--highlight-inline-duration-ms`
- `--highlight-color` / `--highlight-duration-ms` / `--highlight-min-chars`
- `--sign-column`
- `--dim-unchanged` / `--dim-unchanged-pct`
- `--theme`

**Problem:** Three different highlight modes (`word`, `hunk`,
`inline`) plus a generic `highlight-color`/`duration`/`min-chars`
that's probably dead code. Should be unified:

```
--highlight none           # no highlighting
--highlight inline         # highlight freshly typed/deleted chars
--highlight word           # highlight the word about to change
--highlight hunk           # highlight the entire hunk
--highlight-color insert:#3fb950 delete:#f85149
--highlight-duration N     # ms before highlight fades
```

And:
```
--dim-unchanged N          # 0-100% opacity for unchanged lines
--sign-column on|off       # +/- markers
```

---

### Base Operation 7: VIEWPORT (scroll & fold)

**What it does:** Controls what part of the file is visible.

**Current options mapping to this:**
- `--scroll zz|zt|zb|none`
- `--fold-unchanged`
- `--context N`

**Problem:** `--fold-unchanged` and `--context N` are the same
concept (how much context to show around changes). Should be unified:

```
--scroll zz|zt|zb|none     # cursor position (keep)
--context N                # context lines around hunks (0 = fold all)
```

Remove `--fold-unchanged` (it's `--context 0`).

---

### Base Operation 8: INPUT SOURCE

**What it does:** Where the diff comes from.

**Current options mapping to this:**
- Positional `<oldfile> <newfile>`
- `--multi`
- `--replay` / `--from` / `--to`
- `--git-rev`
- `--precomputed`
- `--diff FILE`
- `--auto-precompute` / `--compute-tool` (removed in Phase B refactor)

**Problem:** Too many ways to specify the input. Should be unified
into a single **input mode**:

```
diffvim <old> <new>                           # two-file mode (default)
diffvim --git REV..REV <file>                 # git history
diffvim --precomputed FILE <old> <new>        # precomputed diff
diffvim --diff FILE                           # unified diff input
diffvim --multi <o1:n1> <o2:n2> ...           # multi-file
```

Remove `--auto-precompute` (just use `diffvim-precomputed` wrapper).
Remove `--compute-tool` (use the wrapper).
Remove `--from`/`--to` (use `--git REV..REV`).

---

### Base Operation 9: OUTPUT & BUFFER STATE

**What it does:** What happens after the animation.

**Current options mapping to this:**
- `--output FILE`
- `--keep-dirty`
- `--dry-run`
- `--log-mode` / `--log-file`
- `--no-log-timing`

**Problem:** Clean as-is, just rename for consistency:

```
--output FILE              # save result (keep)
--keep-dirty               # don't mark nomodified (keep)
--dry-run                  # print diff, don't animate (keep)
--log FILE                 # log file (rename from --log-file)
--log-mode text|json|none  # log format (extend)
```

---

### Base Operation 10: ENVIRONMENT & DEBUGGING

**What it does:** Environment setup, debugging, and meta-options.

**Current options mapping to this:**
- `--no-vimrc`
- `--startup-feedback`
- `--max-line-len`
- `--step-mode`
- `--preset`
- `--debug`
- `--no-log-timing`

**Problem:** Clean as-is. These are all genuinely orthogonal:

```
--no-vimrc                 # isolated mode (keep)
--step-mode                # step-through (keep)
--preset NAME              # option bundle (keep)
--debug                    # verbose output (keep)
--max-line-len N           # warning threshold (keep)
--startup-feedback         # progress indicator (keep)
```

---

## 4. Summary: Base Operations Table

| #  | Base Operation        | Current options | Proposed unified interface                          |
| -- | --------------------- | --------------- | --------------------------------------------------- |
| 1  | Diff algorithm        | 5               | `--algorithm`, `--word-diff`, `--indent-aware`      |
| 2  | Post-processing       | 7               | `--op-order MODE` (6 modes)                         |
| 3  | Deletion pacing       | 20              | `--delete-pacing MODE` + `--delete-speed` + `--delete-threshold` |
| 4  | Insertion pacing      | 4               | `--insert-pacing MODE`                              |
| 5  | Timing                | 10              | `--pacing MODE` + `--speed` + `--char-delay` + `--hunk-pause` + `--line-pause` |
| 6  | Highlighting          | 10              | `--highlight MODE` + `--highlight-color` + `--highlight-duration` + `--dim-unchanged` + `--sign-column` + `--theme` |
| 7  | Viewport              | 3               | `--scroll` + `--context`                            |
| 8  | Input source          | 9               | 5 input modes (positional, `--git`, `--precomputed`, `--diff`, `--multi`) |
| 9  | Output & buffer       | 5               | `--output`, `--keep-dirty`, `--dry-run`, `--log`    |
| 10 | Environment & debug   | 7               | `--no-vimrc`, `--step-mode`, `--preset`, `--debug`, `--max-line-len`, `--startup-feedback` |

**Total proposed top-level options:** ~25 (down from 95).
**Total proposed sub-parameters:** ~15 (timing tuning, colors, etc.).
**Grand total:** ~40 options (down from 95).

---

## 5. Overlap Analysis — Detailed

### Overlap 1: `--word-diff` is two things

`--word-diff` currently:
1. Changes the diff algorithm (token-level LCS instead of char-level)
2. Changes the animation (batches word runs with `LookaheadSameTypeRun`)

**Proposed split:**
- `--algorithm word` — changes the diff only
- `--insert-pacing word` — changes the animation only

### Overlap 2: `--word-accel` is two things

`--word-accel` currently:
1. Accelerates char-by-char inserts
2. Accelerates char-by-char deletes (via `--word-accel-delete-pct`)

**Proposed split:**
- `--insert-pacing accel`
- `--delete-pacing accel` (with `--delete-speed` for the pct tuning)

### Overlap 3: Five deletion strategies overlap

All of these control "how fast to delete":
- `--rapid-eol-delete` (rapid shot at EOL)
- `--rapid-identical-chars` (accelerate identical runs)
- `--accel-delete` (accelerate multi-line blocks)
- `--adaptive-word-delete` (word-by-word)
- `--delete-end-first-smart` (word-by-word for trailing deletes)

**Proposed unification:** `--delete-pacing MODE` where MODE is one
of: `char`, `rapid-eol`, `rapid-identical`, `accel`, `word`,
`instant`. The threshold and speed are controlled by
`--delete-threshold` and `--delete-speed`.

### Overlap 4: `--adaptive` vs `--adaptive-timing`

`--adaptive` (6 sub-options) controls line-count-based pausing.
`--adaptive-timing` controls complexity-based delay adjustment.

**Proposed unification:** `--pacing adaptive` for complexity-based,
`--pacing review` for line-count-based pausing.

### Overlap 5: `--delete-end-first` vs `--delete-end-first-smart` vs `--overwrite`

All three reorder ops on a line. They should be modes of `--op-order`:
- `--op-order end-first` (current `--delete-end-first`)
- `--op-order end-first-smart` (current `--delete-end-first-smart`)
- `--op-order overwrite` (current `--overwrite`)

### Overlap 6: `--fold-unchanged` vs `--context N`

`--fold-unchanged` is `--context 0`. Remove `--fold-unchanged`.

### Overlap 7: `--from`/`--to` vs `--git-rev`

`--git-rev REV..REV` is shorthand for `--from REV1 --to REV2`.
Remove `--from`/`--to`, keep only `--git REV..REV`.

### Overlap 8: `--auto-precompute` vs `--precomputed` vs `--compute-tool`

`--auto-precompute` = run the compute tool then use `--precomputed`.
`--compute-tool` = which tool to use for `--auto-precompute`.
**Proposed:** Remove both. Use the `diffvim-precomputed` wrapper
script instead.

---

## 6. Proposed Refactored Option Scheme

### Diff algorithm (Base Op 1)
```
--algorithm patience              # diff algorithm (default: patience)
--indent-aware                          # treat indent-only changes specially
--semantic-cleanup                     # merge adjacent del/ins pairs
```

### Post-processing (Base Op 2)
```
--op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite
                                        # op reordering (default: optimize)
```

### Deletion pacing (Base Op 3)
```
--delete-pacing char|rapid-eol|rapid-identical|accel|word|instant
                                        # deletion strategy (default: rapid-eol)
--delete-speed slow|normal|fast|instant # speed multiplier for deletes
--delete-threshold N                    # min chars to trigger rapid/word (default: 3)
```

### Insertion pacing (Base Op 4)
```
--insert-pacing char|word|accel         # insertion strategy (default: char)
--insert-speed slow|normal|fast         # speed multiplier for inserts
```

### Timing (Base Op 5)
```
--pacing uniform|adaptive|gaussian|review
                                        # global pacing mode (default: uniform)
--speed N                               # global speed multiplier
--char-delay N                          # ms per char (default: 50)
--delete-delay N                        # ms per deleted char (default: 40)
--hunk-pause N                          # ms between hunks (default: 250)
--line-pause N                          # ms at line boundaries (default: 200)
```

### Highlighting (Base Op 6)
```
--highlight none|inline|word|hunk       # highlight mode (default: none)
--highlight-color insert:COLOR delete:COLOR  # colors
--highlight-duration N                  # ms before fade (default: 200)
--dim-unchanged N                       # 0-100 opacity (default: 100)
--sign-column                           # +/- markers
--theme NAME                            # color theme
```

### Viewport (Base Op 7)
```
--scroll zz|zt|zb|none                  # cursor position (default: zz)
--context N                             # context lines (0 = fold all, default: 3)
```

### Input source (Base Op 8)
```
<oldfile> <newfile>                     # two-file mode (default)
--git REV..REV <file>                   # git history replay
--precomputed FILE <old> <new>          # precomputed diff
--diff FILE                             # unified diff input
--multi <o1:n1> <o2:n2> ...             # multi-file
```

### Output & buffer (Base Op 9)
```
--output FILE                           # save result
--keep-dirty                            # don't mark nomodified
--dry-run                               # print diff, don't animate
--log FILE                              # log file
--log-mode text|json|none               # log format
```

### Environment & debug (Base Op 10)
```
--no-vimrc                              # isolated mode
--step-mode                             # step-through
--preset NAME                           # option bundle
--debug                                 # verbose output
--max-line-len N                        # warning threshold
--startup-feedback                      # progress indicator
```

---

## 7. Migration Strategy

The refactoring should be **backward-compatible** — old options
continue to work but are deprecated.

### Phase 1: Add new unified options (no removal)
- Add `--op-order`, `--delete-pacing`, `--insert-pacing`, `--pacing`,
  `--highlight` as new top-level options.
- Each new option maps internally to the existing options it
  replaces.
- Old options continue to work unchanged.

### Phase 2: Deprecation warnings
- When an old option is used, print a deprecation warning to stderr
  suggesting the new equivalent.
- Example: `--delete-end-first-smart` → `warning: --delete-end-first-smart is deprecated, use --op-order end-first-smart`

### Phase 3: Remove old options (after 2 release cycles)
- Remove all deprecated options.
- Update presets to use only the new options.
- Update documentation.

### Phase 4: Update presets
The six presets become much simpler:

```
default:      (no flags)
fast-delete:  --delete-pacing word --delete-threshold 3
review:       --pacing review --highlight hunk --dim-unchanged 50 --scroll zt
ai-code:      --op-order end-first-smart --highlight inline --algorithm word
demo:         --pacing gaussian --speed 0.7 --highlight inline
presentation: --speed 1.2 --scroll zz --delete-pacing char
```

---

## 8. Comparison: Before vs After

| Metric                      | Current | Proposed |
| --------------------------- | ------- | -------- |
| Total CLI options           | 95      | ~40      |
| Top-level options           | 95      | ~25      |
| Sub-parameters              | 0       | ~15      |
| Deletion strategies         | 5 (overlapping) | 1 (with 6 modes) |
| Insertion strategies        | 4 (overlapping) | 1 (with 3 modes) |
| Highlight modes             | 3 (overlapping) | 1 (with 4 modes) |
| Post-processing modes       | 3 (overlapping) | 1 (with 6 modes) |
| Options a newcomer must learn | 95    | 6 (the 6 base operations) |

---

## 9. Base Operations Are Orthogonal

Each base operation controls a different aspect of the animation:

| Base Operation        | What it controls                    | Independent of...        |
| --------------------- | ----------------------------------- | ------------------------ |
| Diff algorithm        | Which chars are marked as changed   | How they're animated     |
| Post-processing       | Order of ops within a line          | Which chars are changed  |
| Deletion pacing       | Speed of delete animation           | Order of ops             |
| Insertion pacing      | Speed of insert animation           | Order of ops             |
| Timing                | Global speed and pauses             | Individual char pacing   |
| Highlighting          | Visual cues                         | Everything else          |
| Viewport              | What's visible                      | Everything else          |
| Input source          | Where the diff comes from           | Everything else          |
| Output & buffer       | What happens after                  | Everything else          |
| Environment & debug   | Meta-options                        | Everything else          |

No two base operations overlap. Every current option maps to exactly
one base operation. This is the key property that makes the
refactoring clean.

---

## 10. Conclusion

The current 95 options reduce to **10 orthogonal base operations**
with ~40 total options (25 top-level + 15 sub-parameters). The
reduction comes from:

1. **Unifying overlapping strategies** — 5 deletion strategies → 1
   `--delete-pacing` with 6 modes
2. **Separating concerns** — `--word-diff` splits into `--algorithm
   word` (diff) and `--insert-pacing word` (animation)
3. **Removing redundancy** — `--fold-unchanged` = `--context 0`,
   `--from`/`--to` = `--git REV..REV`
4. **Delegating to wrapper scripts** — `--auto-precompute` and
   `--compute-tool` replaced by `diffvim-precomputed`

The proposed scheme is backward-compatible (old options work during
a deprecation period), reduces the learning curve from 95 options
to 6 base operations, and eliminates all identified overlaps.
