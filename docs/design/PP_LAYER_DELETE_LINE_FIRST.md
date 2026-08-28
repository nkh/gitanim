# Delete-Line-Content-First Layer

**File:** `layers/c/ad_layer_layer_delete_line_first.c`
**Binary:** `animator/bin/pp_delete_line_first`
**Trigger:** Always runs (not optional)

## Purpose

When a line is fully deleted (content + `\n`) AND the previous line's
`\n` is also deleted (to join), this layer reorders the ops so the
deleted line's content is removed BEFORE the join happens.

This prevents the "join then delete" visual where line B's content
briefly appears on line A before being deleted.

## Example

```
Old:          New:
A             AC
B
C
```

**Raw ops (from compute):**
```
keep   (1,1) 'A'
delete (1,2) \n      ← join A+B (A's \n deleted)
delete (2,1) 'B'     ← delete B content (now on line 1!)
delete (2,1) \n      ← delete B's \n
keep   (3,1) 'C'
```

**After this layer:**
```
keep   (1,1) 'A'
delete (2,1) 'B'     ← delete B content FIRST (on line 2)
delete (2,1) \n      ← delete B's \n (empty line removed)
delete (1,2) \n      ← join A with C (A's \n deleted, C moves up)
keep   (2,1) 'C'
```

Now the animation shows: B's content vanishes on line 2, then line 2
is removed, then A and C join. No "B appears on line A".

## Algorithm

1. Walk ops. Look for pattern:
   - `\n` delete on line N (the join)
   - Content deletes on line N+1 (the deleted line's content)
   - `\n` delete on line N+1 (the deleted line's `\n`)

2. Only match if the `\n` delete on line N is a JOIN — meaning there
   are content ops (keeps/inserts) on line N BEFORE the `\n` delete.
   If line N only has deletes, it's a full line deletion, not a join.

3. When matched, reorder:
   - Emit content deletes (line N+1) FIRST
   - Emit `\n` delete on line N+1 (the deleted line's `\n`)
   - Emit the join `\n` delete (line N) LAST

Works for any number of consecutive line deletions.

## Build

```bash
# Standalone
cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
   -I animator/c -o animator/bin/pp_delete_line_first \
   layers/c/ad_layer_layer_delete_line_first.c

# In pipeline (via ad_postprocess)
compute | ad_postprocess | pace | animator
```

## Tests

```bash
perl animator/tests/test_delete_line_first.pl
```

67 tests: single line, multi-line, start/end, mixed, empty lines,
full deletion, and 50 random property tests.
