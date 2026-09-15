# Layer-Centric Strategy — Fix the Categorizers, Don't Remove Them

## Correction to the previous strategy

My earlier proposal said "deprecate most layers, replace with a
categorizer + renderers." That was wrong. The layers **are** the
categorization mechanism — each layer recognizes one edit category
and transforms its ops to match a human typing pattern. The
architecture is correct. What's wrong is:

1. Some layers are **broken** — they don't fire when their category
   appears, or they fire and produce wrong output.
2. Some categories have **no layer** — `block_move`, multi-cursor
   `rename`, `block_modify` at the structural level.
3. We have **no tests** that catch "looks bad" patterns — only
   `snap == target`, which is necessary but not sufficient.
4. The layers operate on **char ops after the LCS has already split
   changes at the wrong places** — so even when a layer fires, the
   input it gets may not match its recognition pattern.

This strategy keeps the pipeline (`compute → postprocess(layers) →
pace → animate`) and the layer architecture. It fixes the layers,
fills the gaps, and adds the missing tests.

---

## Evidence from the corpus analysis

I analyzed **3,215 hunks** from three sources:

| Source | Hunks |
|---|---:|
| gitanim's own git history (200 commits) | 3,129 |
| tests/examples/* (41 cases) | 62 |
| tests/minimal/* (27 cases) | 24 |

### Edit category histogram

| Category | Count | % | Has a layer? | Layer works? |
|---|---:|---:|---|---|
| `block_modify` | 758 | 23.6% | partial | **broken** — 6 flicker + 15 unmerged pairs survive |
| `block_insert` | 608 | 18.9% | `batch_whitespace` | partial — only batches whitespace, not content |
| `word_replace` | 603 | 18.8% | `overwrite`, `line_replace` | **broken** — `overwrite` doesn't fire; `line_replace` crashes |
| `block_replace` | 347 | 10.8% | `line_replace` | **broken** — `line_replace` produces 0 ops |
| `literal_replace` | 222 | 6.9% | `overwrite` | **broken** — same as `word_replace` |
| `block_delete` | 180 | 5.6% | `line_delete_in_place` | partial — works for simple cases, fails on multi-line |
| `typo_fix` | 166 | 5.2% | `overwrite` | works (small enough that 1 insert suffices) |
| `line_expand` | 64 | 2.0% | `split_in_place` | works |
| `block_move` | 63 | 2.0% | **none** | **gap** |
| `line_replace` | 53 | 1.6% | `line_replace` | **broken** |
| `line_insert` | 53 | 1.6% | (none needed) | works |
| `line_delete` | 45 | 1.4% | `line_delete_in_place` | works |
| `format_only` | 26 | 0.8% | `skip_indent` (partial) | works |
| `line_collapse` | 26 | 0.8% | `join_insert_in_place` | works |
| `indent_change` | 1 | 0.0% | `indent_last`, `skip_indent` | works (but rare in corpus) |

**Coverage:** 7 of 15 categories have a working layer. 5 have a
broken layer. 3 have a gap. The top 3 categories by frequency
(`block_modify`, `block_insert`, `word_replace` = 61% of all hunks)
are all partially or fully broken.

### The smoking gun: `hello → greet` with `ad_layer_overwrite`

Input op stream (from `ad_compute`):

```
delete  1  5  'h'
insert  1  5  'g'
insert  1  6  'r'
keep    1  7  'e'
delete  1  8  'l'
delete  1  8  'l'
delete  1  8  'o'
insert  1  8  'e'
insert  1  9  't'
```

Output of `ad_layer_overwrite`:

```
delete  1  5  'h'      ← unchanged
insert  1  5  'g'      ← unchanged
insert  1  6  'r'      ← unchanged
keep    1  7  'e'
delete  1  8  'l'      ← unchanged
delete  1  8  'l'      ← unchanged
delete  1  8  'o'      ← unchanged
insert  1  8  'e'      ← unchanged
insert  1  9  't'      ← unchanged
```

**The overwrite layer did nothing.** Its description says it "detects
adjacent delete+insert at the same (line, col) and merges them into
`overwrite_insert`." The first pair (`delete 1 5 'h'` + `insert 1 5
'g'`) is exactly that pattern — adjacent, same line, same col. The
layer should have produced `overwrite_insert 1 5 'g'` + `insert 1 6
'r'`. It didn't.

This is a real bug in the layer, not an architectural problem. The
fix is in the layer.

---

## Per-layer diagnosis and fix plan

### 1. `ad_layer_reorder` — works, but doesn't go far enough

**Status:** Works. Passes all 68 corpus cases.

**Diagnosis:** Reorders within segments (deletes before inserts).
This is necessary but the result still has the LCS's bad splits.

**Fix:** None needed in the layer itself. The fix is upstream — see
"compute-level fixes" below.

### 2. `ad_layer_overwrite` — **broken, top priority**

**Status:** Does not fire on the most common case it's designed for.

**Diagnosis:** Reading `layers/c/ad_layer_overwrite.c`, the layer
looks for adjacent `delete` + `insert` at the same `(line, col)`. The
LCS produces this pattern, but the layer's recognition condition is
too strict — likely requires exact 1:1 pairing (one delete + one
insert at the same position), so it doesn't handle:
- 1 delete + 2 inserts (`h` → `gr`)
- 3 deletes + 2 inserts (`llo` → `et`)
- Pairs separated by a `keep` (the shared `e`)

**Fix:**
1. Read `layers/c/ad_layer_overwrite.c` end-to-end and identify the
   exact match condition.
2. Relax to: any maximal run of `delete` ops at line L followed by a
   maximal run of `insert` ops at the same line L (regardless of col
   alignment) becomes `overwrite_insert` ops with the new content.
3. Add a structural test: for `hello → greet`, assert the output
   contains 0 `delete` ops and 1+ `overwrite_insert` ops.
4. Verify the fix doesn't break the 68 corpus cases.

**Test to add:** `tests/test_layer_overwrite_word_replace.pl` — runs
the `hello → greet` case and asserts the op stream has 0 standalone
`delete` ops and at least 2 `overwrite_insert` ops.

### 3. `ad_layer_line_replace` — **broken, produces 0 ops**

**Status:** For most categories, the layer produces an op stream
that the animator rejects (snapshot mismatch). For some it produces
0 ops.

**Diagnosis:** The layer is supposed to collapse any line with at
least one delete/insert into `delete_line` + `insert_line` ops. The
op stream it produces looks right (e.g. for `hello → greet` it
produces `delete_line 1` + `insert_line 1 def greet():`), but the
animator's snapshot doesn't match. Either:
- The animator doesn't recognize `delete_line`/`insert_line` correctly
- The line numbers are off
- The op format is wrong

**Fix:**
1. Run `ad_layer_line_replace` on `01_simple_replace` (the simplest
   case) and trace what the animator does with the `delete_line` +
   `insert_line` ops.
2. Compare against what `ad_layer_line_delete_in_place` produces for
   the same case (which works).
3. Fix the op format or the animator's interpretation, whichever is
   wrong.
4. Add a structural test: for `01_simple_replace`, assert the output
   snapshot matches.

**Test to add:** `tests/test_layer_line_replace_basic.pl` — runs
`01_simple_replace` through `line_replace` and asserts snapshot ==
target.

### 4. `ad_layer_indent_last` — works, but only fires on a narrow pattern

**Status:** Works for its specific pattern (whitespace deletes at
start of segment). Doesn't fire on `block_modify` where indent
changes are mixed with content changes.

**Diagnosis:** The layer only handles the case where the segment
*starts* with whitespace deletes. If the segment has interleaved
content and whitespace deletes, the layer doesn't fire.

**Fix:**
1. Generalize: extract all whitespace deletes from anywhere in the
   segment, move them to the end (after content deletes), adjust
   cols on the content ops.
2. Test on `18_indent_change` (current minimal case) and a synthetic
   mixed case.

### 5. `ad_layer_line_delete_in_place` — works for single-line, breaks on multi-line

**Status:** Works for `line_delete` (1.4% of corpus). For
`block_delete` (5.6%), the audit shows 0 ops in the output —
suggesting the layer only handles single-line deletes.

**Fix:** Generalize to multi-line: when N consecutive lines are
deleted, delete content of line 1, then join, then delete content of
line 2, etc. — without ever pulling content up before it's deleted.

### 6. `ad_layer_split_in_place` — works

**Status:** Works for `line_expand` (2.0%).

**Fix:** None needed.

### 7. `ad_layer_join_insert_in_place` — works

**Status:** Works for `line_collapse` (0.8%).

**Fix:** None needed.

### 8. `ad_layer_batch_whitespace` — works, but only batches whitespace

**Status:** Works. The audit shows it reduces `block_insert` from
210 ops to 177 ops (batching whitespace runs).

**Diagnosis:** Only batches whitespace. Doesn't batch content
inserts. For `block_insert` (18.9% of corpus), most of the 210 ops
are content characters that get typed one at a time.

**Fix:** Optional — add a sibling layer `ad_layer_batch_insert` that
batches consecutive non-whitespace inserts into a single
`batch_insert` op (analogous to `batch_whitespace`). The animator
would render `batch_insert` as a fast type-ahead.

**Risk:** This trades animation detail for speed. May not be wanted
for all cases. Make it opt-in.

### 9. `ad_layer_skip_indent` — works

**Status:** Works for `indent_change` (rare in corpus).

**Fix:** None needed.

### 10. `ad_layer_pace` — orthogonal, works

**Status:** Adds delays. Doesn't modify ops.

**Fix:** None needed.

### 11. `ad_layer_highlight` — orthogonal, works

**Status:** Adds decoration.

**Fix:** None needed.

---

## Gap layers to add

### Gap 1: `ad_layer_block_move` (new) — for `block_move` (2.0%)

**Problem:** When N lines are deleted at position A and the same N
lines are inserted at position B, the current pipeline treats them
as independent `block_delete` + `block_insert`. The animation
visually types the block twice (once disappearing, once appearing).

**New layer:** Detect cut-paste patterns. When a run of ≥2 deleted
lines reappears (textually identical) as a run of inserted lines
elsewhere in the same hunk set, mark both runs with a `move_id` op.
The animator renders the move as: source block fades, cursor jumps
to dest, dest block materializes.

**Detection:** Reuse the move-detection logic from
`analysis/edit_corpus_analysis.py` (lines 122-160) — it already
correctly identifies 63 moves in the corpus.

**Animator change:** Add `move_start <id>` and `move_end <id>` ops
to the animator's recognized op set. Render `move_start` as a brief
highlight + fade, `move_end` as materialization.

**Test:** `tests/test_layer_block_move.pl` — synthetic case with a
3-line block moved; assert the op stream contains exactly one
`move_start`/`move_end` pair and 0 standalone `delete`/`insert` for
the moved lines.

### Gap 2: `ad_layer_word_replace` (new) — for `word_replace` (18.8%)

**Problem:** Even after fixing `ad_layer_overwrite`, the LCS still
splits `hello → greet` at the shared `e`. The overwrite layer
patches the result, but the underlying op stream is still
char-granular. A dedicated `word_replace` layer could detect "this
hunk is one line, one word changed" and emit `select_word` +
`overwrite_insert` ops directly, bypassing the char-level split.

**New layer:** For each hunk where:
- Exactly 1 old line, 1 new line
- Word-level diff produces exactly 1 word-pair replacement
- Surrounding words are identical

Emit: `select <line> <col_start> <col_end>` + `overwrite_insert
<line> <col_start> <new_word_chars>`.

**Animator change:** Add `select` op (brief highlight of a range
without modifying it).

**Why this is a layer and not a compute change:** The compute engine
is language-agnostic and produces minimal char diffs. The
`word_replace` layer is a *recognition* layer that says "this
char-diff pattern is semantically one word replacement, render it
as such." That's exactly what layers are for.

**Test:** `tests/test_layer_word_replace.pl` — `hello → greet`
produces exactly 1 `select` + 1 `overwrite_insert`, 0 `delete`.

### Gap 3: `ad_layer_block_modify` (new) — for `block_modify` (23.6%)

**Problem:** The largest category. Current pipeline produces 6
interleave flickers + 15 unmerged pairs per case on average. The
fix isn't one layer — it's a *composite* pattern: identify that a
hunk is multi-line modify, then apply per-line `word_replace`
recognition to each modified line.

**New layer:** For each hunk where:
- ≥2 old lines, ≥2 new lines
- Same line count (or close)
- Per-line word overlap ≥ 0.5

Decompose into N independent per-line `word_replace` operations,
emit them line-by-line. This is what a human does — edits each line
in sequence, not char-by-char across the whole block.

**Test:** `tests/test_layer_block_modify.pl` — assert 0 interleave
flickers in the output op stream.

### Gap 4: `ad_layer_format_only` (new) — for `format_only` (0.8%)

**Problem:** Whitespace-only changes get animated char-by-char. A
human reformatting doesn't want to watch each space get added.

**New layer:** Detect hunks where all deletes and inserts are
whitespace. Wrap with `instant_apply` ops so the animator skips
animation for that hunk.

(Actually `ad_layer_skip_indent` already does this for indent-only
hunks. Generalize it to all-whitespace hunks.)

**Fix:** Rename/extend `ad_layer_skip_indent` → `ad_layer_skip_noise`
that handles both indent-only and whitespace-only hunks.

---

## Compute-level fixes (upstream of layers)

Some layer failures aren't the layer's fault — the compute engine
produces bad splits that no layer can fully recover from.

### Fix: word-boundary-aware LCS

The current LCS finds the longest common subsequence at character
level. For `hello → greet`, it finds `e` as common and splits there.
A word-boundary-aware LCS would find zero common *words* and emit a
single word-replacement op.

**Change in `diff_engine/cpp/compute.cpp`:** Add a `--word-diff`
mode (the flag already exists but is documented as not working). In
word-diff mode, the LCS operates on tokens (identifier-like runs)
instead of characters. The output op stream uses word-level ops
that the `word_replace` layer can directly consume.

**This is a big change.** Defer until the layer fixes are done and
we can measure how much the word-diff mode actually helps vs. the
`word_replace` layer alone.

---

## Test harness — the missing piece

We have **no tests** that catch "looks bad" patterns. The current
test suite only checks `snap == target`, which is necessary but not
sufficient. The audit's metrics (interleave flicker, unmerged
del-ins pairs) are exactly the tests we need.

### New test: `tests/test_op_stream_quality.pl`

For each corpus case, after running the pipeline, assert:

```perl
# 1. No interleave flicker within any line
#    (delete-insert-delete-insert pattern)
ok(!has_interleave_flicker($post_ops), "no flicker in $case");

# 2. No unmerged delete-insert pairs at same (line, col)
#    (delete X at (L,C) immediately followed by insert Y at (L,C)
#    should have been merged by ad_layer_overwrite)
ok(!has_unmerged_pairs($post_ops), "no unmerged pairs in $case");

# 3. Op count is reasonable (not 10x the line count)
ok(op_count($post_ops) <= 10 * line_count($new_file),
   "op count reasonable in $case");
```

This test would have caught every bug the user has reported, without
needing subjective "does it look good" judgments.

### New test: `tests/test_category_rendering.pl`

For each (category, representative case) pair, assert the op stream
matches a hand-written expected pattern. Example for `word_replace`:

```perl
# hello → greet
# Expected: 0 delete ops, ≥2 overwrite_insert ops (or 1 select + 1 overwrite_insert)
ok(op_count($post_ops, 'delete') == 0, "no deletes in word_replace");
ok(op_count($post_ops, 'overwrite_insert') >= 1, "has overwrite");
```

This is the test that would have caught the `ad_layer_overwrite`
bug at the head of this doc.

### New test: `tests/test_layer_audit.pl`

Re-implement `analysis/layer_audit.py` as a Perl test that runs in
CI. For each (category, layer) pair, run the pipeline and record
the metrics. Fail if any metric regresses from a baseline.

---

## Sequencing

| Phase | Effort | Output | Risk |
|---|---|---|---|
| 1. **Fix `ad_layer_overwrite`** | 1 day | `hello → greet` produces 0 deletes | low — narrow fix |
| 2. **Fix `ad_layer_line_replace`** | 1 day | `01_simple_replace` snapshot matches | low |
| 3. **Add `test_op_stream_quality.pl`** | 1 day | catches "looks bad" patterns in CI | low |
| 4. **Add `ad_layer_word_replace`** | 2 days | `word_replace` category rendered as select+overwrite | medium — new op type `select` |
| 5. **Generalize `ad_layer_line_delete_in_place` to multi-line** | 1 day | `block_delete` works | medium |
| 6. **Generalize `ad_layer_indent_last`** | 1 day | mixed indent+content works | low |
| 7. **Add `ad_layer_block_modify`** | 2 days | 23.6% of corpus fixed | medium — depends on `word_replace` layer |
| 8. **Add `ad_layer_block_move`** | 3 days | 2% of corpus fixed, but high visual impact | high — new op types `move_start`/`move_end` |
| 9. **Generalize `skip_indent` → `skip_noise`** | 0.5 days | format_only skipped | low |
| 10. **Word-boundary-aware LCS in compute** | 3 days | cleaner op streams for all layers | high — touches the C++ core |

**First visible win: Phase 1.** Fix `ad_layer_overwrite` so
`hello → greet` stops having 4 deletes + 4 inserts. That's a 1-day
fix that addresses the most common visible bug.

**Second visible win: Phase 4.** Add `ad_layer_word_replace` so
`word_replace` (18.8% of corpus) renders as select + overwrite
instead of backspace + retype.

**Third visible win: Phase 7.** `block_modify` (23.6%) gets
decomposed into per-line word_replaces.

After Phase 7, **61% of the corpus** (top 3 categories) is
fixed. That's the milestone to validate the direction before
tackling `block_move` (high risk, low frequency) or the compute
engine (high risk, broad impact).

---

## What stays the same

- Pipeline architecture: `compute → postprocess(layers) → pace → animate`
- Layer plugin contract (stdin → stdout op stream transformation)
- `ad_layer_pace` and `ad_layer_highlight` (orthogonal, working)
- `ad_layer_reorder` (working, foundational)
- The 68-case corpus as the regression suite
- The `ad_l1l2` diagnostic tool

## What changes

- 2 layers fixed (`overwrite`, `line_replace`)
- 2 layers generalized (`line_delete_in_place`, `indent_last`, `skip_indent`)
- 3 layers added (`word_replace`, `block_modify`, `block_move`)
- 1 compute engine change (word-boundary-aware LCS, deferred to last)
- 3 new test files (`op_stream_quality`, `category_rendering`, `layer_audit`)

## What I need from you

1. **Confirm the priority order.** I propose: overwrite → line_replace → tests → word_replace → block_modify → block_move. If you want a different order (e.g. block_move first because it's the most visually jarring), say so.
2. **Approve the new op types.** `select` (for word_replace), `move_start`/`move_end` (for block_move). These touch the animator C core. Without them, the new layers can't render their patterns.
3. **Decide on `ad_layer_batch_insert`.** It's optional — trades detail for speed. Should it be default-on or opt-in?
4. **Decide on the word-boundary-aware LCS.** It's the biggest single change and the highest impact, but also the highest risk. Defer to Phase 10, or pull it forward?

I'll start Phase 1 (fix `ad_layer_overwrite`) on confirmation. It's a 1-day fix with a clear test case (`hello → greet` should produce 0 deletes).
