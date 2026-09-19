# 15 Representative Examples to Run

This document lists 15 representative `ad_pipeline` invocations that
exercise the full range of pipeline options. Each example is runnable
as `make ex<N>` (e.g. `make ex1`). Each writes its snapshot to
`/tmp/exN_out.txt` and verifies it matches the example's `new.*` file.

The examples are ordered from simplest to most complex. Each one
introduces one or two new options, so you can see what each option
contributes.

## How to run

```bash
make ex1     # run example 1 (default pipeline, small Python)
make ex7     # run example 7 (overwrite + indent-last on Rust)
make examples  # run all 15 sequentially
```

Each target prints the pipeline command it runs, then runs it with
`--no-display` (no terminal animation) and writes the final buffer to
`/tmp/exN_out.txt`. A `diff` against the expected `new.*` file
verifies correctness. To see the animation in your terminal, drop
`--no-display` and `--speed 1000` from the command (copy it from the
Makefile target).

**Important:** The postprocess layer chain starts empty by default.
Layers that operate on char-level ops (`overwrite`, `indent_last`,
`line_delete_in_place`) expect `ad_layer_reorder` to run FIRST —
reorder normalizes the op order (deletes before inserts within each
line) so the downstream layers see a clean input. The examples below
always include `--postprocess-ad-layer=ad_layer_reorder` first when
using any postprocess layer.

## What each example shows

### ex1 — Default pipeline, small Python

```
make ex1
```
**Files:** `tests/examples/01_small_python/{old.py,new.py}`
**Options:** none (defaults)
**What it shows:** The baseline. A 3-line Python function is deleted
entirely. With no options, the pipeline runs no postprocess layers and
no pace layer — the raw `ad_compute` output goes straight to the
animator. The animation deletes the content char-by-char. This is the
"vanilla" experience — any option below changes something visible.

### ex2 — Large Python with semantic-cleanup

```
make ex2
```
**Files:** `tests/examples/02_large_python/{old.py,new.py}`
**Options:** `--compute-semantic-cleanup`
**What it shows:** A large Python file (~100 lines) with substantial
changes across imports, classes, and functions. `--compute-semantic-cleanup`
tells the diff engine to coalesce small adjacent hunks into larger
ones when they're semantically related (e.g., a class signature change
+ its docstring change become one hunk). Without this option, you'd
see many tiny hunks; with it, the animation flows as fewer, larger
edits. Expect to see the module docstring, imports, and class
definition all animate as coherent blocks.

### ex3 — JSON config with word-diff

```
make ex3
```
**Files:** `tests/examples/03_json_config/{old.json,new.json}`
**Options:** `--compute-word-diff`
**What it shows:** A JSON config file where keys and values change.
`--compute-word-diff` makes the diff engine treat whitespace-delimited
words as atomic units — so `"version": "1.0.0"` → `"version": "2.0.0"`
animates as one word replacement, not 3 char deletes + 3 char inserts.
Expect to see clean word-level edits, not character-by-character
flicker on every value.

### ex4 — Shell script with overwrite layer

```
make ex4
```
**Files:** `tests/examples/04_shell_script/{old.sh,new.sh}`
**Options:** `--postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite`
**What it shows:** A shell script where several words are replaced
(e.g., `APACHE_URL` → `NGINX_URL`). The `ad_layer_overwrite` layer
merges adjacent delete+insert pairs at the same position into
`overwrite_insert` ops — so `delete h insert g` becomes `overwrite_insert g`
(clean char replacement, no backspace+retype flicker). `ad_layer_reorder`
runs first to normalize the op order. Expect to see each replaced
character overwrite in place. This is the Phase 1 + 2 Option C work:
run-level merging handles multi-char replacements cleanly.

### ex5 — Go code with indent-last

```
make ex5
```
**Files:** `tests/examples/05_go_code/{old.go,new.go}`
**Options:** `--postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_indent_last`
**What it shows:** A Go function where the indentation level changes.
The `ad_layer_indent_last` layer moves leading-whitespace deletes to
AFTER the content deletes, so the content disappears first and then
the line shifts left — instead of the line jumping left before its
content vanishes (which looks visually wrong). Expect: content
shrinks to empty, THEN the indent collapses. The `\n` delete is
emitted LAST (Phase 2 fix) so the next line doesn't inherit the
deleted indent.

### ex6 — TypeScript with line_delete_in_place (multi-line block delete)

```
make ex6
```
**Files:** `tests/examples/06_typescript/{old.ts,new.ts}`
**Options:** `--postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_delete_in_place`
**What it shows:** A TypeScript file where a multi-line block is
deleted. Without the layer, the diff engine produces
`delete(L1) + join + delete(L2) + join + delete(L3) + join` — content
jumps up before disappearing (visual flicker). The layer (Phase 2
sliding window) reorders to `delete(L1) + delete(L2) + delete(L3) +
join + join + join` — all content disappears in place first, THEN
lines collapse. Expect: 3 lines of content vanish where they are,
then the empty lines join upward.

### ex7 — Rust with overwrite + indent-last (combined layers)

```
make ex7
```
**Files:** `tests/examples/08_rust_code/{old.rs,new.rs}`
**Options:** `--postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last`
**What it shows:** A Rust struct with both char-level replacements
(field types) and indentation changes. Three layers run in sequence:
reorder first (normalize op order), overwrite (merge delete+insert
into overwrite_insert), then indent-last (move whitespace deletes to
end). The layer order matters — each layer transforms the output of
the previous one. Expect: type names overwrite in place, then indent
collapses after content. This shows how layers compose.

### ex8 — C code with line_replace (collapse whole lines)

```
make ex8
```
**Files:** `tests/examples/09_c_code/{old.c,new.c}`
**Options:** `--postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_replace`
**What it shows:** A C function where a line is heavily rewritten
(multiple char changes on the same line). The `ad_layer_line_replace`
layer collapses the entire line into `delete_line + insert_line <final>`
— so instead of animating each char edit, the whole line is deleted
and the new line appears in one step. Expect: the line vanishes and
reappears with the new content. Good for "big rewrite" diffs where
char-by-char would be too slow. Phase 2 fix: lines with `split_line`
or `join_lines` are NOT collapsed (they keep their char ops).

### ex9 — Java with word delete-pacing

```
make ex9
```
**Files:** `tests/examples/13_java/{old.java,new.java}`
**Options:** `--pace-delete-pacing word`
**What it shows:** A Java class with method changes. `--pace-delete-pacing word`
groups same-type deletes so a run of spaces or a run of letters
deletes in one tick. Compare with ex10 (char pacing) to see the
difference. Expect: word-scale delete grouping, faster than
char-by-char.

### ex10 — Kotlin with char delete-pacing (contrast with ex9)

```
make ex10
```
**Files:** `tests/examples/14_kotlin/{old.kt,new.kt}`
**Options:** `--pace-delete-pacing char`
**What it shows:** A Kotlin file. `--pace-delete-pacing char` deletes
each character individually — every `delete` op gets its own tick.
This is the slowest, most granular delete animation. Compare with
ex9 (word pacing) to see the speed/fluency difference. Expect:
character-by-character deletion, visibly slower than word mode.

### ex11 — Ruby with flash delete-pacing (highlight-then-delete)

```
make ex11
```
**Files:** `tests/examples/16_ruby/{old.rb,new.rb}`
**Options:** `--pace-delete-pacing flash --pace-flash-pause-ms 400 --pace-flash-highlight-ms 300`
**What it shows:** A Ruby file. `flash` mode highlights the whole line
about to be deleted for 300ms, pauses 400ms, then deletes the content
in one shot. Expect: the line flashes (highlighted), then vanishes.
The two `--pace-flash-*` options control the highlight and pause
durations — tune them to make the flash more or less prominent.

### ex12 — Swift with gaussian pacing (natural jitter)

```
make ex12
```
**Files:** `tests/examples/15_swift/{old.swift,new.swift}`
**Options:** `--pace-pacing gaussian --pace-gaussian-jitter-pct 20`
**What it shows:** A Swift file. `gaussian` pacing adds ±20% jitter
to each delay, so the animation has natural variation — some chars
type fast, some slow, like a human typing. Compare with the default
`uniform` pacing (ex1) which is metronomic. Expect: visibly
less-robotic timing; the jitter makes the animation feel organic.

### ex13 — Perl with cursor-glide (smooth cursor between hunks)

```
make ex13
```
**Files:** `tests/examples/23_perl/{old.pl,new.pl}`
**Options:** `--pace-cursor-glide-ms 200 --pace-cursor-glide-show-intermediate 1`
**What it shows:** A Perl file with multiple hunks far apart. The
cursor glides (200ms) between hunks, showing intermediate lines as
it moves — so you see the cursor travel from one edit region to the
next, not just teleport. `--pace-cursor-glide-show-intermediate 1`
makes the lines scroll past during the glide (set to 0 to glide
without showing intermediate content). Expect: visible cursor
movement between hunks, like watching someone scroll to the next
edit.

### ex14 — Haskell with distance-speed (adaptive long jumps)

```
make ex14
```
**Files:** `tests/examples/21_haskell/{old.hs,new.hs}`
**Options:** `--pace-distance-speed adaptive --pace-distance-threshold 10 --pace-distance-fast-mult 3.0`
**What it shows:** A Haskell file where hunks are far apart (>10
lines apart). `distance-speed adaptive` speeds up the animation
by 3x when the next hunk is far away (above the threshold) and
slows it down (0.5x via `--pace-distance-slow-mult`, default) when
close. This keeps the animation engaging for long files — you don't
sit through full-speed animation on a 1000-line jump. Expect: the
fast jumps feel quick, the close-up edits feel deliberate.

### ex15 — Huge Python with everything (combo)

```
make ex15
```
**Files:** `tests/examples/42_large_huge_python/{old.py,new.py}`
**Options:** `--compute-semantic-cleanup --compute-word-diff --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last --postprocess-ad-layer=ad_layer_line_delete_in_place --pace-delete-pacing word --pace-pacing gaussian --pace-distance-speed adaptive`
**What it shows:** The kitchen-sink example. A very large Python
file (~1000+ lines) with every option layered on:
- `semantic-cleanup` + `word-diff` for the diff engine
- 4 postprocess layers in sequence (reorder, overwrite, indent_last,
  line_delete_in_place) — the full Phase 2 chain
- `word` delete-pacing + `gaussian` timing + `adaptive` distance speed
  for the pace layer
Expect: a long animation that showcases every option. Good for a
"full demo" run. If this runs clean (snapshot matches), the whole
pipeline is wired correctly.

## What to look for

For each example, after running `make exN`:

1. **The snapshot test** (printed at the end): should say
   `exN: snapshot matches new file`. If it says `MISMATCH`, something
   broke — the animation produced the wrong final buffer.

2. **The animation** (if you drop `--no-display --speed 1000`):
   watch for the specific behavior described in "What it shows"
   above. If you don't see the expected behavior, the option isn't
   taking effect (check the layer chain with `--postprocess-ad-layer-dry-run`).

3. **The op stream** (if you want to debug): add `--postprocess-ad-layer-keep-temps`
   to keep intermediate files in `/tmp/ad_postprocess_*`, then inspect
   each layer's output to see where the op stream changes.

## Summary table

| # | Example | Key options | What it demonstrates |
|---|---------|-------------|----------------------|
| 1 | 01_small_python | (defaults) | baseline pipeline |
| 2 | 02_large_python | semantic-cleanup | hunk coalescing |
| 3 | 03_json_config | word-diff | word-level atomic edits |
| 4 | 04_shell_script | reorder + overwrite | clean char replacement |
| 5 | 05_go_code | reorder + indent-last | content-then-indent order |
| 6 | 06_typescript | reorder + line_delete_in_place | in-place block delete |
| 7 | 08_rust_code | reorder + overwrite + indent-last | layer composition |
| 8 | 09_c_code | reorder + line_replace | whole-line collapse |
| 9 | 13_java | delete-pacing word | word-scale grouping |
| 10 | 14_kotlin | delete-pacing char | char-by-char (contrast) |
| 11 | 16_ruby | delete-pacing flash | highlight-then-delete |
| 12 | 15_swift | pacing gaussian | natural jitter |
| 13 | 23_perl | cursor-glide | smooth cursor between hunks |
| 14 | 21_haskell | distance-speed adaptive | fast long jumps |
| 15 | 42_large_huge_python | everything | kitchen-sink combo |
