# Overwrite Transform Layer

**File:** `animator/c/pp_layer_overwrite.c`
**Binary:** `animator/bin/pp_overwrite`
**Trigger:** `--overwrite` (env: `DIFFVIM_OVERWRITE=1`)

## Purpose

When a `delete` (code != 10) is immediately followed by an `insert`
(code != 10) at the same `(line, col)`, replace the pair with a single
`overwrite_insert` op. The animator applies the insert in-place
(deletes the old char, then inserts the new one in one step — no gap,
no flicker).

**Codes need NOT match** — this is position-based, not value-based.
Example: `delete 'a'` at (1,5) + `insert 'B'` at (1,5) →
`overwrite_insert 'B'` at (1,5).

## Algorithm

1. Linear scan over ops.
2. If `delete` (code != 10) immediately followed by `insert` (code != 10)
   at the same `(line, col)`:
   - Skip the `delete`.
   - Change the `insert` type to `overwrite_insert`.
   - The op's code becomes the insert's code (the new char).
   - The op's line/col stays (same position).
3. All other ops pass through unchanged.

## Animator Behavior

The C animator handles `overwrite_insert` by:
1. Calling `delete_char()` (removes the char at cursor).
2. Calling `insert_char()` (inserts the new char at cursor).

This is a single-step replacement — no delay between delete and insert.

## Debug Ops

If `DV_OP_DEBUG=1`, a `debug` op is inserted before each
`overwrite_insert`:

```
debug	overwrite	merged delete(108) + insert(112) → overwrite_insert(112) at line=1 col=2
```

Debug ops are ignored by all other layers and the animator.

## Build

```bash
# Standalone
cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
   -I animator/c -o animator/bin/pp_overwrite animator/c/pp_layer_overwrite.c

# In pipeline
compute | pp_layer0 | pp_overwrite | pp_layer3 | pace | animator
```

## Debug Logging

```bash
DV_DEBUG_POSTPROCESS=/tmp/dv_debug pp_overwrite < input > output
cat /tmp/dv_debug/postprocess.log
```

Log shows: op count, merge count, per-hunk statistics.

## Tests

```bash
bash tests/test_overwrite_layer.sh
```

10 tests:
1. Overwrite merges adjacent delete+insert ✓
2. Without overwrite, no overwrite_insert ops ✓
3. Animation WITH overwrite matches ✓
4. Animation WITHOUT overwrite matches ✓
5. op-debug inserts debug ops ✓
6. Debug logging produces files ✓
7. Debug log contains merge info ✓
8. Non-adjacent delete+insert NOT merged ✓
9. Multiple adjacent pairs merged ✓
10. Multiple pairs animation correct ✓

## Interaction with Other Layers

- **Layer 0 (V2 conversion):** Overwrite runs after V2 conversion.
- **Layer 3 (cursor recomp):** Overwrite runs before cursor recomp.
  The overwrite_insert ops have the original line/col from compute.
  Layer 3 will recompute them.
- **Pace:** The pace tool uses minimal delay for `overwrite_insert`
  ops (1ms, type "overwrite").
