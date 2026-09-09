# Architecture Change: Remove \n from Char Ops

*Date: 2026-09-09*

## Proposal

Change the diff engine so `\n` is NOT treated as a regular character in
the char-level diff. Instead, line boundaries are explicit line-level
ops. This simplifies all layers and eliminates the root cause of most
layer bugs.

## Current Architecture (the problem)

### How it works now

1. **Line-level diff** (patience): produces `KEEP/DELETE/INSERT` line ops
2. **Hunk construction**: for each group of non-keep line ops, the diff
   engine concatenates old lines with `\n` and new lines with `\n`:
   ```cpp
   old_text = "line1\nline2\nline3"
   new_text = "line1_modified\nline2_modified"
   ```
3. **Char-level diff** (anchored LCS): diffs `old_text` vs `new_text`.
   The `\n` chars are part of the diff — they can be `keep \n`,
   `delete \n`, or `insert \n`.
4. **Op emission**: each char op (including `\n`) gets `(line, col)`.
   The diff engine tracks `cur_line` which advances on `\n keep/insert`
   but NOT on `\n delete`.

### Why it's problematic

- `\n delete` (line join) and `\n insert` (line split) are interleaved
  with content char ops
- After a `\n delete`, `cur_line` doesn't advance — subsequent ops
  target the joined line, but layers can't tell which "original line"
  they belong to
- Layers that recompute positions get confused by the non-advancing
  `cur_line`
- Layers that operate per-line (line_replace, line_delete_in_place)
  can't easily group ops by original line
- The `\n` handling is asymmetric: `\n delete` doesn't advance
  `cur_line`, but `\n keep/insert` does

## Proposed Architecture

### New op types

Replace `keep/delete/insert` of `\n` (code 10) with explicit line ops:

| Old op | New op | Meaning |
|--------|--------|---------|
| `keep \n` | `keep_line\t<L>` | Line L is unchanged — advance to next line |
| `delete \n` | `join_lines\t<L>` | Join line L with L+1 (delete the newline between them) |
| `insert \n` | `split_line\t<L>\t<col>` | Split line L at col C (insert a newline) |

### New op stream format

```
HUNK  <target>  <del>  <ins>  <end_ins>  <end_del>
keep    <line>  <col>  <code>     ← char ops (code is NEVER 10)
delete  <line>  <col>  <code>     ← char ops (code is NEVER 10)
insert  <line>  <col>  <code>     ← char ops (code is NEVER 10)
keep_line       <line>             ← line boundary (was keep \n)
join_lines      <line>             ← line join (was delete \n)
split_line      <line>  <col>      ← line split (was insert \n)
HUNK_END
```

### How the diff engine changes

Instead of concatenating lines with `\n` and running one char diff:

1. **Line-level diff** stays the same (patience)
2. **For each hunk**, instead of building `old_text` and `new_text`:
   - Pair up old lines and new lines
   - For each pair, run char diff on the individual lines (no `\n`)
   - Between line pairs, emit `keep_line`, `join_lines`, or `split_line`

**Example:** old has 3 lines, new has 2 lines (lines 2+3 merged):

```
Old:               New:
line1: "hello"     line1: "hello"
line2: "world"     line2: "worldfoo"
line3: "foo"
```

Line diff: `KEEP line1, DELETE line2, DELETE line3, INSERT "worldfoo"`

Hunk construction:
- Line 1 is kept → `keep_line 1`
- Lines 2+3 deleted, "worldfoo" inserted → char diff "world\nfoo" vs "worldfoo"
  → `keep "world"`, `delete \n`, `keep "foo"` ... wait, this still has \n.

**The problem:** even with per-line pairing, when multiple old lines
map to one new line (or vice versa), we STILL need to handle the join/split.

### Better approach: per-line char diff + explicit join/split

1. Run the line-level diff (patience)
2. For each hunk, walk through the line ops:
   - `KEEP old_line L`: emit `keep_line L`
   - `DELETE old_line L` + `INSERT new_line M` (1:1 replacement):
     char-diff `old_lines[L]` vs `new_lines[M]` → emit char ops, then `keep_line`
   - `DELETE old_line L` (no insert — pure deletion):
     emit char ops for deleting all of `old_lines[L]`, then `join_lines L`
   - `INSERT new_line M` (no delete — pure insertion):
     emit `split_line` at the appropriate position, then char ops for inserting `new_lines[M]`
   - `DELETE old_line L1, L2` + `INSERT new_line M1` (2:1 merge):
     char-diff `old_lines[L1] + old_lines[L2]` vs `new_lines[M1]`,
     but treat the boundary between L1 and L2 as a `join_lines` op
     instead of a `\n` char

### The key insight

The `\n` in the char diff represents a LINE BOUNDARY, not a character.
By making it an explicit line-level op (`join_lines` / `split_line` /
`keep_line`), we separate the two concerns:
- **Char ops** operate on characters within a single line
- **Line ops** operate on line boundaries

This means:
- `cur_line` ALWAYS advances after a line op (keep_line, join_lines, split_line)
- No more "don't advance on \n delete" confusion
- Layers can easily detect line boundaries
- Position tracking is uniform: line ops advance the line, char ops advance the col

## Impact Analysis

### Files that need changes

| File | Changes needed | Complexity |
|------|---------------|------------|
| **diff_engine/cpp/compute.cpp** | Rewrite hunk construction: per-line char diff + line ops | HIGH |
| **diff_engine/perl/compute.pl** | Same rewrite (Perl twin) | HIGH |
| **animator/c/ad.c** | Replace `code==10` handlers with `keep_line`/`join_lines`/`split_line` | MEDIUM |
| **animator/perl/ad.pl** | Same (Perl twin) | MEDIUM |
| **apps/vim/ad_vim** | Replace vimscript `code==10` handlers | MEDIUM |
| **layers/c/ad_layer_common.h** | Add parsing for new op types, update Op struct | LOW |
| **layers/c/ad_layer_reorder.c** | Simplify: no more \n special-casing | LOW |
| **layers/c/ad_layer_overwrite.c** | Simplify: no more \n special-casing | LOW |
| **layers/c/ad_layer_indent_last.c** | Simplify: segment boundaries are line ops | LOW |
| **layers/c/ad_layer_line_delete_in_place.c** | Simplify or become unnecessary | LOW |
| **layers/c/ad_layer_skip_indent.c** | Minor: \n check becomes line op check | LOW |
| **layers/c/ad_layer_pace.c** | Simplify: no more \n special-casing in delay computation | MEDIUM |
| **layers/c/ad_layer_highlight.c** | Minor: \n check becomes line op check | LOW |
| **layers/c/ad_layer_line_replace.c** | Simplify: line boundaries are explicit | LOW |
| **scripts/ad_annotate.c** | Update: \n keeps become keep_line | LOW |
| **scripts/vim/ad_ops_syntax.vim** | Add syntax for new op types | LOW |
| **Perl twins** (all layers + animator) | Mirror C changes | MEDIUM |

### Total: ~25 files, but most changes are simplifications (removing \n special-casing)

### What gets SIMPLIFIED

- **reorder**: no more "don't touch \n ops" — line ops are boundaries, period
- **overwrite**: no more "only non-\n ops" — all char ops are non-\n
- **line_delete_in_place**: may become unnecessary (join_lines is already explicit)
- **line_replace**: line boundaries are explicit, no virtual line tracking needed
- **pace**: no more \n special-casing in delay computation
- **animator**: `cur_line` always advances on line ops — uniform, no asymmetry

### What gets HARDER

- **diff engine**: hunk construction becomes more complex (per-line pairing
  instead of concatenate-and-diff)
- **Line merges/splits**: need explicit detection of N:1 and 1:N line mappings

### Test impact

- All 42 examples must still pass (output identical)
- All 50 property tests must still pass
- L1/L2 should show 42/42 for ALL layer combinations (not just reorder)
- New tests needed for: join_lines, split_line, keep_line op types

## Implementation Plan

### Branch: `refactor/no-newline-in-char-ops`

### Phase 1: Diff engine rewrite (C++ only)

1. Create branch `refactor/no-newline-in-char-ops`
2. Rewrite `compute.cpp` hunk construction:
   - For each hunk, walk line ops
   - Pair old/new lines (handle 1:1, N:1, 1:N, N:M cases)
   - For 1:1 replacement: char-diff individual lines, emit char ops + keep_line
   - For N:1 merge: char-diff with join_lines at boundaries
   - For 1:N split: char-diff with split_line at boundary
   - For pure delete: emit delete char ops + join_lines
   - For pure insert: emit split_line + insert char ops
3. Emit new op types: `keep_line`, `join_lines`, `split_line`
4. Test: `bin/ad_compute old.py new.py /tmp/ops.tsv` produces correct ops
5. Verify: C animator (with new op handlers) produces correct output

### Phase 2: Animator updates

1. Add handlers for `keep_line`, `join_lines`, `split_line` in C animator
2. Remove all `code == 10` special-casing from C animator
3. Add handlers in vimscript animator
4. Remove all `code == 10` special-casing from vimscript animator
5. Test: 42/42 examples pass with no layers

### Phase 3: Layer updates

1. Update `ad_layer_common.h`: parse new op types
2. Simplify each layer (remove \n special-casing):
   - reorder: line ops are segment boundaries
   - overwrite: all char ops are non-\n, merge freely
   - indent_last: segment boundaries are line ops
   - line_delete_in_place: may become unnecessary
   - skip_indent: check for line ops instead of \n
   - pace: no \n special-casing
   - highlight: check for line ops instead of \n
   - line_replace: use explicit line boundaries
3. Test: L1/L2 shows 42/42 for ALL layer combinations

### Phase 4: Tooling updates

1. Update `ad_annotate` for new op types
2. Update vim syntax file
3. Update Perl twins (diff engine, animator, all layers)
4. Update documentation (vocabulary, layer reference, etc.)

### Phase 5: Merge

1. Run ALL tests (examples, property, fuzz, layers)
2. Verify L1/L2 on all layer combinations
3. Merge to main

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Diff engine rewrite introduces bugs | Test against all 42 examples + 50 property tests after each step |
| Per-line char diff produces different (worse) animation | Compare op counts before/after — should be similar |
| Perl twins fall behind | Do C first, verify, then port to Perl |
| Line merge/split detection is complex | Start simple: handle 1:1, N:1, 1:N. Handle N:M as sequence of N:1 + 1:N. |

## Decision Points

1. **Should `keep_line` carry the line number?** Yes — the animator needs
   to know which line to advance from.

2. **Should `join_lines` carry the line number?** Yes — join line L with L+1.

3. **Should `split_line` carry the col?** Yes — split at the col where the
   new line starts.

4. **What about `is_end_insert` / `is_end_delete`?** These become:
   - `is_end_insert`: `split_line` at end of file (no content after)
   - `is_end_delete`: `join_lines` at last line (no next line to join with)

5. **Should the HUNK header change?** No — `target/del/ins` still describe
   the line-level change. The ops within just use new types.

## Estimated effort

- Phase 1 (diff engine): 2-3 hours
- Phase 2 (animators): 1 hour
- Phase 3 (layers): 2 hours (mostly simplification/deletion)
- Phase 4 (tooling): 1 hour
- Phase 5 (testing): 30 min

Total: ~6-7 hours of focused work.
