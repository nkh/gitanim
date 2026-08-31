# Layers Reference

This document describes every layer in the `ad` (animate-diff) pipeline,
with pseudo-code and a concrete example.

## Pipeline overview

```
ad_compute  →  ad_postprocess  →  ad_layer_pace  →  ad (animator)
                  ↑
                  runs the layer chain in argv order:
                  --ad-layer=<name> --ad-layer=<name> ...
```

**No layer is default.** The postprocess chain starts empty. Users add
layers via `--ad-layer=<name>` or convenience flags. The `ad_vim` and
`ad_pipeline` launchers also accept convenience flags (`--indent-last`,
`--overwrite`, `--line-delete-in-place`) that map to `--ad-layer=`.

---

## Layer 1: `ad_layer_reorder` — Reorder within lines

**Purpose:** Within each line, emit deletes before inserts. Prevents
interleaved "delete char, insert char, delete char, insert char" flicker.

**Pseudo-code:**
```
for each segment (bounded by keeps and \n ops):
    emit non-\n deletes (in original order)
    emit non-\n inserts (in original order)
    emit debug ops (in original order)
    emit the boundary op (keep or \n) in place

walk output, assign positions:
    for non-\n ops: assign (current_line, current_col)
    for \n keep/insert: advance to next line
    for \n delete: DON'T advance (join brings content HERE)
```

**Example:**
- Old: `abc` → New: `xBc`
- Raw ops (interleaved):
  ```
  keep    (1,1) 'a' → 'x'  (delete 'a' + insert 'x')
  delete  (1,1) 'a'
  insert  (1,1) 'x'
  keep    (1,2) 'b'
  delete  (1,3) 'c'
  insert  (1,3) 'C'
  ```
- After reorder:
  ```
  delete  (1,1) 'a'      ← deletes first
  delete  (1,3) 'c'
  insert  (1,1) 'x'      ← then inserts
  insert  (1,3) 'C'
  keep    (1,2) 'b'      ← keep in place
  ```

**Line-awareness:** Never touches `\n` ops (preserves their positions).
Only reorders character ops within a line.

---

## Layer 2: `ad_layer_overwrite` — Merge delete+insert into overwrite

**Purpose:** When a delete+insert happen at the same `(line, col)`,
merge them into a single `overwrite_insert` op. Prevents the
"delete then insert" flicker for in-place edits.

**Pseudo-code:**
```
walk ops:
    if op[i] is delete(non-\n) and op[i+1] is insert(non-\n)
       at same (line, col):
       (and not blocked by prev-delete-same-pos or next-insert-same-line)
       emit overwrite_insert(code=op[i+1].code, pos=op[i+1].pos)
       skip both ops
    else:
       emit op[i] unchanged

walk output, assign positions (same as reorder)
```

**Example:**
- Old: `abc` → New: `xbc`
- Raw ops:
  ```
  delete  (1,1) 'a'
  insert  (1,1) 'x'
  keep    (1,2) 'b'
  keep    (1,3) 'c'
  ```
- After overwrite:
  ```
  overwrite_insert  (1,1) 'x'  ← single op, replaces 'a' with 'x'
  keep              (1,2) 'b'
  keep              (1,3) 'c'
  ```

**Line-awareness:** Never touches `\n` ops. Only merges non-`\n`
delete+insert pairs.

---

## Layer 3: `ad_layer_indent_last` — Move whitespace deletes to end

**Purpose:** When a line with leading whitespace is being deleted,
delete the content FIRST, then the whitespace. Prevents the line from
"shifting left" before its content disappears.

**Pseudo-code:**
```
for each segment (bounded by \n ops):
    find leading run of whitespace deletes (space/tab)
    if found:
        emit content deletes (col bumped by +n_indent)
        emit whitespace deletes (col=1)
    else:
        emit unchanged
```

**Example:**
- Old: `    print("hi")` → New: `` (line deleted)
- Raw ops (whitespace deleted first):
  ```
  delete  (1,1) ' '    ← 4 spaces deleted
  delete  (1,2) ' '
  delete  (1,3) ' '
  delete  (1,4) ' '
  delete  (1,5) 'p'    ← then content
  delete  (1,6) 'r'
  ...
  ```
- After indent_last:
  ```
  delete  (1,5) 'p'    ← content first (col bumped by +4)
  delete  (1,6) 'r'
  ...
  delete  (1,1) ' '    ← then whitespace (col=1)
  delete  (1,1) ' '
  delete  (1,1) ' '
  delete  (1,1) ' '
  ```

**Line-awareness:** Uses `\n` as segment boundary. Only reorders within
a line's content.

---

## Layer 4: `ad_layer_line_delete_in_place` — Delete lines on their own line

**Purpose:** When a line is fully deleted (content + `\n`) AND the previous
line's `\n` is also deleted (to join), reorder so the content is deleted
FIRST (on its own line), then the `\n` joins. Prevents "join then delete"
visual where content briefly appears on the wrong line.

**Pseudo-code:**
```
walk ops:
    if op[i] is delete(\n)        ← joiner
       and op[i+1..k] is delete(content)
       and op[k+1] is delete(\n)  ← content's own \n:

       emit op[i+1..k]      (content deletes, line = joiner.line + 1)
       emit op[k+1]         (content's \n, line = joiner.line + 1)
       [joiner \n stays, re-iterate]
    else:
       emit op[i] unchanged
```

**Example:**
- Old:
  ```
  A
  B
  C
  ```
- New: `AC` (B deleted, A and C joined)
- Raw ops (joiner first):
  ```
  keep    (1,1) 'A'
  delete  (1,2) \n      ← joiner (joins A and B)
  delete  (2,1) 'B'     ← B content (now on line 1!)
  delete  (2,1) \n      ← B's \n
  keep    (3,1) 'C'
  ```
- After line_delete_in_place:
  ```
  keep    (1,1) 'A'
  delete  (2,1) 'B'     ← B content first (on its own line)
  delete  (2,1) \n      ← B's \n (removes empty line)
  delete  (1,2) \n      ← joiner last (joins A and C)
  keep    (2,1) 'C'
  ```

**Line-awareness:** This is THE line-aware layer — it reorders whole
lines (content before joiner `\n`).

---

## Layer 5: `ad_layer_skip_indent` — Skip animation for indent-only hunks

**Purpose:** When a hunk's only change is leading whitespace (indent
change), apply the ops instantly (no animation). The content is
unchanged, so there's nothing to "watch" being typed.

**Pseudo-code:**
```
for each hunk:
    if ALL delete/insert ops are whitespace (space/tab) or \n:
        wrap hunk's ops with markers:
            delay 0  indent_skip_start    ← before ops
            ... (original ops, unchanged) ...
            delay <pause_ms>  indent_skip_end  ← after ops
    else:
        emit unchanged
```

**Example:**
- Old: `def foo():` (no indent) → New: `    def foo():` (4-space indent)
- Raw ops:
  ```
  HUNK 1 1 1 0 0
  insert  (1,1) ' '
  insert  (1,1) ' '
  insert  (1,1) ' '
  insert  (1,1) ' '
  keep    (1,1) 'd'
  ...
  HUNK_END
  ```
- After skip_indent:
  ```
  HUNK 1 1 1 0 0
  delay  0  indent_skip_start       ← marker: skip animation
  insert  (1,1) ' '
  insert  (1,1) ' '
  insert  (1,1) ' '
  insert  (1,1) ' '
  keep    (1,1) 'd'
  ...
  delay  300  indent_skip_end         ← marker: pause after
  HUNK_END
  ```

**Line-awareness:** Hunk-level (looks at all ops in a hunk).

---

## Layer 6: `ad_layer_pace` — Insert delays between ops

**Purpose:** Add timing (delay ops) between content ops so the
animation runs at a readable speed. Does NOT modify, reorder, or add
content ops — only inserts `delay` lines.

**Pseudo-code:**
```
walk ops:
    for each keep/delete/insert op:
        emit op
        emit delay based on pacing mode:
            char:     <type_delay_ms>
            word:     <word_pause_ms> (after word batch)
            hunk:     <hunk_pause_ms> (between hunks)
            awd_slow: <slow_ms> (first 3 chars of word)
            awd_fast: <fast_ms> (rest of word)
            awd_skip: 0 (whitespace deletes, instant)
```

**Example:**
- Input:
  ```
  delete  (1,1) 'a'
  delete  (1,2) 'b'
  ```
- Output:
  ```
  delete  (1,1) 'a'
  delay   80  awd_slow
  delete  (1,2) 'b'
  delay   40  char
  ```

**Line-awareness:** None — only adds timing.

---

## Layer 7: `ad_layer_highlight` — Insert decoration ops

**Purpose:** Add visual decorations (highlight, dim, fold, signs, markers)
based on the diff. Does NOT modify content ops — only inserts decoration
ops.

**Pseudo-code:**
```
walk ops:
    for each hunk:
        if --highlight=inline: emit highlight op for changed region
        if --highlight=word:    emit highlight op for each changed word
        if --highlight=hunk:    emit highlight op for whole hunk
        if --dim-unchanged:     emit dim op for unchanged lines
        if --fold-unchanged:   emit fold op for unchanged regions
        if --sign-column:       emit sign op for each changed line
        if --git-blame:         emit marker ops with blame info
```

**Example:**
- Input:
  ```
  HUNK 1 1 1 0 0
  delete  (1,1) 'a'
  insert  (1,1) 'x'
  HUNK_END
  ```
- Output (with `--highlight=inline`):
  ```
  HUNK 1 1 1 0 0
  highlight  1 1 1 1  delete  500
  delete     (1,1) 'a'
  highlight  1 1 1 1  insert  500
  insert     (1,1) 'x'
  HUNK_END
  ```

**Line-awareness:** None — only adds decoration.

---

## Layer summary

| Layer                  | Type                | Modifies positions?   | Touches `\n`?   | Line-aware?      |
| ---------------------- | ------------------- | --------------------- | --------------- | ---------------- |
| `reorder`              | Reorder within line | Yes (recomputes)      | No (preserves)  | Yes              |
| `overwrite`            | Merge delete+insert | Yes (recomputes)      | No (preserves)  | Yes              |
| `indent_last`          | Reorder within line | Yes (col bump)        | No (boundary)   | Yes              |
| `line_delete_in_place` | Reorder whole lines | Yes (decrement)       | Yes (matches)   | Yes              |
| `skip_indent`          | Mark hunks for skip | No (markers only)     | No              | Yes (hunk-level) |
| `pace`                 | Add timing          | No (delays only)      | No              | No               |
| `highlight`            | Add decoration      | No (decorations only) | No              | No               |

---

## Default chain

**No layer is default.** The postprocess chain starts empty:

```bash
# No layers (raw compute output → pace → animate):
ad_vim old.py new.py

# Add layers explicitly:
ad_vim --indent-last old.py new.py
ad_vim --overwrite --line-delete-in-place old.py new.py
ad_vim --ad-layer=ad_layer_reorder --ad-layer=ad_layer_overwrite old.py new.py
```

**Convenience flags** (in `ad_vim` and `ad_pipeline`):
- `--indent-last` → `--ad-layer=ad_layer_indent_last`
- `--overwrite` → `--ad-layer=ad_layer_overwrite`
- `--line-delete-in-place` → `--ad-layer=ad_layer_line_delete_in_place`

**Generic layer addition:**
- `--ad-layer=<name>` → adds any layer to the chain

**Layer order matters.** Layers run in argv order. Typical order:
```
reorder → overwrite → indent_last → line_delete_in_place → skip_indent → pace → highlight
```
