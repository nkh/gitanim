# animator/

The animator: stage 4 of the `ad` pipeline. Reads timed op stream
(computed by ad_compute → ad_postprocess → ad_layer_pace) and applies
the ops to a buffer, rendering the animation to the terminal or vim.

## Contents

- `c/ad.c` — C implementation (built to `bin/ad`)
- `perl/ad.pl` — Perl fallback (produces identical output)
- `perl/colorize.pl` — syntax highlighting helper for the animator
- `tests/` — animator-specific tests (most tests live in `tests/`)

## Binary

`bin/ad` — built from `c/ad.c` by `make`.

Usage:

    ./bin/ad --no-display --speed 1000 --snapshot out.txt old.py < timed_ops.txt

## Vimscript engine

The vim application (`apps/vim/ad_vim`) sources a vimscript engine that
applies the same timed op stream inside vim. See `apps/vim/plugin.vim`
and `apps/vim/autoload_diffvim/`.
