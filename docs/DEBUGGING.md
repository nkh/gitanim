# Debugging the diffvim pipeline

This document explains how to debug the diffvim pipeline. It covers:
- What each stage produces
- How to run stages separately
- What to look for in each stage's output
- How to use the minimal test cases
- Common errors and their causes

## TL;DR — the one command you need

```bash
bash scripts/dv_debug.sh <oldfile> <newfile>
```

This runs all 4 stages, prints a summary to stdout, AND writes the
stage files to `/tmp/dv_debug/` so you can inspect them:

```
/tmp/dv_debug/raw.txt    ← Stage 1: compute output (raw char ops)
/tmp/dv_debug/post.txt   ← Stage 2: postprocess output (per-op positions)
/tmp/dv_debug/timed.txt  ← Stage 3: pace output (delays added)
/tmp/dv_debug/snap.txt   ← Stage 4: animator final buffer
```

## The pipeline

```
                  ┌─────────────┐     ┌──────────────┐     ┌─────────┐     ┌───────────┐
<old> <new> ──→   │  compute    │ ──→ │  postprocess │ ──→ │  pace   │ ──→ │  animator │
                  └─────────────┘     └──────────────┘     └─────────┘     └───────────┘
                  diffvim-compute-cpp diffvim-postprocess diffvim-pace   diffvim-animator-c
                                       (or postprocess.pl) (or pace.pl)   (or animator.pl)
                                                                                   │
                                                                                   ↓
                                                                              terminal animation
                                                                              (or --snapshot FILE)
```

Each stage reads from stdin and writes to stdout. Each stage has a
**specific job** — see [POSTPROCESS_TRANSFORMS.md](POSTPROCESS_TRANSFORMS.md)
for details on what the postprocess does.

## Running stages separately

### Stage 1: compute (diffvim-compute-cpp)

Produces raw char-level ops from the diff between old and new files.

```bash
./compute/bin/diffvim-compute-cpp old.txt new.txt raw.txt

# Or to stdout:
./compute/bin/diffvim-compute-cpp old.txt new.txt /dev/stdout
```

**Output format (v2 TSV):**
```
# diffvim raw diff v2
# algorithm patience
# hunk_count N
HUNK    <target>        <del>   <ins>   <end_ins>       <end_del>
keep    <line>  <col>   <code>  <char_repr>
delete  <line>  <col>   <code>  <char_repr>
insert  <line>  <col>   <code>  <char_repr>
HUNK_END
```

**What to check:**
- `hunk_count` matches the number of `HUNK`/`HUNK_END` pairs
- Each hunk's target line is correct (line in old file where the hunk starts)
- The first column of every op line is `keep`, `delete`, or `insert` (no `op` prefix)
- Tabs (`\t`) separate every field, not spaces

**Common errors:**
- `# diffvim precomputed diff v1` → your binary is stale. Rebuild: `make -C compute clean && make -C compute`
- `HUNK 1 1 1 0 0` (spaces, not tabs) → same — v1 format, rebuild

### Stage 2: postprocess (diffvim-postprocess)

Reads raw ops, reorders them, computes per-op (line, col) positions.

```bash
./animator/bin/diffvim-postprocess < raw.txt > post.txt

# With transforms:
./animator/bin/diffvim-postprocess --semantic-cleanup --indent-aware < raw.txt > post.txt
```

**Output format (v2 TSV):**
```
# diffvim post-processed v2
HUNK    <target>        <del>   <ins>   <end_ins>       <end_del>
keep    <line>  <col>   <code>  <char_repr>
delete  <line>  <col>   <code>  <char_repr>
insert  <line>  <col>   <code>  <char_repr>
HUNK_END
```

**What to check:**
- Hunk count matches Stage 1
- Within each line group, deletes come before inserts
- `\n` deletes (code 10) come LAST in their line group
- See [POSTPROCESS_TRANSFORMS.md](POSTPROCESS_TRANSFORMS.md) for the full list of transformations

**Common errors:**
- `ERROR: input is v1 format` → your compute binary is stale. Rebuild.
- `WARNING: no hunks and no ops parsed` → input was empty or wrong format. Check Stage 1 output.

### Stage 3: pace (diffvim-pace)

Reads post-processed ops, inserts delays between them. **Does NOT
modify, reorder, or add ops.** Only inserts `delay` lines.

```bash
./animator/bin/diffvim-pace < post.txt > timed.txt

# With options:
./animator/bin/diffvim-pace --delete-pacing word --insert-pacing char < post.txt > timed.txt
```

**Output format (v2 TSV):**
```
# diffvim timed ops v2
# delete_pacing word
# insert_pacing char
HUNK    <target>        <del>   <ins>   <end_ins>       <end_del>
keep    <line>  <col>   <code>  <char_repr>
delay   1       char
delete  <line>  <col>   <code>  <char_repr>
delay   40      char
...
HUNK_END
delay   250     hunk
HUNK    ...
```

**What to check:**
- Same op count as Stage 2 (pace only adds `delay` lines)
- Delay types: `char`, `word`, `hunk`, `awd_slow`, `awd_fast`, `awd_skip`
- `delay\t<ms>\t<type>` — ms comes FIRST, type SECOND (v1 had them reversed)

**Common errors:**
- `ERROR: input has 'op\t<type>...' prefix` → input is v1 format. Check Stage 2.
- `WARNING: no ops read from input` → Stage 2 produced no output. Check that.

### Stage 4: animator (diffvim-animator-c)

Reads timed ops, animates the transformation in the terminal.

```bash
# Animate (uses TTY):
./animator/bin/diffvim-animator-c old.txt < timed.txt

# Snapshot only (no animation, for testing):
./animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot out.txt old.txt < timed.txt
```

**Keyboard controls (during animation):**
- `q` / `Esc` / `Ctrl-C` — stop
- `Space` / `p` — pause / resume
- `n` — skip to next hunk
- `+` — speed up (x1.5)
- `-` — slow down (x0.67)
- `=` — reset speed to 1.0
- `?` / `h` — show help

**Common errors:**
- `ERROR: timed stream uses v1 'op\t<type>...' prefix` → input is v1 format
- `WARNING: no ops were applied` → timed stream was empty. Check Stage 3.

## The dv_debug.sh script

Run `bash scripts/dv_debug.sh <old> <new>` to get a full breakdown:

```
══════════════════════════════════════════════════════════════
 diffvim pipeline debugger
══════════════════════════════════════════════════════════════

─── INPUT FILES ──────────────────────────────────────────────
OLD: old
     1  1234 67890
     2  abc
     ...

─── STAGE 1: RAW DIFF OPS (compute) ──────────────────────────
compute: 0.34 ms (read 0.06 + diff 0.01 + write 0.25)
...
  → 27 lines written to /tmp/dv_debug/raw.txt
  → Header: # diffvim raw diff v2

─── STAGE 2: POST-PROCESSED OPS (postprocess) ───────────────
  → 24 lines written to /tmp/dv_debug/post.txt
...

─── STAGE 3: TIMED OPS (pace) ───────────────────────────────
  → 50 lines written to /tmp/dv_debug/timed.txt
...

─── STAGE 4: ANIMATOR RESULT ────────────────────────────────

─── RESULT COMPARISON ────────────────────────────────────────
Expected (new file):
     1  1234
...
Actual (animator output):
     1  1234
...

✓ MATCH — animator output matches new file
```

The stage files are kept in `/tmp/dv_debug/` so you can inspect them
with `less`, `cat -A`, `wc -l`, `diff`, etc.

## Useful commands for inspecting stage files

```bash
# View with tabs visible (tabs shown as ^I):
cat -A /tmp/dv_debug/post.txt | head -20

# View with line numbers and tabs as visible chars:
less -S /tmp/dv_debug/post.txt
# (less -S prevents wrapping, type :n to switch files)

# Count lines per stage:
wc -l /tmp/dv_debug/*.txt

# Show just the HUNK headers:
grep '^HUNK' /tmp/dv_debug/post.txt

# Show just the deletes:
grep '^delete' /tmp/dv_debug/post.txt

# Show the \n deletes specifically:
grep '^delete.* 10      ' /tmp/dv_debug/post.txt

# Compare final output with expected:
diff /tmp/dv_debug/snap.txt new.txt

# View the timed ops with delay types highlighted:
grep -E '^(delay|HUNK|HUNK_END)' /tmp/dv_debug/timed.txt
```

## Running the Perl pipeline (instead of C)

If you suspect a C-specific bug, run the same case through the Perl
pipeline. If both produce the same output, the bug is in the compute
or in the format spec; if they differ, the bug is in one of them.

```bash
# Pure Perl pipeline:
perl compute/perl/compute_builtin.pl old new /tmp/raw.txt
perl animator/perl/postprocess.pl < /tmp/raw.txt > /tmp/post.txt
perl animator/perl/pace.pl < /tmp/post.txt > /tmp/timed.txt
perl animator/perl/animator.pl --no-display --speed 1000 --snapshot /tmp/out.txt old < /tmp/timed.txt
diff /tmp/out.txt new
```

## Running the vimscript animator

The `./diffvim old new` launcher uses the vimscript animator. To
test it headless (no vim window), use:

```bash
bash tests/test_vimscript_animator.sh examples/01_small_python
```

This extracts the vimscript engine, patches it to be synchronous
(no timers), runs it in `vim -e -s -n` headless mode, and compares
the output.

## The minimal test cases

`tests/minimal/` contains 25 small `old` + `new` pairs that each
test ONE specific transformation. Run them all:

```bash
bash tests/run_minimal_tests.sh
```

Output:
```
01_simple_replace              PASS  (raw:   23 lines, post:   22 lines)
02_simple_insert               PASS  (raw:   23 lines, post:   22 lines)
...
25_complex_mix                 PASS  (raw:   49 lines, post:   48 lines)

=== Results: 25 passed, 0 failed ===
```

If a case fails, the script prints the expected output, the actual
output, and the first 5 lines of each stage so you can see where
it diverged.

Run a single case:
```bash
bash tests/run_minimal_tests.sh 11_delete_last_line
```

Debug a single case with the full debugger:
```bash
bash scripts/dv_debug.sh tests/minimal/11_delete_last_line/old \
                          tests/minimal/11_delete_last_line/new
```

## What to look for in the post-processed output

The `post.txt` file is the most important stage to debug. It shows
what the animator will actually do. See
[POSTPROCESS_TRANSFORMS.md](POSTPROCESS_TRANSFORMS.md) for the full
list of transformations and what to look for.

The key sanity checks:

1. **Each op carries (line, col)** — keep/insert advance col, delete doesn't
2. **Deletes come before inserts** within each line group
3. **\n deletes come LAST** in their line group (content first, then \n)
4. **End-delete hunks** redirect the `\n delete` to `(line-1, 1)` because
   there's no next line to join with

## Common symptoms and their causes

### "Animation complete but no animation"

The timed stream is empty. Check:
```bash
wc -l /tmp/dv_debug/timed.txt
head -5 /tmp/dv_debug/timed.txt
```

If empty, work backwards: check `post.txt`, then `raw.txt`. The
compute binary is probably stale (v1 format) — the postprocess
parses 0 hunks from v1 input.

### "The animation looks really bad" (visual artifacts)

This is usually a problem in the **postprocess** — the ops are
correct but they're in an order that produces bad visuals. Check:
- Are deletes coming before inserts within each line?
- Are `\n` deletes coming after content deletes?

See [POSTPROCESS_TRANSFORMS.md](POSTPROCESS_TRANSFORMS.md) for
what each transformation should look like.

### "diffvim (the launcher) shows wrong output"

The diffvim launcher uses the vimscript animator, which has its
own snapshot writer. Check:
```bash
bash tests/test_vimscript_animator.sh examples/<name>
```

If that passes but the launcher doesn't, the issue is in the
launcher's pipeline setup, not the animator.

### "MD5 mismatch on large files"

Run the specific case through dv_debug.sh and look at the diff:
```bash
bash scripts/dv_debug.sh examples/34_large_javascript/old.js \
                          examples/34_large_javascript/new.js 2>&1 | tail -30
```

The diff at the end shows the exact mismatch.

## If you find a bug

1. Reproduce it with a minimal test case (copy it to `tests/minimal/`)
2. Run `bash scripts/dv_debug.sh <old> <new>` and save the output
3. Identify which stage produces wrong output
4. File an issue with: the old/new files, the dv_debug.sh output,
   and the specific stage that's wrong

## Rebuilding after a `git pull`

The compute binary is gitignored (it's a compiled C++ binary). After
a `git pull`, you must rebuild:

```bash
make -C compute clean && make -C compute
# Animator binaries are tracked in git, but if you modify C source:
cc -O2 -o animator/bin/diffvim-animator-c animator/c/animator.c
cc -O2 -o animator/bin/diffvim-postprocess animator/c/postprocess.c
cc -O2 -o animator/bin/diffvim-pace animator/c/pace.c
```

If you see `# diffvim precomputed diff v1` in Stage 1 output, your
binary is stale.
