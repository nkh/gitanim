# Postprocess Operations — `animator/c/postprocess.c`

This document is a complete, code-faithful reference for **every** operation
and transformation the postprocessor applies to the raw char-op stream. It
covers the v2 TSV pipeline (`cc -O2 -o diffvim-postprocess postprocess.c`).
Reading this document alone should be sufficient to reimplement the
postprocessor from scratch.

## Op format / data model

The postprocessor reads v2 TSV from stdin:

```
# diffvim raw diff v2
HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
keep\t<line>\t<col>\t<code>
delete\t<line>\t<col>\t<code>
insert\t<line>\t<col>\t<code>
HUNK_END
```

The internal `Op` struct is `{ char type[20]; int code; int line; int col; }`.
Only `type` and `code` are read from input — the input `line`/`col` fields are
ignored, and `postprocess.c` **recomputes** every op's `(line, col)` itself
during the emit loop. (The header comment says: *"The postprocess stage OWNS
cursor positioning."*). The raw input line/col from `compute` is informational.

`code` is the byte value (10 = `\n`, 9 = `\t`, 32 = space, 33..126 printable,
etc.).

Two entry modes exist:

- **Batch** — `read_input()` slurps the whole file, then `write_output()`
  processes all hunks with the full transform stack **and** the ghost-line
  fix logic.
- **Streaming** (`--stream`) — `stream_process()` calls `process_one_hunk()`
  per hunk. The streaming path applies `semantic_cleanup` and
  `reorder_hunk_ops` but **does NOT** apply `overwrite_transform`, the
  ghost-line `\n`-delete look-ahead, or the insert-`\n`-first fix. See
  *Caveats — streaming mode* at the end.

## Transform pipeline (batch mode)

Per hunk, in `write_output()` (lines 541–828):

```
   raw ops  ──►  [if do_semantic]      semantic_cleanup
              ──►  [if op_order_optimize]  reorder_hunk_ops
                                  ├──  op_order_left_to_right  ─► left_to_right_line
                                  ├──  op_order_end_first(_smart) ─► end_first_line
                                  ├──  op_order_optimize      ─► optimize_line
                                  └──  (else)                 ─► memcpy
                                  then [if do_indent_last]    ─► indent_last_transform
              ──►  [if do_overwrite]     overwrite_transform
              ──►  emit loop:
                     ├── per-op (line,col) cursor simulation
                     ├── ghost-line fix on "delete \n"
                     └── ghost-line fix on inserts at col 1 with line_has_content
```

**Order is fixed** — semantic-cleanup always runs before reordering; reordering
always runs before overwrite; the ghost-line fix always runs last, in the
emit loop. None of these can be reordered by the user.

**Default flags:**
| Flag                       | Default | Activated by |
|----------------------------|---------|--------------|
| `op_order_optimize`        | **1**   | `--op-order optimize` (default; also cleared by `natural`) |
| `op_order_left_to_right`   | 0       | `--op-order left-to-right` |
| `op_order_end_first`       | 0       | `--op-order end-first` |
| `op_order_end_first_smart` | 0       | `--op-order end-first-smart` |
| `do_semantic`              | 0       | `--semantic-cleanup` |
| `do_indent`                | 0       | `--indent-aware` (flag only — see below) |
| `do_overwrite`             | 0       | `--overwrite` |
| `do_indent_last`           | 0       | `--indent-last` |
| `stream_mode`              | 0       | `--stream` |

The op-order flags are mutually exclusive in practice (the dispatcher checks
them in order: left-to-right wins, then end-first/end-first-smart, then
optimize, else raw copy).

---

# 1. DEFAULT OPERATIONS (always-on, no option needed)

These run unconditionally on every hunk in batch mode.

## 1.1 Header rewriting

**Where:** `write_output()`, lines 543–560.

**What it does:** Walks the collected header lines and rewrites them on the
way to stdout:

- `# diffvim raw diff`      → `# diffvim post-processed v2`
- `# diffvim precomputed`   → `# diffvim post-processed v2`
- `# semantic_cleanup N`   → `# semantic_cleanup <do_semantic>`  (reflects current flag)
- `# indent_aware N`       → `# indent_aware <do_indent>`
- `# optimize_sequence N`  → `# optimize_sequence <op_order_optimize>`
- `# hunk_count N`         → `# hunk_count <n_hunks>`  (recomputed)
- `# word_diff ...` and `# left_to_right ...`  → passed through verbatim
- Any other header line    → **silently dropped**

**Related options:** every transform flag has a corresponding header field
that gets rewritten here, so downstream stages can read the actual flag
values. `indent-aware` is purely a propagated flag (no transform applied in
this file — see §2.4).

## 1.2 Hunk header emission

**Where:** `write_output()`, line 566.

For each hunk the line
```
HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
```
is emitted. The `end_ins` / `end_del` flags come from `compute` and indicate
whether the hunk is inserting/deleting the very last line of the file (which
has no trailing `\n`). These flags are consulted by the ghost-line fix
(§1.6) and otherwise ignored.

After all ops in a hunk, `HUNK_END` is printed; after all hunks, a single
blank line is printed at the bottom of the file.

## 1.3 Default op-order mode = `optimize` (the `optimize_line` transform)

**Where:** `reorder_hunk_ops()` (line 383) → `optimize_line()` (line 299).

This is **always on** unless the user passes `--op-order natural`.

**Triggering pattern:** Any line group (a run of ops terminated by `\n`)
with more than one op. Single-op line groups are copied verbatim.

**Steps taken:** Within each line group, partition the ops into "change
regions" delimited by `keep` ops. Then, within each change region, emit in
four sweeps:

1. **Content deletes** (code != 10) — delete old content first
2. **Content inserts** (code != 10) — insert new content
3. **\n deletes** (code == 10) — join lines AFTER content is done
4. **\n inserts** (code == 10) — create new lines AFTER content is done

This ordering PREVENTS ghost lines: the \n delete only happens
after all content changes, so it never joins a line that still has
pending content ops.

`keep` ops are emitted in place (in their original position between change
regions). The `\n` delete is moved to the end of each change region's
delete sweep so that line content is removed before the line's terminator
vanishes.

**Example input ops (raw compute order):**
```
keep    'a'           col 1
insert  'X'           col 2
delete  'b'           col 2
keep    'c'           col 3
delete  '\n'          col 4
insert  'Y'           col 4
```

**After optimize_line:**
```
keep    'a'                              (kept in place)
delete  'b'           ← content delete first
delete  '\n'          ← newline delete after content
insert  'X'           ← inserts last
keep    'c'                              (kept in place)
delete  (no more deletes in this region)
insert  'Y'
```

(In reality, optimize_line splits only between `keep`s, so a `\n` delete
that ends the line stays grouped with the content deletes of its region.)

**How other options interfere:**
- `--op-order natural` disables this; raw patience order is emitted.
- `--op-order left-to-right` replaces this with `left_to_right_line` (§2.1.2).
- `--op-order end-first` or `end-first-smart` calls `end_first_line` (§2.1.3,
  §2.1.4), which itself calls `optimize_line` first.
- `--indent-last` runs *after* this and operates on the optimized output
  (§2.2).
- `--overwrite` runs *after* this and relies on deletes+inserts being
  adjacent (§2.5).

**Related options:** the `--semantic-cleanup` step, which runs before this,
can eliminate `delete+insert` pairs entirely, so they never reach this
function.

## 1.4 Per-op `(line, col)` cursor simulation

**Where:** `write_output()`, lines 641–818.

The postprocessor walks each hunk's final ops and simulates a cursor over
the *original* file as if the buffer were being edited in place. Variables:

- `cur_line = hunks[h].target + line_offset` (initial cursor position;
  `line_offset` accumulates net newline inserts minus deletes from earlier
  hunks, so each hunk targets the **current** buffer position, not the
  original old-file line)
- `cur_col = 1`
- `line_has_content = 0` (true if a non-`\n` `keep` has been emitted on the
  current line)
- `newl_ins`, `newl_del` (counters added to `line_offset` for the next hunk)

**Cursor rules** (when no ghost-line fix triggers):

| Op type        | code | Action                                                         | Effect on cursor |
|----------------|------|----------------------------------------------------------------|------------------|
| `keep`         | ≠ 10 | emit `op\tkeep\t<cur_line>\t<cur_col>\t<code>`                  | `cur_col++`, `line_has_content = 1` |
| `keep`         | = 10 | emit `keep\t<cur_line>\t<cur_col>\t10`                         | `cur_line++`, `cur_col = 1`, `line_has_content = 0` |
| `delete`       | ≠ 10 | emit `op\tdelete\t<cur_line>\t<cur_col>\t<code>`                | cursor unchanged |
| `delete`       | = 10 | **see ghost-line fix (§1.6)**                                  | varies |
| `insert`       | ≠ 10 | **see ghost-line fix (§1.7)** first, then `op\tinsert\t<cur_line>\t<cur_col>\t<code>` | `cur_col++` |
| `insert`       | = 10 | emit `insert\t<cur_line>\t<cur_col>\t10`                      | `cur_line++`, `cur_col = 1`, `newl_ins++`, `line_has_content = 0` |
| `overwrite_insert` | ≠ 10 | emit `op\toverwrite_insert\t<cur_line>\t<cur_col>\t<code>` | `cur_col++` (same as insert, but pace will use zero delay) |

**`line_offset` accumulation:** after each hunk, `line_offset += newl_ins - newl_del`. This means each hunk's `target` line is corrected by every
line that previous hunks have added or removed. Without this correction,
later hunks in a multi-hunk diff would target stale line numbers.

**Output format** (1-indexed line/col):

```
op\t<keep|delete|insert|overwrite_insert>\t<line>\t<col>\t<code>\t<char_repr>
```

where `<char_repr>` is `\n`, `\t`, `\r`, `space`, `'c'` for printable, or
the decimal code otherwise. (Emit is via `emit_op()` line 625.)

## 1.5 Ghost-line fix — "delete `\n`" look-ahead

**Where:** `write_output()`, lines 654–775, inside the `\n` `delete` branch.

This is the most subtle part of the postprocessor. Without it, deleting a
`\n` *before* deleting the next line's content would join the next line's
content onto the current line, producing the "ghost line" bug (the joined-in
content briefly appears in the wrong place during animation).

**Triggering pattern:** an op `delete \n` (i.e. `type == "delete"` and
`code == 10`) anywhere in the hunk.

**Look-ahead logic:**

1. From position `i+1`, scan forward `j` while the ops are
   `delete` with `code != 10`. Let `n_content = j - (i+1)` be the count of
   content deletes that follow the `\n` delete.
2. Check what follows at position `j`:
   - If `j < n_out` and `final_ops[j]` is `keep` or `insert`, set
     `followed_by_keep_or_insert = 1`.
3. Dispatch on the combination:

| `n_content` | `followed_by_keep_or_insert` | `i == 0 && end_del` | Action |
|-------------|------------------------------|---------------------|--------|
| > 0         | 0                            | no                  | **"Delete next line" pattern** — see below |
| > 0         | 0                            | yes                 | **"End-delete with content" variant** — see below |
| (any)       | 1                            | —                   | **Legitimate line merge** — emit `delete \n` at `(cur_line, cur_col)`, `newl_del++`, `line_has_content = 0`. Cursor unchanged. |
| 0           | 0                            | yes (`i==0 && end_del && cur_line>1`) | **"Delete last line" pattern** — emit `delete \n` at `(cur_line - 1, 1)`, `newl_del++`. Cursor unchanged. |
| 0           | 0                            | no                  | **Normal `\n` delete** — emit `delete \n` at `(cur_line, cur_col)`, `newl_del++`. Cursor unchanged. |

### "Delete next line" pattern (the main case)

Triggered when content deletes follow the `\n` delete, and no `keep`/`insert`
intervenes. The fix: do *not* delete the `\n` from `cur_line` (which would
join the next line onto `cur_line`). Instead, advance the cursor to the
next line, delete its content there, *then* delete the (now empty) next
line's `\n` to join the line *after* next.

**Pseudocode (normal branch, no end_del):**
```
next_line = cur_line + 1
for k in (i+1 .. j-1):
    emit delete  <next_line>  1  <code>     // delete content on next line
emit delete  <next_line>  1  10            // delete the empty next line's \n
newl_del++
line_has_content = 0
i = j                                        // skip past content deletes
continue                                     // skip the normal `i++`
```

`cur_line` is intentionally **not** incremented here. After this branch the
next op (originally at index `j`) is treated as being on `cur_line + 1`
(because the line *after* the emptied next line has now shifted up into the
next line's slot).

**End-delete variant** (when `i == 0` and the hunk's `end_del` flag is set):
the "next line" is actually the *last line of the file* (which has no `\n`
after it). The content lives on `cur_line` itself, not `cur_line+1`:

```
for k in (i+1 .. j-1):
    emit delete  <cur_line>  1  <code>
emit delete  <cur_line - 1>  1  10    // join empty last line onto previous
newl_del++
line_has_content = 0
i = j
continue
```

### "Delete last line" pattern

When `delete \n` is the first op of a hunk (`i == 0`) and the hunk's
`end_del` flag is set, the file's *last* line is being deleted (there is no
content after it to look ahead at). Emit the `\n` delete at
`(cur_line - 1, 1)`, joining the empty current line onto the *previous*
line, preserving the previous line's content. `cur_line` is unchanged.

### "Legitimate line merge"

When the `\n` delete is immediately followed by a `keep` or `insert` (not
content deletes), the line boundary is being genuinely removed — e.g. two
paragraphs being merged into one. Emit `delete \n` at `(cur_line, cur_col)`
normally. Cursor unchanged.

### Normal `\n` delete

Catch-all: emit `delete \n` at `(cur_line, cur_col)`. Cursor unchanged.

**Example (delete-next-line pattern):**

Input ops (already optimized):
```
delete 'X'  ← line 7's content
delete '\n' ← line 7's terminator
delete 'Y'  ← line 8's content (next line)
delete 'Z'
```

Without the fix, emitting at `cur_line` would join "YZ" onto line 7's tail
during animation (the ghost-line bug). With the fix:

```
delete  line=7   col=1   'X'        ← delete line 7's content (already there)
delete  line=8   col=1   'Y'        ← delete line 8's content at cur_line+1
delete  line=8   col=1   'Z'
delete  line=8   col=1   10         ← delete the now-empty line 8's \n
```

`cur_line` stays at 7 (line 9's content shifts up into line 8's slot, so
the next iteration again operates on what is now line 8 = original line 9).

**How other options interfere:**
- The fix operates on `final_ops`, i.e. *after* `semantic_cleanup`,
  `reorder_hunk_ops`, and `overwrite_transform`. So all three transforms
  must have already run.
- `--semantic-cleanup` may merge some `delete + insert` pairs into `keep`s,
  reducing the number of `\n` deletes that reach this branch.
- `--indent-last` reorders so the `\n` delete is last in its line group;
  this is *helpful* because the look-ahead for "delete next line" pattern
  depends on the `\n` delete being followed by content deletes —
  `indent-last` doesn't change whether content follows, only its order
  within the *current* line.
- `--overwrite` may convert a `delete+insert` pair into
  `delete+overwrite_insert`. The `\n` look-ahead only counts *content*
  deletes (code != 10), and only triggers the merge behavior on `keep`/
  `insert` (it does **not** check `overwrite_insert` — so an
  `overwrite_insert` immediately after a `\n` delete is *not* treated as
  a "legitimate merge"; the dispatcher's `followed_by_keep_or_insert`
  check ignores it). This is a subtle interaction worth noting.

**Related options:** none that control whether the fix runs. It is always
active in batch mode. (In `--stream` mode it is *not* applied — see
caveats.)

## 1.6 Ghost-line fix — insert `\n` first when inserting at col 1 with content

**Where:** `write_output()`, lines 798–806.

**Triggering pattern:** an op `insert` with `code != 10`, where `cur_col == 1`
and `line_has_content == 1` (i.e. a non-`\n` keep has already been emitted
on the current line, but the cursor is back at column 1).

**Steps taken:** before emitting the user-facing insert, emit a synthetic
`insert \n` at `(cur_line, 1)` to push the existing content onto a new
line. Then advance `cur_line++`, `cur_col = 1`, `newl_ins++`,
`line_has_content = 0`. Finally, emit the original insert op.

This prevents the inserted character from pushing the existing line's
content rightward (a visual artifact the comment calls out as
"adding `import json` before `import os`" — though in practice, in
`optimize` mode the keeps come before the inserts in each line group, so
this branch fires only in narrow scenarios where the cursor has been
reset to col 1 by an intermediate `\n`-delete without resetting
`line_has_content`).

**How other options interfere:** none directly — it is unconditional in the
emit loop. It interacts with `--op-order` modes that change which ops are
emitted at `cur_col == 1` (e.g. `left-to-right` puts keeps first; deletes
and inserts follow, by which point `cur_col > 1`).

**Related options:** none.

## 1.7 `line_offset` cross-hunk accounting

**Where:** `write_output()`, line 562 (`line_offset = 0`) and line 824
(`line_offset += newl_ins - newl_del`).

Each hunk's `target` line is corrected by every newline inserted/deleted by
prior hunks. This is a **default** behavior — there is no flag to disable
it. Without it, a diff with multiple hunks would mis-target every hunk after
the first.

**Example:**
- Hunk 0 at target=5 inserts 2 newlines (`newl_ins=2`, `newl_del=0`). After
  hunk 0, `line_offset = 2`.
- Hunk 1's `target=8` is emitted as `cur_line = 8 + 2 = 10` — the post-hunk-0
  line number, not the original old-file line 8.

---

# 2. OPTION-ACTIVATED TRANSFORMS

## 2.1 `--op-order MODE` (op-order modes)

Activates one of five reordering strategies inside `reorder_hunk_ops()`.
The dispatcher (lines 386–417) splits each hunk into **line groups**
(runs terminated by `\n`, inclusive), then applies the chosen line-group
transform only when the group has more than one op. Single-op groups are
copied verbatim.

The op-order flags are mutually exclusive — the dispatcher checks them in
this priority order: `op_order_left_to_right`, then
`op_order_end_first || op_order_end_first_smart`, then
`op_order_optimize`, else "natural" (raw memcpy).

### 2.1.1 `--op-order optimize` (the DEFAULT — see §1.3)

Calls `optimize_line()`. Already documented in §1.3 as a default operation;
listed here only because the user may explicitly request it.

### 2.1.2 `--op-order natural`

**What activates it:** `--op-order natural` (clears `op_order_optimize`,
no other flag set).

**State that triggers it:** every line group.

**Steps taken:** raw `memcpy` of the input line group to the output — no
reordering. The patience order from `compute` is preserved as-is.

**How other options interfere:**
- `--indent-last` still runs *after* the memcpy if set (so even in
  `natural` mode, leading-whitespace deletes can be moved to last).
- `--overwrite` still runs on the result, but is unlikely to find adjacent
  `delete+insert` pairs unless `compute` happened to emit them adjacent.

**Related options:** mutually exclusive with the other op-order modes.

### 2.1.3 `--op-order left-to-right`

**What activates it:** `--op-order left-to-right` (sets
`op_order_left_to_right = 1`).

**State that triggers it:** every line group with >1 op.

**Steps taken** (`left_to_right_line()`, lines 350–359):
Stable three-pass partition of the line group:

1. All `keep` ops (in original order)
2. All `delete` ops (in original order, **including** `\n` deletes — no
   special-casing)
3. All `insert` ops (in original order)

No special handling of `\n` deletes — they are emitted wherever they fall
in the original delete order, which means a trailing `\n` delete on the
line group will naturally end up at the end of the delete sweep.

**Example input:**
```
insert 'X'
keep   'a'
delete 'b'
keep   'c'
delete '\n'
```

**After left_to_right_line:**
```
keep   'a'
keep   'c'
insert 'X'
delete 'b'
delete '\n'
```

**How other options interfere:**
- `--indent-last` still runs after this transform on the same line group.
- `--overwrite` may find fewer adjacent `delete+insert` pairs than in
  `optimize` mode, because deletes are all grouped together (interrupted
  only by other deletes), not interleaved with inserts.
- The ghost-line fix (§1.5) runs on the result; the look-ahead still works
  because it scans for `delete` ops regardless of order.

**Related options:** mutually exclusive with the other op-order modes.
Conflicts conceptually with `optimize` (the default) — they produce
different orders.

### 2.1.4 `--op-order end-first`

**What activates it:** `--op-order end-first` (sets `op_order_end_first = 1`).

**State that triggers it:** every line group with >1 op.

**Steps taken** (`end_first_line()`, lines 364–377):
1. Calls `optimize_line(in, count, out)` — so the result is identical to
   the default `optimize` order.
2. Computes `last_non_nl = (in[count-1].code == 10) ? count-2 : n_out-1`
3. Checks `if (last_non_nl >= 0 && out[last_non_nl].type == "delete")` —
   but **the body of this `if` is empty** (it's a comment-only block).

So `end-first` mode is currently **identical to `optimize`**. The comment
acknowledges this: *"end-first is the same as optimize for single-line
groups. The real difference is for multi-line groups, which we don't handle
here."* A future implementation may move trailing deletes (the last
non-`\n` op) before the inserts in the line group, but that behavior is
not yet implemented.

**How other options interfere:** same as `optimize` (since it calls
`optimize_line`).

**Related options:** `end-first-smart` calls the same function — they are
identical in this implementation.

### 2.1.5 `--op-order end-first-smart`

**What activates it:** `--op-order end-first-smart` (sets
`op_order_end_first_smart = 1`).

**State that triggers it:** every line group with >1 op.

**Steps taken:** identical to `--op-order end-first` (§2.1.4). The
dispatcher treats `end_first_smart` the same as `end_first`. There is no
"smart" behavior implemented in `postprocess.c` — the name is reserved.

## 2.2 `--indent-last`

**What activates it:** `--indent-last` (or `--transform indent-last`),
sets `do_indent_last = 1`.

**Where:** `reorder_hunk_ops()`, lines 404–408 (applies
`indent_last_transform()` *after* the op-order transform on every line
group); `indent_last_transform()` itself at lines 444–508.

**State that triggers it (per line group):**

1. The line group must have more than one op.
2. **Every** non-`\n` op in the line group must be a `delete` (no `keep`s,
   no `insert`s). I.e. the entire line is being deleted. If any `keep` or
   non-`\n` `insert` is present, the transform is a no-op and the line
   group is copied verbatim.
3. The line group must start with one or more `delete` ops whose `code` is
   `32` (space) or `9` (tab). This leading run is the *indentation*. If
   there is no leading whitespace (i.e. content begins at column 1), the
   transform is a no-op.

**Steps taken:**

1. Scan from the start of the line group, counting the run of leading
   whitespace `delete` ops. Call the end of this run `indent_end`.
2. Emit the line group in four sweeps:

   1. **Content deletes** — all ops from `indent_end` to the end of the
      group, **excluding** the `\n` delete.
   2. **Indentation deletes** — the leading whitespace run
      (`ops[0 .. indent_end-1]`).
   3. **Newline delete** — the `\n` delete (if any), emitted last.

**Example** (a line `\t\t 12345 6789\n` being fully deleted):

Input ops (already optimized, so deletes are already in original order):
```
delete '\t'    ← leading indentation
delete '\t'    ← leading indentation
delete ' '
delete '1'
delete '2'
delete '3'
delete '4'
delete '5'
delete ' '
delete '6'
delete '7'
delete '8'
delete '9'
delete '\n'
```

After `indent_last_transform`:
```
delete ' '     ← content (non-leading whitespace, after indent_end)
delete '1'
delete '2'
delete '3'
delete '4'
delete '5'
delete ' '
delete '6'
delete '7'
delete '8'
delete '9'
delete '\t'    ← indentation (moved to last)
delete '\t'    ← indentation
delete '\n'    ← newline (kept at very end)
```

The visible effect during animation: the line's text disappears first
(while the indentation is still anchored to the left margin), then the
indentation collapses, then the line itself is removed. This prevents the
"left shift" artifact where deleting the indentation first causes the
remaining content to visibly slide left before being deleted.

**How other options interfere:**
- Runs *after* the op-order transform. In `optimize` mode, all deletes are
  already grouped together, so `indent_last` just reorders *within* that
  delete group. In `left-to-right` mode, same — all deletes are together.
  In `natural` mode, the input may not have deletes grouped, but
  `indent_last_transform` walks linearly and only looks at the *leading*
  run, so it still works.
- The "entire line is being deleted" check examines the *post-reorder*
  ops, which in `optimize` mode means the line group is `delete+delete+...
  +delete(\n)`. The check passes if there are no `keep`s or `insert`s.
- `--semantic-cleanup` runs *before* this; if it converts a `delete+insert`
  pair to a `keep`, that line group will no longer satisfy the "all
  deletes" condition and `indent_last` will be a no-op for it.
- `--overwrite` runs *after* this; since `indent_last` only operates on
  pure-delete line groups, there are no `insert`s to convert to
  `overwrite_insert` afterward.

**Related options:** specifically designed to compose with `--op-order
optimize` (the default). Without an op-order transform that groups
deletes, `indent_last` still functions but may produce surprising orders
in `natural` mode.

## 2.3 `--semantic-cleanup`

**What activates it:** `--semantic-cleanup` (or
`--transform semantic-cleanup`), sets `do_semantic = 1`.

**Where:** `write_output()` line 576–580 (runs *first*, on the raw ops
before any reordering); `semantic_cleanup()` at lines 320–346.

**State that triggers it:** any adjacent pair of ops where one is `delete`
and the other is `insert` (in either order), and both have the **same
`code`** (i.e. the character being deleted is the same as the character
being inserted at the same position — a net no-op).

**Steps taken:** Single linear scan from `i = 0` to `count`:

- If `in[i]` is `delete` and `in[i+1]` is `insert` and
  `in[i].code == in[i+1].code`: emit one `keep` with that code, advance `i`
  by 2.
- Else if `in[i]` is `insert` and `in[i+1]` is `delete` and
  `in[i].code == in[i+1].code`: emit one `keep` with that code, advance `i`
  by 2.
- Else: copy `in[i]` to output, advance `i` by 1.

The resulting `keep` op inherits the *code* of the cancelled pair (the
`line`/`col` fields are recomputed later in the emit loop, so they don't
matter).

**Example input:**
```
delete 'a'
insert 'a'
delete 'b'
insert 'c'
```

After `semantic_cleanup`:
```
keep 'a'        ← (delete 'a' + insert 'a') cancelled → keep
delete 'b'      ← no match
insert 'c'
```

**How other options interfere:**
- Runs **before** every other transform, so its output feeds
  `reorder_hunk_ops`, `overwrite_transform`, and the ghost-line fix.
- By converting `delete+insert` pairs to `keep`s, it can change which line
  groups satisfy `indent_last`'s "all deletes" condition (turning a
  formerly all-delete line into a line with a `keep`, which disables
  `indent_last` for that group).
- By removing `delete+insert` pairs, it reduces the number of adjacent
  `delete+insert` pairs available for `overwrite_transform` to convert.

**Related options:** composes cleanly with all other options. Often paired
with `--op-order optimize` to first cancel no-op edits, then reorder.

## 2.4 `--indent-aware`

**What activates it:** `--indent-aware` (or `--transform indent-aware`),
sets `do_indent = 1`.

**Where:** the flag is **parsed and emitted in the output header**
(`# indent_aware 1`), but it is **NOT consulted by any transform in
`postprocess.c`**. There is no `indent-aware` transform implemented in this
file.

**State that triggers it:** none — the flag is a pure pass-through.

**Steps taken:** the flag value is written to the output header line
`# indent_aware <do_indent>` so downstream stages (the `pace` tool or the
`animator`) can read it and apply indent-only-change handling themselves.
The postprocessor itself does nothing different when this flag is set.

**How other options interfere:** none — the flag is independent.

**Related options:** expected to be combined with `--op-order optimize`
(the downstream consumer reads both). Without a downstream consumer, this
flag is inert.

## 2.5 `--overwrite`

**What activates it:** `--overwrite` (or `--transform overwrite`), sets
`do_overwrite = 1`.

**Where:** `write_output()` lines 589–596 (runs *after*
`reorder_hunk_ops`); `overwrite_transform()` at lines 514–531.

**State that triggers it:** an adjacent pair in the final op array where:
- `final_ops[i]` is `delete` and `code != 10` (a content delete, not `\n`)
- `final_ops[i+1]` is `insert` and `code != 10` (a content insert, not `\n`)

The two ops do **not** need to have the same `code` — the transform is
about position, not value. (It converts "delete char X then insert char Y
at the same place" into "overwrite X with Y".)

**Steps taken:** single linear scan:

1. Copy `in[i]` to `out`.
2. If `do_overwrite` and the pair `(in[i], in[i+1])` matches the pattern:
   - Keep `out[n_out-1]` as a `delete` (the line
     `strcpy(out[n_out - 1].type, "delete")` is a no-op since it was
     already `"delete"`).
   - Advance `i` by 1 (skip the insert).
   - Copy `in[i]` (the insert) to `out[n_out]` and overwrite its `type`
     field with `"overwrite_insert"`.
   - `n_out++`.

**Example input** (after optimize_line — deletes before inserts in the
same change region):
```
delete 'a'
insert 'X'
delete 'b'
insert 'Y'
keep   'c'
```

After `overwrite_transform`:
```
delete           'a'
overwrite_insert 'X'
delete           'b'
overwrite_insert 'Y'
keep             'c'
```

The downstream `pace` tool is expected to use **zero delay** between a
`delete` and the immediately-following `overwrite_insert`, producing the
visual effect of in-place character replacement (no gap, no flicker).

**How other options interfere:**
- Runs **after** `reorder_hunk_ops`. In `optimize` mode, content deletes
  and inserts within the same change region are already adjacent (deletes
  first, then inserts), so the transform finds pairs readily. In
  `left-to-right` mode, all deletes are grouped together, then all
  inserts — so adjacent `delete+insert` pairs occur only at the
  delete/insert boundary, not throughout.
- Runs **after** `indent_last`, but `indent_last` only applies to
  all-delete line groups (no inserts), so `overwrite` finds nothing to
  convert in those groups anyway.
- Runs **before** the ghost-line fix's `followed_by_keep_or_insert` check.
  The check explicitly tests for `"keep"` or `"insert"` — it does **not**
  recognize `"overwrite_insert"`. So a `\n` delete immediately followed by
  an `overwrite_insert` is treated as if it's followed by neither — i.e.
  it can fall into the "delete next line" pattern. This is a subtle
  interaction: if `overwrite` has converted the post-`\n`-delete `insert`
  into `overwrite_insert`, the ghost-line dispatcher may misclassify the
  pattern. In practice, `\n` deletes are rarely adjacent to content
  inserts because `optimize_line` puts `\n` deletes at the *end* of each
  change region's delete sweep, after content deletes.
- The emit loop (§1.4) handles `overwrite_insert` exactly like `insert`
  for cursor purposes (`cur_col++`), but emits the type string
  `op\toverwrite_insert\t...` so `pace` can recognize it.

**Related options:** most useful with `--op-order optimize` (the default)
because that mode produces the adjacent `delete+insert` pairs the
transform relies on. With `--op-order natural`, pairs may not be adjacent.

---

# 3. Caveats — streaming mode (`--stream`)

The streaming code path (`stream_process()` → `process_one_hunk()`) is a
**simplified** version of the batch path. Differences:

| Feature                              | Batch (`write_output`) | Streaming (`process_one_hunk`) |
|--------------------------------------|------------------------|--------------------------------|
| `semantic_cleanup`                   | ✓ if `do_semantic`     | ✓ if `do_semantic`             |
| `reorder_hunk_ops` (incl. all op-order modes) | ✓ if `op_order_optimize` | ✓ if `op_order_optimize` |
| `indent_last_transform` (inside `reorder_hunk_ops`) | ✓ if `do_indent_last` | ✓ if `do_indent_last` |
| `overwrite_transform`                | ✓ if `do_overwrite`    | **✗ NOT applied**              |
| Ghost-line fix on `delete \n`        | ✓ always               | **✗ NOT applied**              |
| Ghost-line fix on `insert` at col 1  | ✓ always               | **✗ NOT applied**              |
| `line_offset` cross-hunk accounting  | ✓                      | ✓                              |
| Header `# hunk_count`                | ✓ (actual count)       | emitted as `-1` (unknown)      |
| `end_del` / `end_ins` flags          | consulted by ghost-line fix | parsed but ignored        |

In streaming mode the emit loop is a simple `for` over `final_ops`: each
`\n` op emits at `(cur_line, cur_col)`, content ops emit at the current
cursor with `cur_col++` for `keep`/`insert`. No look-ahead. This means
streaming output can exhibit the ghost-line bug for diffs that delete a
line whose content extends to the next line.

Streaming mode is appropriate when latency matters more than correctness
(e.g. piping through `pace` for live animation), or when the input is
known to not trigger the ghost-line bug (single-line hunks, no `\n`
deletes adjacent to content deletes).

---

# 4. Quick reference — option interaction matrix

| Option             | Default | Runs at step | Modifies                          | Reads from            |
|--------------------|---------|--------------|-----------------------------------|-----------------------|
| (header rewrite)   | always  | header       | header lines                      | all flags             |
| (cursor sim)       | always  | emit         | `(line, col)` per op             | `target`, `line_offset` |
| (ghost-line: `\n`) | always  | emit         | `delete \n` line numbers          | `end_del` flag, lookahead |
| (ghost-line: ins)  | always  | emit         | inserts synthetic `insert \n`     | `line_has_content`    |
| `optimize`         | ON      | reorder      | order within line groups          | line-group boundaries |
| `natural`          | off     | reorder      | (none — raw memcpy)              | —                     |
| `left-to-right`     | off     | reorder      | order within line groups          | line-group boundaries |
| `end-first`        | off     | reorder      | (identical to `optimize`)        | —                     |
| `end-first-smart`   | off     | reorder      | (identical to `optimize`)        | —                     |
| `indent-last`      | off     | reorder (after op-order) | moves leading-ws deletes to last | all-deletes check    |
| `semantic-cleanup` | off     | first        | merges canceling pairs to `keep`  | adjacent pairs        |
| `indent-aware`     | off     | (header only)| (flag pass-through)              | —                     |
| `overwrite`        | off     | after reorder| marks `insert` → `overwrite_insert` | adjacent `delete+insert` |

**Composition rules of thumb:**

- `semantic-cleanup` first, then op-order mode, then `indent-last`
  (inside the same call to `reorder_hunk_ops`), then `overwrite`, then
  the emit-loop ghost-line fixes.
- `indent-last` and `overwrite` are non-overlapping by construction
  (`indent-last` only touches all-delete line groups; `overwrite` only
  touches `delete+insert` adjacent pairs).
- `indent-aware` is a no-op in this file — it only changes the output
  header for downstream consumption.
- `end-first` and `end-first-smart` are reserved names that currently
  behave identically to the default `optimize` mode.
- The `--transform NAME[:VALUE]` flag is the canonical interface; the
  bare flags (`--semantic-cleanup`, etc.) are shorthands.

---

# 5. Reproducing the postprocessor — checklist

To reimplement `postprocess.c` from this document:

1. Parse v2 TSV input. Reject v1 (space-separated `HUNK `) with an error.
   Collect header lines, hunks (with `target`/`del`/`ins`/`end_ins`/
   `end_del`/`op_start`/`op_count`), and ops (`type`, `code`).
2. Initialize flags from CLI: `op_order_optimize = 1` by default; the
   `--op-order` argument can clear it (`natural`) or set one of
   `left_to_right` / `end_first` / `end_first_smart`.
3. For each hunk (batch mode):
   1. If `do_semantic`: run `semantic_cleanup` on the raw ops.
   2. If `op_order_optimize`: run `reorder_hunk_ops` — split into line
      groups, dispatch to the chosen mode (`left_to_right_line`,
      `end_first_line`, `optimize_line`, or raw memcpy), then if
      `do_indent_last` run `indent_last_transform` on each group's
      result.
   3. If `do_overwrite`: run `overwrite_transform` on the reordered ops.
   4. Emit the hunk header `HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>`.
   5. Walk `final_ops` with the cursor-simulation emit loop:
      - For `delete \n`: run the look-ahead (§1.5) and dispatch to one of
        the five branches.
      - For non-`\n` `insert` at `cur_col == 1 && line_has_content`:
        emit a synthetic `insert \n` first (§1.6).
      - For all other ops: emit at `(cur_line, cur_col)` and update the
        cursor per the table in §1.4.
   6. Emit `HUNK_END` and accumulate `line_offset += newl_ins - newl_del`.
4. After all hunks, emit a trailing blank line.

Streaming mode skips step 3.3 (overwrite) and simplifies step 3.5 to a
plain cursor walk (no ghost-line fix), and emits `# hunk_count -1` in
the header.
