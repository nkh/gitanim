# diffvim Vocabulary

Think of diffvim as a tiny movie studio for your code. The old file
is the "before" shot, the new file is the "after" shot, and diffvim
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

---

## The Production Pipeline (Stages)

Think of the pipeline as an assembly line. Each stage takes the
previous stage's output, does one job, and passes it along.

| Stage | Job | Analogy |
|-------|-----|---------|
| **compute** | Figures out WHAT changed (char-level diff) | The script — "remove this, add that" |
| **postprocess** | Figures out the ORDER and POSITION of each change | The storyboard — "do this first, then that, at this line and column" |
| **pace** | Adds TIMING — how long to pause between each action | The director's timing notes — "pause here for drama" |
| **decorate** | Adds VISUAL FX — highlights, dimming, fold markers | The special effects department |
| **animate** | PLAYS the animation — applies ops to a virtual buffer and renders | The screening — the audience watches |

---

## The Script (Operations / Ops)

Every action in the animation is an "op" — a single instruction.

| Op | What it does | Think of it as |
|----|-------------|----------------|
| **keep** | "This char is fine — leave it, move cursor forward" | A walk-on extra |
| **delete** | "This char shouldn't be here — remove it" | A cut scene |
| **insert** | "Add this new char right here" | A new line of dialogue |
| **delay** | "Wait N milliseconds before the next op" | A dramatic pause |
| **highlight** | "Flash this region with color" | A spotlight |
| **glide** | "Smoothly move the cursor from line A to line B" | A camera pan |
| **HUNK** | "A new section of changes starts here" | A new scene |

---

## Positions

| Term | Meaning |
|------|---------|
| **line** | 1-indexed row number (line 1 is the first line) |
| **col** | 1-indexed column (character position, not bytes — Unicode-aware) |
| **target line** | Where in the old file a hunk begins |

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

## The Ghost Line Bug (and its fix)

**The Ghost Line** is a visual hiccup: when a `\n` (newline) is
deleted, two lines merge. If the second line still has content,
that content "jumps up" onto the first line — like a ghost
appearing where it shouldn't.

**The Fix**: Delete the content FIRST (emptying the line), THEN
delete the `\n` (joining the empty line with the next). The content
never jumps — the line just quietly disappears.

**The Cursor Fix**: Even after the ghost-line fix, the op stream
may have backward line numbers. The animator decouples the
"internal cursor" (where the buffer operation happens) from the
"displayed cursor" (what the user sees). For `\n` deletes, only
the internal cursor moves — the displayed cursor stays put, so
the user never sees the cursor jump backwards.

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
| **post-processed ops** | Postprocess output — same ops but reordered, positioned, with ghost-line fix applied |
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
