# Session Handoff — 2026-08-19

## Context for the next session

This document is for the next AI session working on diffvim/gitanim.
The project has undergone a major refactor. Read this first.

## What diffvim IS

diffvim animates a code diff (old file → new file) as if a human were
typing it. The pipeline is: compute → postprocess → pace → animate.
All four stages are external executables. The vimscript engine only
handles the animate stage.

## Current Architecture

```
compute (C++ Patience diff) → postprocess (C/Perl) → pace (C/Perl) → animate (C/Perl/vimscript)
```

- **Compute**: `ad_compute` — Patience diff (the only algorithm;
  LCS and Myers were removed)
- **Postprocess**: `ad_postprocess` — op reordering + per-op (line,col)
  positioning. Supports `--transform NAME` flags and `--stream` mode.
- **Pace**: `ad_layer_pace` — timing + batching. Emits typed delays
  (`delay\t<type>\t<ms>`). Does NOT modify ops.
- **Animate**: `ad` (C) or `diffvim` (vimscript) — reads
  the timed op stream and renders. Incremental rendering (no flashing).

## What WORKS right now

- **42/42 examples pass** MD5 round-trip verification with the C animator
- 96 Perl tests pass
- Cross-language parity (C == Perl) for postprocess and pace
- No flashing (incremental rendering in both animators)
- Syntax coloring via `diffvim-colorize` (vim/pygmentize backends, runs
  in parallel with the pipeline)
- `--stream` mode in postprocess (true Unix pipes)
- `--transform NAME` flags in postprocess (composable transformations)
- Typed delays (11 types: type, keep, delete, hunk_pause, etc.)
- diffvim uses the external pipeline (old vimscript code removed, ~2800
  lines deleted, launcher is now ~1800 lines)

## What NOT to do

1. **Do NOT reintroduce LCS or Myers.** Patience is the only algorithm.
2. **Do NOT reintroduce `--tool`.** The C++ compute tool is the default.
3. **Do NOT use `redraw!`** in the vimscript animator — it causes flashing.
   Use `redraw` (incremental) and only render at delay boundaries.
4. **Do NOT use `\033[2J`** (clear screen) in the C animator — use
   per-line clear (`\033[<line>;1H\033[2K`) and only redraw changed lines.
5. **Do NOT allocate fixed-size arrays that don't grow.** The
   `line_modified` array caused a heap-buffer-overflow that corrupted
   large-file output. Always use `ensure_*_capacity()` patterns.

## Key commands

```bash
# Run MD5 verification on all 42 examples (~2 min)
bash tests/verify_md5.sh

# Test a single file
./animator/ad_pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py
md5sum /tmp/out.txt tests/tests/examples/01_small_python/new.py

# Run Perl tests
perl animator/tests/test_all_animators.pl
perl animator/tests/test_cross_language.pl
perl animator/tests/test_newline_fix.pl
perl animator/tests/test_roundtrip.pl
perl animator/tests/test_roundtrip_verify.pl

# Run pipeline stages manually
./bin/ad_compute old.py new.py /tmp/raw.txt
./bin/ad_postprocess < /tmp/raw.txt > /tmp/post.txt
./bin/ad_layer_pace < /tmp/post.txt > /tmp/timed.txt
./bin/ad --no-display --speed 1000 --snapshot /tmp/out.txt old.py < /tmp/timed.txt

# Test streaming mode
./bin/ad_postprocess --stream < /tmp/raw.txt | \
  ./bin/ad_layer_pace | \
  ./bin/ad --no-display --speed 1000 --snapshot /tmp/out.txt old.py

# Use AddressSanitizer to find memory bugs
cc -O0 -g -fsanitize=address -o /tmp/anim_asan animator/c/ad.c
/tmp/anim_asan --no-display --speed 1000 --snapshot /tmp/out.txt old.py < /tmp/timed.txt
```

## Key documents

- `docs/PIPELINE.md` — pipeline architecture reference
- `docs/DEVELOPER_GUIDE.md` — comprehensive developer/onboarding guide
- `docs/ARCHITECTURE_ANALYSIS.md` — architecture analysis (historical)
- `CHANGELOG.md` — full change history

## Git state

- Branch: `main`
- The old in-vim compute/postprocess/pace code was removed (~2800 lines)
- The vimscript engine is now a ~200-line timed-op-stream reader
