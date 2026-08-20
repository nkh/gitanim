# Postprocess options that change ops

The postprocess stage (`diffvim-postprocess`) applies several optional
transforms. Some are always-on, some are option-dependent.

## Transform pipeline

Transforms are applied in this order:

```
raw ops from compute
    │
    ├── 1. [always] op reordering (optimize_sequence)
    ├── 2. [optional] semantic_cleanup (--semantic-cleanup)
    ├── 3. [optional] indent_aware (--indent-aware)
    ├── 4. [always] per-op (line, col) position computation
    ├── 5. [always] ghost-line fix (content deletes before \n delete)
    └── 6. [always] end-delete hunk fix (\n delete redirected)
        │
        ▼
post-processed ops (to pace)
```

## Options

### `--op-order natural|optimize` (default: optimize)

Controls step 1 — op reordering within each line group.

- `optimize` (default): Within each "change region" (between keeps and
  \n boundaries), emit all DELETEs first, then all INSERTs. Keeps stay
  in place. This produces the "delete old word, then type new word"
  visual.
- `natural`: No reordering. Ops are emitted in the raw diff order from
  compute. This may produce interleaved delete+insert (visually
  horrible for word replacements).

**Effect on ops**: Reorders within line groups. Does NOT change op count.

### `--semantic-cleanup` (default: off)

Controls step 2. Merges adjacent `delete X` + `insert X` pairs (where
the chars are identical) into a single `keep X` op.

**Example**: `delete 'a', insert 'a'` → `keep 'a'`

**Effect on ops**: Reduces op count (merges canceling pairs).

### `--indent-aware` (default: off)

Controls step 3. Treats indent-only changes (whitespace at start of
line) as keeps instead of delete+insert.

**Effect on ops**: Converts delete/insert pairs to keeps when only
indentation changed.

### `DIFFVIM_LEFT_TO_RIGHT=1` (env var, default: 1 in launcher)

This is a **compute-stage** option (not postprocess), but it affects
the ops the postprocess receives. When enabled, the compute applies the
`left_to_right` transform: within each change region (consecutive
non-keep, non-\n ops), all DELETEs are emitted first, then all INSERTs.
Keeps and \n ops stay in place.

**Effect on ops**: Reorders within change regions. Does NOT change op
count. Positions are recomputed at write time.

### `--stream` (default: off)

Enables streaming mode: reads and processes one hunk at a time, emits
it immediately. Does not change the ops — only the I/O pattern.

### `--transform NAME[:VALUE]` (repeatable)

Generic way to specify transforms. Each `--transform` flag is applied
in order. Available transforms:
- `op-order:natural` / `op-order:optimize`
- `semantic-cleanup`
- `indent-aware`
- `overwrite`

## Summary table

| Option | Default | Where | Changes op count? | Changes op order? |
|--------|---------|-------|-------------------|-------------------|
| `--op-order optimize` | on | postprocess | No | Yes (within line groups) |
| `--semantic-cleanup` | off | postprocess | Yes (reduces) | No |
| `--indent-aware` | off | postprocess | Yes (reduces) | No |
| `DIFFVIM_LEFT_TO_RIGHT=1` | on (launcher) | compute | No | Yes (within change regions) |
| `--stream` | off | postprocess | No | No (I/O only) |
| `--overwrite` | off | postprocess | No | No (alias for optimize) |

## Always-on transforms (cannot be disabled)

1. **Per-op (line, col) position computation** — walks the ops and
   computes cursor positions. Always applied.

2. **Ghost-line fix** — when `delete \n` would join two lines and the
   line has kept content, reorders the next line's content deletes to
   target `(line+1, 1)` before the `\n` delete.

3. **End-delete hunk fix** — when the last line is being deleted
   (is_end_delete hunk), redirects the `\n` delete to `(line-1, 1)`.
