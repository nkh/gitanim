# Layer Analysis & Fix Plan — Detailed Engineering Document

**Date:** 2026-09-15
**Status:** Awaiting decisions on questions at the end of each phase
**Prerequisite reading:** `docs/design/LAYERS_REVIEW.md`, `analysis/edit_corpus_summary.md`

---

## 1. What this document is

This is not a strategy doc. It is a per-layer engineering analysis with:
- The layer's documented contract (what it claims to do)
- The exact source code that implements it (line numbers, function names)
- A concrete failing test case (1-3 lines of input)
- The root cause of the failure (which code path doesn't fire and why)
- The fix design (which lines change, what the new logic is)
- The test that verifies the fix
- Acceptance criteria (binary pass/fail conditions)
- Risk assessment
- Open questions for you

Every claim here is verified by `tests/test_layer_contracts.pl`, which
runs in `make test` and currently reports **27 passed, 2 failed**.

---

## 2. Test infrastructure added

### 2.1 `tests/test_layer_contracts.pl` (new)

A contract test for each of the 9 postprocess layers. Each test case:
1. Hand-crafts a 1-3 line input op stream that exercises the layer's
   documented pattern.
2. Pipes it directly into the layer binary (NOT through the full
   pipeline).
3. Asserts properties of the OUTPUT op stream: op count, op type,
   op positions, ordering — NOT the animator's final snapshot.

**Why not snapshot tests:** The raw op stream from `ad_compute`
already produces the correct final buffer when run through the
animator. So `snap == target` passes with NO layer at all. It
cannot tell whether a layer fires. Contract tests can.

### 2.2 Makefile wiring

- New target `test-layer-contracts` — runs the contract tests with
  `set -o pipefail` so failures propagate through `tail`.
- Added to `test-layers` aggregate target.
- `test-layers` is already in the `test` target, so contract test
  failures now block `make test`.

### 2.3 Current test results

```
=== Layer contract results: 27 passed, 2 failed ===
Failed assertions:
  - expected 0 standalone deletes (got 4) — overwrite layer did not fire on multi-delete run
  - expected ≥2 overwrite_insert ops, got 0 — only single-pair merges detected
```

Both failures are in `ad_layer_overwrite` on the `hello → greet`
pattern. The other 7 layers pass their contract tests.

---

## 3. Corpus analysis summary

Analyzed **3,215 hunks** from gitanim's own git history (200 commits)
+ 68 test cases. Full data at `analysis/edit_corpus.csv` and
`analysis/edit_corpus_summary.md`.

| Category | % of hunks | Layer that should handle it | Status |
|---|---:|---|---|
| block_modify | 23.6% | (no single layer — needs decomposition) | **gap** |
| block_insert | 18.9% | batch_whitespace (partial) | partial |
| word_replace | 18.8% | overwrite, line_replace | **broken** |
| block_replace | 10.8% | line_replace | **broken** |
| literal_replace | 6.9% | overwrite | **broken** (same bug as word_replace) |
| block_delete | 5.6% | line_delete_in_place | partial (single-line only) |
| typo_fix | 5.2% | overwrite | works |
| line_expand | 2.0% | split_in_place | works |
| block_move | 2.0% | (none) | **gap** |
| line_replace | 1.6% | line_replace | **broken** |
| line_insert | 1.6% | (none needed) | works |
| line_delete | 1.4% | line_delete_in_place | works |
| format_only | 0.8% | skip_indent | works |
| line_collapse | 0.8% | join_insert_in_place | works |
| indent_change | 0.0% | indent_last, skip_indent | works |

**Top 3 categories (61% of corpus):** block_modify, block_insert,
word_replace. All three are partially or fully broken.

---

## 4. Per-layer analysis

### 4.1 `ad_layer_reorder` — WORKS

**Contract:** Within each segment (bounded by keeps and \n ops),
emit all deletes first, then all inserts, then debug ops. Boundaries
emitted in place.

**Source:** `layers/c/ad_layer_reorder.c`, function `layer_reorder`,
lines 23-70.

**Test case:** Interleaved `delete insert delete insert keep` →
should become `delete delete insert insert keep`.

**Result:** PASS. The 4-sweep algorithm correctly reorders.

**No fix needed.**

---

### 4.2 `ad_layer_overwrite` — BROKEN (2 test failures)

**Contract:** Merge adjacent `delete` + `insert` at the same
`(line, col)` into `overwrite_insert`.

**Source:** `layers/c/ad_layer_overwrite.c`, function
`layer_overwrite`, lines 14-64.

#### The bug

Lines 36-42 of `ad_layer_overwrite.c`:

```c
int next_is_insert_same_line = 0;
if (i + 2 < n_ops
    && strcmp(ops[i+2].type, "insert") == 0 && !ad_layer_is_line_op(&ops[i+2])
    && ops[i+2].line == ops[i+1].line) {
    next_is_insert_same_line = 1;
}
if (!prev_is_delete_same_pos && !next_is_insert_same_line) can_merge = 1;
```

**What this code does:** Before merging a `delete + insert` pair,
it checks if the op AFTER the insert (at index `i+2`) is also an
insert on the same line. If yes, it refuses to merge.

**Why this is wrong:** The guard was presumably added to prevent
"losing" the second insert when merging. But `overwrite_insert`
followed by `insert` is a perfectly valid op sequence — the
overwrite replaces one char, the insert adds another. There is no
information loss.

**Concrete failing case (`hello → greet`):**

Input op stream (from `ad_compute`):
```
delete  1  5  'h'
insert  1  5  'g'    ← should merge with delete above
insert  1  6  'r'    ← this is ops[i+2], triggers the guard
keep    1  7  'e'
delete  1  8  'l'
delete  1  8  'l'
delete  1  8  'o'
insert  1  8  'e'    ← should merge with the 3 deletes above
insert  1  9  't'    ← this is ops[i+2], triggers the guard again
```

For the first pair (`delete 1 5 'h'` + `insert 1 5 'g'`):
- `ops[i+2]` = `insert 1 6 'r'` — same line, is insert
- `next_is_insert_same_line = 1`
- `can_merge = 0` ← **merge blocked**

The layer emits the ops unchanged. **0 overwrite_insert ops
produced.** The animation does: backspace `h`, type `g`, type `r`,
leave `e`, backspace `l`, `l`, `o`, type `e`, type `t`. That's the
robotic pattern the user complains about.

#### Fix design

**Option A (minimal):** Remove the `next_is_insert_same_line` guard
entirely. Delete lines 36-42. The merge becomes: "any `delete` +
`insert` at the same `(line, col)` becomes `overwrite_insert`."

Risk: The guard may have been added to fix a different bug. Need to
check `git blame` and the test history. If the guard was added
without a test, remove it. If it was added to fix a real bug, that
bug needs a different fix.

**Option B (conservative):** Keep the guard but relax it. Only
block the merge if `ops[i+2]` is an insert at the SAME `(line, col)`
as `ops[i+1]` (truly overlapping), not just the same line.

```c
if (i + 2 < n_ops
    && strcmp(ops[i+2].type, "insert") == 0 && !ad_layer_is_line_op(&ops[i+2])
    && ops[i+2].line == ops[i+1].line
    && ops[i+2].col == ops[i+1].col) {  // ← add col check
    next_is_insert_same_line = 1;
}
```

**Option C (correct):** Generalize the merge to handle runs. A
maximal run of N deletes at `(L, C)` followed by a maximal run of M
inserts at `(L, C)` should become `min(N, M)` overwrite_inserts +
`|N - M|` leftover deletes or inserts. This handles `llo → et`
(3 deletes + 2 inserts → 2 overwrite_inserts + 1 leftover delete).

**Recommendation:** Option A first (remove the guard), run all
tests, see what breaks. If nothing breaks, ship it. If something
breaks, switch to Option B. Option C is the long-term fix but
requires more test coverage.

#### Test that verifies the fix

Already in `tests/test_layer_contracts.pl`, section 2 (Case 2a):
```
Input: hello → greet pattern (hand-crafted op stream)
Assert: 0 standalone deletes
Assert: ≥2 overwrite_insert ops
```

#### Acceptance criteria

- `make test-layer-contracts` reports 0 failures (currently 2).
- `make test-minimal` still passes 27/27 (no regression).
- `make test-property` still passes 50/50.

#### Risk

LOW. The change is 7 lines deleted (Option A) or 1 line added
(Option B). The test suite catches regressions. The `hello → greet`
case is the most common visible bug.

#### Open questions for you

**Q1:** Do you want me to check `git blame` on lines 36-42 before
removing the guard, or just remove it and see what breaks?

**Q2:** Option A (remove guard), Option B (relax guard), or Option
C (generalize to runs)? I recommend A first, then C if needed.

#### Phase 2 (Option C) — IMPLEMENTED 2026-09-17

Phase 1 shipped Option A and confirmed it left middle-of-run deletes
unmerged (the `'llo' → 'et'` case produced 2 standalone deletes +
2 overwrite_inserts). Phase 2 generalizes the merge to runs as
described above.

**Code changes:**

- `layers/c/ad_layer_overwrite.c` — rewritten. The merge now scans a
  maximal run of N non-line-op deletes at `(L, C)`, then a maximal run
  of M non-line-op inserts starting at `(L, C)` and advancing by 1
  col each. Emits `min(N, M)` overwrite_inserts using the first
  `min(N, M)` insert codes, then `|N - M|` leftover deletes or inserts
  from the tail of whichever run was longer. A position-walk pass
  after the merge recomputes `(line, col)` so the leftover ops land at
  the correct cursor position (the walk skips line ops and `\n` ops,
  matching the Perl twin).

- `layers/perl/ad_layer_overwrite.pl` — rewritten to mirror the C
  version. `parse_op` was also fixed to handle all line-op formats
  (`keep_line`, `join_lines`, `split_line`, `delete_line`,
  `insert_line`, `batch_insert`) and a catch-all for unknown op
  types (previously the Perl parse_op only handled the standard
  4-field format and silently dropped every line op, which broke
  C/Perl parity on every real example).

- `tests/test_layer_contracts.pl` — Case 2a assertions updated to
  the Option C contract (3 overwrite_inserts, 1 leftover delete,
  1 leftover insert for the `hello → greet` input). Added three new
  cases:
    - 2c: pure 3D + 2I at one position (the `'llo' → 'et'` shape).
    - 2d: 2D + 3I (M > N — leftover insert).
    - 2e: 3 deletes with no following inserts (no merge).

**Test results:**

- `make test-layer-contracts`: 35 pass / 0 fail (up from 28/1).
- `make test-layer-overwrite`: 5 pass / 0 fail — C/Perl parity now
  verified on 19/19 real examples (up from 0/19; the pre-existing
  parity failure was the parse_op bug fixed in this phase).
- `make test-minimal`: 27/27 pass (no regression).
- `make test-property`: 50/50 pass (no regression).
- `make test-property-reversed`: 100/100 pass (no regression).
- `make test-reversed`: 68/68 corpus cases pass (no regression).
- `make test-examples`: 36/36 examples pass (no regression).
- `make test-fuzz`: 60/60 pass (no regression).

Pre-existing failures NOT caused by Option C (verified by running
the same tests on the pre-Option-C HEAD): `ad_layer_highlight` parity,
`ad_layer_indent_last` parity, `ad_layer_reorder` parity, l2r
algorithm tests, `test_all_animators` whole-line insert/delete Perl
cases. None of these touch `ad_layer_overwrite`.

---

### 4.3 `ad_layer_indent_last` — BROKEN (Phase 2 fix applied 2026-09-17)

**Contract:** For each line segment that starts with leading
whitespace deletes (space OR tab), move those whitespace deletes to
AFTER the content deletes AND BEFORE the trailing `\n` char op. Bump
content op cols by `+n_indent`. Indent deletes are placed at col 1.
The `\n` op (if any) is emitted LAST (after the indent deletes), not
in the middle of the segment.

**Correct output order:** `content (col +n_indent) → indent (col 1) →
\n op (original position)`.

**Source:** `layers/c/ad_layer_indent_last.c`, function
`layer_indent_last`.

**Test case:** `delete(space) delete(space) delete(a) delete(b)
delete(\n)` → should become `delete(a, col+2) delete(b, col+2)
delete(space, col 1) delete(space, col 1) delete(\n)`. (The `\n` is
LAST, not in the middle of the segment.)

#### The bug (pre-Phase-2)

The C version searched for the trailing `\n` op using
`ad_layer_is_line_op(&ops[j])`, which matches line-level op types
(`keep_line`, `join_lines`, `split_line`, `delete_line`,
`batch_insert`) but NOT a `delete \n` op (which has type `"delete"`
and code 10, not a line-level type). As a result, the `\n` search
returned -1, `content_end = i` (whole segment), and the `\n` op
ended up inside the content run — producing output order
`content → \n → indent` instead of the correct
`content → indent → \n`.

The Perl twin happened to use `$in[$j]{code} == 10` (the correct
check) and so already produced the correct order. The two twins
disagreed on every input that had a trailing `\n` op.

#### Why the order matters

If the `\n` delete is applied before the indent deletes, the line
join happens while the deleted line's indentation is still in the
buffer. The next line is then pulled up at the (now-to-be-deleted)
indentation level, causing it to appear incorrectly indented during
the animation. Applying the `\n` delete LAST — after the indent
deletes — ensures the next line is pulled up at column 1 (no
inherited indentation).

#### Fix design (Phase 2)

**C version:** Change the `\n`-op detection from
`ad_layer_is_line_op(&ops[j])` to `ops[j].code == AD_LAYER_CHAR_NEWLINE`
(matching the Perl twin). The rest of the algorithm is unchanged:
emit content (col bumped) → indent (col 1) → `\n` op (last, original
position).

**Perl twin:** Already correct. But `parse_op` was extended to
handle all line-op formats (`delete_line`, `insert_line`,
`split_line`, `join_lines`, `keep_line`, `batch_insert`) and a
catch-all for unknown op types — this was the same pre-existing
parse_op bug fixed in `ad_layer_overwrite.pl` during Phase 1, applied
here for the same reason (C/Perl parity on real examples).

**Contract test (`tests/test_layer_contracts.pl` Case 3):** Asserts
the exact delete-code order `[97, 98, 32, 32, 10]` — content 'a',
content 'b', space, space, `\n`. The previous test only checked that
the first delete was content and that the content col was bumped — it
did not assert the position of `\n` relative to the indent deletes,
which is why the bug went undetected.

Added Case 3b: TAB indentation (codes 9 instead of 32). Verifies the
layer treats tabs as leading-whitespace exactly like spaces, with the
same content-bump and the same `content → indent → \n` order.

Added Case 3c: segment with NO trailing `\n` op (content deletes
only). The layer should still move the indent to the end; there's
just no `\n` to emit. Order: `content → indent`.

#### Acceptance criteria

- `make test-layer-contracts`: 0 failures (Case 3 order assertions
  now enforced; previously the order was not checked).
- `make test-minimal`: 27/27 pass (no regression).
- `make test-property`: 50/50 pass (no regression).
- `make test-property-reversed`: 100/100 pass (no regression).
- `make test-reversed`: 68/68 corpus cases pass (no regression).
- `make test-examples`: 36/36 examples pass (no regression).
- C/Perl parity on `tests/test_indent_last.pl`: PASS (was failing
  pre-Phase-2 due to the Perl `parse_op` line-op bug; now both twins
  produce byte-identical output).

#### Risk

LOW. The change is a one-line check substitution (line 62 of the C
version) plus the Perl `parse_op`/`write_op` line-op handling
extension. The test suite catches regressions. The `hello → greet`
case in §4.2 (Option C, Phase 1 of this work) is unaffected — it
doesn't go through `ad_layer_indent_last`.

#### Caveat (carried forward from Phase 1)

The test only covers the case where the segment STARTS with
whitespace deletes. If whitespace deletes are interleaved with
content deletes (e.g., `delete(space) delete(a) delete(space)
delete(b)`), the layer may not fire correctly. This is a gap in test
coverage, not necessarily a bug. Add a test case for interleaved
whitespace in a later phase.

---

### 4.4 `ad_layer_line_delete_in_place` — FIXED (Phase 2, handles arbitrary N lines)

**Contract:** When the diff engine deletes N consecutive lines, it
produces `delete(L1) + join_lines + delete(L2) + join_lines + ... +
delete(LN) + join_lines`. The layer reorders to `delete(L1) +
delete(L2 at L+1) + delete(L3 at L+2) + ... + delete(LN at L+N-1) +
join + join + ... + join` so all content disappears in place before
lines join. Handles arbitrary N, not just 2.

**Source:** `layers/c/ad_layer_line_delete_in_place.c`, function
`layer_line_delete_in_place`.

#### The bug (pre-Phase-2)

The C version only handled the 2-line case. For 3+ line deletions, the
3rd line's content was moved to line 2 (should be line 3), and joins
were interleaved with content deletes instead of all at the end.
The corpus analysis flagged this: `block_delete` (5.6% of corpus)
showed 0 ops in the output.

#### Fix design (Phase 2 — sliding window)

Rewritten with a sliding 2-line window algorithm:
1. Walk the ops. When a `join_lines(L)` is followed by content deletes
   (first at col 1), start a block.
2. Within the block, match `join + delete+` repeatedly (the 2-line
   window). Each match:
   - Emits content deletes at `L + 1 + line_off` (offset = batches
     already emitted).
   - Defers the join to a pending list.
   - Advances `line_off` by 1.
3. When the block ends (no more join+delete pattern, or a trailing
   join with no content), emit all pending joins at the end.

This handles arbitrary N because the window slides by 1 line per
match (the joiner's line conceptually advances by 1 each iteration,
tracked via the `line_off` counter). All content deletes are emitted
first (at their correct pre-join lines), then all joins at the end.

**Perl twin:** Mirrored the same sliding-window algorithm. Also
fixed `parse_op`/`write_op` to handle all line-op formats and a
catch-all for unknown op types (same fix as overwrite/indent_last
Perl twins).

**Contract test:** Updated Case 4a (2-line) with line-number
assertions. Added Case 4b (3-line), 4c (5-line stress test), and
4d (partial content at col > 1 — should NOT match).

#### Acceptance criteria

- `make test-layer-contracts`: 0 failures (Cases 4a-4d all pass).
- `make test-minimal`: 27/27 pass (no regression).
- `make test-property`: 50/50 pass (no regression).
- `make test-property-reversed`: 100/100 pass (no regression).
- `make test-reversed`: 68/68 pass (no regression).
- `make test-examples`: 36/36 pass (no regression).
- C/Perl parity: byte-identical on all test cases.
- `test_line_delete_in_place.pl` end-state simulation: 15/15 pass
  (was 0/15 pre-Phase-2 — the simulation didn't handle line ops).

---

### 4.5 `ad_layer_split_in_place` — WORKS

**Contract:** Reorder `insert(L, col 1, chars) + split_line(L, K)`
to `split_line(L, 1) + insert(L, col 1, chars)` so the split
happens before the insert (no on-screen concatenation).

**Source:** `layers/c/ad_layer_split_in_place.c`, custom `main`
(lines 20-165) — does NOT use `ad_layer_run` because it needs
access to the HUNK header's del count.

**Test case:** `insert(a) insert(b) split_line keep(c)` with
`del > 0`. Assert `split_line` comes before any `insert`.

**Result:** PASS.

**No fix needed.**

---

### 4.6 `ad_layer_join_insert_in_place` — WORKS

**Contract:** Reorder `join_lines(L) + insert(L, col 1, chars) +
keep(L, ...)` to `insert(L+1, col 1, chars) + keep(L+1, ...) +
join_lines(L)` so inserts happen on line L+1 before the join (no
on-screen concatenation).

**Source:** `layers/c/ad_layer_join_insert_in_place.c`, function
`layer_join_insert_in_place`, lines 26-122.

**Test case:** `join_lines insert(a) insert(b) keep(c)`. Assert
`join_lines` moved after inserts, and insert line bumped from 1 to
2.

**Result:** PASS.

**No fix needed.**

---

### 4.7 `ad_layer_batch_whitespace` — WORKS

**Contract:** Replace runs of consecutive whitespace inserts
(space=32, tab=9) with a single `batch_insert` op.

**Source:** `layers/c/ad_layer_batch_whitespace.c`, custom `main`
(lines 16-102).

**Test case:** 4 consecutive space inserts + 1 content insert.
Assert 1 `batch_insert` produced, 0 standalone space inserts
remain.

**Result:** PASS.

**No fix needed.** Optional enhancement: add `ad_layer_batch_insert`
for non-whitespace runs (Phase 9, opt-in).

---

### 4.8 `ad_layer_skip_indent` — WORKS

**Contract:** Detect indent-only hunks (all deletes/inserts are
whitespace or \n) and wrap with delay markers so the pace layer
applies them instantly.

**Source:** `layers/c/ad_layer_skip_indent.c`, function
`layer_skip_indent`, lines 47-133.

**Marker format:** `delay\t-1\t0\t0` (start) and `delay\t-1\t1\t<N>`
(end, where N is pause-after-ms).

**Test case:** Indent-only hunk (4 space deletes + 4 space inserts).
Assert both markers emitted. Also test negative case: content-change
hunk should NOT get markers.

**Result:** PASS.

**No fix needed.** Optional: generalize to `skip_noise` for any
whitespace-only hunk (Phase 9).

---

### 4.9 `ad_layer_line_replace` — WORKS for tested case

**Contract:** For ANY line with at least one delete or insert,
collapse all its char ops into `delete_line + insert_line <final_text>`.

**Source:** `layers/c/ad_layer_line_replace.c`, function
`layer_line_replace`, lines 63-209.

**Test case:** Single line with `keep(a) delete(b) insert(B)
keep(c)`. Assert 1 `delete_line` + 1 `insert_line` with text "aBc",
0 char-level ops.

**Result:** PASS.

**Known issue (from earlier audit):** When run through the full
pipeline, `line_replace` produces 0 ops for some categories and the
snapshot doesn't match. This suggests the layer works in isolation
but breaks when fed real `ad_compute` output. Needs a separate
integration test.

**Fix needed in Phase 2:** Add an integration test that runs
`line_replace` on real `ad_compute` output from `01_simple_replace`
and verifies the snapshot matches.

---

## 5. Phases — detailed engineering plan

Each phase has: scope, files changed, lines of code, test added,
acceptance criteria, risk, and dependencies.

---

### Phase 1: Fix `ad_layer_overwrite` merge guard

**Scope:** Remove or relax the `next_is_insert_same_line` guard in
`ad_layer_overwrite.c` so the layer fires on multi-delete +
multi-insert runs.

**Files changed:**
- `layers/c/ad_layer_overwrite.c` — delete or modify lines 36-42
- `layers/perl/ad_layer_overwrite.pl` — same change for parity

**Lines of code:** ~7 lines deleted (Option A) or ~1 line added
(Option B).

**Test:** Already exists in `tests/test_layer_contracts.pl`
section 2a. Currently fails. After fix, should pass.

**Acceptance criteria:**
1. `make test-layer-contracts` → 0 failures (currently 2)
2. `make test-minimal` → 27/27 pass (no regression)
3. `make test-property` → 50/50 pass (no regression)
4. `make test-property-reversed` → 100/100 pass (no regression)
5. Manual: `hello → greet` produces 0 standalone `delete` ops in
   the post-process output

**Risk:** LOW. The change is small and well-tested. The main risk
is that the guard was added to fix a different bug that we'll
re-introduce. Mitigation: run the full test suite after the change.

**Dependencies:** None. This is the first phase.

**Estimated time:** 2-4 hours (including `git blame` investigation
and running the full test suite).

**Open questions:**
- **Q1 (repeated):** Option A (remove guard), B (relax guard), or
  C (generalize to runs)?
- **Q2:** Should I check `git blame` on lines 36-42 first to
  understand why the guard was added?

---

### Phase 2: Add integration test for `ad_layer_line_replace`

**Scope:** The contract test for `line_replace` passes in isolation
but the earlier audit showed it produces 0 ops when fed real
`ad_compute` output. Add an integration test that runs the full
pipeline with `line_replace` on a simple case and verifies the
snapshot matches.

**Files changed:**
- `tests/test_layer_contracts.pl` — add Case 9b: integration test
  that runs `ad_compute` on `01_simple_replace`, pipes through
  `line_replace`, runs through pace + animator, asserts snapshot ==
  target.

**Lines of code:** ~30 lines of Perl.

**Test:** The new test case itself.

**Acceptance criteria:**
1. The integration test runs and either passes or fails with a
   clear diagnostic.
2. If it fails, the failure is filed as a bug for Phase 2b.

**Risk:** LOW. This is a test-only change.

**Dependencies:** None.

**Estimated time:** 1-2 hours.

**Sub-phase 2b (conditional): Fix `line_replace` integration bug**

If the integration test fails, investigate why. Likely causes:
- The `virtual_line` tracking in `layer_line_replace` doesn't match
  the animator's line numbering after `join_lines`/`split_line` ops.
- The `delete_line`/`insert_line` op format is slightly wrong (field
  count, text encoding).
- The animator doesn't handle `delete_line`/`insert_line` correctly
  when mixed with other op types.

**Estimated time:** 4-8 hours (depends on the root cause).

**Open questions:**
- **Q3:** Is `line_replace` even needed? It produces a "delete whole
  line, retype whole line" animation which is visually worse than
  `overwrite` for small changes. Maybe deprecate it instead of
  fixing it?

---

### Phase 3: Add `ad_layer_line_delete_in_place` multi-line test

**Scope:** The contract test only covers 2-line deletion. The
corpus audit showed 0 ops for `block_delete` (3+ lines). Add a
test case for 3+ line deletion and verify the layer handles it.

**Files changed:**
- `tests/test_layer_contracts.pl` — add Case 4b: 3-line deletion
  with `join_lines` between each.

**Lines of code:** ~20 lines of Perl.

**Acceptance criteria:**
1. The 3-line test case runs and either passes or fails with a
   clear diagnostic.
2. If it fails, the layer's pattern matching needs to be
   generalized (Phase 3b).

**Risk:** LOW. Test-only change.

**Dependencies:** None.

**Estimated time:** 1-2 hours.

**Sub-phase 3b (conditional): Generalize `line_delete_in_place` to
N-line runs**

If the 3-line test fails, the layer's pattern matching (lines 93-167
of `ad_layer_line_delete_in_place.c`) only handles the 2-line case
(`join + delete + join`). Generalize to detect runs of
`join + delete+ + join + delete+ + join + ...` and batch all
deletes before all joins.

**Estimated time:** 4-6 hours.

---

### Phase 4: Add `ad_layer_block_move` (new layer)

**Scope:** Detect cut-paste patterns where a run of ≥2 deleted lines
reappears as a run of inserted lines elsewhere in the same file.
Mark both runs with `move_start`/`move_end` ops so the animator can
render the move as a single cut-paste operation.

**Detection algorithm:** Reuse the move-detection logic from
`analysis/edit_corpus_analysis.py` (lines 122-160). It already
correctly identifies 63 moves in the corpus.

**Files changed:**
- `layers/c/ad_layer_block_move.c` — new file (~200 lines)
- `layers/perl/ad_layer_block_move.pl` — new file (parity twin)
- `layers/c/ad_layer_common.h` — add `move_start`/`move_end` to the
  op type set
- `animator/c/ad.c` — recognize `move_start`/`move_end` ops
  (~50 lines: render as brief highlight + fade for source, brief
  materialize for dest)
- `tests/test_layer_contracts.pl` — add section 10: block_move
  contract test
- `Makefile` — add `bin/ad_layer_block_move` to `LAYER_BINS`

**Lines of code:** ~300 lines C + ~100 lines Perl + ~30 lines test.

**Test case:**
```
Input: 3 lines deleted at position A, same 3 lines inserted at
       position B (different hunk or different part of same hunk).
Assert: 1 move_start op at source, 1 move_end op at dest, 0
        standalone delete/insert ops for the moved lines.
```

**Acceptance criteria:**
1. Contract test passes.
2. `make test-minimal` still passes (no regression on existing
   cases — the new layer is opt-in, not default).
3. Manual: run on a synthetic block-move case, verify the animation
   shows the block lifting from source and materializing at dest.

**Risk:** MEDIUM. Requires adding new op types to the animator C
core. The animator's op dispatch is in `animator/c/ad.c` and needs
careful modification.

**Dependencies:** None (can be developed in parallel with Phases
1-3).

**Estimated time:** 2-3 days.

**Open questions:**
- **Q4:** Should `block_move` be default-on or opt-in? Move
  detection adds overhead (O(n²) in the worst case for comparing
  all deleted lines against all inserted lines). For large files
  this could be slow.
- **Q5:** What's the move detection threshold? ≥2 identical lines
  is the current proposal. Should it be ≥3 to reduce false
  positives (e.g., blank lines or `}` lines that appear many
  times)?
- **Q6:** Should the animator render `move_start` as a fade or as
  a "cut" (line disappears instantly)? Fade is prettier but takes
  longer.

---

### Phase 5: Add `ad_layer_word_replace` (new layer)

**Scope:** For hunks where exactly 1 line changes and the change is
a single word replacement (e.g., `hello → greet`), emit `select
<line> <col_start> <col_end>` + `overwrite_insert <line> <col_start>
<new_word_chars>` instead of char-level delete+insert.

**Detection algorithm:**
1. Hunk has exactly 1 old line and 1 new line.
2. Tokenize both lines into words (identifier-like runs).
3. If exactly 1 word differs and surrounding words are identical,
   emit `select` + `overwrite_insert`.

**Files changed:**
- `layers/c/ad_layer_word_replace.c` — new file (~150 lines)
- `layers/perl/ad_layer_word_replace.pl` — parity twin
- `layers/c/ad_layer_common.h` — add `select` op type
- `animator/c/ad.c` — recognize `select` op (~30 lines: render as
  brief highlight of the range without modifying it)
- `tests/test_layer_contracts.pl` — add section 11: word_replace
  contract test
- `Makefile` — add `bin/ad_layer_word_replace` to `LAYER_BINS`

**Lines of code:** ~200 lines C + ~80 lines Perl + ~30 lines test.

**Test case:**
```
Input: "def hello():" → "def greet():"
Assert: 1 select op (cols 5-9), 1 overwrite_insert op with 'greet',
        0 standalone delete ops.
```

**Acceptance criteria:**
1. Contract test passes.
2. `make test-minimal` still passes (no regression — opt-in layer).
3. Manual: `hello → greet` renders as select-word + type-over, not
   backspace + retype.

**Risk:** MEDIUM. Requires adding `select` op to the animator. The
tokenization logic needs to handle edge cases (punctuation, Unicode,
no-whitespace lines like `a=hello`).

**Dependencies:** Phase 1 (overwrite fix) should land first so we
can compare the two approaches on the same test case.

**Estimated time:** 2-3 days.

**Open questions:**
- **Q7:** Should `word_replace` replace `overwrite` or complement
  it? `overwrite` handles multi-char changes at the same position;
  `word_replace` handles whole-word swaps. They overlap on cases
  like `hello → greet` (which is both a word replace and a
  positional overwrite).
- **Q8:** What tokenization rule? `re.findall(r"[A-Za-z_][A-Za-z0-9_]*")`
  is the simple choice but misses operators, strings, etc. Should
  we use a proper lexer (tree-sitter) or stick with regex?
- **Q9:** Should `select` highlight the word before overwriting, or
  just overwrite directly? Highlight adds a visual cue but takes
  ~200ms.

---

### Phase 6: Add `ad_layer_block_modify` (new layer)

**Scope:** For hunks where ≥2 old lines and ≥2 new lines change
with per-line word overlap ≥ 0.5, decompose into N independent
per-line `word_replace` operations. This is the largest category
(23.6% of corpus) and currently produces 6 interleave flickers +
15 unmerged pairs per case.

**Detection algorithm:**
1. Hunk has ≥2 old lines and ≥2 new lines.
2. Line counts match (or differ by ≤ 1).
3. For each line pair (old[i], new[i]), compute word-level Jaccard
   similarity. If ≥ 0.5, classify as `word_replace` on that line.
4. Emit per-line `select` + `overwrite_insert` ops.

**Files changed:**
- `layers/c/ad_layer_block_modify.c` — new file (~250 lines)
- `layers/perl/ad_layer_block_modify.pl` — parity twin
- `tests/test_layer_contracts.pl` — add section 12: block_modify
  contract test
- `Makefile` — add `bin/ad_layer_block_modify` to `LAYER_BINS`

**Lines of code:** ~300 lines C + ~120 lines Perl + ~40 lines test.

**Test case:**
```
Input: 3-line block where each line has 1 word replaced.
Assert: 0 interleave flickers in the output op stream.
Assert: 3 select ops (one per line), 3 overwrite_insert ops.
```

**Acceptance criteria:**
1. Contract test passes.
2. The `block_modify` category cases from the corpus produce 0
   interleave flickers (measured by `analysis/layer_audit.py`).
3. `make test-minimal` still passes.

**Risk:** MEDIUM. Depends on Phase 5 (`word_replace`) for the
per-line rendering. The line-pairing algorithm needs to handle
insertions/deletions within the block (not just 1:1 line matches).

**Dependencies:** Phase 5.

**Estimated time:** 2-3 days.

**Open questions:**
- **Q10:** How to pair old lines with new lines when counts differ?
  Use LCS at the line level, or just pair by position?
- **Q11:** What Jaccard threshold? 0.5 is the proposal. Too low
  → false positives (unrelated lines get paired). Too high →
  real modifications get treated as block_replace instead.

---

### Phase 7: Generalize `ad_layer_indent_last` to interleaved whitespace

**Scope:** The current layer only fires when the segment STARTS with
whitespace deletes. If whitespace deletes are interleaved with
content deletes (e.g., re-indent + modify), the layer doesn't fire.

**Files changed:**
- `layers/c/ad_layer_indent_last.c` — modify the segment scan
  (lines 43-51) to collect ALL whitespace deletes from anywhere in
  the segment, not just the leading run.
- `layers/perl/ad_layer_indent_last.pl` — same change for parity.
- `tests/test_layer_contracts.pl` — add Case 3b: interleaved
  whitespace + content deletes.

**Lines of code:** ~20 lines C + ~15 lines Perl + ~15 lines test.

**Acceptance criteria:**
1. New test case passes.
2. Existing test case still passes.
3. `make test-minimal` still passes.

**Risk:** LOW. The change is a generalization of existing logic.

**Dependencies:** None.

**Estimated time:** 4-6 hours.

---

### Phase 8: Generalize `ad_layer_skip_indent` → `ad_layer_skip_noise`

**Scope:** Currently only fires on indent-only hunks. Generalize to
fire on any whitespace-only hunk (including trailing whitespace
changes, blank line additions, etc.).

**Files changed:**
- `layers/c/ad_layer_skip_indent.c` — rename to `ad_layer_skip_noise.c`,
  update the detection condition (lines 51-61) to check for
  whitespace-only instead of indent-only.
- `layers/perl/ad_layer_skip_indent.pl` — same.
- `Makefile` — update layer name.
- `tests/test_layer_contracts.pl` — update section 8 to test
  whitespace-only (not just indent-only) hunks.

**Lines of code:** ~10 lines C + ~10 lines Perl + ~20 lines test
+ Makefile changes.

**Acceptance criteria:**
1. Contract test passes for both indent-only and whitespace-only
   hunks.
2. `make test-minimal` still passes.

**Risk:** LOW. The generalization is straightforward.

**Dependencies:** None.

**Estimated time:** 2-4 hours.

**Open question:**
- **Q12:** Rename the layer or keep the old name? Renaming breaks
  existing configs but is more honest about what it does.

---

### Phase 9: Add `ad_layer_batch_insert` (optional, opt-in)

**Scope:** Like `batch_whitespace` but for non-whitespace content
runs. Batches consecutive `insert` ops of non-whitespace chars into
a single `batch_insert` op.

**Files changed:**
- `layers/c/ad_layer_batch_insert.c` — new file (~100 lines, mostly
  copied from `batch_whitespace.c`)
- `tests/test_layer_contracts.pl` — add section 13.

**Lines of code:** ~100 lines C + ~20 lines test.

**Acceptance criteria:**
1. Contract test passes.
2. `make test-minimal` still passes (layer is opt-in, not default).

**Risk:** LOW. Pure addition, no changes to existing code.

**Dependencies:** None.

**Estimated time:** 2-4 hours.

**Open question:**
- **Q13:** Should this be default-on for large insertions (>50 chars)?
  Or always opt-in? Default-on trades animation detail for speed on
  large blocks.

---

### Phase 10: Word-boundary-aware LCS in compute (DEFERRED)

**Scope:** Add a `--word-diff` mode to `ad_compute` that runs the
LCS on tokens (identifier-like runs) instead of characters. The
output op stream uses word-level ops that the `word_replace` layer
can directly consume.

**Files changed:**
- `diff_engine/cpp/compute.cpp` — add word-level LCS mode (~200
  lines)
- `diff_engine/perl/compute.pl` — same for parity

**Lines of code:** ~400 lines total.

**Risk:** HIGH. Touches the C++ core. The word-level LCS may
produce different op streams that break existing layers. Needs
extensive testing.

**Dependencies:** All other phases should land first so we can
measure whether word-diff mode actually helps vs. the `word_replace`
layer alone.

**Estimated time:** 3-5 days.

**Open question:**
- **Q14:** Is this worth doing at all? If the `word_replace` layer
  (Phase 5) handles the common cases, the compute-level change may
  be unnecessary complexity. Defer this decision until after Phase
  5 lands and we can measure.

---

## 6. Phase summary table

| Phase | Scope | Effort | Risk | Depends on | New op types? |
|---|---|---|---|---|---|
| 1 | Fix overwrite merge guard | 2-4h | LOW | none | no |
| 2 | line_replace integration test | 1-2h | LOW | none | no |
| 2b | Fix line_replace (conditional) | 4-8h | MEDIUM | 2 | no |
| 3 | line_delete_in_place multi-line test | 1-2h | LOW | none | no |
| 3b | Generalize line_delete_in_place (conditional) | 4-6h | MEDIUM | 3 | no |
| 4 | Add block_move layer | 2-3d | MEDIUM | none | yes: move_start, move_end |
| 5 | Add word_replace layer | 2-3d | MEDIUM | 1 | yes: select |
| 6 | Add block_modify layer | 2-3d | MEDIUM | 5 | no (uses select) |
| 7 | Generalize indent_last | 4-6h | LOW | none | no |
| 8 | skip_indent → skip_noise | 2-4h | LOW | none | no |
| 9 | Add batch_insert (opt-in) | 2-4h | LOW | none | no |
| 10 | Word-boundary LCS (DEFERRED) | 3-5d | HIGH | 1-9 | no |

**First visible win:** Phase 1 (2-4 hours) — fixes the most common
visible bug (`hello → greet` stops having 4 backspaces).

**61% of corpus fixed:** After Phases 1, 5, 6 — the top 3 categories
(word_replace, block_insert via batch_whitespace, block_modify)
are handled.

---

## 7. Open questions (consolidated)

**Q1:** For `ad_layer_overwrite` fix: Option A (remove guard), B
(relax guard), or C (generalize to runs)?

**Q2:** Should I check `git blame` on the guard lines before
removing them?

**Q3:** Is `ad_layer_line_replace` even needed? It produces a
"delete whole line, retype whole line" animation which is visually
worse than `overwrite` for small changes. Deprecate it instead of
fixing it?

**Q4:** Should `block_move` (Phase 4) be default-on or opt-in?

**Q5:** Move detection threshold: ≥2 identical lines, or ≥3?

**Q6:** Animator `move_start` rendering: fade or instant cut?

**Q7:** Should `word_replace` (Phase 5) replace `overwrite` or
complement it?

**Q8:** Tokenization for `word_replace`: regex or tree-sitter?

**Q9:** Should `select` highlight the word before overwriting, or
just overwrite directly?

**Q10:** For `block_modify` (Phase 6), how to pair old/new lines
when counts differ?

**Q11:** Jaccard threshold for `block_modify`: 0.5, or something
else?

**Q12:** Rename `skip_indent` → `skip_noise`, or keep the old name?

**Q13:** Should `batch_insert` (Phase 9) be default-on for large
insertions?

**Q14:** Is Phase 10 (word-boundary LCS) worth doing at all, or
defer indefinitely after Phase 5?

---

## 8. What I've already done (before you decide)

1. **`tests/test_layer_contracts.pl`** — contract tests for all 9
   layers. 27 pass, 2 fail (both in `overwrite`).
2. **`make test-layer-contracts`** — new Makefile target, wired
   into `make test-layers` and `make test`. Uses `set -o pipefail`
   so failures propagate.
3. **`analysis/edit_corpus.csv`** — 3,215 hunks categorized.
4. **`analysis/layer_audit.py`** — per-(category, layer) quality
   metrics.
5. **This document** — detailed per-layer analysis with fix designs.

The 2 failing contract tests are the proof that the test
infrastructure works. They catch the exact bug the user has been
reporting. `make test` now blocks on these failures.

---

## 9. What I need from you

Read this document. Answer the 14 questions (or tell me to use my
judgment on the ones you don't care about). Pick a phase to start
with (I recommend Phase 1 — it's 2-4 hours and fixes the most
common visible bug).

I will not write any more code until you've reviewed this document
and told me which phase to start.
