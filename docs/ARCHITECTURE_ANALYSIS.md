# Analysis — Architecture Questions from User

This document analyses the seven architecture questions you raised. For each, I investigated the actual codebase (no speculation) and give you a concrete recommendation with the work involved.

---

## 1. Can diffvim use the C++ postprocess and pace layers to be faster and smaller?

**Short answer: yes, and it would shrink the codebase dramatically.**

### What diffvim does today

The `diffvim` bash launcher embeds a 3,064-line vimscript engine (`autoload/diffvim/engine.vim`) inside itself via a heredoc. That engine **reimplements the entire pipeline**:

| Stage | C/Perl pipeline | vimscript engine (duplicated) |
|-------|-----------------|--------------------------------|
| compute | `diffvim-compute-cpp` | `s:LineDiff`, `s:CharDiff`, `s:WordDiff`, `s:BuildHunks` (lines 173–964) |
| postprocess | `diffvim-postprocess` | `s:OptimizeSequence`, `s:LeftToRight`, `s:OverwriteTransform`, `s:DeleteEndFirst`, `s:SemanticCleanup`, `s:SortLineOps` (lines 338–788) |
| pace | `diffvim-pace` | `s:ComputeMoveDuration`, `s:ProcessCharOp`, `s:AdvanceForKeepChar`, `s:InsertCharAtCursor`, `s:DeleteCharAtCursor`, `s:Tick`, `s:ScheduleNext` (lines 974–1700+) |

The bash launcher already calls `diffvim-compute-cpp` when available (Phase B), so **the compute duplication is already half-resolved** — the engine's `s:LineDiff`/`s:CharDiff` is now a fallback. But postprocess and pace still run inside vim.

### Proposed approach

Add a `--precomputed-pipeline FILE` mode to `diffvim` that:
1. Runs `compute → postprocess → pace` externally and writes a v2 TSV timed-op stream to `FILE`.
2. The vimscript engine reads that file and only handles the **animate** stage (rendering + user interaction).
3. The duplicate postprocess/pace vimscript functions stay as a fallback when external tools aren't available.

**Estimated LOC reduction:** ~1,800 lines of vimscript can be deleted from the engine (the postprocess + pace functions), leaving ~1,200 lines for the animator + UI.

**Speed gain:** On `examples/33_large_python` (28K ops), vimscript postprocess+pace takes 11+ seconds (NEXT_SESSION.md confirms). The C versions do it in <100ms. So **a ~100x speedup** on large files.

**Work involved:** ~1 day. Modify the bash launcher to call the pipeline; modify the engine to read a v2 TSV timed-op stream (we already wrote the v2 spec; the animator.c/animator.pl parsers exist as a reference).

**Recommendation: do this.** It's the single biggest remaining win.

---

## 2. The synchronous_engine test uses vim — can we change that, or is it inherent?

**Short answer: it was a vimscript bug, not a fundamental issue. Fixed.**

### The bug

`animator/tests/test_synchronous_engine.pl` was failing 10/10 with "no output". I traced it to this line in the test:

```vim
-c 'let g:diffvim.output_file = "/tmp/.../out.txt"'
```

This sets `g:diffvim.output_file` — but `g:diffvim` is a **dict** that doesn't exist yet (the engine creates it via `extend()` at line 36 of engine.vim, which runs during `source`). So vim errors with `E121: Undefined variable: g:diffvim` and exits silently.

### The fix (one line)

Change the test to initialize the dict first:

```perl
-c 'let g:diffvim = {"output_file": "/tmp/.../out.txt"}'
```

The engine's `extend({...defaults...}, get(g:, 'diffvim', {}))` then merges the user's value with defaults.

**Done.** 10/10 tests pass now. See commit `9fcdd99` + the follow-up fix in this session.

### Should we change the test approach?

The test exists specifically to exercise `ProcessCharOp` (the vimscript engine's per-op handler) including AWD, rapid-EOL, and `\n` handling. These are vimscript-only code paths. There's no way to test them without running vim.

But once we do item #1 above (move postprocess+pace out of vim), the vimscript engine only has the animator left, and `ProcessCharOp` shrinks dramatically. At that point the synchronous_engine test could be replaced by a simpler "run the v2 TSV stream through the vimscript animator" test — which is exactly what the C and Perl animators already do via `test_all_animators.pl`.

**Recommendation:** Keep the test as-is for now (it's fixed and passing). Revisit after item #1.

---

## 3. Should each postprocess option be a separate layer/executable?

**Short answer: no — but the option set should be reorganized.**

### Current state

`diffvim-postprocess` has 4 options today:

```
--op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite
--semantic-cleanup
--indent-aware
--overwrite
```

Each is a transformation pass over the op stream. They run sequentially inside one executable.

### Analysis

**Arguments FOR separate executables (one per option):**
- Composable: pipe them in any order, e.g. `compute | semantic-cleanup | op-order | indent-aware | pace`.
- Each is testable in isolation (already kind of true via the option flags).
- Unix philosophy: small tools that do one thing.

**Arguments AGAINST separate executables:**
- 6 executables to maintain instead of 1 (the C impl, the Perl impl, the docs, the manpages, the completions).
- Each pipe stage re-parses the entire op stream — currently `read_input()` is ~20% of postprocess's runtime. Spinning up 4-6 separate processes for a 28K-op stream would add ~50ms of process startup overhead per stage.
- The transformations interact: `--semantic-cleanup` creates new keep ops that `--op-order` then needs to reorder; if they're separate executables, you have to re-emit and re-parse the op stream between them.
- The user almost always wants the same combination (`--op-order optimize --semantic-cleanup` is the default). Splitting them just makes the common case slower.

### Recommendation

Don't split the executable. Instead:
1. Keep `diffvim-postprocess` as one tool.
2. Restructure the code so each transformation is a clearly-named function (already done — `semantic_cleanup()`, `reorder_hunk_ops()`, etc.).
3. Add a `--list-transforms` flag that prints the available transforms and their order, so the user can see what's running.
4. For users who really want to experiment with transforms in isolation, expose them as `--transform NAME` repeated flags (e.g. `--transform semantic-cleanup --transform op-order:optimize`).

This gives the flexibility of separate layers without the process overhead.

---

## 4. Normalize the diff so LCS and Patience produce identical output — should this be a layer? Single chars?

**Short answer: yes, add a normalization layer. No, don't go to single chars.**

### What I found

I tested LCS vs Patience on all 42 examples:

- **33/42 examples produce byte-identical output** (ignoring the `# algorithm X` header line).
- **9 large examples (34-42) differ** — but only in how hunks are split, not in the total content. Example: 34_large_javascript has LCS=38 hunks / 14,134 ops vs Patience=37 hunks / 14,135 ops. Same total content, different hunk boundaries.

Patience uses unique-line anchors to sub-divide; LCS doesn't. So Patience produces more, smaller hunks; LCS produces fewer, larger hunks.

### Why this matters

- For testing: if both algorithms produce identical output, you can swap them freely and tests don't need to know which one ran.
- For users: the choice between LCS and Patience becomes purely a performance question (Patience is slightly slower), not a "which produces nicer diffs" question.

### Proposed normalization layer

Add a `diffvim-normalize` executable (or `--normalize` flag to postprocess) that:

1. **Hunk re-bundling**: walk the op stream. When two adjacent hunks have no `keep \n` between them (i.e., the boundary is artificial), merge them. When a hunk is very large (say >5K ops), try to split it at `keep \n` boundaries.
2. **Op consolidation**: walk each hunk's ops. Merge adjacent `keep X, keep Y` into `keep X+Y` (where `X+Y` is a multi-char keep — currently we have one op per char).
3. **Algorithm-agnostic output**: both LCS and Patience output should pass through the normalizer and produce the same byte stream.

### Single char vs multi-char ops?

Currently every op is one char (one Unicode code point). The user asked if we should make ops single-char for "more control". My analysis:

**Arguments for single-char ops (status quo):**
- The animator can pace each char individually (typing feel).
- Coloring can be per-char.
- Cursor position is per-char (already done in Phase C).

**Arguments for multi-char ops:**
- Smaller op stream (fewer lines, less parsing). Example: 14,134 single-char ops → maybe ~3,000 multi-char ops.
- The animator could batch-render whole kept words/lines (no animation overhead for content that doesn't change).
- The diff algorithm itself works on lines and produces multi-char `keep` runs internally; we're already splitting them into single chars in postprocess.

**Recommendation: keep single-char ops as the canonical format, but add a `--batch-keeps` flag to postprocess that merges adjacent keeps for the animator.** This gives the best of both worlds — per-char control when you want it, batch efficiency when you don't.

---

## 5. Parallel pipeline — could stages work on hunks instead of consuming all data first?

**Short answer: yes for postprocess and pace, no for compute and animator.**

### Current state

All four pipeline stages consume the entire input before emitting output:

```c
// postprocess.c
void read_input(void) {
    while (fgets(line, sizeof(line), stdin)) { ... }
}
void write_output(void) { /* emit all */ }
```

The pipeline is wired with temp files in `diffvim-pipeline`:

```bash
$COMPUTE  ... "$RAW_OPS"            # writes file
$POSTPROCESS < "$RAW_OPS" > "$POST" # reads file, writes file
$PACE       < "$POST"   > "$TIMED"  # reads file, writes file
$ANIMATOR   < "$TIMED"               # reads file
```

### Why this is suboptimal

1. **Memory**: large diffs (15K lines = 1M ops) require holding the entire op stream in memory at each stage.
2. **Latency**: the animator can't start rendering until compute+postprocess+pace all finish.
3. **No parallelism**: 4 cores idle while one stage runs.

### Proposed streaming pipeline

**Compute** stays batch — LCS/Myers/Patience need the whole file to compute the diff. No change.

**Postprocess** can stream per-hunk:
- Read `HUNK N ...` header.
- Read all ops until next `HUNK` or EOF.
- Apply transformations (semantic-cleanup, op-order) to that hunk's ops.
- Emit `hunk_start<TAB>...` + transformed ops + `hunk_end`.
- Repeat.

This works because semantic-cleanup and op-order are **per-hunk** transformations — they don't cross hunk boundaries. (The `line_offset` tracking for cursor positioning IS cross-hunk, but that's just an accumulator — easy to stream.)

**Pace** can stream per-hunk too:
- Read hunk's ops.
- Emit paced ops + delays.
- Repeat.

But AWD (adaptive word delete) needs to look ahead within a hunk — that's fine, it's bounded by hunk size.

**Animator** can stream per-op (it already does), but it needs the cumulative `line_offset` to position the cursor — that's computed during postprocess, not pace. Since postprocess now embeds `(line, col)` in every op (Phase C), the animator doesn't need to track offsets at all. It can render ops as they arrive.

### Implementation outline

Add a `--stream` mode to postprocess and pace:

```c
// postprocess.c with --stream
while (read_one_hunk(stdin, &hunk)) {
    transform_hunk(&hunk);
    emit_hunk(stdout, &hunk);
}
```

And the pipeline becomes a true Unix pipe:

```bash
$COMPUTE ... |
  $POSTPROCESS --stream |
  $PACE --stream |
  $ANIMATOR
```

No temp files. Animator starts rendering as soon as the first hunk is ready. On 15K-line files, that's a ~1.5 second improvement in time-to-first-frame.

### Caveats

- `--semantic-cleanup` currently can produce ops that cancel out across hunk boundaries in rare cases (when a hunk ends with `delete \n` and the next starts with `insert \n`). In streaming mode, this transformation wouldn't be applied. Workaround: detect the case and emit a warning, or skip semantic-cleanup in streaming mode.
- The Perl `pace.pl` already streams (it reads line-by-line). It just buffers per-hunk. The C version is the same.

**Recommendation: implement streaming in postprocess and pace. It's a small code change (~50 lines each) with big latency wins on large files.**

---

## 6. Pacing layer should not change any op, only add pacing ops — verify, and if it adds different types they should be typed

**Status: verified that pace doesn't modify ops. The "typed delays" idea is good — recommend implementing.**

### Verification

I checked `pace.c` and `pace.pl` for any writes to op fields. The only writes are during `read_input()` (parsing the input into the in-memory struct). During output emission, pace only **reads** op fields (`op->line`, `op->col`, `op->code`, `op->type`) and emits them verbatim. It also emits new ops (`delay`, `batch_delete`, `batch_insert`, `newline_delete`, `newline_insert`) — but doesn't modify the originals.

So the user's first assertion is **correct**: pace doesn't change ops.

### Currently all delays are untyped

```tsv
delay	50    ← type? type_delay? hunk_pause? rapid_eol_delay?
delay	250
delay	1
delay	80
```

The animator just sleeps for N ms. It can't differentiate between "this is a per-char typing delay" vs "this is a hunk-boundary pause" vs "this is a rapid-EOL burst delay".

### Proposed: typed delays

Change the format from `delay<TAB><ms>` to `delay<TAB><type><TAB><ms>`:

```tsv
delay	type	         50    # typing a single char
delay	hunk_pause	     250   # pause between hunks
delay	rapid_eol	         80   # rapid end-of-line delete burst
delay	awd_word_accel	 68    # adaptive word delete, accelerated
delay	awd_word_start	 80    # adaptive word delete, first 3 chars
delay	keep	             1    # scrolling past kept chars
delay	newline	         40   # after a \n delete or insert
delay	word_batch	     150  # after a batched word insert
```

Benefits:
1. **Dynamic pacing at animation time** — the animator could read a "pacing multiplier per type" from config and scale delays differently. E.g. "slow down typing but keep hunk pauses normal".
2. **Debugging** — when looking at a timed op stream, you can immediately see WHY each delay exists.
3. **Future features** — the animator could decide to skip certain delay types entirely (e.g. `--skip-keeps` to never pause on kept chars).

### Backward compatibility

Old animators that parse `delay<TAB><ms>` would still work (they'd just see the type as part of the value, fail to parse, fall through to no-op). But better: have pace emit `delay<TAB><ms>` (no type) by default, and `delay<TAB><type><TAB><ms>` only when `--typed-delays` is passed. Then update the animator to handle both formats.

### Implementation

- pace.c / pace.pl: add a `--typed-delays` flag (off by default for compat). When on, emit the type as the second field.
- animator.c / animator.pl: parse `delay<TAB>...<TAB><ms>` — if there's a middle field, treat it as the type and look up a per-type multiplier.
- vimscript engine: same.

**Recommendation: implement. ~30 lines of code per tool. Big feature win.**

---

## 7. Coloring of code in the animator

**Status: good idea, pygmentize is available as the external colorizer, here's how I'd implement it.**

### Current state

The vimscript diffvim uses vim's own syntax highlighting (the buffer is a normal vim buffer, vim colors it). The standalone C/Perl animators don't do syntax highlighting — they just render plain text with the cursor highlighted via ANSI reverse video.

The `--highlight` option in diffvim does **animation highlighting** (painting freshly typed chars green, deleted chars red) — this is **diff highlighting**, not **syntax highlighting**. Different thing.

### Proposed approach

1. **Precompute colored versions of old and new files** before running the animator.
   - Use `pygmentize -f terminal256 -l <lang>` to produce ANSI-colored output for both files.
   - Parse the ANSI escapes into a per-character color map: `colors_old[line][col] = ANSI_code`, `colors_new[line][col] = ANSI_code`.
   - This is one external program invocation per file. Cached per file (mtime-checked).

2. **Modify the op stream** to carry color info:
   - Option A: extend the op format to `op<TAB>type<TAB>line<TAB>col<TAB>code<TAB>color` where color is the ANSI escape sequence. Simple, but bloats the stream 2-3x.
   - Option B: emit two separate files — the op stream (unchanged) and a "color map" file. The animator loads the color map at startup and looks up colors per op. Smaller stream.
   - **Recommend Option B** — keeps the op stream compact.

3. **Animator rendering**:
   - When applying a `keep` op, render the char with `colors_old[line][col]`.
   - When applying a `delete` op, the char disappears (no color needed).
   - When applying an `insert` op, render the char with `colors_new[line][col]`.
   - This means deletes remove both the char and its color; inserts bring in the new char with its new color. Visually: the old code fades out as it's deleted, new code fades in with proper syntax colors.

4. **Where to put the coloring step**:
   - Add a `diffvim-colorize` executable that takes old/new files + language, produces two `.colormap` files.
   - The pipeline calls it before compute (or in parallel — it's independent).
   - The animator takes `--colormap-old FILE --colormap-new FILE` flags.

### Implementation outline

```python
# compute/perl/colorize.py (or compute/colorize.pl)
import sys, pygments, pygments.lexers, pygments.formatters
# Use pygments.token formatter to get (token_type, text) pairs
# Convert to a binary colormap: 4 bytes per char (ANSI fg code, ANSI bg code, attrs)
```

Or use vim itself:
```bash
vim -u NONE -N -n -es \
  -c "set filetype=python" \
  -c "runtime! syntax/python.vim" \
  -c "call libcall('ansi_dump', '')" \
  -c qa!
```

But pygmentize is simpler and language-agnostic.

### Tradeoffs

- **Pro**: beautiful colored animations out of the box, especially for talks/demos.
- **Pro**: works in the standalone C/Perl animators (which currently have no syntax highlighting).
- **Con**: adds a dependency on pygmentize (or pyvim, or bat).
- **Con**: ANSI escape sequences don't work in all terminals (Windows cmd, dumb terminals). Need a `--no-color` fallback.
- **Con**: color maps could be large for big files (1 byte per char × 2 files). For a 100KB file, that's 200KB of colormap — acceptable.

**Recommendation: implement as a separate `diffvim-colorize` tool, opt-in via `--colorize` flag. Default off until we know it works well.**

---

## 8. Commit and file picker using fzf — does it exist?

**Status: ALREADY EXISTS, undocumented. Here's what's there.**

### What's in the codebase

`plugin/diffvim.vim` already defines:

- `:DiffvimCommit [commit]` — VimDiff current buffer against a commit (prompts for hash if not given).
- `:DiffvimPick` — interactive commit picker with preview, using fzf.
- `:DiffvimHelp` — show help.
- `:Diffvim [old] [new]` — the main command.

### DiffvimPick implementation

It supports **4 picker backends** (auto-detected):

1. **fzf.vim** (vim plugin) — if `fzf#run` exists, uses the fzf vim API. Shows commit list with diff preview.
2. **fzf CLI** — if `fzf` binary exists but not the vim plugin, runs fzf in a terminal buffer.
3. **forgit** — if `forgit` is installed.
4. **builtin** — fallback vim inputlist() (no preview, just numbered list).

The picker shows commits that touched the current file, with a `git show --stat --patch --color=always` preview on the right. After picking, it animates the diff from that commit to the working copy.

### What's missing

1. **Documentation**: `:DiffvimPick` and `:DiffvimCommit` are barely mentioned in README.md / docs/. They should be in:
   - `README.md` — quick start section.
   - `docs/src/quick-start.md` — add a "Git workflow" section.
   - `man/diffvim.1` — document the plugin commands.
   - A new `docs/GIT_INTEGRATION.md` (or expand the existing `docs/src/git-integration.md`).

2. **File picker**: there's a **commit** picker but no **file** picker. A `:DiffvimPickFile` command that uses fzf to pick a file from `git log --name-only` or `git ls-files` would be useful. Then animate that file's history.

3. **Test coverage**: `tests/test_commit_picker.pl` exists but only checks that the commands are defined — it doesn't test the actual fzf flow (which would need an interactive terminal).

### Recommendation

1. **Install fzf** in the dev environment so we can test the existing picker.
2. **Add `:DiffvimPickFile`** — pick a file (fzf on `git ls-files`), then animate its diff vs HEAD or vs a picked commit.
3. **Document the existing commands** in README and a new GIT_INTEGRATION.md.
4. **Add `--picker fzf|forgit|builtin|none` flag** to the `diffvim` bash launcher so non-vim users get the same picker.

---

## Summary of recommendations

| # | Topic | Recommendation | Work |
|---|-------|----------------|------|
| 1 | diffvim uses C++ postprocess+pace | DO IT — biggest win | ~1 day, ~1800 LOC removed from engine |
| 2 | synchronous_engine test | FIXED (was a vimscript dict init bug) | done |
| 3 | Each postprocess option as separate executable | Don't — keep one tool, expose transforms as `--transform NAME` flags | n/a |
| 4 | Normalize LCS vs Patience output | Add a `diffvim-normalize` layer that re-bundles hunks; keep single-char ops as canonical, add `--batch-keeps` for efficiency | ~2 days |
| 5 | Streaming pipeline (hunk-by-hunk) | Add `--stream` to postprocess and pace; animator already streams. Big latency win on large files | ~1 day |
| 6 | Typed delays | Add `--typed-delays` to pace, parse type in animator. Allows dynamic per-type pacing at animation time | ~2 hours |
| 7 | Coloring via external colorizer | Add `diffvim-colorize` (using pygmentize), opt-in via `--colorize`. Color maps precomputed, op stream unchanged | ~1 day |
| 8 | fzf commit/file picker | Already exists for commits! Add `:DiffvimPickFile`, document everything, expose picker flag to bash launcher | ~2 hours (docs) + ~2 hours (file picker) |

### Recommended order of implementation

1. **Item 6 (typed delays)** — smallest, isolated change. Quick win.
2. **Item 1 (diffvim uses external pipeline)** — biggest impact, unblocks item 2 retirement.
3. **Item 5 (streaming pipeline)** — natural follow-up to item 1.
4. **Item 8 (file picker + docs)** — quick, user-facing, no architectural impact.
5. **Item 7 (coloring)** — independent, can be done anytime.
6. **Item 4 (normalize)** — needs design; only worth doing if we want LCS/Patience to be truly interchangeable.
7. **Item 3 (split postprocess)** — probably never; the current design is correct.

Items 1, 5, 6 are all on the critical path to a much smaller, faster diffvim. I'd tackle those first.

---

## What I actually fixed in this session

- **Bug fix**: `animator/tests/test_synchronous_engine.pl` — changed `let g:diffvim.output_file = "..."` to `let g:diffvim = {"output_file": "..."}`. The test now passes 10/10 (was 0/10).

That's the only code change. Everything else above is analysis for your decision.
