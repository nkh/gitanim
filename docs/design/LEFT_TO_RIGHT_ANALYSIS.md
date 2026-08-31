# left_to_right — what it does, and why it's currently broken

## What it does

The `left_to_right` transform reorders ops within each line group:

- **All keeps first** (in original order)
- **Then all deletes** (in original order)
- **Then all inserts** (in original order)

The `\n` op stays at the end of its line group.

The positions (line, col) are then recomputed by walking the reordered ops.

## Without vs with left_to_right — a simple example

### Input

```
OLD: abcXYZ
NEW: abcdefXYZ
```

(The `def` is inserted between `abc` and `XYZ`.)

### Without left_to_right (AD_LEFT_TO_RIGHT=0)

```
HUNK	1	1	1	0	0
keep	1	1	97	'a'
keep	1	2	98	'b'
keep	1	3	99	'c'
insert	1	4	100	'd'      ← insert d at col 4 (after c)
insert	1	5	101	'e'      ← insert e at col 5
insert	1	6	102	'f'      ← insert f at col 6
keep	1	7	88	'X'      ← keep X at col 7 (after the inserts)
keep	1	8	89	'Y'
keep	1	9	90	'Z'
HUNK_END
```

**Animation walkthrough (what the animator does):**

| Op | Action | Buffer after |
|----|--------|--------------|
| keep 'a' | cursor 1→2 | `abcXYZ` |
| keep 'b' | cursor 2→3 | `abcXYZ` |
| keep 'c' | cursor 3→4 | `abcXYZ` |
| insert 'd' at col 4 | insert d before X | `abcdXYZ` |
| insert 'e' at col 5 | insert e before X | `abcdeXYZ` |
| insert 'f' at col 6 | insert f before X | `abcdefXYZ` |
| keep 'X' at col 7 | cursor 7→8 | `abcdefXYZ` |
| keep 'Y' | cursor 8→9 | `abcdefXYZ` |
| keep 'Z' | cursor 9→10 | `abcdefXYZ` |

**Final buffer:** `abcdefXYZ` ✅ **CORRECT**

**Visual:** the cursor types `abc`, then inserts `def` (shifting `XYZ` to the right), then continues past `XYZ`. This looks like natural human typing.

### With left_to_right=1 (AD_LEFT_TO_RIGHT=1, the current default)

```
HUNK	1	1	1	0	0
keep	1	1	97	'a'
keep	1	2	98	'b'
keep	1	3	99	'c'
keep	1	4	88	'X'      ← keep X at col 4 (NOT after the insert)
keep	1	5	89	'Y'
keep	1	6	90	'Z'
insert	1	7	100	'd'      ← insert d at col 7 (END of line!)
insert	1	8	101	'e'
insert	1	9	102	'f'
HUNK_END
```

**Animation walkthrough:**

| Op | Action | Buffer after |
|----|--------|--------------|
| keep 'a' | cursor 1→2 | `abcXYZ` |
| keep 'b' | cursor 2→3 | `abcXYZ` |
| keep 'c' | cursor 3→4 | `abcXYZ` |
| keep 'X' at col 4 | cursor 4→5 | `abcXYZ` |
| keep 'Y' | cursor 5→6 | `abcXYZ` |
| keep 'Z' | cursor 6→7 | `abcXYZ` |
| insert 'd' at col 7 | insert d at END | `abcXYZd` |
| insert 'e' at col 8 | insert e at END | `abcXYZde` |
| insert 'f' at col 9 | insert f at END | `abcXYZdef` |

**Final buffer:** `abcXYZdef` ❌ **WRONG** — should be `abcdefXYZ`

**Visual:** the cursor walks through the whole line keeping everything, then `def` appears appended at the end. The buffer ends up wrong.

## Why it's broken

The `left_to_right` transform was designed for a line-by-line diff view (where you show the old line, then mark what changed). It doesn't work for character animation because:

1. **Positions are recomputed** after reordering. The keeps advance the cursor through the ORIGINAL line positions, but the inserts end up at the END of the kept content — not at their natural mid-line positions.

2. **The animator applies ops to a live buffer.** When the animator processes "keep 'X' at col 4", it doesn't modify the buffer — it just advances the cursor. The buffer still has the original content. So when "insert 'd' at col 7" runs, it inserts at col 7 of the original buffer (which is past the end), not at col 4 (where 'd' should go).

3. **The keeps and inserts are no longer positionally consistent.** Without l2r, the insert at col 4 happens BEFORE the keep at col 7 — so the buffer is `abcdXYZ` when "keep 'X' at col 7" runs. With l2r, the keep at col 7 runs first (buffer still `abcXYZ`), then the insert at col 7 appends.

## When left_to_right MIGHT make sense

In theory, l2r could be useful if you want to:
- Show the "kept skeleton" of the line first
- Then delete the old content
- Then insert the new content

But for this to work correctly, the transform would need to also adjust the positions so deletes and inserts target the right place AFTER the keeps have advanced the cursor. The current implementation doesn't do this — it just recomputes positions naively.

## How to test it yourself

```bash
cd /home/z/my-project/gitanim

# Create a simple test case
printf 'abcXYZ\n' > /tmp/old.txt
printf 'abcdefXYZ\n' > /tmp/new.txt

# WITHOUT left_to_right (currently the default is 1, so set it to 0):
AD_LEFT_TO_RIGHT=0 ./bin/ad_compute /tmp/old.txt /tmp/new.txt /tmp/raw.txt 2>/dev/null
./bin/ad_postprocess < /tmp/raw.txt > /tmp/post.txt 2>/dev/null
./bin/ad_layer_pace < /tmp/post.txt > /tmp/timed.txt 2>/dev/null
./bin/ad --no-display --speed 1000 --snapshot /tmp/out.txt /tmp/old.txt < /tmp/timed.txt 2>/dev/null
echo "Without l2r:"; cat /tmp/out.txt

# WITH left_to_right=1:
AD_LEFT_TO_RIGHT=1 ./bin/ad_compute /tmp/old.txt /tmp/new.txt /tmp/raw.txt 2>/dev/null
./bin/ad_postprocess < /tmp/raw.txt > /tmp/post.txt 2>/dev/null
./bin/ad_layer_pace < /tmp/post.txt > /tmp/timed.txt 2>/dev/null
./bin/ad --no-display --speed 1000 --snapshot /tmp/out.txt /tmp/old.txt < /tmp/timed.txt 2>/dev/null
echo "With l2r:"; cat /tmp/out.txt

echo "Expected:"; cat /tmp/new.txt
```

## Current default

The launcher currently exports `AD_LEFT_TO_RIGHT=1` by default. This means the ad_vim launcher produces **wrong output** for any mid-line insert.

The `dv_debug.sh` script and `verify_md5.sh` set `AD_LEFT_TO_RIGHT` to 0 (or don't set it, and the compute tool defaults to 0), which is why those tests pass but the launcher fails.

## Options

1. **Fix the `left_to_right` transform** so it correctly adjusts positions for the animator
2. **Change the default to 0** (what I did — but you said not to remove functionality)
3. **Keep the default at 1** but document that it produces wrong output for mid-line inserts
4. **Remove the transform entirely** (most aggressive)

The decision is yours. The transform is in `compute/cpp/ad_compute.cpp`, function `left_to_right()`.
