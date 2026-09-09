# ad Vocabulary

Think of `ad` as a tiny movie studio for your code. The old file
is the "before" shot, the new file is the "after" shot, and `ad`
films the transformation — typing, deleting, and rearranging — as if
a human were doing it live.

---

## The Cast (Files and Data)

| Term | What it is |
|------|------------|
| **old file** | The "before" — your original code, before changes |
| **new file** | The "after" — what the code should look like when done |
| **snapshot** | A photo of the buffer at a specific moment. The final snapshot is the result. |
| **colormap** | A makeup file — each line of source code, pre-colored with syntax highlighting (ANSI codes). Applied to the buffer for visual flair. |
| **op stream** | The TSV file containing all operations (keep/delete/insert/etc.) that transform old into new. Produced by compute, modified by layers, consumed by the animator. |

---

## The Two Animators

The project has two animators that apply the same op stream:

| Animator | Language | When to use |
|----------|----------|-------------|
| **`ad_vim`** | Vimscript (embedded in `apps/vim/ad_vim`) | Interactive use — watch the animation inside vim, review diffs, use keyboard controls. Slower for large files. |
| **`bin/ad`** | C (in `animator/c/ad.c`) | Headless — testing, CI, when you just want the output. Faster and more reliable. Invoke via `ad_pipeline` or directly with precomputed ops. |

Both animators apply the SAME op stream. If they produce different output, one has a bug. The C animator is the reference implementation.

---

## The Production Pipeline (Stages)

Think of the pipeline as an assembly line. Each stage takes the
previous stage's output, does one job, and passes it along.

| Stage | Binary | Job | Analogy |
|-------|--------|-----|---------|
| **compute** | `bin/ad_compute` | Figures out WHAT changed (char-level diff) | The script — "remove this, add that" |
| **postprocess** | `pipeline/ad_postprocess` | Runs the layer chain — transforms ops (reorder, merge, etc.) | The storyboard — "do this first, then that, at this line and column" |
| **pace** | `bin/ad_layer_pace` | Adds TIMING — how long to pause between each action | The director's timing notes — "pause here for drama" |
| **decorate** | `bin/ad_layer_highlight` | Adds VISUAL FX — highlights, dimming, fold markers | The special effects department |
| **animate** | `bin/ad` or `apps/vim/ad_vim` | PLAYS the animation — applies ops to a virtual buffer and renders | The screening — the audience watches |

---

## The Script (Operations / Ops)

Every action in the animation is an "op" — a single instruction.

| Op | Format | What it does |
|----|--------|-------------|
| **keep** | `keep\t<line>\t<col>\t<code>` | "This char is fine — leave it, move cursor forward" |
| **delete** | `delete\t<line>\t<col>\t<code>` | "This char shouldn't be here — remove it" |
| **insert** | `insert\t<line>\t<col>\t<code>` | "Add this new char right here" |
| **keep_line** | `keep_line\t<L>` | "Line L is unchanged — advance to next line" (replaces old `keep \n`) |
| **join_lines** | `join_lines\t<L>` | "Join line L with L+1" (replaces old `delete \n`) |
| **split_line** | `split_line\t<L>\t<col>` | "Split line L at col C" (replaces old `insert \n`) |
| **delete_line** | `delete_line\t<line>` | "Remove this entire line atomically" (used by line_replace layer) |
| **insert_line** | `insert_line\t<line>\t<text>` | "Insert this entire line atomically" (used by line_replace layer) |
| **delay** | `delay\t<ms>\t<type>` | "Wait N milliseconds before the next op" |
| **highlight** | `highlight\t<sl>\t<sc>\t<el>\t<ec>\t<type>\t<dur>` | "Flash this region with color" |
| **glide** | `glide\t<from>\t<to>\t<ms>\t<show>` | "Smoothly move the cursor from line A to line B" |
| **HUNK** | `HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>` | "A new section of changes starts here" |
| **HUNK_END** | `HUNK_END` | "End of this section" |
| **EOF** | `EOF` or `done` | "End of op stream" |

**Note:** Char ops (keep/delete/insert) NEVER contain code 10 (`\n`).
Line boundaries are explicit line-level ops: `keep_line`, `join_lines`,
`split_line`. This separation simplifies all layers — no `\n`
special-casing needed.

---

## Positions

| Term | Meaning |
|------|---------|
| **line** | 1-indexed row number (line 1 is the first line) |
| **col** | 1-indexed column (character position, not bytes — Unicode-aware) |
| **target line** | Where in the old file a hunk begins |
| **line_shift** | Cumulative delta from \n deletes (joins, -1) and \n inserts (splits, +1). Used to remap op line numbers to buffer line numbers. |
| **ops_pre_shifted** | Flag set when a position-changing layer (reorder, overwrite, etc.) has already shifted op positions. The animator skips its own line_shift remapping when this is set. |

---

## Hunk Metadata

A HUNK header carries stats about the scene:

```
HUNK  <target_line>  <del_count>  <ins_count>  <is_end_insert>  <is_end_delete>
```

| Field | Meaning |
|-------|---------|
| **target line** | Where the action starts in the old file |
| **del count** | How many old lines are being removed |
| **ins count** | How many new lines are being added |
| **is_end_insert** | 1 if we're appending at the very end of the file |
| **is_end_delete** | 1 if we're chopping off the end of the file |

---

## Layers

Layers are standalone executables that transform the op stream. They
are chained by `ad_postprocess` in the order specified by `--ad-layer`
flags.

| Layer | What it does |
|-------|-------------|
| **ad_layer_reorder** | Reorders ops within each line (deletes before inserts) |
| **ad_layer_overwrite** | Merges adjacent delete+insert into overwrite_insert |
| **ad_layer_indent_last** | Moves leading whitespace deletes to end of line |
| **ad_layer_line_delete_in_place** | Reorders ops so content is deleted BEFORE lines are joined. Two modes: `--mode batch` (delete all content first, then join all) and `--mode interleaved` (delete content → join → delete next → join). Default: batch. |
| **ad_layer_skip_indent** | Skips animation for indent-only changes |
| **ad_layer_pace** | Inserts delay ops between content ops |
| **ad_layer_highlight** | Inserts highlight/dim/fold/sign decoration ops |
| **ad_layer_line_replace** | Collapses char ops into delete_line/insert_line (whole-line replacement) |

---

## L1/L2 Debugging

The L1/L2 tool (`scripts/ad_l1l2`) tests the **op stream** (not the
animator). It applies the ops to the old file using the C animator
(the reference implementation), then compares the result against the
new file line-by-line.

| Term | Meaning |
|------|---------|
| **L1** | Last line where old+ops matches new (everything up to here is correct) |
| **L2** | First line where old+ops differs from new (the bug starts here). 0 = all match. |
| **L_TOTAL** | Total lines compared (max of buffer and new file) |

Usage in `ad_session`:
- Runs automatically on session start and on ops.tsv save
- `<leader>b`: manual re-run
- `<leader>f`: fold identical lines (folds 1..L1)
- `<leader>t`: trim — create reduced files from L2 onward

---

## Timing (Pacing)

Pacing controls the rhythm of the animation — fast, slow, jittery, smooth.

| Term | What it controls |
|------|-----------------|
| **delete pacing** | How deletions feel: `char` (one at a time), `word` (word-by-word), `instant` (zap!), `flash` (highlight then zap), `rapid-eol` (accelerate at end of line) |
| **insert pacing** | How typing feels: `char` (one at a time), `word` (type whole words, pause after spaces) |
| **pacing mode** | Overall rhythm: `uniform` (steady), `adaptive` (varies), `gaussian` (natural jitter), `review` (slow, careful) |
| **AWD** | Adaptive Word Delete: spaces vanish instantly, first few chars are slow, then accelerate — feels like a human getting impatient |
| **cursor glide** | Between hunks, the cursor glides smoothly instead of teleporting |
| **distance speed** | Hunks far away play fast (quick glance); nearby hunks play slow (every char visible) |

---

## Syntax Highlighting (Colormap)

| Term | How it works |
|------|-------------|
| **colormap-old** | Pre-colored version of the old file (syntax-highlighted) |
| **colormap-new** | Pre-colored version of the new file |
| **progressive recoloring** | Unmodified lines show old colors; as lines are modified, they switch to new colors — visual feedback of what changed |
| **colorize** | The tool that generates colormaps (backends: vim, pygmentize, bat, none) |

---

## Display Modes

| Term | What you see |
|------|-------------|
| **scroll mode** | How the viewport follows the cursor: `zz` (center), `zt` (top), `zb` (bottom), `none` (don't scroll) |
| **diff-stat** | An overlay showing "N/M lines changed" |
| **diff-highlight** | Modified lines get a subtle background tint |
| **bell** | Terminal bell rings on potential errors |
| **sign column** | `+` and `-` signs in the margin for added/removed lines |
| **dim-unchanged** | Unchanged lines are dimmed to draw focus to changes |

---

## The Formats

| Format | What it contains |
|--------|-----------------|
| **raw ops** | Compute output — char-level keep/delete/insert with HUNK headers |
| **post-processed ops** | Postprocess output — same ops but reordered, positioned (per-op `(line, col)`) |
| **timed ops** | Pace output — post-processed ops with `delay` lines inserted between them |
| **decorated ops** | Decorate output — timed ops with highlight/dim/fold/sign metadata |

All formats are **TSV** (tab-separated values). Every field is
separated by `\t`. Every file ends with a blank line.

---

## Delay Types

The pace stage inserts delays with a "type" tag so the animator
can adjust timing per category:

| Type | When it's used |
|------|----------------|
| `char` | After each character (normal typing) |
| `word` | After completing a word |
| `hunk` | Between hunks |
| `glide` | During a cursor glide between hunks |
| `awd_slow` | AWD: first few chars of a delete run |
| `awd_fast` | AWD: accelerated word batches |
| `awd_skip` | AWD: spaces deleted instantly |
| `flash_pause` | Flash mode: pause after highlight |
| `flash_delete` | Flash mode: instant delete after pause |
| `rapid_eol` | Rapid end-of-line acceleration |
| `rapid_identical` | Rapid runs of the same character |
| `overwrite` | Minimal delay for overwrite (delete+insert at same position) |
| `pause_after` | Pause after N changed lines |
| `block_start` | Pause before a delete block |
| `block_end` | Pause after a delete block |
