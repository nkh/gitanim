# animator/perl/

Perl implementation of the animator pipeline stages. Mirror of the C
implementation in `../c/`. Produces byte-identical output.

## Files

- `animator.pl` — Terminal animator. Reads timed ops from stdin,
  applies them to a virtual buffer. Supports `--no-display` for
  headless testing and `--snapshot FILE` to write the final buffer.
- `postprocess.pl` — Same transformations as the C version.
  See `../../docs/POSTPROCESS_TRANSFORMS.md` for details.
- `pace.pl` — Same delay insertion as the C version.
- `colorize.pl` — Syntax highlighting. Supports `vim` and `pygmentize`
  backends. Used by `diffvim-pipeline` to colorize old/new files
  in parallel with the compute stage.

## Usage

```bash
# Post-process raw ops:
perl animator/perl/postprocess.pl < raw.txt > post.txt

# Add delays:
perl animator/perl/pace.pl < post.txt > timed.txt

# Animate (terminal):
perl animator/perl/animator.pl old.txt < timed.txt

# Animate (headless, for testing):
perl animator/perl/animator.pl --no-display --speed 1000 --snapshot out.txt old.txt < timed.txt
```

## Why Perl?

The Perl implementations exist as a fallback — if the C binaries
are missing or don't work on a particular platform, the pipeline
falls back to Perl. Both produce identical output, verified by
`tests/verify_md5.sh` (42/42 pass for both C and Perl).

## Related

- `../c/` — C implementation (produces identical output)
- `../../docs/POSTPROCESS_TRANSFORMS.md` — What postprocess does
- `../../tests/verify_md5.sh` — Verifies C == Perl
