# Postprocess Rewrite — Design Document

**Status:** Implemented. The layered architecture below is reflected in
the current code (`postprocess.c`, `pp_layer0_v2.c`, `pp_layer1_reorder.c`,
`pp_layer_indent_last.c`, `pp_layer_overwrite.c`). Cursor recomputation
is performed by the inline `adjust_positions()` function in
`postprocess.c`, not by a separate layer.

---

## 1. Analysis of Current Problems

### 1.1 The Ghost-Line Fix Was Treating a Symptom, Not the Cause

The ghost-line fix existed because the old `optimize_line` ordering
was wrong: it put `\n` deletes BEFORE content inserts, joining two
lines while one still had pending inserts. The ghost-line "fix" then
tried to patch this by moving content deletes to `cur_line + 1` and
emitting the `\n` delete at a different position.

We fixed the ordering (4-sweep: content deletes → content inserts →
`\n` deletes → `\n` inserts), which prevents ghost lines from
ever existing. The ghost-line fix has now been REMOVED entirely from
the emit loop.

**Conclusion:** The ghost-line fix HAS BEEN REMOVED entirely. The
4-sweep ordering prevents the problem it was trying to fix.

### 1.2 The Emit Loop Does Too Many Things

The current `write_output()` function does ALL of these in one pass:
- Cursor simulation (tracking cur_line, cur_col)
- Op emission (writing to stdout)
- line_offset accounting

This makes it impossible to debug, test, or modify any one part
without affecting the others. Each branch interacts with the others
in subtle ways.

### 1.3 Indent-Last Can't Work Because Groups Get Merged

The `indent_last_transform` runs inside `reorder_hunk_ops`, which
splits groups by `\n` boundaries. (Earlier, the ghost-line fix in the
emit loop used to change line numbers and effectively merge groups,
overwriting the indent-last result. That code path has now been removed.)

Also, the compute sometimes doesn't generate `\n` deletes for all
deleted lines (when patience diff anchors change). Without `\n`
boundaries, the reorder can't split into per-line groups, so
indent-last can't detect leading indentation.

### 1.4 No Debugging Visibility

There is no way to see what each transformation does to the ops.
The only output is the final postprocess stream. If something is
wrong, you have to add `fprintf(stderr, ...)` calls and recompile.

---

## 2. Do We Need to Look at diffvim-compute?

**Yes, but only for one thing: `\n` generation.**

The compute generates char-level ops by diffing `old_text` vs
`new_text` (where each is the concatenation of lines with `\n`).
The LCS should match `\n` chars naturally. But when the patience
diff at the LINE level groups multiple deleted lines into one hunk,
the char-level diff sees `old_text = "line1\nline2\nline3"` and
`new_text = ""`. The LCS of this is empty, so ALL chars (including
`\n`) are deletes. This should produce `\n` deletes for each line.

**But the 20-line truncation showed missing `\n` deletes.** This
happens because the patience diff at the LINE level finds different
anchors when the file is truncated. The line-level diff might match
some lines as "keep" that shouldn't be kept, causing the char-level
diff to see a different `old_text`/`new_text` pair.

**Recommendation:** The compute is mostly fine. The issue is that
the postprocess RELIES on `\n` deletes being present to split into
per-line groups. If the compute doesn't generate them, the postprocess
should handle it gracefully (not crash, not produce wrong output).
But fixing the compute to always generate `\n` deletes is a separate
task.

---

## 3. New Design: Layered Postprocess

### 3.1 Architecture

```
compute output (raw ops)
    │
    ▼
┌──────────────────┐
│ Layer 0: V2      │  Convert format, no modification
│ Conversion       │
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ Layer 1: Reorder │  optimize_line / left_to_right / end_first
│                  │  (4-sweep: content del → content ins → \n del → \n ins)
└──────────────────┘
    │
    ▼
┌──────────────────────┐
│ delete-indent-last   │  Reorder leading-whitespace deletes to end
│ (optional:           │  of line group. Does NOT touch line/col.
│  --indent-last)      │
└──────────────────────┘
    │
    ▼
┌──────────────────────┐
│ overwrite            │  Mark adjacent delete+insert pairs as
│ (optional:           │  overwrite_insert.
│  --overwrite)        │
└──────────────────────┘
    │
    ▼
┌──────────────────────┐
│ adjust_positions     │  Recursive inline pass in postprocess.c:
│ (inline, not a layer)│  adjust (line, col) based on \n deletes.
└──────────────────────┘
    │
    ▼
postprocess output (V2 TSV)
```

> Cursor recomputation is NOT a layer. There is no `pp_layer3_cursor.c`.
> The position fix happens in `adjust_positions()` inside `postprocess.c`.

### 3.2 Key Design Principles

1. **Each layer is a pure function:** `Op[] → Op[]`. No side effects,
   no stdout writing. The output of one layer is the input to the next.

2. **Each layer can be enabled/disabled.** If `--op-order natural`
   is set, Layer 1 is a no-op. `--indent-last` and `--overwrite`
   gate the optional transforms. `adjust_positions` always runs.

3. **Each layer can dump its input and output** for debugging.
   `DV_DEBUG_POSTPROCESS=1` causes each layer to write its input
   and output to `/tmp/dv_debug/layer_N_input.txt` and
   `layer_N_output.txt`.

4. **No ghost-line fix.** The 4-sweep ordering in Layer 1 prevents
   ghost lines. There is no patch layer for line-joining artifacts.
   If a ghost line appears, it's a bug in Layer 1.

5. **Position adjustment happens in `adjust_positions()` (inline in
   `postprocess.c`), not in a layer.** It walks the op array and
   fixes `(line, col)` based on `\n` deletes:
   - Track `deleted_lines` and a `characters` carry counter.
   - Rule 1: when the op's (line − deleted_lines) differs from
     `current_line`, reset `characters` to 0.
   - Rule 2: for non-`\n` ops, update `characters` (+1 for insert,
     −1 for delete, net 0 for `overwrite_insert`).
   - Rule 3: `op.line −= deleted_lines; op.col += characters`.
   - Rule 4 (delete `\n`): `deleted_lines += 1`; if `characters > 0`,
     recurse on the rest of the buffer with the carried `characters`
     (the "line join" case).
   - Rule 5 (keep/insert/overwrite_insert `\n`): reset `characters = 0`.

6. **Streaming support:** Each layer reads from stdin and writes to
   stdout. Layers can be piped:
   ```
   compute | postprocess --layer 0 | postprocess --layer 1 | ...
   ```
   Or all layers run in one process (default).

### 3.3 Layer Details

#### Layer 0: V2 Conversion

**Purpose:** Convert compute output to V2 TSV format. No modification
of ops — just format.

**Input:** Raw compute output (may be V1 or V2 format)
**Output:** V2 TSV with headers

```
Input:  HUNK <target> <del> <ins> <end_ins> <end_del>  (space-separated)
        keep <line> <col> <code>                       (space-separated)
Output: HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
        keep\t<line>\t<col>\t<code>
```

**What it does:**
- Detect V1 (space-separated) vs V2 (tab-separated)
- Convert V1 → V2 if needed
- Write headers (`# diffvim post-processed v2`, etc.)
- Pass through HUNK/HUNK_END and ops unchanged

**What it does NOT do:**
- Reorder ops
- Change line/col
- Add/remove ops

#### Layer 1: Reorder

**Purpose:** Reorder ops within each line group (between `\n` ops)
so the `\n` delete that joins two lines happens AFTER all content
changes on each line.

**Input:** V2 ops (from Layer 0)
**Output:** V2 ops (reordered)

**4-sweep order within each change region (between keeps):**
1. Content deletes (code != 10)
2. Content inserts (code != 10)
3. `\n` deletes (code == 10)
4. `\n` inserts (code == 10)

**Alternative modes:**
- `natural`: no reordering (pass-through)
- `left-to-right`: keeps, then deletes, then inserts (per line group)
- `end-first`: same as optimize (stub — no real difference)

**Why this works:**
When the `\n` delete (sweep 3) joins two lines, both lines already
have their final content (sweeps 1 and 2 are done). The joined line
has correct content — no transient mismatch.

#### Layer 2: Transforms

Each transform is a separate sub-layer. They run in order:

**2a. semantic_cleanup** (option: `--semantic-cleanup`)
- Merge canceling delete+insert pairs → keep
- Runs BEFORE reorder (on raw ops)
- Actually, should run AFTER reorder (on reordered ops) to catch
  adjacent pairs

**2b. delete-indent-last** (option: `--indent-last`, file: `pp_layer_indent_last.c`)
- For each line group (between `\n` ops):
  - Find leading whitespace (space/tab deletes at start of group)
  - Move them to the end of the line group (just before the `\n` delete)
- **Reorders ops only.** Does NOT modify `line`/`col` positions.
- Runs AFTER reorder (so groups are per-line, with `\n` at end)

**2c. overwrite** (option: `--overwrite`, file: `pp_layer_overwrite.c`)
- Mark adjacent delete+insert pairs as `overwrite_insert`
- Runs AFTER reorder and delete-indent-last

> `semantic_cleanup` was proposed but is not implemented. The
> "Layer 2" grouping in earlier drafts was replaced by two
> standalone layer files (`pp_layer_indent_last.c`,
> `pp_layer_overwrite.c`) invoked conditionally by `postprocess.c`.

#### adjust_positions (inline in postprocess.c)

**Purpose:** Assign correct `(line, col)` to every op, after all
layers have run. Not a layer — runs in-place on the Op array.

**Algorithm:** See principle 5 above. The recursive call handles the
"line join" case (a `\n` delete that merges two lines, carrying the
trailing characters of the first line onto the second).

There is no look-ahead and no 5-branch dispatcher. Just the rule-based
walk described above.

**line_offset accounting:** After each hunk, `line_offset += newl_ins - newl_del`
is applied to the next hunk's ops before `adjust_positions` runs.

---

## 4. Debugging Support

### 4.1 Layer Dumps

When `DV_DEBUG_POSTPROCESS=1` is set, each layer writes its input
and output to files:

```
/tmp/dv_debug/
  layer0_input.txt     # raw compute output
  layer0_output.txt    # V2 converted
  layer1_input.txt     # V2 ops (before reorder)
  layer1_output.txt    # V2 ops (after reorder)
  indent_last_input.txt  # before delete-indent-last (if --indent-last)
  indent_last_output.txt # after delete-indent-last
  overwrite_input.txt    # before overwrite (if --overwrite)
  overwrite_output.txt   # after overwrite
```

> `adjust_positions` runs in-place on the same buffer; it has no
> separate input/output dump. Inspect `postprocess.log` for the
> per-hunk op count and the `deleted_lines` totals.

### 4.2 dv_snapshot Integration

`dv_snapshot.sh` should show the layer dumps alongside the final
output. A "postprocess layers" panel at the top of the HTML page
shows what each layer did:

```
Layer 0 (V2 conversion):       1200 ops → 1200 ops (no change)
Layer 1 (reorder):              1200 ops → 1200 ops (56 ops moved)
delete-indent-last (--indent-last): 1200 ops → 1200 ops (20 ops moved)
overwrite (--overwrite):        1200 ops → 1200 ops (8 pairs merged)
adjust_positions:              in-place (line/col updated)
```

### 4.3 Per-Op Trace

Each op in the final output should have a "history" showing which
layers touched it:

```
Op #45: delete  line=8  col=1  code=32 (space)
  Layer 0: passthrough
  Layer 1: moved from position 12 to position 45 (reorder sweep 1)
  delete-indent-last: moved from position 12 to position 45
  overwrite: not merged (no adjacent insert at same position)
  adjust_positions: line changed from 17 to 8 (in-place)
```

This is ambitious but would make debugging trivial.

---

## 5. Vocabulary

| Term | Definition |
|------|-----------|
| **layer** | A processing stage that takes ops and produces ops. Pure function. |
| **line group** | A sequence of ops between two `\n` ops. Represents one line's changes. |
| **change region** | A sub-sequence within a line group, delimited by `keep` ops. |
| **4-sweep reorder** | The ordering: content deletes → content inserts → `\n` deletes → `\n` inserts. |
| **leading whitespace** | Space/tab deletes at the START of a line group, before any non-whitespace content. |
| **adjust_positions** | The inline pass in `postprocess.c` that fixes `(line, col)` based on `\n` deletes. Replaces the earlier proposed "cursor recomputation" layer. |
| **line_offset** | Cumulative `(newline_inserts - newline_deletes)` from prior hunks. |
| **layer dump** | Debug output showing a layer's input and output. |

---

## 6. Implementation Plan

### Phase 1: Base Layer (V2 conversion only)

Rewrite `postprocess.c` as a thin V2 converter. No reordering,
no transforms. Just:
- Read compute output
- Detect V1/V2
- Convert to V2 TSV
- Write headers
- Pass ops through with ORIGINAL line/col

**Test:** Output should match the compute output (just reformatted).

### Phase 2: Layer 1 (Reorder)

Add the 4-sweep reorder as a separate pass. No position adjustment —
just reorder ops within line groups.

**Test:** Verify 4-sweep order. No transient line-joining artifacts
in snapshots.

### Phase 3: adjust_positions (inline)

Implement position adjustment as an inline recursive function in
`postprocess.c`. Not a separate layer — runs in-place after every
transform has finished.

**Test:** Verify line/col are correct. Output matches expected files.

### Phase 4: Transforms (delete-indent-last, overwrite)

Add `pp_layer_indent_last.c` (reorder leading-whitespace deletes to
end of line group; no line/col changes) and `pp_layer_overwrite.c`
(mark adjacent delete+insert pairs as `overwrite_insert`). Each is a
pure function on the op array, gated by `--indent-last` and
`--overwrite` respectively.

**Test:** Verify delete-indent-last moves LEADING whitespace only and
does not change any `line`/`col`. Verify overwrite merges only
adjacent same-position pairs.

### Phase 5: Debugging Support

Add layer dumps (`DV_DEBUG_POSTPROCESS=1`).
Add layer info to dv_snapshot HTML.

### Phase 6: Ghost-Line Fix Removed

The legacy ghost-line fix code has been deleted from the postprocess.
The 4-sweep ordering in Layer 1 + `adjust_positions` handles line
joining correctly without it.

**Test:** Run all 42 examples. If any produce transient
line-joining artifacts, the 4-sweep ordering has a bug — fix the
ordering, don't re-add a patch.

---

## 7. File Structure

```
animator/c/
  postprocess.c           # Orchestrator; contains inline adjust_positions()
  pp_layer0_v2.c          # Layer 0: V2 conversion
  pp_layer1_reorder.c     # Layer 1: 4-sweep reorder
  pp_layer_indent_last.c  # delete-indent-last transform (--indent-last)
  pp_layer_overwrite.c     # overwrite transform (--overwrite)
  pp_common.h             # Shared types (Op struct, helpers, debug dumps)
```

Or keep it in one file but with clear section markers:

```
postprocess.c:
  // ===== Layer 0: V2 Conversion (in pp_layer0_v2.c) =====
  // ===== Layer 1: Reorder (in pp_layer1_reorder.c) =====
  // ===== delete-indent-last (in pp_layer_indent_last.c) =====
  // ===== overwrite (in pp_layer_overwrite.c) =====
  // ===== adjust_positions (inline) =====
  // ===== Debug =====
  // ===== Main =====
```

---

## 8. Streaming Mode

Each layer can be a separate process:
```bash
compute | pp_layer0 | pp_layer1 | pp_indent_last | pp_overwrite > output
```

Or all in one process (default, for performance — and the only mode
that runs `adjust_positions`):
```bash
compute | postprocess --indent-last > output
```

The streaming API:
- Each layer reads TSV from stdin, writes TSV to stdout
- Layers are stateless (no global variables)
- The `--stream` flag enables streaming mode (one layer at a time)
- Without `--stream`, all layers run in one process (buffer the ops)

---

## 9. What About the Compute?

The compute is mostly fine. The only issue is that the patience diff
at the LINE level can produce different results when the file is
truncated. This is expected behavior for patience diff — it finds
unique common lines as anchors, and truncation changes which lines
are unique.

**No changes needed to compute for now.** The postprocess should handle
missing `\n` deletes gracefully (don't crash, don't produce wrong output).
Indent-last should work when `\n` deletes are present, and be a no-op
when they're not.

---

## 10. Questions for the User

1. **Should indent-last apply to partially-deleted lines** (lines with
   both keeps and deletes)? Currently it only applies to entirely-deleted
   lines. The user's rules say "when a full line is to be deleted".

2. **Should `adjust_positions` handle the case where `\n` deletes
   are missing?** (e.g., when the compute doesn't generate them for
   truncated files). Or should the compute be fixed to always generate
   them?

3. **Should the layer dumps be in TSV format** (easy to diff) or
   in a human-readable format (easy to read)?
