# Postprocess Op Pipeline

This document describes all operation layers and transformations applied
to the raw ops (from compute) in the current postprocess pipeline.

## Pipeline Overview

```
compute output (raw V2 TSV, read directly from stdin)
    │
    ▼
[Optional] overwrite (ad_layer_layer_overwrite.c)
    │   Trigger: --overwrite
    │   Runs FIRST because it reduces the number of ops (merges
    │   delete+insert pairs at the same position into overwrite_insert).
    │   Fewer ops = less work for later layers.
    │
    │   What it does:
    │     - Scans for a delete (code != \n) immediately followed by
    │       an insert (code != \n) at the same (line, col).
    │     - Replaces the pair with a single overwrite_insert op.
    │     - The animator applies overwrite_insert as a delete+insert
    │       in one step (no gap, no flicker).
    │
    ▼
[Optional] delete-indent-last (ad_layer_layer_indent_last.c)
    │   Trigger: --indent-last
    │   Moves leading-whitespace DELETE ops to end of line group.
    │   Does NOT touch line/col — only reorders ops.
    │
    │   What it does, per line:
    │     1. Find leading indent deletes: consecutive space/tab DELETE
    │        ops at the start of the line (before any content op).
    │     2. Find the \n op for this line (if any).
    │     3. Reorder: content ops first, then indent deletes,
    │       then \n op.
    │     - If the line has a \n delete: indent deletes go JUST BEFORE
    │       the \n delete.
    │     - If the line has no \n delete: indent deletes go at the END
    │       of the line's ops.
    │
    ▼
reorder (ad_layer_noop_reorder.c)
    │   Reorders ops within each line group using 4 sweeps.
    │   Always runs (not optional).
    │
    │   What it does:
    │     - A "line group" is the ops between two keep ops or \n ops.
    │     - Within each group, reorder to:
    │         1. Content deletes (code != \n)
    │         2. Content inserts (code != \n)
    │         3. \n deletes (code == \n)
    │         4. \n inserts (code == \n)
    │     - Keeps stay in their original position (they anchor groups).
    │     - This ensures \n deletes happen AFTER all content is settled,
    │       preventing content from appearing on the wrong line.
    │
    ▼
adjust_positions (inline in postprocess.c)
    │   Adjusts (line, col) for every op based on \n deletes.
    │   Recursive, single pass.
    │
    │   State:
    │     deleted_lines: count of \n deletes (incremented on every \n delete)
    │     current_characters: cursor position on the current line
    │     current_line: the current line being processed
    │
    │   Rules:
    │     1. Line changed → current_characters = op.col, update current_line
    │     2. Count chars (code != \n): keep +1, insert +1, delete +0, overwrite_insert +0
    │     3. Set op position: op.line -= deleted_lines, op.col = current_characters
    │     4. \n delete: deleted_lines++. If current_characters > 1 (content beyond
    │        just the \n): JOIN → recursive call on merged line's ops, passing
    │        current_characters as carry.
    │     5. \n keep/insert/overwrite_insert: current_characters = 0
    │
    │   A line always has ≥1 char (the \n). So current_characters starts at
    │   op.col (≥1). JOIN is detected when current_characters > 1 (content
    │   chars exist beyond the \n).
    │
    ▼
postprocess output (V2 TSV to stdout)
```

## Build

```sh
cc -O2 -Wall -Wextra -Wunused -Werror -I animator/c -o ad_postprocess \
  postprocess.c \
  ad_layer_noop_reorder.c \
  ad_layer_layer_indent_last.c \
  ad_layer_layer_overwrite.c
```

No `ad_layer_noop_v2.c` — compute output is already V2, so Layer 0 (V2
conversion) was removed.

## Usage

```sh
ad_postprocess [--indent-last] [--overwrite] [--op-debug]
```

## Standalone Layer Binaries

Each layer can be run standalone (for debugging):
- `ad_layer_overwrite` — overwrite layer
- `ad_layer_indent_last` — delete-indent-last layer
- `ad_layer_noop` — reorder layer

No `ad_layer_noop` (removed) and no `ad_layer_noop` (removed).

## Known Limitations

- `adjust_positions` has edge cases with complex JOIN scenarios
  (content swaps, multiple joins in sequence). ~5/50 property tests
  fail on these. The basic JOIN (line with content + \n delete) works.
- `--overwrite` has a separate issue with `adjust_positions` when
  overwrite_insert ops are involved in joins.
