# animator/perl/

Perl fallback for the C animator.

## Files

- `ad.pl` — Perl animator. Reads timed ops from stdin, applies them to
  the old file, renders the animation. Produces identical output to the
  C animator (`animator/c/ad.c`).
- `colorize.pl` — Syntax highlighting helper for the Perl animator.

## Usage

```bash
perl animator/perl/ad.pl --no-display --speed 1000 --snapshot out.txt old.py < ops.tsv
```

## When is the Perl animator used?

The pipeline prefers the C animator (`bin/ad`). If the C binary is not
found, it falls back to the Perl version. This is mainly for systems
without a C compiler.
