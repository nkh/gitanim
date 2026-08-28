# animator/c/

C implementation of the animator pipeline stages (postprocess, pace,
animator).

## Files

- `animator.c` — Terminal animator. Reads timed ops from stdin,
  applies them to a virtual buffer, renders to the terminal.
  Supports keyboard input (q=quit, Space=pause, n=next hunk,
  +/-=speed, ==reset).
- `postprocess.c` — Orchestrates the layered postprocess pipeline:
  Layer 0 (V2 conversion) → Layer 1 (reorder) → delete-indent-last
  (optional, `--indent-last`) → overwrite (optional, `--overwrite`)
  → `adjust_positions()`. The `adjust_positions()` function is inline
  in this file — a recursive walk that fixes per-op `(line, col)`
  based on `\n` deletes. There is no separate cursor-recomputation
  layer. See `../../docs/POSTPROCESS_LAYERS.md` for the layer
  breakdown and `../../docs/POSTPROCESS_TRANSFORMS.md` for what
  the transforms do.
- `ad_layer_noop_v2.c` — Layer 0: V1/V2 detection and conversion.
- `ad_layer_noop_reorder.c` — Layer 1: 4-sweep reorder within line groups.
- `pp_layer_indent_last.c` — delete-indent-last transform (reorders
  leading-whitespace deletes; does NOT touch line/col).
- `pp_layer_overwrite.c` — overwrite transform (marks delete+insert
  pairs as `overwrite_insert`).
- `ad_layer_common.h` — Shared types (Op struct: `type`, `code`, `line`,
  `col` — no `pos_set` field), logging, TSV parsing, standalone runner.
- `ad_layer_pace.c` — Reads post-processed ops, inserts `delay` lines between
  them. Does NOT modify, reorder, or add ops (except delays).

## Build

There's no Makefile in this directory. Build from the project root.
`postprocess.c` must be compiled together with the layer files it
orchestrates (the `adjust_positions()` step lives only in this
combined binary — there is no standalone `ad_layer_noop` for cursor
recomputation):

```bash
cc -O2 -o bin/ad animator/c/ad.c
cc -O2 -Wall -Wextra -Wunused -Werror -I animator/c \
   -o bin/ad_postprocess \
   animator/c/postprocess.c \
   animator/c/ad_layer_noop_v2.c \
   animator/c/ad_layer_noop_reorder.c \
   layers/c/ad_layer_layer_indent_last.c \
   layers/c/ad_layer_layer_overwrite.c
cc -O2 -o bin/ad_layer_pace animator/c/ad_layer_pace.c
```

Or all at once:
```bash
cd /path/to/gitanim
cc -O2 -o bin/ad animator/c/ad.c
cc -O2 -Wall -Wextra -Wunused -Werror -I animator/c \
   -o bin/ad_postprocess \
   animator/c/postprocess.c animator/c/ad_layer_noop_v2.c \
   animator/c/ad_layer_noop_reorder.c layers/c/ad_layer_layer_indent_last.c \
   layers/c/ad_layer_layer_overwrite.c
cc -O2 -o bin/ad_layer_pace animator/c/ad_layer_pace.c
```

## Input validation

All three tools detect v1 format input and exit with a loud error
message. This prevents silent failures when the compute binary is
stale (v1 output instead of v2).

## Related

- `../perl/` — Perl implementation (produces identical output)
- `../../docs/POSTPROCESS_LAYERS.md` — Layer-by-layer breakdown
- `../../docs/POSTPROCESS_TRANSFORMS.md` — What postprocess does
- `../../docs/DEBUGGING.md` — How to debug
