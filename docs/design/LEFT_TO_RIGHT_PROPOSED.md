# Proposed left_to_right algorithm — pseudo-code

## The problem

Current implementation moves ALL keeps to the front, then ALL deletes,
then ALL inserts. This breaks positions (inserts end up at end of line
instead of mid-line) and produces wrong output.

## What left_to_right should do

When a word is replaced by another word (`world` → `there`), the diff
produces interleaved `delete insert delete insert` which looks horrible
to watch. The goal: within each change region, do all deletes first,
then all inserts.

**Keeps must stay in place** — they are the anchors that define where
change regions are.

## Pseudo-code

```
function left_to_right(ops):
    """
    Reorder ops so that within each change region (between keeps),
    all deletes come before all inserts. Keeps stay in place.
    
    A "change region" is a maximal sequence of consecutive non-keep ops
    (deletes and inserts). Keeps act as boundaries between regions.
    """

    output = empty list
    i = 0
    n = length(ops)
    
    while i < n:
        if ops[i].type == KEEP:
            # Keep stays in place — emit unchanged
            output.append(ops[i])
            i = i + 1
        else:
            # Start of a change region: collect consecutive non-keep ops
            region = empty list
            while i < n and ops[i].type != KEEP:
                region.append(ops[i])
                i = i + 1
            
            # Within this region: emit all DELETEs first, then all INSERTs
            for op in region:
                if op.type == DELETE:
                    output.append(op)
            for op in region:
                if op.type == INSERT:
                    output.append(op)
    
    # Positions are recomputed at write time by walking the output.
    # Since keeps stayed in place, positions will be correct.
    return output
```

## Examples

### Example 1: Single word replacement (`hello world` → `hello there`)

**Input** (natural diff order):
```
keep h, keep e, keep l, keep l, keep o, keep space,
delete w, delete o, insert t, insert h, insert e,
keep r,
delete l, delete d, insert e
```

Two change regions:
- Region 1: `delete w, delete o, insert t, insert h, insert e`
- Region 2: `delete l, delete d, insert e`

**After left_to_right**:
```
keep h, keep e, keep l, keep l, keep o, keep space,
delete w, delete o, insert t, insert h, insert e,     ← deletes then inserts
keep r,                                                  ← stay in place
delete l, delete d, insert e                            ← deletes then inserts
```

**Animation**: cursor walks through `hello `, deletes `wo`, types `the`, keeps `r`, deletes `ld`, types `e`.

### Example 2: Multiple word replacements (`foo bar` → `xyz qux`)

**Input**:
```
delete f, insert x, delete o, insert y, delete o, insert z,
keep space,
delete b, insert q, delete a, insert u, delete r, insert x
```

Two change regions (split by `keep space`):
- Region 1: `delete f, insert x, delete o, insert y, delete o, insert z`
- Region 2: `delete b, insert q, delete a, insert u, delete r, insert x`

**After left_to_right**:
```
delete f, delete o, delete o, insert x, insert y, insert z,
keep space,
delete b, delete a, delete r, insert q, insert u, insert x
```

**Animation**: delete `foo`, type `xyz`, keep space, delete `bar`, type `qux`. Each word replacement is handled independently.

### Example 3: Pure insertion (`abcXYZ` → `abcdefXYZ`)

**Input**:
```
keep a, keep b, keep c,
insert d, insert e, insert f,
keep X, keep Y, keep Z
```

Change region: `insert d, insert e, insert f` (already all inserts, no reordering needed)

**After left_to_right**:
```
keep a, keep b, keep c,
insert d, insert e, insert f,
keep X, keep Y, keep Z
```

**Animation**: cursor walks to `c`, inserts `def`, continues past `XYZ`. Identical to without left_to_right — correct!

### Example 4: Pure deletion (`abcdef` → `abc`)

**Input**:
```
keep a, keep b, keep c,
delete d, delete e, delete f
```

Change region: `delete d, delete e, delete f` (already all deletes, no reordering needed)

**After left_to_right**: same as input.

## Why this is correct

The key insight: **keeps define the anchor points**. The cursor walks
through keeps, and between two keeps there's a change region. Within
that region, we delete the old content first, then insert the new
content.

The positions are recomputed at write time by walking the output:
- `keep` advances col by 1
- `insert` advances col by 1
- `delete` keeps col the same (next char shifts in)
- `\n` (code 10) advances line, resets col to 1

Since keeps stayed in place, the cursor is at the right position when
the deletes and inserts run. This is the same position computation
that already works correctly without left_to_right.

## Comparison with current implementation

| | Current (broken) | Proposed (correct) |
|---|---|---|
| Keeps | Moved to front | Stay in place |
| Deletes | After all keeps | Within each change region |
| Inserts | After all deletes | Within each change region |
| Positions | Wrong (inserts at end) | Correct (inserts mid-line) |
| Animation | Cursor walks whole line, then appends | Natural: delete old, type new |

## Edge cases

1. **Newlines in change regions**: A `delete \n` or `insert \n` is part
   of the change region (it's not a keep). It stays in the region and
   gets reordered with the other deletes/inserts. The position
   computation handles `\n` ops correctly (advances line).

2. **Empty change regions**: If there are no non-keep ops between two
   keeps, nothing happens (the while loop just skips to the next keep).

3. **Change region at start/end of hunk**: Works the same — the
   region extends from the first non-keep op to the next keep (or end
   of ops).

4. **Consecutive change regions** (no keep between them): Treated as
   one region. This is correct — if there's no keep between them,
   they're part of the same "word replacement".

## What this does NOT do

- Does NOT move keeps
- Does NOT merge change regions across keeps
- Does NOT change the op count (same number of keep/delete/insert)
- Does NOT change what gets deleted/inserted (only the order)
