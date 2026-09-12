# Animation Analysis: 02_large_python new→old

## Input
- old file: `tests/examples/02_large_python/new.py` (123 lines)
- new file: `tests/examples/02_large_python/old.py` (76 lines)
- Direction: new → old (deleting 47 lines, modifying content)
- Layers: split_in_place → line_delete_in_place → batch_whitespace

## What the diff does

1. Line 2: change `CSV/JSON` → `CSV` (char-level: delete `/JSON`)
2. Line 5: delete `import json` (whole line)
3. Lines 8-20 → line 7: collapse 13 lines into 1 (delete 12 lines, modify 1)
4. Line 24→11: change `CSV/JSON` → `CSV` (char-level: delete `/JSON`)
5. Lines 26-28→13-15: modify 3 lines (char-level changes)
6. ... more changes throughout

## What a human would do (optimal animation)

### Rule 1: Whole-line deletion
When a whole line is removed (e.g., `import json`):
- Delete each character one by one (left to right)
- When the line is empty, it disappears (no join with next line)
- The line below shifts up AFTER the line is empty

**NOT**: line vanishes instantly (current `delete_line` behavior)
**NOT**: line is joined to next line then content deleted (old `join_lines` behavior)

### Rule 2: Partial-line deletion + line collapse
When a line's content is partially deleted and the line is joined with
the next (e.g., `from typing..., Any, Callable, Iterator` → `from typing...`):
- Delete the extra characters (`, Any, Callable, Iterator`) in place
- When only the kept content remains, join the empty remainder with
  the next line (or delete the line if it's fully empty)

**NOT**: join first, then delete the joined content (content jumps up)

### Rule 3: Indentation deletion
When indentation and content are both deleted:
- Delete the content first (left to right)
- Delete the indentation LAST (so the line doesn't shift left prematurely)

### Rule 4: Multi-line collapse
When N lines collapse into 1 (e.g., 13 lines → 1):
- Delete the content of each line being removed (char by char)
- Remove each empty line (shift next line up)
- Process from top to bottom

## Current animation problems

### Problem 1: `delete_line` vanishes instantly (28 occurrences)

**What happens**: 28 `delete_line` ops remove entire lines in one frame.
The user sees lines blink out of existence.

**Root cause**: The diff engine collapses `delete@col1+ + join_lines`
into a single `delete_line` op. This is correct for buffer state but
wrong for animation — the line should be deleted char-by-char first,
then the empty line removed.

**Fix**: DON'T collapse to `delete_line` in the diff engine. Keep
the `delete@col1+ + join_lines` pattern. The `line_delete_in_place`
layer moves the deletes to BEFORE the join (on line L+1). The
animation shows char-by-char deletion on L+1, then `join_lines`
removes the empty line (no visual jump because L+1 is empty).

### Problem 2: Partial deletes still use join (19 occurrences)

**What happens**: 19 `join_lines` ops remain for partial-line deletes.
The `line_delete_in_place` layer moves post-join deletes to before
the join. The animation should be: delete chars on L+1 (before join),
then join (pull empty L+1 up to L).

**Status**: This is partially fixed — the deletes are moved before
the join. But the animation still shows the join (pulling the empty
line up). This is acceptable IF the line is empty after the deletes.

### Problem 3: `batch_insert` causes flashing

**What happens**: `batch_insert` ops insert all whitespace at once.
Even with a delay after, the insertion is instant (one frame for all
chars).

**Fix**: The pace layer should insert whitespace chars with minimal
delay between them (but still char-by-char, not all at once). Or
`batch_whitespace` should only batch for op count reduction, not
for animation speed.

## What needs to be done

### Fix 1: Remove `delete_line` collapse from diff engine

The `delete_line` collapse in `diff_engine/cpp/compute.cpp` should
be REMOVED. The raw ops should keep the `delete@col1+ + join_lines`
pattern. The `line_delete_in_place` layer already handles this:
- Pattern 1: `join_lines + delete@col1 + join_lines` → moves deletes
  before the first join
- Pattern 2: `delete + join_lines + delete` → moves post-join deletes
  before the join

Both patterns produce: `delete@col1 on L+1 (char-by-char) + join_lines
(empty line pulled up — no visual jump)`.

### Fix 2: Verify the animation step-by-step

After removing the `delete_line` collapse:
1. Generate raw ops (should have 0 `delete_line`, 47+ `join_lines`)
2. Apply `line_delete_in_place` (should move all deletes before joins)
3. Trace the animation with snapshots
4. Verify: each line is deleted char-by-char, then the empty line
   vanishes (no join with content)

### Fix 3: Check indentation ordering

For lines where indentation AND content are deleted:
- Content deletes should happen first
- Indentation deletes should happen last
- The `indent_last` layer handles this, but it must run AFTER
  `line_delete_in_place` (so the deletes are already in the right
  position)
