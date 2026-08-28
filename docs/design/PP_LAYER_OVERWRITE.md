# Overwrite Transform Layer

**File:** `layers/c/ad_layer_layer_overwrite.c`
**Binary:** `bin/ad_layer_overwrite`
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
debug   overwrite       merged delete(108) + insert(112) → overwrite_insert(112) at line=1 col=2
```

Debug ops are ignored by all other layers and the animator.

## Build

```bash
# Standalone
cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror \
   -I animator/c -o bin/ad_layer_overwrite layers/c/ad_layer_layer_overwrite.c

# In pipeline (via ad_postprocess, which also runs adjust_positions)
compute | ad_postprocess --overwrite | pace | animator
```

> Standalone `ad_layer_overwrite` does NOT run `adjust_positions`. The
> position-fixing pass lives only inside `postprocess.c`. Use
> `ad_postprocess --overwrite` to get the full pipeline.
> If you pipe layers manually, you must apply your own equivalent
> of `adjust_positions` afterwards (or just use `ad_postprocess`).

## Debug Logging

```bash
AD_DEBUG_LAYERS=/tmp/ad_debug ad_layer_overwrite < input > output
cat /tmp/ad_debug/postprocess.log
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
- **Layer 1 (reorder):** Overwrite runs after reorder.
- **delete-indent-last (--indent-last):** Overwrite runs after
  delete-indent-last, when both are enabled.
- **adjust_positions (inline in postprocess.c):** Runs AFTER overwrite.
  The `overwrite_insert` ops have the original line/col from compute;
  `adjust_positions` then fixes them in-place based on `\n` deletes.
  There is no separate `ad_layer_noop` step.
- **Pace:** The pace tool uses minimal delay for `overwrite_insert`
  ops (1ms, type "overwrite").
