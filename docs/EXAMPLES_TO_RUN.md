# 15 Representative Examples to Run

This document lists 15 representative `ad_vim` invocations that
exercise the full range of pipeline options. Each example opens vim
and animates the diff — you watch the transformation happen in real
time, as if a human were typing it.

## How to run

```bash
make ex1           # open vim, animate the diff
make ex7           # open vim with overwrite + indent-last layers
make examples      # animate all 15 in vim (one after another)
```

To run headless (no vim, just verify the output is correct):

```bash
make ex1 HEADLESS=1           # verify snapshot matches new file
make examples HEADLESS=1       # verify all 15 snapshots match
```

## What happens when you run `make exN`

1. The `ad_vim` script runs the full pipeline internally:
   - `ad_compute` (diff engine) — computes the raw op stream
   - `ad_postprocess` (layer chain) — applies reorder + any layers you specified
   - `ad_layer_pace` (pace layer) — adds timing delays (if pace options given)
2. Vim opens with the old file loaded
3. The vimscript engine reads the timed op stream and animates each op:
   - deletes remove characters (with the pacing you chose)
   - inserts type characters (with the pacing you chose)
   - the cursor moves between edit regions (with glide if enabled)
4. When the animation finishes, the buffer contains the new file content
5. Press `:q` to quit (or `q` during animation to stop early)

## Controls during animation

While vim is animating, you can interact:

| Key | Action |
|-----|--------|
| `<Space>` | pause / resume |
| `n` | skip current hunk (apply instantly, move to next) |
| `b` | back to previous hunk (revert and restart) |
| `q` | stop animation (leave buffer in current state) |
| `+` | speed up (×1.5) |
| `-` | slow down (×0.67) |
| `=` | reset speed to 1.0 |
| `?` | show help |

## What each example shows

### ex1 — Default pipeline, small Python

```
make ex1
```
**Files:** `tests/examples/01_small_python/{old.py,new.py}`
**Options:** none (defaults)
**What it shows:** The baseline. A 3-line Python function is deleted
entirely. With no options, the default delete-pacing is `word` —
same-type deletes group into one tick. The animation deletes the
content word-by-word, then the line collapses. This is the "vanilla"
experience — any option below changes something visible.

### ex2 — Large Python with word-diff

```
make ex2
```
**Files:** `tests/examples/02_large_python/{old.py,new.py}`
**Options:** `--word-diff`
**What it shows:** A large Python file (~100 lines) with substantial
changes. `--word-diff` makes the diff engine treat whitespace-delimited
words as atomic units — so multi-char changes on the same word animate
as one replacement, not character-by-character flicker. Expect: clean
word-level edits across imports, classes, and functions.

### ex3 — JSON config with word-diff

```
make ex3
```
**Files:** `tests/examples/03_json_config/{old.json,new.json}`
**Options:** `--word-diff`
**What it shows:** A JSON config file where keys and values change.
`--word-diff` makes `"version": "1.0.0"` → `"version": "2.0.0"`
animate as one word replacement. Expect: clean word-level edits, not
character-by-character flicker on every value.

### ex4 — Shell script with overwrite layer

```
make ex4
```
**Files:** `tests/examples/04_shell_script/{old.sh,new.sh}`
**Options:** `--ad-layer=ad_layer_reorder --overwrite`
**What it shows:** A shell script where several words are replaced
(e.g., `APACHE_URL` → `NGINX_URL`). The `--overwrite` layer merges
adjacent delete+insert pairs at the same position into
`overwrite_insert` ops — so `delete h insert g` becomes
`overwrite_insert g` (clean char replacement, no backspace+retype
flicker). Expect: each replaced character overwrites in place.

### ex5 — Go code with indent-last

```
make ex5
```
**Files:** `tests/examples/05_go_code/{old.go,new.go}`
**Options:** `--ad-layer=ad_layer_reorder --indent-last`
**What it shows:** A Go function where the indentation level changes.
The `--indent-last` layer moves leading-whitespace deletes to AFTER
the content deletes, so the content disappears first and then the
line shifts left — instead of the line jumping left before its content
vanishes. Expect: content shrinks to empty, THEN the indent collapses.

### ex6 — TypeScript with line_delete_in_place

```
make ex6
```
**Files:** `tests/examples/06_typescript/{old.ts,new.ts}`
**Options:** `--ad-layer=ad_layer_reorder --line-delete-in-place`
**What it shows:** A TypeScript file where a multi-line block is
deleted. Without the layer, content jumps up before disappearing
(visual flicker). The layer reorders so all content disappears in
place first, THEN lines collapse. Expect: 3 lines of content vanish
where they are, then the empty lines join upward.

### ex7 — Rust with overwrite + indent-last (combined layers)

```
make ex7
```
**Files:** `tests/examples/08_rust_code/{old.rs,new.rs}`
**Options:** `--ad-layer=ad_layer_reorder --overwrite --indent-last`
**What it shows:** A Rust struct with both char-level replacements
and indentation changes. Three layers run in sequence: reorder
(normalize), overwrite (merge delete+insert), indent-last (move
whitespace deletes to end). Expect: type names overwrite in place,
then indent collapses after content. Shows layer composition.

### ex8 — C code with line_replace (collapse whole lines)

```
make ex8
```
**Files:** `tests/examples/09_c_code/{old.c,new.c}`
**Options:** `--ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace`
**What it shows:** A C function where a line is heavily rewritten.
The `line_replace` layer collapses the entire line into
`delete_line + insert_line <final>` — so instead of animating each
char edit, the whole line is deleted and the new line appears in one
step. Expect: the line vanishes and reappears with the new content.

### ex9 — Java with word delete-pacing

```
make ex9
```
**Files:** `tests/examples/13_java/{old.java,new.java}`
**Options:** `--delete-pacing word`
**What it shows:** A Java class with method changes. `--delete-pacing word`
groups same-type deletes so a run of spaces or letters deletes in one
tick. Compare with ex10 (char pacing) to see the difference. Expect:
word-scale delete grouping, faster than char-by-char.

### ex10 — Kotlin with char delete-pacing (contrast with ex9)

```
make ex10
```
**Files:** `tests/examples/14_kotlin/{old.kt,new.kt}`
**Options:** `--delete-pacing char`
**What it shows:** `--delete-pacing char` deletes each character
individually — every `delete` op gets its own tick. This is the
slowest, most granular delete animation. Compare with ex9 (word
pacing) to see the speed/fluency difference. Expect: character-by-
character deletion, visibly slower than word mode.

### ex11 — Ruby with flash delete-pacing (highlight-then-delete)

```
make ex11
```
**Files:** `tests/examples/16_ruby/{old.rb,new.rb}`
**Options:** `--delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300`
**What it shows:** `flash` mode highlights the whole line about to be
deleted for 300ms, pauses 400ms, then deletes the content in one shot.
Expect: the line flashes (highlighted), then vanishes. Tune the two
`--flash-*` options to make the flash more or less prominent.

### ex12 — Swift with gaussian pacing (natural jitter)

```
make ex12
```
**Files:** `tests/examples/15_swift/{old.swift,new.swift}`
**Options:** `--pacing gaussian --gaussian-jitter-pct 20`
**What it shows:** `gaussian` pacing adds ±20% jitter to each delay,
so the animation has natural variation — some chars type fast, some
slow, like a human typing. Compare with the default `uniform` pacing
(ex1) which is metronomic. Expect: less-robotic, organic timing.

### ex13 — Perl with cursor-glide (smooth cursor between hunks)

```
make ex13
```
**Files:** `tests/examples/23_perl/{old.pl,new.pl}`
**Options:** `--cursor-glide-ms 200 --cursor-glide-show-intermediate 1`
**What it shows:** The cursor glides (200ms) between hunks, showing
intermediate lines as it moves — so you see the cursor travel from
one edit region to the next, not just teleport. Expect: visible
cursor movement between hunks, like watching someone scroll to the
next edit.

### ex14 — Haskell with distance-speed (adaptive long jumps)

```
make ex14
```
**Files:** `tests/examples/21_haskell/{old.hs,new.hs}`
**Options:** `--distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3.0`
**What it shows:** `distance-speed adaptive` speeds up the animation
by 3× when the next hunk is far away (>10 lines apart) and slows it
down when close. This keeps the animation engaging for long files —
you don't sit through full-speed animation on a 1000-line jump.
Expect: fast jumps feel quick, close-up edits feel deliberate.

### ex15 — Huge Python with everything (kitchen-sink combo)

```
make ex15
```
**Files:** `tests/examples/42_large_huge_python/{old.py,new.py}`
**Options:** `--word-diff --ad-layer=ad_layer_reorder --overwrite --indent-last --line-delete-in-place --delete-pacing word --pacing gaussian --distance-speed adaptive`
**What it shows:** The kitchen-sink example. A very large Python
file (~1000+ lines) with every option layered on:
- `--word-diff` for word-level atomic edits
- 4 postprocess layers in sequence (reorder, overwrite, indent_last,
  line_delete_in_place)
- `word` delete-pacing + `gaussian` timing + `adaptive` distance speed
Expect: a long animation that showcases every option. Good for a
"full demo" run.

## Summary table

| # | Example | Key options | What it demonstrates |
|---|---------|-------------|----------------------|
| 1 | 01_small_python | (defaults) | baseline pipeline |
| 2 | 02_large_python | word-diff | word-level atomic edits |
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
