# animator/

The animator is stage 4 of the diffvim pipeline. It reads a timed op
stream (from pace) and applies each op to a virtual buffer, rendering
the result to the terminal.

## Pipeline context

```
compute → postprocess → pace → ANIMATOR → terminal
```

The animator reads TSV ops from stdin. Each op carries its own (line,
col) position. The animator moves the cursor there before applying
the op.

## Subdirectories

| Subdir | Contents |
|--------|----------|
| `c/` | C implementation (animator.c, postprocess.c, pp_layer0_v2.c, pp_layer1_reorder.c, pp_layer_indent_last.c, pp_layer_overwrite.c, pace.c) |
| `perl/` | Perl implementation (animator.pl, postprocess.pl, pace.pl, colorize.pl) |
| `bin/` | Compiled C binaries (tracked in git) |
| `docs/` | Animator-specific documentation |
| `tests/` | Perl test scripts |

## Files in this directory

- `diffvim-pipeline` — Bash script that runs the full pipeline:
  `compute → postprocess → pace → animator`. Routes options by prefix.
  Use `--compute-*`, `--postprocess-*`, `--pace-*`, `--animator-*`
  to pass options to each stage.

## C implementation (`c/`)

- `animator.c` — Terminal animator. Reads timed ops from stdin,
  applies them to a buffer, renders to the terminal.
  Keyboard controls: q=quit, Space=pause, n=next hunk, +/-=speed.
- `postprocess.c` — Orchestrates the layered postprocess pipeline
  (Layer 0 V2 conversion → Layer 1 reorder → optional
  delete-indent-last → optional overwrite → inline
  `adjust_positions()`). The `adjust_positions()` step is a recursive
  in-place walk that fixes per-op `(line, col)` based on `\n` deletes —
  it is NOT a separate layer (there is no `pp_layer3`). See
  `docs/POSTPROCESS_LAYERS.md` for the layer breakdown and
  `docs/POSTPROCESS_TRANSFORMS.md` for what the transforms do.
- `pace.c` — Reads post-processed ops, inserts `delay` lines between
  them. Does NOT modify, reorder, or add ops (except delays).

Build:
```bash
cc -O2 -o bin/diffvim-animator-c c/animator.c
cc -O2 -Wall -Wextra -Wunused -Werror -I c \
   -o bin/diffvim-postprocess \
   c/postprocess.c c/pp_layer0_v2.c c/pp_layer1_reorder.c \
   c/pp_layer_indent_last.c c/pp_layer_overwrite.c
cc -O2 -o bin/diffvim-pace c/pace.c
```

## Perl implementation (`perl/`)

Mirror of the C implementation, used as a fallback. Produces
byte-identical output.

- `animator.pl` — Terminal animator (use `--no-display` for testing)
- `postprocess.pl` — Same transformations as C version
- `pace.pl` — Same delay insertion as C version
- `colorize.pl` — Syntax highlighting (vim/pygmentize backends)

## Tests (`tests/`)

Run all tests:
```bash
for t in test_all_animators test_cross_language test_newline_fix \
         test_roundtrip test_roundtrip_verify test_snapshot_each_op \

    perl tests/$t.pl
done
```

See `tests/README.md` for details on each test.

## Docs (`docs/`)

- `README.md` — Animator overview
- `COMPARISON.md` — C vs Perl comparison

## Related

- `../compute/` — Stage 1 (diff computation)
- `../docs/DEBUGGING.md` — How to debug the pipeline
- `../docs/POSTPROCESS_LAYERS.md` — Layer-by-layer breakdown of postprocess
- `../docs/POSTPROCESS_TRANSFORMS.md` — What postprocess does
- `../scripts/dv_debug.sh` — Run all stages and inspect output
