# `--line-delete-in-place` — Pseudo-code and Design Analysis

This document explains, in pseudo-code, what the
`ad_layer_line_delete_in_place` layer is **supposed** to do, why it is
currently broken, and what a correct implementation would look like.

## The Problem the Layer Solves

When a line is fully deleted (its content + its `\n`) AND the previous
line's `\n` is also deleted (to join the surviving lines), the naive op
order from compute causes a "join then delete" visual:

```
Old:                New:
A                   AC
B
C
```

**Naive op order (from compute):**
```
keep   (1,1) 'A'
delete (1,2) \n     ← joiner — joins A's line with B's line
delete (2,1) 'B'    ← delete B content (B is now ON line 1!)
delete (2,1) \n     ← delete B's own \n
keep   (3,1) 'C'
```

**Visual problem:** When `delete (1,2) \n` runs, the buffer becomes
`["AB", "C"]` — B briefly appears on line 1 next to A. Then B is
deleted, then B's `\n` joins A with C. The user sees "AB" briefly before
"B" vanishes — visually jarring.

**Desired behavior:** Delete B's content FIRST (while B is still on its
own line 2), then delete B's `\n` (removes the now-empty line 2), then
delete the joiner `\n` (joins A with C). The user sees "B" disappear on
its own line, then the empty line collapses, then A and C join — much
smoother.

## Correct Pseudo-code

```
function line_delete_in_place(ops, n_ops):
    """Reorder line-delete sequences so content is deleted BEFORE the join.

    Pattern detected (by op CODE, not line number — positions may have
    been recomputed by a previous layer):

        delete(code=\n)        <- joiner \n (joins line N with line N+1)
        delete(code!=\n) ...   <- content deletes (1 or more, on line N+1)
        delete(code=\n)        <- content's own \n (separates N+1 from N+2)

    Rewritten as:
        delete(content) ...    <- content deletes first
        delete(\n)             <- content's own \n (removes empty line N+1)
        delete(\n)             <- joiner \n last (joins surviving lines)

    CRITICAL: After reordering, the (line, col) positions on the moved
    ops MUST be updated to match the new execution order. The current
    implementation does NOT do this — it just swaps the ops in place,
    keeping their original positions. This is the root cause of the bug.

    Position update rules (what a correct implementation must do):
      - Content deletes: keep their ORIGINAL position (line N+1, col X)
        because they execute on the same line they always did. The line
        has not been joined yet when they run.
      - Content's \n: keep its ORIGINAL position (line N+1, end-of-content).
      - Joiner \n: keep its ORIGINAL position (line N, original col).

    If positions are NOT updated, two things go wrong:
      (a) The moved content deletes point to the wrong line (the joined
          line, which no longer has the content to delete — they become
          silent no-ops).
      (b) The \n deletes happen at the wrong cursor position (because
          the animator's cursor is wherever the last op left it).
    """
    result = []
    i = 0
    while i < n_ops:
        # Look for pattern: \n delete, then 1+ content deletes, then \n delete
        if (i + 2 < n_ops
            and is_delete(ops[i]) and is_newline(ops[i])
            and is_delete(ops[i+1]) and not is_newline(ops[i+1])):

            # Collect the content deletes
            joiner_nl = ops[i]              # the first \n delete (joiner)
            content_start = i + 1
            content_end = content_start
            while (content_end < n_ops
                   and is_delete(ops[content_end])
                   and not is_newline(ops[content_end])):
                content_end += 1

            # Check if followed by another \n delete (the content's own \n)
            if (content_end < n_ops
                and is_delete(ops[content_end])
                and is_newline(ops[content_end])):

                contents_nl = ops[content_end]   # the second \n delete

                # ── Pattern matched: emit content, content's \n, joiner \n ──
                # CRITICAL: Each op keeps its ORIGINAL (line, col).
                # The original positions ARE correct — they point to where
                # the content lived in the OLD file (before any joining).
                # The animator will execute them in this new order, and
                # because the content deletes run BEFORE the joiner \n
                # delete, the line still exists when they execute.
                for k in range(content_start, content_end):
                    result.append(ops[k])           # content deletes (orig pos)
                result.append(contents_nl)          # content's \n (orig pos)
                result.append(joiner_nl)            # joiner \n (orig pos, last)

                i = content_end + 1
                continue

        result.append(ops[i])
        i += 1

    return result
```

## Why the Current Implementation Is Broken

The current C implementation (`layers/c/ad_layer_line_delete_in_place.c`)
follows the pseudo-code above, BUT it runs **after** `ad_layer_reorder`
which has already normalized ALL positions to `(current_line, 1)`.

### The pipeline order is:

```
compute → ad_layer_reorder → ad_layer_line_delete_in_place → pace → animate
```

### What `ad_layer_reorder` does to positions

`ad_layer_reorder.c` does TWO things:
1. **Reorders ops** within each segment (deletes before inserts, etc.).
2. **Walks forward through the output** and OVERWRITES every op's
   `(line, col)` to a recomputed position based on the new order.

The forward-walking position overwrite (lines 68-81 of `ad_layer_reorder.c`)
looks like this:

```c
int current_line = (out_count > 0) ? out[0].line : 1;
int current_col = 1;
for (int i = 0; i < out_count; i++) {
    out[i].line = current_line;     // ← OVERWRITES original position
    out[i].col  = current_col;     // ← OVERWRITES original position
    if (is_keep_or_insert(out[i])) {
        if (is_newline(out[i])) { current_line++; current_col = 1; }
        else current_col++;
    }
}
```

After reorder, ALL ops in the same hunk have positions like `(N, 1)`,
`(N, 1)`, `(N, 1)`, ... — they all point to the hunk's target line,
column 1. The original positions (which referenced the OLD file's
line structure) are LOST.

### What this means for the layer

When `ad_layer_line_delete_in_place` runs after reorder:

- The "joiner \n" op's position is `(N, 1)` (not `(1, 2)` as the design doc shows).
- The "content delete" op's position is `(N, 1)` (not `(2, 1)` as the design doc shows).
- The "content's \n" op's position is `(N, 1)` (not `(2, 1)` as the design doc shows).

The layer can still DETECT the pattern by op CODE (it doesn't need line
numbers to know "first \n, then content, then \n"). But when it reorders,
the moved ops retain their `(N, 1)` positions, which are now wrong because
the order has changed.

### Concrete trace: `A\nB\nC\nD\n → A\nD\n` (delete B and C)

**After `ad_layer_reorder`, ops look like (all at line 2, col 1):**

```
keep   (1,1) 'A'
delete (2,1) 'B'      <- B content
delete (2,1) \n       <- B's \n (joiner, in the layer's terminology)
delete (2,1) 'C'      <- C content
delete (2,1) \n       <- C's \n (content's own \n)
keep   (1,2) 'D'      <- D, on line 1 col 2 (after join)
```

Wait — that's the WRONG order. Let me re-check. Actually after reorder, ops
within a segment are sorted: deletes first (non-\n), then \n deletes, then
\n inserts. But \n ops are SEGMENT BOUNDARIES, so each line's content is
its own segment.

**Actual post-reorder ops (verified by running the pipeline):**

```
keep   (1,1) 'A'      <- line 1
delete (2,1) 'B'      <- line 2 content (segment 1)
delete (2,1) \n       <- line 2 \n (boundary)
delete (2,1) 'C'      <- line 3 content (segment 2)
delete (2,1) \n       <- line 3 \n (boundary)
keep   (1,2) 'D'      <- D, position recomputed
```

Wait, the reorder doesn't change the segment boundaries. So the layer
SEES the pattern: `delete \n, delete 'C', delete \n` — and matches it!

**After `ad_layer_line_delete_in_place`:**

```
keep   (1,1) 'A'
delete (2,1) 'B'      <- B content (unchanged)
delete (2,1) 'C'      <- C content MOVED before B's \n
delete (2,1) \n       <- C's \n MOVED before B's \n
delete (2,1) \n       <- B's \n (now last)
keep   (1,2) 'D'
```

### What the animator does with this

The animator (`animator/c/ad.c` and `apps/vim/autoload_diffvim/engine.vim`)
processes ops in order. Key behavior:

- For non-`\n` deletes: SET cursor to `(line, col)`, then delete char at cursor.
- For `\n` deletes: DON'T set cursor — use the current cursor position
  and join the current line with the next line.

Tracing the animator on the post-layer ops:

| Step | Op | Cursor before | Buffer before | Buffer after |
|------|-----|---------------|----------------|--------------|
| 1 | keep A (1,1) | (1,1) | `["A","B","C","D"]` | `["A","B","C","D"]` (cursor → (1,2)) |
| 2 | delete B (2,1) | (1,2) | same | set cursor (2,1), delete 'B' → `["A","","C","D"]`, cursor (2,1) on "" |
| 3 | delete C (2,1) | (2,1) | `["A","","C","D"]` | set cursor (2,1), delete char at col 1 of "" — **NO-OP** (empty line) |
| 4 | delete \n (2,1) | (2,1) | same | don't move cursor, join line 2 ("") with line 3 ("C") → `["A","C","D"]` |
| 5 | delete \n (2,1) | (2,1) | `["A","C","D"]` | don't move cursor, join line 2 ("C") with line 3 ("D") → `["A","CD"]` |
| 6 | keep D (1,2) | (2,1) | `["A","CD"]` | set cursor (1,2), advance. Buffer unchanged. |

**Final: `["A", "CD"]`** — WRONG (expected `["A", "D"]`).

### Why step 3 is a no-op

After step 2, the cursor is at (2,1) on line 2, which is now an empty
string `""`. Step 3 says "delete C at (2,1)" — set cursor to (2,1), then
delete char at col 1 of `""`. There is no char at col 1 of an empty
string, so the delete is silently dropped.

The intent of step 3 was to delete 'C' from line 3 (where C still lives
in the buffer). But the op's position is `(2,1)` (because reorder
normalized it), so the animator goes to line 2 (which is empty) and
deletes nothing.

### Why step 5 joins the wrong lines

After step 4, the cursor is at (2,1) on line 2, which is now `"C"`
(because line 2 was joined with line 3). Step 5 says "delete \n at (2,1)"
— don't move cursor (animator skips for \n deletes), join current line
(line 2 = "C") with next line (line 3 = "D") → `["A", "CD"]`.

The intent of step 5 was to delete B's `\n` (which joins line 2 with
line 3 — but at this point in execution, B's `\n` no longer exists in
the buffer; it was already consumed by step 4).

## Two Fixes Are Needed

### Fix 1: The layer must preserve/update positions

The layer should NOT rely on the post-reorder positions. It has two options:

**Option A — Run the layer BEFORE reorder.** Move the layer earlier in
the chain so it sees the original compute positions (which reference
the OLD file's line structure). The layer reorders using its current
algorithm, keeping original positions. Reorder then runs after and
normalizes positions to the post-execution order.

**Option B — Have the layer recompute positions itself.** After
reordering, walk the output forward and assign positions based on the
NEW execution order. This is what `ad_layer_reorder` already does
internally — the layer would need to do the same.

### Fix 2: The animator must honor positions for `\n` deletes

The animator's "don't move cursor for `\n` deletes" behavior is
currently in `apps/vim/autoload_diffvim/engine.vim` (lines 1877-1887):

```vim
elseif l:cmd ==# 'delete' && len(l:parts) >= 4
    " For \n deletes (code 10), DON'T move the visual cursor —
    " the join happens at the internal cursor, but the displayed
    " cursor stays where the previous content op left it.
    let l:del_code = str2nr(l:parts[3])
    if l:del_code != 10
        call s:TimedSetCursor(str2nr(l:parts[1]), str2nr(l:parts[2]))
    endif
    call s:TimedDeleteChar(l:del_code)
```

This was added to prevent the cursor from visually jumping up to the
preserved line above during `\n` deletes. But it breaks the layer's
intended behavior — the layer EXPECTS the animator to honor the op's
position so the `\n` delete happens at the right line.

**Fix:** Always call `TimedSetCursor(line, col)` for `\n` deletes too.
The visual cursor jump can be solved differently — e.g., by having the
post-processor insert explicit `glide` ops for cursor movement between
hunks, rather than having the animator implicitly not move for `\n`
deletes.

## Test That Catches the Bug

See `layers/tests/test_line_delete_in_place_per_op.pl`. It:

1. Runs the full pipeline (with and without the layer) on minimal cases.
2. Injects a `snapshot <file>` op after every keep/delete/insert op.
3. The animator writes the buffer state to that file at that point.
4. Compares each snapshot against HAND-WRITTEN expected snapshots.

The expected snapshots encode what the buffer SHOULD look like at each
step. The current implementation fails the "WITH layer" cases for
multi-line deletes — exactly at the op where the layer's incorrect op
order causes the cursor to be at the wrong position.

## Summary

| Aspect | Current State |
|--------|---------------|
| Layer detects the pattern correctly | ✓ Yes (by op code, not line number) |
| Layer reorders ops correctly | ✓ Yes (content first, then \ns) |
| Layer updates positions on moved ops | ✗ NO — this is bug #1 |
| Animator honors positions for `\n` deletes | ✗ NO — this is bug #2 |
| Reorder layer preserves original positions | ✗ NO — it overwrites them (bug #3, but harder to fix) |
| Test catches the bug | ✓ Yes (per-op snapshot test) |

The layer is **disabled** in the pipeline until both fixes are applied.
