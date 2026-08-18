# Non-Character-Based Deletion and Insertion

## Overview

By default, diffvim animates every character deletion and insertion one
at a time. For large changes, this can be slow and tedious. This document
describes all the options that make deletions and insertions faster,
batched, or non-character-based.

---

## Options Summary

| Option | What it does | When to use |
|--------|-------------|-------------|
| `--max-hunk-chars N` | Apply entire hunk instantly if > N changed chars | Very large hunks |
| `--max-word-chars N` | Type words <= N chars instantly, pause after | Short words |
| `--word-diff` | Group changes by word tokens, batch word runs | Natural typing feel |
| `--rapid-eol-delete` | Delete trailing line text in one rapid shot | End-of-line deletions |
| `--accel-delete` | Block-based multi-line deletion with accel/decel | Multi-line block deletes |
| `--overwrite` | Replace words in place instead of delete+insert | Word replacement |
| `--delete-end-first` | Delete end-of-line before inserting | Mixed insert+delete on one line |
| `--left-to-right` | Sort ops within each line (no jumping around) | Coherent cursor movement |
| `--optimize-sequence` | Consolidate interleaved del/ins pairs | Eliminate erratic movement |
| `--semantic-cleanup` | Merge canceling del+ins pairs into keeps | Remove redundant ops |

---

## Detailed Descriptions

### 1. `--max-hunk-chars N` (instant whole hunk)

**What happens:** If a hunk has more than N changed characters, the
entire hunk is applied instantly with no animation. A message is shown:
"hunk 3 has 250 changed chars (> 200), applying instantly".

**Effect:** The viewer sees the hunk appear/disappear in one shot. No
character-by-character animation.

**When to use:** For very large hunks where character animation would
take too long (e.g., > 500 chars).

**Example:**
```bash
diffvim --max-hunk-chars 200 old.py new.py
```

### 2. `--max-word-chars N` (instant short words)

**What happens:** If a contiguous sequence of changed characters forms
a word (non-space chars terminated by space/newline) and the word length
is <= N, the entire word is typed instantly, then a pause follows.

**Effect:** Short words appear as a unit. Longer words are still
animated character by character.

**When to use:** When you want short identifiers (`x`, `i`, `fn`) to
appear instantly but longer words (`calculate_total`) to be animated.

**Example:**
```bash
diffvim --max-word-chars 5 old.py new.py
# Words <= 5 chars: typed instantly + 150ms pause
# Words > 5 chars: char by char
```

### 3. `--word-diff` (word-level diff + batched word runs)

**What happens:** Two things:
1. The diff is computed at the word-token level (not char level). This
   groups consecutive chars within a word as a single token.
2. During animation, contiguous delete or insert runs (non-space,
   non-newline chars) are applied as a batch — the whole word is
   deleted or inserted in one shot, then a pause follows.

**Effect:** Words appear and disappear as units. The cursor doesn't
move character by character within a word.

**When to use:** When you want a natural "typing words" feel instead
of "typing characters".

**Example:**
```bash
diffvim --word-diff old.py new.py
# "hello" is deleted as one unit, "world" is inserted as one unit
```

### 4. `--rapid-eol-delete` (rapid end-of-line deletion, default: on)

**What happens:** When the cursor is at the end of the line and all
remaining text after the cursor is being deleted, those deletes are
applied in one rapid shot (default 80ms) instead of char by char.

**Effect:** Trailing text vanishes quickly. The viewer sees the cursor
reach end of line, then the tail disappears.

**When to use:** Almost always (it's the default). Disable with
`--no-rapid-eol-delete` when you want to see every character disappear.

**Options:**
- `--rapid-eol-delay-ms N` (default 80) — delay after the rapid shot
- `--rapid-eol-min-chars N` (default 3) — minimum trailing chars to trigger

### 5. `--accel-delete` (block-based multi-line deletion with acceleration)

**What happens:** When multiple consecutive lines are deleted:
1. The cursor advances past leading whitespace (deletion starts at the
   first non-space character, not at a random indent position).
2. Lines are deleted in blocks of `--block-delete-size` (default 3) lines.
3. A pause of `--pause-before-delete-ms` (default 200ms) before the first block.
4. Each block is deleted instantly, then a delay follows.
5. The delay starts at `--accel-delete-start-ms` (default 80ms) and
   accelerates (multiplied by `--accel-delete-accel` / 100, default 0.85)
   until it reaches `--accel-delete-min-ms` (default 10ms).
6. Near the end (last 30% of the run), the delay decelerates back up.
7. A pause of `--pause-after-delete-ms` (default 200ms) after the last block.

**Effect:** Large blocks don't vanish in one shot. The viewer sees
blocks of 3 lines disappear with accelerating speed, then decelerating
near the end. The acceleration profile is a triangle: slow start →
fast middle → slow end.

**When to use:** When deleting 5+ lines. For 2-4 lines, the default
char-by-char is fine.

**Good values for block sizes 2-100 lines:**
- 2-5 lines: `--block-delete-size 1 --accel-delete-start-ms 60 --accel-delete-min-ms 15`
- 5-20 lines: `--block-delete-size 3 --accel-delete-start-ms 80 --accel-delete-min-ms 10` (default)
- 20-50 lines: `--block-delete-size 5 --accel-delete-start-ms 100 --accel-delete-min-ms 8`
- 50-100 lines: `--block-delete-size 8 --accel-delete-start-ms 120 --accel-delete-min-ms 5`

**Acceleration computation:** The delay for block N is:
- Phase 1 (accelerate): `delay = start_ms * accel^N` (decreasing)
- Phase 2 (cruise): `delay = min_ms` (constant)
- Phase 3 (decelerate): `delay = min_ms / accel^remaining` (increasing)

The transition from accelerate to decelerate happens when `remaining < total * 0.3`.

**Example:**
```bash
diffvim --accel-delete --block-delete-size 3 \
  --pause-before-delete-ms 200 --pause-after-delete-ms 200 \
  --accel-delete-start-ms 80 --accel-delete-min-ms 10 --accel-delete-accel 85 \
  old.py new.py
```

### 6. `--overwrite` (overwrite mode for word replacement)

**What happens:** When a word is deleted and a new word takes its place:
- If the replacement is **shorter**: overwrite the old word char by char
  (delete+insert pairs), then delete the extra old chars.
- If the replacement is **same length**: pure overwrite (all delete+insert
  pairs become keeps, no deletion needed).
- If the replacement is **longer**: overwrite the old word, then insert
  the remaining new chars.

**Effect:** Instead of "delete everything, then type everything", the
viewer sees "type over the old word". More natural for word replacement.

**When to use:** When most changes are word replacements (e.g., renaming
variables, changing function names).

### 7. `--delete-end-first` (delete end-of-line before inserting)

**What happens:** When a line has both inserts and end-of-line deletes,
the end-of-line is deleted first (with a short pause), then the inserts
are applied.

**Effect:** The viewer sees the tail of the line disappear, then new
text is inserted. More natural than "insert, then delete end".

**Options:**
- `--delete-end-first-delay-ms N` (default 100) — pause between delete and insert

### 8. `--left-to-right` (sort ops within each line)

**What happens:** Within each line, all operations are sorted so:
1. Keeps come first (in original order)
2. Deletes come next (sorted by position, left to right)
3. Inserts come last (sorted by position, left to right)

**Effect:** The cursor never jumps back and forth within a line. Deletes
go from left to right, then inserts go from left to right.

**When to use:** When the Patience produces erratic, jumping op sequences
(common with complex line modifications).

### 9. `--optimize-sequence` (consolidate interleaved ops, default: on)

**What happens:** Interleaved delete/insert pairs (e.g., `del a, ins x,
del b, ins y`) are consolidated into `del a, del b, ins x, ins y` (all
deletes first, then all inserts).

**Effect:** The cursor does one pass for deletes, then one pass for
inserts, instead of alternating between the two.

### 10. `--semantic-cleanup` (merge canceling pairs)

**What happens:** Adjacent delete+insert pairs where both ops have the
same character (e.g., `delete 'a', insert 'a'`) are merged into a single
`keep 'a'` op.

**Effect:** Reduces the total number of operations. Characters that
don't actually change are not animated.

### 11. `--word-accel` (accelerated char-by-char word insert/delete)

**What happens:** When a word is inserted or deleted character by
character, the delay starts at 2x the base delay and decreases to 0.5x
by the end of the word. A short pause (10% of total word time) follows.
Total time equals uniform char-by-char. Deletion is 20% faster by
default (configurable via `--word-accel-delete-pct`).

**Effect:** The viewer sees the word being typed/deleted with a natural
acceleration — slow start lets them see the beginning, then it speeds up.
The pause at the end gives time to read the complete word.

### 12. `--rapid-identical-chars` (accelerate identical char runs)

**What happens:** When a run of identical characters (e.g. `---------`)
is being deleted, each char is deleted with exponentially decreasing
delay (`delay * accel^count`). Default accel=0.5 (50%), so delays go
40ms → 20ms → 10ms → 5ms → 2ms → 1ms.

**Effect:** Long runs of identical chars vanish rapidly instead of
boring the viewer with uniform deletion.

### 13. `--preset NAME` (named option sets)

**What happens:** Applies a named preset that sets multiple options:
- `fast-delete`: all acceleration + optimization features
- `review`: all highlighting + pause features
- `present`: slow speed + dramatic highlighting
- `ai-code`: optimized for AI-generated diffs
- `custom`: reads from `DIFFVIM_PRESET_CUSTOM` env var

**Effect:** One flag sets 5-10 options at once. No need to remember
long command lines.

---

## Combining Options

For the best viewer experience, combine options:

```bash
# Natural word-based animation
diffvim --word-diff --semantic-cleanup --optimize-sequence old.py new.py

# Fast review of large files
diffvim --max-hunk-chars 500 --accel-delete --speed 2 old.py new.py

# Precise, coherent animation
diffvim --left-to-right --optimize-sequence --overwrite --highlight-inline old.py new.py

# Everything on (kitchen sink)
diffvim --word-diff --semantic-cleanup --optimize-sequence --left-to-right \
  --overwrite --accel-delete --highlight-inline --highlight-hunk \
  old.py new.py
```

---

## Verifying with Log Mode

Use `--log-mode 2` to see exactly what happens to each line, including
acceleration delays:

```bash
diffvim --log-mode 2 --log-file analysis.txt --accel-delete old.py new.py
cat analysis.txt
```

The log shows:
- The current line state
- A marker line with `d` at the delete position (or the inserted char)
- The acceleration delay for each delete (e.g., `# delay=80ms`)
- The resulting line after the operation

This lets you verify the acceleration profile is optimal before running
the actual animation.
