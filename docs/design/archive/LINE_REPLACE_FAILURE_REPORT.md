# Line Replace Layer — Failure Analysis Report

*Generated using the L1/L2 debugging tool (scripts/ad_l1l2)*
*Date: 2026-09-08*

## Summary

The `ad_layer_line_replace` layer fails on **all 42 test examples**. L1/L2
analysis shows the failures start at line 1 or 2 in most cases, indicating
a fundamental bug in how the layer emits `delete_line`/`insert_line` ops.

## Methodology

The L1/L2 debugging tool works as follows:
1. Apply the op stream to the old file using the C animator (verified
   correct: 42/42 examples pass without layers)
2. Compare the resulting buffer against the new file line-by-line
3. Find L1 (last line where buffer matches new) and L2 (first line where
   it differs)

This tests the **op stream** (diff engine + layers), not the animator.
Since the C animator is verified correct (42/42 without layers), any L2 > 0
indicates a bug in the ops produced by the diff engine or layers.

## Test Results

### C animator without layers (baseline)
```
C animator: 42 pass, 0 fail
```
All examples pass — the diff engine and C animator are correct.

### C animator with ad_layer_line_replace
```
line_replace: 0 pass, 42 fail
```

### L1/L2 breakdown per example

| Example | L1 | L2 | L_TOTAL | Notes |
|---------|----|----|---------|-------|
| 01_small_python | 1 | 2 | 3 | Only 1 of 3 lines deleted |
| 02_large_python | 0 | 1 | 123 | First line already wrong |
| 03_json_config | 1 | 2 | 26 | |
| 04_shell_script | 0 | 1 | 54 | |
| 05_go_code | 2 | 3 | 81 | |
| ... | ... | ... | ... | All 42 fail |

Most failures are at L2=1 or L2=2, meaning the very first or second line
is already wrong.

## Root Cause Analysis

### Example 01 (simplest case)

**Old file (3 lines):**
```
def greet(name):
    print("Hello, " + name)
    return None
```

**New file:** empty (0 lines)

**Raw ops (from diff engine):**
```
HUNK 1 3 1 0 0
delete 1 1 'd'     (delete all chars of line 1)
delete 1 1 'e'
...
delete 1 1 \n      (delete newline between line 1 and 2)
delete 1 1 ' '     (delete all chars of line 2)
...
delete 1 1 \n      (delete newline between line 2 and 3)
delete 1 1 ' '     (delete all chars of line 3)
...
HUNK_END
```

**Ops produced by line_replace layer:**
```
HUNK 1 3 1 0 0
delete_line 1
insert_line 1  (empty text)
HUNK_END
```

**What the animator produces:**
```
(empty line)
    print("Hello, " + name)
    return None
```

**Expected:** empty file (0 lines)

### The bug

The layer emits ONE `delete_line 1` + `insert_line 1` (empty) for all
three lines' worth of deletes. The animator:
1. Deletes line 1 (`def greet(name):`) — buffer now has 2 lines
2. Inserts empty line at position 1 — buffer has 3 lines: `""`, `    print(...)`, `    return None`

But the expected result is an empty file. The layer should have emitted
THREE `delete_line 1` ops (one per original line), not one
`delete_line` + one `insert_line`.

### Why it happens

The layer uses "virtual line" tracking: it groups ops by virtual line
number, where virtual_line advances on `\n keep/insert` but NOT on
`\n delete`. When `\n delete` joins two lines, the joined content stays
on the same virtual line.

For this example:
- All ops for lines 1, 2, 3 are at virtual_line 1 (because `\n delete`
  doesn't advance virtual_line)
- The layer sees one group at virtual_line 1 with only deletes
- It emits one `delete_line 1` + `insert_line 1` (empty, since all
  chars were deleted)
- But this only handles ONE buffer line, not three

### The fix needed

The layer must emit a `delete_line` for EACH actual buffer line that
gets consumed. When a `\n delete` happens, it means two lines are being
joined. If both lines' content is fully deleted, the layer should emit
TWO `delete_line` ops (one for each original line).

The current approach of grouping by virtual_line is wrong because it
collapses multiple buffer lines into one virtual line when `\n delete`
happens.

**Proposed fix:** Instead of virtual_line tracking, the layer should:
1. Simulate the buffer walk (tracking actual line numbers)
2. When a `\n delete` is encountered, emit a `delete_line` for the
   current line if it has changes, then continue with the next line
3. When a `\n insert` is encountered, emit an `insert_line` for the
   new line
4. When a `\n keep` is encountered, the line is unchanged — pass through

## L1/L2 with other layer combinations

### Individual layers and combinations

| Layer combination | Pass | Fail | Notes |
|-------------------|------|------|-------|
| ad_layer_reorder | 42 | 0 | ✓ Correct |
| ad_layer_reorder + ad_layer_overwrite | 28 | 14 | ✗ 14 failures |
| ad_layer_reorder + ad_layer_indent_last | 42 | 0 | ✓ Correct |
| ad_layer_reorder + ad_layer_line_delete_in_place | 31 | 11 | ✗ 11 failures |
| ad_layer_reorder + ad_layer_skip_indent | 40 | 2 | ✗ 2 failures |
| ad_layer_line_replace | 0 | 42 | ✗ All fail |

**Key finding:** L1/L2 discovered bugs in `overwrite`, `line_delete_in_place`,
and `skip_indent` layers that were NOT caught by the existing test suite
(`run_all_examples.sh` only tests with `ad_layer_reorder`).

### Detailed L1/L2 for failing combinations

#### reorder + overwrite (14 fail)

```
FAIL 01_small_python                     L1=0  L2=1/1
FAIL 04_shell_script                     L1=16 L2=17/54
FAIL 05_go_code                          L1=78 L2=79/81
FAIL 07_text_prose                       L1=5  L2=6/36
FAIL 33_large_python                     L1=4  L2=5/393
FAIL 34_large_javascript                 L1=6  L2=7/354
FAIL 35_large_perl                       L1=2  L2=3/491
FAIL 36_large_rust                       L1=83 L2=84/554
FAIL 37_large_go                         L1=48 L2=49/594
FAIL 38_large_java                       L1=21 L2=22/604
FAIL 39_large_typescript                 L1=1  L2=2/479
FAIL 40_large_csharp                     L1=0  L2=1/816
FAIL 41_large_ruby                       L1=2  L2=3/858
FAIL 42_large_huge_python                L1=3  L2=4/1221
```

#### reorder + line_delete_in_place (11 fail)

```
FAIL 07_text_prose                       L1=5   L2=6/36
FAIL 33_large_python                     L1=23  L2=24/393
FAIL 34_large_javascript                 L1=3   L2=4/354
FAIL 35_large_perl                       L1=181 L2=182/491
FAIL 36_large_rust                       L1=116 L2=117/554
FAIL 37_large_go                         L1=38  L2=39/594
FAIL 38_large_java                       L1=94  L2=95/604
FAIL 39_large_typescript                 L1=98  L2=99/479
FAIL 40_large_csharp                     L1=38  L2=39/816
FAIL 41_large_ruby                       L1=0   L2=1/858
FAIL 42_large_huge_python                L1=2   L2=3/1221
```

#### reorder + skip_indent (2 fail)

```
FAIL 35_large_perl                       (L1/L2 not captured)
FAIL 38_large_java                       (L1/L2 not captured)
```

## Conclusion

The L1/L2 debugging tool correctly identified that `ad_layer_line_replace`
produces incorrect ops for all 42 examples. The root cause is the
virtual_line tracking collapsing multiple buffer lines into one when
`\n delete` happens. The layer needs to be rewritten to track actual
buffer lines and emit one `delete_line`/`insert_line` per actual line.
