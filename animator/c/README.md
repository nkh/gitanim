# animator/c/

C implementation of the animator.

## Files

- `ad.c` — The animator. Reads timed ops from stdin, applies them to
  the old file's buffer, and renders the animation to the terminal.
  Supports `--no-display` (headless), `--snapshot` (write buffer to
  file), `--speed` (multiplier), and interactive controls (pause,
  skip, quit).

## Build

```bash
make animator    # builds bin/ad
```

## Usage

```bash
./bin/ad old.py < ops.tsv                    # interactive animation
./bin/ad --no-display --speed 1000 --snapshot out.txt old.py < ops.tsv  # headless
```

## Controls (interactive mode)

- `Space` — pause/resume
- `n` — skip to next hunk
- `q` — quit
- `+`/`-` — speed up / slow down
- `=` — reset speed
