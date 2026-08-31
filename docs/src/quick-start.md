# Quick Start

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


## Basic Usage

```bash
# Animate a diff between two files
./ad_vim old.py new.py
```

Vim opens with `old.py`, the cursor glides to the first change, and
characters are deleted/typed to transform the buffer into `new.py`.

## During Animation

| Key | Action |
|-----|--------|
| `Space` | Pause / resume |
| `n` | Skip current hunk (apply instantly) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation |
| `+` | Speed up (x1.5) |
| `-` | Slow down (x0.67) |
| `=` | Reset speed to 1.0x |
| `u` | Undo last hunk |
| `Ctrl-r` | Redo hunk |
| `?` | Show help overlay |

## After Animation

The buffer is a normal vim buffer — you can `:w`, `:wq`, edit further, etc.

## Try the Examples

The repo includes example file pairs in `tests/tests/examples/`:

```bash
# Small Python diff (f-string conversion)
./ad_vim tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py

# Large Python diff (class refactoring)
./ad_vim tests/tests/examples/02_large_python/old.py tests/tests/examples/02_large_python/new.py

# JSON config update
./ad_vim tests/tests/examples/03_json_config/old.json tests/tests/examples/03_json_config/new.json

# Shell script improvement
./ad_vim tests/tests/examples/04_shell_script/old.sh tests/tests/examples/04_shell_script/new.sh

# Go code expansion
./ad_vim tests/tests/examples/05_go_code/old.go tests/tests/examples/05_go_code/new.go

# TypeScript interface growth
./ad_vim tests/tests/examples/06_typescript/old.ts tests/tests/examples/06_typescript/new.ts

# Text prose rewrite
./ad_vim tests/tests/examples/07_text_prose/old.txt tests/tests/examples/07_text_prose/new.txt
```

## Common Options

```bash
# Slow down for a presentation
./ad_vim --speed 0.5 old.py new.py

# Center cursor during animation
./ad_vim --scroll zz old.py new.py

# Type short words instantly
./ad_vim --max-word-chars 5 old.py new.py

# Write result to file and quit
./ad_vim --output result.py old.py new.py

# Replay git history
./ad_vim --replay src/main.py
```

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
