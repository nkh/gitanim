# Postprocess Rewrite — Design Document

**Status:** Design only. No code changes until approved.

---

## 1. Analysis of Current Problems

### 1.1 The Ghost-Line Fix Is Treating a Symptom, Not the Cause

The ghost-line fix exists because the old `optimize_line` ordering
was wrong: it put `\n` deletes BEFORE content inserts, joining two
lines while one still had pending inserts. The ghost-line "fix" then
tried to patch this by moving content deletes to `cur_line + 1` and
emitting the `\n` delete at a different position.

We fixed the ordering (4-sweep: content deletes → content inserts →
`\n` deletes → `\n` inserts), which should prevent ghost lines from
ever existing. But the ghost-line fix is STILL in the emit loop,
interfering with the correct ordering.

**Conclusion:** The ghost-line fix should be REMOVED entirely. The
4-sweep ordering prevents the problem it was trying to fix.

### 1.2 The Emit Loop Does Too Many Things

The current `write_output()` function does ALL of these in one pass:
- Cursor simulation (tracking cur_line, cur_col)
- Ghost-line fix (5 branches of look-ahead logic)
- Ghost-line fix for inserts (synthetic `\n` insert)
- Op emission (writing to stdout)
- line_offset accounting

This makes it impossible to debug, test, or modify any one part
without affecting the others. Each branch interacts with the others
in subtle ways.

### 1.3 Indent-Last Can't Work Because Groups Get Merged

The `indent_last_transform` runs inside `reorder_hunk_ops`, which
splits groups by `\n` boundaries. But the ghost-line fix in the emit
loop then changes line numbers and effectively merges groups. The
indent-last result is overwritten.

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
┌──────────────────┐
│ Layer 2: Trans-  │  indent_last, semantic_cleanup, overwrite
│ forms            │  (each is a separate sub-layer)
└──────────────────┘
    │
    ▼
┌──────────────────┐
│ Layer 3: Cursor   │  Recompute (line, col) for every op
│ Recomputation    │  (no ghost-line fix — just track cursor)
└──────────────────┘
    │
    ▼
postprocess output (V2 TSV)
```

### 3.2 Key Design Principles

1. **Each layer is a pure function:** `Op[] → Op[]`. No side effects,
   no stdout writing. The output of one layer is the input to the next.

2. **Each layer can be enabled/disabled.** If `--op-order natural`
   is set, Layer 1 is a no-op. If `--indent-last` is not set, that
   sub-layer in Layer 2 is skipped.

3. **Each layer can dump its input and output** for debugging.
   `DV_DEBUG_POSTPROCESS=1` causes each layer to write its input
   and output to `/tmp/dv_debug/layer_N_input.txt` and
   `layer_N_output.txt`.

4. **No ghost-line fix.** The 4-sweep ordering in Layer 1 prevents
   ghost lines. If a ghost line appears, it's a bug in Layer 1,
   not something to patch in Layer 3.

5. **The cursor recomputation (Layer 3) is simple:**
   - Track `cur_line` and `cur_col`
   - For `keep` (code != 10): advance `cur_col`
   - For `keep` (code == 10): `cur_line++`, `cur_col = 1`
   - For `delete` (code != 10): `cur_col` stays (content removed)
   - For `delete` (code == 10): join current line with next.
     `cur_col` stays at the join point.
   - For `insert` (code != 10): advance `cur_col`
   - For `insert` (code == 10): split line. `cur_line++`, `cur_col = 1`
   - Set the op's `(line, col)` to the current cursor position
     BEFORE applying the op (so the animator knows WHERE to apply it)

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
- Ghost-line fix

#### Layer 1: Reorder

**Purpose:** Reorder ops within each line group (between `\n` ops)
to prevent ghost lines.

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

**Why this prevents ghost lines:**
When the `\n` delete (sweep 3) joins two lines, both lines already
have their final content (sweeps 1 and 2 are done). The joined line
has correct content — no ghost.

#### Layer 2: Transforms

Each transform is a separate sub-layer. They run in order:

**2a. semantic_cleanup** (option: `--semantic-cleanup`)
- Merge canceling delete+insert pairs → keep
- Runs BEFORE reorder (on raw ops)
- Actually, should run AFTER reorder (on reordered ops) to catch
  adjacent pairs

**2b. indent_last** (option: `--indent-last`)
- For each line group (between `\n` ops):
  - Check if ALL ops are deletes (no keeps/inserts) → entirely deleted
  - Find leading whitespace (space/tab deletes at start of group)
  - Move them to just before the `\n` delete
- Runs AFTER reorder (so groups are per-line, with `\n` at end)

**2c. overwrite** (option: `--overwrite`)
- Mark adjacent delete+insert pairs as `overwrite_insert`
- Runs AFTER reorder and indent_last

#### Layer 3: Cursor Recomputation

**Purpose:** Assign correct `(line, col)` to every op.

**Input:** V2 ops (reordered and transformed, but with raw line/col)
**Output:** V2 ops with corrected `(line, col)`

**Algorithm:**
```
cur_line = target_line + line_offset
cur_col = 1

for each op:
    op.line = cur_line
    op.col = cur_col

    if op is keep:
        if code == 10:  # \n keep
            cur_line++
            cur_col = 1
        else:
            cur_col++
    elif op is delete:
        if code == 10:  # \n delete — join with next line
            # cur_line stays (content from next line joins onto current)
            # cur_col stays at end of current content
            pass
        else:
            # cur_col stays (content removed at cursor)
            pass
    elif op is insert:
        if code == 10:  # \n insert — split line
            cur_line++
            cur_col = 1
        else:
            cur_col++
```

**NO ghost-line fix.** No look-ahead. No 5-branch dispatcher.
Just simple cursor tracking.

**line_offset accounting:** After each hunk, `line_offset += newl_ins - newl_del`.

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
  layer2a_input.txt    # before semantic_cleanup
  layer2a_output.txt   # after semantic_cleanup
  layer2b_input.txt    # before indent_last
  layer2b_output.txt   # after indent_last
  layer2c_input.txt    # before overwrite
  layer2c_output.txt   # after overwrite
  layer3_input.txt     # before cursor recomp
  layer3_output.txt    # final output (with correct line/col)
```

### 4.2 dv_snapshot Integration

`dv_snapshot.sh` should show the layer dumps alongside the final
output. A "postprocess layers" panel at the top of the HTML page
shows what each layer did:

```
Layer 0 (V2 conversion):  1200 ops → 1200 ops (no change)
Layer 1 (reorder):         1200 ops → 1200 ops (56 ops moved)
Layer 2b (indent-last):   1200 ops → 1200 ops (20 ops moved)
Layer 3 (cursor recomp):   1200 ops → 1200 ops (line/col updated)
```

### 4.3 Per-Op Trace

Each op in the final output should have a "history" showing which
layers touched it:

```
Op #45: delete  line=8  col=1  code=32 (space)
  Layer 0: passthrough
  Layer 1: moved from position 12 to position 45 (reorder sweep 1)
  Layer 2b: moved from position 12 to position 45 (indent-last)
  Layer 3: line changed from 17 to 8 (cursor recomp)
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
| **cursor recomputation** | Assigning `(line, col)` to each op based on cursor simulation. |
| **line_offset** | Cumulative `(newline_inserts - newline_deletes)` from prior hunks. |
| **layer dump** | Debug output showing a layer's input and output. |

---

## 6. Implementation Plan

### Phase 1: Base Layer (V2 conversion only)

Rewrite `postprocess.c` as a thin V2 converter. No reordering,
no transforms, no ghost-line fix. Just:
- Read compute output
- Detect V1/V2
- Convert to V2 TSV
- Write headers
- Pass ops through with ORIGINAL line/col

**Test:** Output should match the compute output (just reformatted).

### Phase 2: Layer 1 (Reorder)

Add the 4-sweep reorder as a separate pass. No ghost-line fix.
No cursor recomputation — just reorder ops within line groups.

**Test:** Verify 4-sweep order. No ghost lines in snapshots.

### Phase 3: Layer 3 (Cursor Recomputation)

Add cursor recomputation as a separate pass. Simple tracking:
`cur_line`, `cur_col`. No look-ahead, no 5-branch dispatcher.

**Test:** Verify line/col are correct. Output matches expected files.

### Phase 4: Layer 2 (Transforms)

Add indent-last, semantic_cleanup, overwrite as separate passes.
Each is a pure function on the op array.

**Test:** Verify indent-last moves LEADING whitespace only.

### Phase 5: Debugging Support

Add layer dumps (`DV_DEBUG_POSTPROCESS=1`).
Add layer info to dv_snapshot HTML.

### Phase 6: Remove Ghost-Line Fix

Delete ALL ghost-line fix code from the old postprocess.
The 4-sweep ordering should make it unnecessary.

**Test:** Run all 42 examples. If any produce ghost lines, the
4-sweep ordering has a bug — fix the ordering, don't add a patch.

---

## 7. File Structure

```
animator/c/
  postprocess.c          # Main entry point, orchestrates layers
  pp_layer0_v2.c         # Layer 0: V2 conversion
  pp_layer1_reorder.c     # Layer 1: 4-sweep reorder
  pp_layer2_transforms.c # Layer 2: indent-last, semantic, overwrite
  pp_layer3_cursor.c      # Layer 3: cursor recomputation
  pp_debug.c             # Debug: layer dumps, per-op trace
  pp_common.h            # Shared types (Op struct, helpers)
```

Or keep it in one file but with clear section markers:

```
postprocess.c:
  // ===== Layer 0: V2 Conversion =====
  // ===== Layer 1: Reorder =====
  // ===== Layer 2: Transforms =====
  // ===== Layer 3: Cursor Recomputation =====
  // ===== Debug =====
  // ===== Main =====
```

---

## 8. Streaming Mode

Each layer can be a separate process:
```bash
compute | pp_v2 | pp_reorder | pp_indent_last | pp_cursor > output
```

Or all in one process (default, for performance):
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

1. **Should the ghost-line fix be completely removed?** My analysis
   says yes — the 4-sweep ordering prevents ghost lines. But I've been
   wrong before. Should I keep it as a fallback?

2. **Should indent-last apply to partially-deleted lines** (lines with
   both keeps and deletes)? Currently it only applies to entirely-deleted
   lines. The user's rules say "when a full line is to be deleted".

3. **Should the cursor recomputation handle the case where `\n` deletes
   are missing?** (e.g., when the compute doesn't generate them for
   truncated files). Or should the compute be fixed to always generate
   them?

4. **Should the layer dumps be in TSV format** (easy to diff) or
   in a human-readable format (easy to read)?
