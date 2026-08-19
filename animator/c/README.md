# animator/c/

C implementation of the animator pipeline stages (postprocess, pace,
animator).

## Files

- `animator.c` — Terminal animator. Reads timed ops from stdin,
  applies them to a virtual buffer, renders to the terminal.
  Supports keyboard input (q=quit, Space=pause, n=next hunk,
  +/-=speed, ==reset).
- `postprocess.c` — Reads raw ops from compute, reorders them,
  computes per-op (line, col) positions. See
  `../../docs/POSTPROCESS_TRANSFORMS.md` for what it does.
- `pace.c` — Reads post-processed ops, inserts `delay` lines between
  them. Does NOT modify, reorder, or add ops (except delays).

## Build

There's no Makefile in this directory. Build from the project root:

```bash
cc -O2 -o animator/bin/diffvim-animator-c animator/c/animator.c
cc -O2 -o animator/bin/diffvim-postprocess animator/c/postprocess.c
cc -O2 -o animator/bin/diffvim-pace animator/c/pace.c
```

Or all at once:
```bash
for f in animator pace postprocess; do
    cc -O2 -o animator/bin/diffvim-$f animator/c/$f.c
done
```

## Input validation

All three tools detect v1 format input and exit with a loud error
message. This prevents silent failures when the compute binary is
stale (v1 output instead of v2).

## Related

- `../perl/` — Perl implementation (produces identical output)
- `../../docs/POSTPROCESS_TRANSFORMS.md` — What postprocess does
- `../../docs/DEBUGGING.md` — How to debug
