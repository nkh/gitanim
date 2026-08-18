# Session Handoff — 2026-08-18

## Context for the next session

This document is for the next AI session working on diffvim/gitanim.
The previous session was long and the AI's capacity may have been
reduced. Read this first.

## What diffvim IS

diffvim animates a code diff (old file → new file) as if a human were
typing it. The user wants the animation to feel NATURAL — not a
mechanical application of diff ops. This is the key design principle
that the previous session lost sight of.

## The pipeline (4 stages)

```
compute → postprocess → pace → animate
```

1. **compute**: diff algorithm (LCS/Myers/Patience) produces char-level
   ops. 4 implementations: C, C++, Rust, Go.
2. **postprocess**: reorders/transforms ops to look natural. THIS IS
   WHERE THE GHOST-LINE FIX BELONGS.
3. **pace**: adds timing, delays, batch operations. Tracks line_offset
   for correct cursor targeting.
4. **animate**: applies ops to a virtual buffer, renders to terminal.

Read `docs/PIPELINE.md` for full details.

## THE GHOST LINE PROBLEM — UNRESOLVED

This is the #1 issue. When the diff produces:
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

**What the postprocessor should do** (NOT YET IMPLEMENTED):

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

The postprocessor is in `animator/perl/postprocess.pl` (also C and Go
versions). Read it to understand current transformations.

## What WORKS right now

- diffvim-pipeline (Go animator): **42/42 examples pass** MD5
  verification. Use `--speed 1000` for testing (makes delays ≈0).
- diffvim (vimscript, synchronous test mode): 32/42 pass (10 are
  large-file timeouts, not correctness issues).
- Cross-language parity: all 4 compute tools, all 3 postprocess/pace
  tools produce identical output.

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

# Rebuild Go animator (Go is at /home/z/go/bin/go)
export PATH=/home/z/go/bin:$PATH GOROOT=/home/z/go GOPATH=/home/z/gopath
cd animator/go && go build -o ../bin/diffvim-animator animator.go

# Rebuild C animator
cd animator/c && cc -O2 -o ../bin/diffvim-animator-c animator.c
```

## Algorithm timing (15K-line synthetic file)

| Algorithm | C (ms) | C++ (ms) | Rust (ms) | Go (ms) | Notes |
|-----------|--------|----------|-----------|---------|-------|
| LCS       | 1679   | 1585     | 4797      | 2758    | Default, works |
| Myers     | KILLED | KILLED   | KILLED    | KILLED  | OOM on 15K lines |
| Patience  | 2307   | 1687     | 5332      | 3024    | Works, similar to LCS |

LCS and Patience produce identical op counts. Myers is slower and
OOM-prone. **Consider dropping Myers** or replacing with linear-space
variant.

## Git state

- Branch: `main`, all changes pushed
- Last commit: `410cfdb` (revert ghost-line experiment — was an empty
  commit, only rebuilt C binary)
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

## File locations

```
gitanim/
├── diffvim                  # main tool (bash + vimscript)
├── compute/bin/             # 4 diff compute tools
├── animator/
│   ├── bin/                 # compiled binaries
│   ├── go/                  # Go source (animator.go, pace.go, postprocess.go)
│   ├── perl/                # Perl source
│   ├── c/                   # C source
│   └── diffvim-pipeline     # runs all 4 stages
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
