# Session Handoff — 2026-08-18 (updated after Phase A–C refactor)

## Context for the next session

This document is for the next AI session working on diffvim/gitanim.
The previous session was long and the AI's capacity may have been
reduced. Read this first.

> **Refactor outcome (Phases A–C).** The codebase was simplified:
> only one compute implementation remains (`compute/cpp/`),
> the postprocess/pace/animator stages exist in C and Perl only (Go is
> gone), the `--tool` flag was removed, and `--algorithm` accepts only
> `lcs|patience` (Myers dropped). The timed op stream was upgraded to
> v2 (TSV, per-op `(line, col)`); cursor positioning now lives in
> postprocess, not pace. The Perl `compute/perl/compute_builtin.pl`
> wrapper was added as the fallback for `diffvim-pipeline`.

## What diffvim IS

diffvim animates a code diff (old file → new file) as if a human were
typing it. The user wants the animation to feel NATURAL — not a
mechanical application of diff ops. This is the key design principle
that the previous session lost sight of.

## The pipeline (4 stages)

```
compute → postprocess → pace → animate
```

1. **compute**: line diff (LCS or Patience) produces char-level ops.
   One implementation: C++ (`compute/bin/diffvim-compute-cpp`). If
   the C++ binary is missing, `diffvim` falls back to the embedded
   vimscript LCS, and `diffvim-pipeline` falls back to
   `compute/perl/compute_builtin.pl`.
2. **postprocess**: reorders/transforms ops to look natural, and owns
   per-op `(line, col)` positioning so the animator is scroll-safe.
   THIS IS WHERE THE GHOST-LINE FIX BELONGS.
3. **pace**: adds timing, delays, batch operations. Positioning is
   passed through untouched — pace only owns delays and batching now.
4. **animate**: applies ops to a virtual buffer. Each op carries its
   own `(line, col)`, so the animator has no `glide` handler — it
   just sets the cursor before applying each op.

Read `docs/PIPELINE.md` for full details.

## THE GHOST LINE PROBLEM — STILL UNRESOLVED (Phase F)

This is the #1 outstanding issue. When the diff produces:
```
keep "foo"
delete \n
keep "bar"
```
(joining two lines into "foobar"), the animator mechanically joins the
lines. Visually, "bar" jumps up onto the "foo" line — this looks bad.

**The fix belongs in POSTPROCESS, not in the animator.**

The previous session tried to fix it in the animator (DeleteNewlineAtCursor)
by NOT joining — just moving the cursor to the next line. This BROKE
mixed delete+insert sequences (07_text_prose and all large files)
because the buffer retained extra `\n`s, causing subsequent inserts to
land on wrong lines.

**What the postprocessor should do** (NOT YET IMPLEMENTED — Phase F):

Detect the pattern `keep X, delete \n, keep Y` (a join) and transform
it into a sequence that animates naturally. Options:

- **Option A**: Split into delete+insert. Transform `keep "foo",
  delete \n, keep "bar"` into `keep "foo\n", delete "bar", insert
  "bar"`. The `\n` stays with the keep, and the second line is deleted
  then re-inserted in place. Visually: "bar" disappears and reappears
  on the same line.

- **Option B**: Reorder ops so all char deletes on a line happen
  before the `\n` delete. Then the `\n` delete uses the "remove empty
  line" path (the line is already empty by then).

The postprocessor is in `animator/perl/postprocess.pl` (also a C
version in `animator/c/postprocess.c`). Read it to understand current
transformations.

## What WORKS right now

- diffvim-pipeline (C animator): **42/42 examples pass** MD5
  verification. Use `--speed 1000` for testing (makes delays ≈0).
- diffvim (vimscript, synchronous test mode): 32/42 pass (10 are
  large-file timeouts, not correctness issues).
- Cross-language parity: the C++ compute tool, plus C and Perl
  postprocess/pace, produce identical output.

## Key commands

```bash
# Run MD5 verification on all 42 examples
cd /home/z/my-project/gitanim && bash scripts/verify_md5.sh

# Run vim correctness test (tests 01-34, then hangs on large files)
cd /home/z/my-project/gitanim && perl tests/test_vim_correctness.pl

# Test a single file with the pipeline
cd /home/z/my-project/gitanim
animator/diffvim-pipeline --no-display --speed 1000 --snapshot /tmp/out.txt \
    examples/02_large_python/old.py examples/02_large_python/new.py
md5sum /tmp/out.txt examples/02_large_python/new.py

# Rebuild the C++ compute tool
make -C compute cpp

# Rebuild C animator
make -C animator/c all
```

## Algorithm timing (15K-line synthetic file)

| Algorithm | C++ (ms) | Notes |
|-----------|----------|-------|
| LCS       | 1585     | Default, works |
| Patience  | 1687     | Works, similar to LCS |

LCS and Patience produce identical op counts. Myers was dropped during
the Phase A refactor — it OOMs on 15K-line files and produced the same
op count as LCS.

## Git state

- Branch: `main`, all changes pushed
- Last commit before refactor: `410cfdb` (revert ghost-line experiment
  — was an empty commit, only rebuilt C binary)
- The WORKING code is the always-join behavior from commit `d79258c`

## What NOT to do

1. **Do NOT try to fix ghost-line in the animator.** The animator must
   mechanically apply what it's given. Fix it in postprocess.

2. **Do NOT use `--speed 0.05`** — that's SLOWER (delay = delay_ms /
   speed, so 0.05 multiplies delays by 20). Use `--speed 1000` for
   fast testing.

3. **Do NOT run `perl scripts/verify_md5.pl`** — it's the old
   sequential version, takes 30+ minutes. Use `bash scripts/verify_md5.sh`
   (parallel, 8 concurrent, ~2 minutes total).

4. **Do NOT commit empty commits.** If the source files end up identical
   to HEAD, there's nothing to commit.

5. **Do NOT reintroduce `--tool` or `--algorithm myers`.** They were
   removed in Phase A/B deliberately — see the [Unreleased] entry in
   `CHANGELOG.md` for the rationale.

## File locations

```
gitanim/
├── diffvim                  # main tool (bash + vimscript)
├── compute/
│   ├── cpp/                 # C++ compute source (only compute impl)
│   ├── perl/                # Pure-Perl fallback wrapper
│   └── bin/diffvim-compute-cpp
├── animator/
│   ├── bin/                 # compiled binaries (C only)
│   ├── perl/                # Perl source (animator.pl, pace.pl, postprocess.pl)
│   ├── c/                   # C source (animator.c, pace.c, postprocess.c)
│   └── diffvim-pipeline     # runs all 4 stages (C-preferred, Perl fallback)
├── examples/                # 42 file pairs for testing
├── tests/                   # vimscript engine tests
├── scripts/verify_md5.sh   # MD5 verification script
└── docs/PIPELINE.md        # pipeline architecture document
```

## User expectations

The user is frustrated with the previous session. Key points:
- The user knows what they want — implement what they say, don't second-guess
- The user wants the postprocess layer to transform ops for natural animation
- The user wants the changelog updated regularly
- The user wants documentation kept current
- Don't speculate about failures you can't reproduce — verify everything
