# Phase F — Ghost-Line Problem: Analysis & Proposed Fix

**Status:** Design only — NOT YET IMPLEMENTED. Awaiting user approval.

## The Problem

When a diff produces a sequence like:

```
keep "foo"
delete \n        ← joins line N with line N+1
keep "bar"
```

the animator's `delete_char(10)` removes the `\n` between lines N and N+1, **joining** them. Visually, line N+1's content ("bar") jumps up onto line N ("foo") — even though in the final new file, "foo" and "bar" are on separate lines.

The user (NEXT_SESSION.md directive) was unambiguous: **the fix belongs in postprocess, not in the animator.** The animator must mechanically apply what it's given.

## Concrete Example — `examples/07_text_prose`, Hunk 2

Old line 5: `The system consists of three main components: the frontend, the backend,`
New line 5: `The system consists of three main components:`

The diff says:
1. Keep `The system consists of three main components:` (29 chars)
2. Delete ` the frontend, the backend,` (chars)
3. **Delete `\n`** (joins old line 5 with old line 6)
4. Delete `and the database. The frontend is a web application built with React.`
5. **Delete `\n`** (joins with line 7)
6. Delete `The backend is a REST API built with Node.js and Express. The database`
7. **Delete `\n`** (joins with line 8)
8. ... (more deletes)
9. Insert `\n\n` (new empty lines)
10. Insert `1. Frontend — a single-page application built with React 18 and TypeScript,`

**Visual artifact**: After step 2, the buffer has:
```
The system consists of three main components:
 the frontend, the backend, and the database. The frontend is a web application built with React.
 The backend is a REST API built with Node.js and Express. The database
 is PostgreSQL.
 ...
```

When step 3 deletes `\n`, the line 6 content jumps UP onto line 5:
```
The system consists of three main components: the frontend, the backend, and the database. The frontend is a web application built with React.
 The backend is a REST API built with Node.js and Express. The database
 is PostgreSQL.
 ...
```

This looks **unnatural** — a human typist would never join two lines and then immediately delete the joined-in content. They'd delete the chars on the current line, then delete the line below.

## Two Fix Options (from NEXT_SESSION.md)

### Option A — Split into delete+insert

Transform:
```
keep "foo"
delete \n
keep "bar"
```

into:
```
keep "foo\n"
delete "bar"
insert "bar"
```

The `\n` stays with the keep; the second line's content is deleted then re-inserted in place. Visually: "bar" disappears and reappears on the same line.

**Pros**: Simple transformation; preserves the original line structure.
**Cons**: Causes a visible "flash" (delete then re-insert of the same content). For a long joined line, this means deleting 100 chars and re-inserting 100 chars — wasteful and visually noisy.

### Option B — Defer the join (reorder ops)

Reorder ops so all char deletes on a line happen BEFORE the `\n` delete. Then the `\n` delete uses the "remove empty line" path (the line is already empty by then).

Transform:
```
keep "foo"
delete \n
keep "bar"
delete "bar"           ← (the actual deletes that come after)
```

into:
```
keep "foo"
delete "bar"            ← delete the next line's content first
delete \n               ← then remove the now-empty line
```

**Pros**: No re-insertion; the `\n` delete becomes a "remove empty line" op (which the animator handles correctly and naturally). Visually: the next line's content disappears, then the (now empty) line vanishes — exactly what a human would do.

**Cons**: The postprocess must look AHEAD across the `\n` delete to find the subsequent deletes that belong to the joined-in content. This requires identifying the boundary between "deletes of this line's content" vs "deletes of the next line's content" (which is what the `\n` delete demarcates).

## My Recommendation: **Option B (defer the join)**

Option B is more natural and avoids the wasteful delete-then-reinsert pattern. The implementation:

### Detection

The postprocess walks the ops within each hunk. When it encounters a sequence:

```
keep "X..."          ← content of line N (last keep before \n)
delete \n            ← the join
delete "Y..."        ← content of line N+1 (next line's chars)
[keep "Z"]           ← or end of hunk / next \n
```

it should reorder to:

```
keep "X..."
delete "Y..."        ← delete line N+1's content first
delete \n            ← then remove the now-empty line N+1
[keep "Z"]
```

### Implementation outline (postprocess.c + postprocess.pl)

Add a new transformation pass, **after** `reorder_hunk_ops()` (so it operates on already-optimized ops):

```c
/* ghost_line_fix: detect "keep X, delete \n, delete Y" and reorder to
 * "keep X, delete Y, delete \n" so the \n delete finds an empty line.
 *
 * Multi-line case: if there are multiple consecutive "delete \n, delete Y"
 * pairs (joining 3+ lines into one), each \n delete should be deferred
 * until its corresponding Y content is deleted.
 *
 * Algorithm: scan ops left-to-right. Maintain a "pending \n deletes" queue.
 * When we encounter a non-newline delete, emit it immediately. When we
 * encounter a \n delete, push it onto the pending queue. When we encounter
 * a keep or insert, first flush all pending \n deletes (in reverse order,
 * so the last-pushed \n is emitted first — joining the closest pair first),
 * then emit the keep/insert.
 *
 * Edge case: \n delete immediately followed by a keep — this is the original
 * ghost-line case. After the fix, the \n delete is deferred until the next
 * non-delete op, which means the keep happens first, then the \n delete joins.
 * This is still wrong! We need to look ahead: if the op after \n delete is a
 * keep, we need to find the deletes that come AFTER the keep and move them
 * before both the \n delete and the keep.
 */
```

The "edge case" is the crux: the original `keep "foo", delete \n, keep "bar"` pattern has the deletes of "bar" happening LATER (after the keep of "bar"), not before. So the simple "defer \n deletes" doesn't work — we need to actually look at what comes after the `keep "bar"` and decide whether those deletes belong to the joined-in content.

### More sophisticated algorithm

The real signal is: **a `\n` delete between two `keep` runs is a join**, and the joined-in content (line N+1's chars) is what gets deleted between the `\n` delete and the next `\n` delete (or the next `keep \n`).

A simpler way to think about it: when we see `delete \n`, scan forward. Find the next `\n` (keep or delete). All the chars between this `\n` delete and the next `\n` are "the joined-in content of line N+1". Move those deletes BEFORE the `\n` delete. Now the `\n` delete is the last op on its line, which means line N+1 is empty when we delete its `\n` — so the animator takes the "remove empty line" path.

### Pseudocode

```
for each hunk:
    ops = hunk.ops
    out = []
    i = 0
    while i < len(ops):
        if ops[i] is delete_\n:
            # Look ahead: find the next \n (keep or delete), exclusive.
            # All ops between are "the joined-in content".
            j = i + 1
            joined_content = []
            while j < len(ops) and not is_newline_op(ops[j]):
                if ops[j].type == 'delete':
                    joined_content.append(ops[j])
                elif ops[j].type == 'keep':
                    # A keep between \n deletes means the joined-in content
                    # is partially preserved — abort the reorder for safety.
                    joined_content = None
                    break
                elif ops[j].type == 'insert':
                    # Inserts in the joined region are fine to leave in place.
                    pass
                j += 1

            if joined_content:
                # Emit the joined-in content deletes first, then the \n delete.
                out.extend(joined_content)
                out.append(ops[i])  # the \n delete
                i = j  # skip past the joined content
            else:
                # Couldn't safely reorder; emit as-is.
                out.append(ops[i])
                i += 1
        else:
            out.append(ops[i])
            i += 1
    hunk.ops = out
```

### Test cases to add (after implementation)

1. **Simple join**: `keep "foo", delete \n, delete "bar"` → `keep "foo", delete "bar", delete \n`
2. **Multi-line join**: `keep "foo", delete \n, delete "bar", delete \n, delete "baz"` → `keep "foo", delete "bar", delete "baz", delete \n, delete \n` (both \n deletes at the end, after all content deletes)
3. **Mixed**: `keep "foo", delete \n, keep "bar"` (the original ghost-line case from NEXT_SESSION.md) — **option B does NOT directly fix this case** because there are no subsequent deletes to move. The fix here would be to convert to Option A (delete "bar" and re-insert it). This is the only case where Option A is needed.
4. **Edge case**: `keep "foo", delete \n, insert "X", delete "bar"` — the insert breaks the contiguous delete run. Should we still move "delete bar" before the `\n` delete? Probably yes, but visually the insert would happen first, then the line vanish — might look odd. Need to test.

## What I'd like you to confirm before I implement

1. **Option B for the common case** (multi-char deletes after `\n` delete) — confirm this is the right approach.
2. **Option A as fallback** for the pure `keep X, delete \n, keep Y` case (no deletes in between) — confirm we should transform to `keep "X\n", delete "Y", insert "Y"`. This causes a brief flash but is the only way to avoid the visual jump.
3. **Mixed insert/delete case** — what should happen if the sequence is `keep "foo", delete \n, insert "X", delete "bar"`? My recommendation: leave as-is (don't reorder) — the insert happening before the line vanishes is acceptable.
4. **Where to add the test**: `tests/test_ghost_line.pl` (new file) with the 4 cases above, asserting the postprocess output matches the expected transformation.

Awaiting your decision.
