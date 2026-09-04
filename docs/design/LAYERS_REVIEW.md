# Layers — Implementation Review

This document lists every layer in the `ad` (animate-diff) pipeline,
with its description, pseudo-code, file examples, ops before/after, and
known problems.

**Test status (end-state correctness, 42 examples):**
- `reorder` alone: **42/42 pass** ✓
- Every other layer alone: **1/5 pass** ✗ (broken when run without reorder)

The core problem: every layer except `reorder` produces positions that
the animator can't handle correctly. See "Known problems" under each
layer.

---

## 1. `ad_layer_reorder`

**File:** `layers/c/ad_layer_reorder.c` (C), `layers/perl/ad_layer_reorder.pl` (Perl twin)

### Description

Within each line (segment bounded by keeps and `\n` ops), emit all
deletes first, then all inserts. Prevents interleaved
"delete char, insert char, delete char, insert char" flicker.

After reordering, walks the output forward and recomputes `(line, col)`
for every op based on the new execution order. Tracks `line_shift`:
`\n` deletes don't advance `current_line` (join brings content to the
same line); `\n` keeps/inserts advance to the next line.

### Pseudo-code

```
function layer_reorder(ops, n_ops):
    # Pass 1: 4-sweep within segments
    out = []
    segment_start = 0
    for i in 0..n_ops:
        is_boundary = (i == n_ops) OR
                       (ops[i].type == "keep") OR
                       (ops[i].code == NEWLINE)
        if is_boundary:
            # Sweep 1: non-\n deletes
            for j in segment_start..i:
                if ops[j].type == "delete" and ops[j].code != NEWLINE:
                    out.append(ops[j])
            # Sweep 2: non-\n inserts
            for j in segment_start..i:
                if ops[j].type in ("insert", "overwrite_insert")
                   and ops[j].code != NEWLINE:
                    out.append(ops[j])
            # Sweep 3: debug ops (original order)
            for j in segment_start..i:
                if is_debug(ops[j]):
                    out.append(ops[j])
            # Emit boundary (keep or \n) in place
            if i < n_ops:
                out.append(ops[i])
            segment_start = i + 1

    # Pass 2: position walk
    current_line = out[0].line
    current_col = 1
    for i in 0..len(out):
        if is_debug(out[i]): continue
        if out[i].code != NEWLINE:
            out[i].line = current_line
            out[i].col = current_col
            if out[i].type in ("keep", "insert", "overwrite_insert"):
                current_col++
        else:
            out[i].line = current_line
            out[i].col = current_col
            if out[i].type == "delete":
                # \n delete: join — DON'T advance
                pass
            else:
                # \n keep or insert: advance to next line
                current_line++
                current_col = 1
    return out
```

### File example

**Old:** `ab` → **New:** `xb`

### Ops before

```
HUNK  1  2  1  0  0
delete  1  1  97  'a'
insert  1  1  120 'x'
keep    1  2  98  'b'
HUNK_END
```

### Ops after

```
HUNK  1  2  1  0  0
delete    1  1  97  'a'     ← deletes first
insert    1  1  120 'x'     ← then inserts
keep      1  2  98  'b'     ← keep in place
HUNK_END
```

### Known problems

**None.** This layer produces correct end-state for all 42 test
examples when run alone. The position walk correctly handles `\n`
deletes (don't advance) and `\n` keeps/inserts (advance).

---

## 2. `ad_layer_overwrite`

**File:** `layers/c/ad_layer_overwrite.c` (C), `layers/perl/ad_layer_overwrite.pl` (Perl twin)

### Description

Detects adjacent `delete` + `insert` at the same `(line, col)` and
merges them into a single `overwrite_insert` op. Prevents the
"delete then insert" flicker for in-place character replacements.

The merge is suppressed if:
- The previous op was a delete at the same position (would lose info)
- The next-next op is an insert on the same line (would interrupt a
  multi-char insert run)

After merging, walks the output and recomputes `(line, col)`.

### Pseudo-code

```
function layer_overwrite(ops, n_ops):
    out = []
    i = 0
    while i < n_ops:
        can_merge = False
        if i+1 < n_ops
           and ops[i].type == "delete" and ops[i].code != NEWLINE
           and ops[i+1].type == "insert" and ops[i+1].code != NEWLINE
           and ops[i].line == ops[i+1].line
           and ops[i].col == ops[i+1].col:

            # Check prev_is_delete_same_pos
            prev_del_same = (i > 0
                and ops[i-1].type == "delete"
                and ops[i-1].code != NEWLINE
                and ops[i-1].line == ops[i].line
                and ops[i-1].col == ops[i].col)

            # Check next_is_insert_same_line
            next_ins_same = (i+2 < n_ops
                and ops[i+2].type == "insert"
                and ops[i+2].code != NEWLINE
                and ops[i+2].line == ops[i+1].line)

            if not prev_del_same and not next_ins_same:
                can_merge = True

        if can_merge:
            out.append(overwrite_insert, code=ops[i+1].code,
                       line=ops[i+1].line, col=ops[i+1].col)
            i += 2
        else:
            out.append(ops[i])
            i += 1

    # Position walk (same as reorder)
    current_line = out[0].line
    current_col = 1
    for i in 0..len(out):
        if out[i].code != NEWLINE:
            out[i].line = current_line
            out[i].col = current_col
            if out[i].type in ("keep", "insert", "overwrite_insert"):
                current_col++
        else:
            current_line = out[i].line + 1
            current_col = 1
    return out
```

### File example

**Old:** `abc` → **New:** `xbc`

### Ops before

```
HUNK  1  3  1  0  0
delete  1  1  97  'a'
insert  1  1  120 'x'
keep    1  2  98  'b'
keep    1  3  99  'c'
HUNK_END
```

### Ops after

```
HUNK  1  3  1  0  0
overwrite_insert  1  1  120 'x'   ← merged: delete 'a' + insert 'x'
keep              1  2  98  'b'
keep              1  3  99  'c'
HUNK_END
```

### Known problems

**The position walk does NOT handle `\n` deletes correctly.** Unlike
`reorder`, this layer's position walk advances `current_line` for ALL
`\n` ops (including deletes), which is wrong — a `\n` delete joins lines
(content stays on the same line). This causes wrong positions when the
diff has `\n` deletes.

**Test result:** 1/5 pass (alone, without reorder). When combined with
reorder (which fixes positions first), it works better.

---

## 3. `ad_layer_indent_last`

**File:** `layers/c/ad_layer_indent_last.c` (C), `layers/perl/ad_layer_indent_last.pl` (Perl twin)

### Description

When a line with leading whitespace is being deleted, moves the
whitespace deletes to AFTER the content deletes. Prevents the line
from "shifting left" before its content disappears.

Within each segment (bounded by `\n` ops), if the segment starts with
whitespace deletes (space/tab), those are moved to the end. Content
deletes get their `col` bumped by `+n_indent` (because the indent is
still in the buffer when content runs first).

### Pseudo-code

```
function layer_indent_last(ops, n_ops):
    out = []
    seg_start = 0
    for i in 0..n_ops:
        is_boundary = (i == n_ops) OR
                      (ops[i].code == NEWLINE) OR
                      (i > seg_start and ops[i].line != ops[i-1].line)
        if is_boundary:
            # Find leading run of indent deletes (space/tab)
            indent_end = seg_start
            for j in seg_start..i:
                if ops[j].type == "delete"
                   and ops[j].code in (SPACE, TAB):
                    indent_end = j + 1
                else:
                    break
            n_indent = indent_end - seg_start

            if n_indent == 0:
                # No indent deletes — pass through
                out.extend(ops[seg_start..i])
            else:
                # Find \n op at tail
                nl = find_last(ops, indent_end..i, code==NEWLINE)
                content_end = (nl >= 0) ? nl : i

                # Content ops: bump col by +n_indent
                for j in indent_end..content_end:
                    op = ops[j]
                    op.col += n_indent
                    out.append(op)

                # Indent deletes: keep at col 1
                for j in seg_start..indent_end:
                    op = ops[j]
                    op.col = 1
                    out.append(op)

                # \n op: keep as-is
                if nl >= 0:
                    out.append(ops[nl])
            seg_start = i
    return out
```

### File example

**Old:** `    print("hi")` → **New:** `` (line deleted)

### Ops before

```
HUNK  1  13  0  0  0
delete  1  1  32  space      ← 4 spaces deleted first
delete  1  2  32  space
delete  1  3  32  space
delete  1  4  32  space
delete  1  5  112 'p'        ← then content
delete  1  6  114 'r'
delete  1  7  105 'i'
delete  1  8  110 'n'
delete  1  9  116 't'
delete  1  10 10  \n
HUNK_END
```

### Ops after

```
HUNK  1  13  0  0  0
delete  1  9  112 'p'        ← content first (col bumped by +4)
delete  1  10 114 'r'
delete  1  11 105 'i'
delete  1  12 110 'n'
delete  1  13 116 't'
delete  1  14 10  \n
delete  1  1  32  space      ← then indent (col=1)
delete  1  1  32  space
delete  1  1  32  space
delete  1  1  32  space
HUNK_END
```

### Known problems

**Does not recompute `line` values — only adjusts `col`.** When the
diff has `\n` deletes that join lines, the `line` values become stale
after the join. This causes wrong positions.

**Test result:** 1/5 pass (alone, without reorder). The `col` bump
logic is correct, but the `line` values are not recomputed.

---

## 4. `ad_layer_line_delete_in_place`

**File:** `layers/c/ad_layer_line_delete_in_place.c` (C), `layers/perl/ad_layer_line_delete_in_place.pl` (Perl twin)

### Description

When a line is fully deleted (content + `\n`) AND the previous line's
`\n` is also deleted (to join the surviving lines), reorders so the
content is deleted FIRST (on its own line), then the `\n` joins.

**Pattern matched:**
```
delete(\n)            ← joiner \n (joins line N with line N+1)
delete(content)...    ← content deletes on line N+1
delete(\n)            ← content's own \n
```

**Rewritten as:**
```
delete(content)...    ← content deleted first (on line N+1)
delete(\n)            ← content's \n (removes empty line N+1)
[joiner \n stays, re-iterate]
```

### Pseudo-code

```
function layer_line_delete_in_place(ops, n_ops):
    work = copy(ops)              # mutable copy
    out = []
    i = 0
    while i < len(work):
        # Pattern: delete(\n), delete(content)..., delete(\n)
        if i+2 < len(work)
           and work[i].type == "delete"
           and work[i].code == NEWLINE:

            if work[i+1].type == "delete"
               and work[i+1].code != NEWLINE:

                # Collect content deletes
                ce = i + 1
                while ce < len(work)
                      and work[ce].type == "delete"
                      and work[ce].code != NEWLINE:
                    ce++

                # Check: work[ce] is delete(\n)
                if ce < len(work)
                   and work[ce].type == "delete"
                   and work[ce].code == NEWLINE:

                    # Pattern matched!
                    # Emit content (line = joiner.line + 1)
                    for k in i+1..ce:
                        op = work[k]
                        op.line = work[i].line + 1
                        out.append(op)

                    # Emit content's \n (line = joiner.line + 1)
                    op = work[ce]
                    op.line = work[i].line + 1
                    out.append(op)

                    # Decrement later ops by 1 (content's line removed)
                    for k in ce+1..len(work):
                        work[k].line--

                    # Remove emitted ops from work[]
                    remove work[i+1..ce]
                    # DON'T advance i — re-iterate (work[i] is still joiner \n)
                    continue

        # No match — emit unchanged
        out.append(work[i])
        i++
    return out
```

### File example

**Old:**
```
A
B
C
```
**New:** `AC` (B deleted, A and C joined)

### Ops before

```
HUNK  1  3  1  0  0
keep    1  1  65  'A'
delete  1  2  10  \n       ← joiner (joins A and B)
delete  2  1  66  'B'      ← B content (now on line 1!)
delete  2  1  10  \n       ← B's \n
keep    3  1  67  'C'
HUNK_END
```

### Ops after

```
HUNK  1  3  1  0  0
keep    1  1  65  'A'
delete  2  1  66  'B'      ← content first (on line 2)
delete  2  1  10  \n       ← B's \n (removes empty line 2)
delete  1  2  10  \n       ← joiner last (joins A and C)
keep    2  1  67  'C'      ← (line decremented from 3 to 2)
HUNK_END
```

### Known problems

**The decrement logic is wrong.** After the pattern fires:
1. Content + content's `\n` are emitted (2 lines worth of ops removed)
2. Later ops are decremented by 1 (only 1 line removed)

But the joiner `\n` is ALSO still in the stream and will be emitted
later — when it runs, it removes ANOTHER line. So the total line
reduction is 2, but only 1 decrement is applied. This causes later
ops to point to the wrong line.

**Additionally:** The `line + 1` assignment for moved content assumes
the joiner is at `work[i].line`, but after reorder's position walk,
all ops in the segment have the SAME line (the joined line). So
`work[i].line + 1` is wrong — it should be the original line of the
content.

**Test result:** 1/5 pass (alone). When combined with reorder, gets
30/42 (reorder fixes most, LDI breaks some).

---

## 5. `ad_layer_skip_indent`

**File:** `layers/c/ad_layer_skip_indent.c` (C), `layers/perl/ad_layer_skip_indent.pl` (Perl twin)

### Description

When a hunk's only change is leading whitespace (indent change),
wraps the hunk's ops with marker ops so the animator applies them
instantly (no animation). The content is unchanged, so there's nothing
to "watch" being typed.

**Marker ops inserted:**
```
delay  0  indent_skip_start       ← before the hunk's ops
... (original ops, unchanged) ...
delay  <pause_ms>  indent_skip_end ← after the hunk's ops
```

The `pace` layer recognizes these markers and sets delays to 0
(instant) within the skip region, plus adds the specified pause after.

### Pseudo-code

```
function layer_skip_indent(ops, n_ops, pause_ms=300):
    out = []
    i = 0
    while i < n_ops:
        if ops[i] is HUNK header:
            # Collect hunk's ops
            hunk_ops = collect until HUNK_END

            # Check if indent-only: all delete/insert ops are
            # whitespace (space/tab) or \n
            is_indent_only = True
            has_change = False
            for op in hunk_ops:
                if op.type in ("delete", "insert", "overwrite_insert"):
                    has_change = True
                    if op.code not in (SPACE, TAB, NEWLINE):
                        is_indent_only = False
                        break

            if has_change and is_indent_only:
                # Wrap with markers
                out.append(delay, 0, "indent_skip_start")
                out.extend(hunk_ops)
                out.append(delay, pause_ms, "indent_skip_end")
            else:
                out.extend(hunk_ops)
        else:
            out.append(ops[i])
        i++
    return out
```

### File example

**Old:** `def foo():` (no indent) → **New:** `    def foo():` (4-space indent)

### Ops before

```
HUNK  1  1  4  0  0
insert  1  1  32  space
insert  1  1  32  space
insert  1  1  32  space
insert  1  1  32  space
keep    1  1  100 'd'
keep    1  2  101 'e'
keep    1  3  102 'f'
HUNK_END
```

### Ops after

```
HUNK  1  1  4  0  0
delay   0    300  indent_skip_start     ← marker: skip animation
insert  1  1  32  space
insert  1  1  32  space
insert  1  1  32  space
insert  1  1  32  space
keep    1  1  100 'd'
keep    1  2  101 'e'
keep    1  3  102 'f'
delay   300  300  indent_skip_end       ← marker: pause after
HUNK_END
```

### Known problems

**The markers use the `delay` op format, but with custom type strings
(`indent_skip_start`, `indent_skip_end`).** If the `pace` layer runs
AFTER `skip_indent`, it may not recognize these custom types and could
insert additional delays, breaking the "instant" behavior.

**Test result:** 1/5 pass (alone). The layer doesn't modify ops, only
adds markers — but the markers' interaction with `pace` is fragile.

---

## 6. `ad_layer_pace`

**File:** `layers/c/ad_layer_pace.c` (C), `layers/perl/ad_layer_pace.pl` (Perl twin)

### Description

Inserts `delay` ops between content ops to control animation speed.
Does NOT modify, reorder, or add content ops — only inserts timing.

**Delay types:**
- `char` — per-character (normal typing speed)
- `word` — after completing a word batch
- `hunk` — between hunks
- `awd_slow` — AWD: initial slow chars before acceleration
- `awd_fast` — AWD: accelerated word batches
- `awd_skip` — AWD: spaces deleted instantly

### Pseudo-code

```
function layer_pace(ops, n_ops, options):
    out = []
    i = 0
    while i < n_ops:
        if ops[i] is HUNK header:
            out.append(ops[i])
            i++
            continue

        out.append(ops[i])

        if ops[i] in (keep, delete, insert):
            # Compute delay based on pacing mode
            if delete_pacing == "char":
                delay = char_delay_ms
            elif delete_pacing == "word":
                if end_of_word_batch(ops, i):
                    delay = word_pause_ms
                else:
                    delay = char_delay_ms
            elif delete_pacing == "awd":
                if at_word_start(ops, i):
                    delay = awd_slow_ms
                else:
                    delay = awd_fast_ms
            # ... similar for insert_pacing ...

            out.append(delay, delay_ms, delay_type)

        i++
    return out
```

### File example

**Old:** `ab` → **New:** `xb`

### Ops before

```
HUNK  1  2  1  0  0
delete  1  1  97  'a'
insert  1  1  120 'x'
keep    1  2  98  'b'
HUNK_END
```

### Ops after

```
HUNK  1  2  1  0  0
delete  1  1  97  'a'
delay   80  awd_slow         ← delay after delete
insert  1  1  120 'x'
delay   80  awd_slow         ← delay after insert
keep    1  2  98  'b'
delay   1   char             ← delay after keep
HUNK_END
```

### Known problems

**None.** This layer only inserts delays and doesn't modify content
ops. It passes all tests because it doesn't affect end-state.

---

## 7. `ad_layer_highlight`

**File:** `layers/c/ad_layer_highlight.c` (C), `layers/perl/ad_layer_highlight.pl` (Perl twin)

### Description

Inserts decoration ops (highlight, dim, fold, sign, marker) based on
the diff. Does NOT modify content ops — only inserts decorations.

**Decoration op types:**
- `highlight\t<sl>\t<sc>\t<el>\t<ec>\t<type>\t<dur>` — highlight a region
- `dim\t<sl>\t<el>\t<pct>` — dim a line range
- `fold\t<sl>\t<el>` — fold a line range
- `sign\t<line>\t<type>` — place a sign
- `marker\t<line>\t<col>\t<text>` — echo marker text

### Pseudo-code

```
function layer_highlight(ops, n_ops, options):
    out = []
    for each hunk in ops:
        if highlight_mode == "inline":
            for each changed region in hunk:
                out.append(highlight, sl, sc, el, ec, type, duration)
        elif highlight_mode == "word":
            for each changed word in hunk:
                out.append(highlight, sl, sc, el, ec, "word", duration)
        elif highlight_mode == "hunk":
            out.append(highlight, hunk_start, 1, hunk_end, -1, "hunk", duration)

        if dim_unchanged:
            for each unchanged line range:
                out.append(dim, sl, el, dim_pct)

        if fold_unchanged:
            for each unchanged region:
                out.append(fold, sl, el)

        if sign_column:
            for each changed line:
                out.append(sign, line, "add" or "del")

        out.extend(hunk's ops)
    return out
```

### File example

**Old:** `abc` → **New:** `xbc`

### Ops before

```
HUNK  1  3  1  0  0
delete  1  1  97  'a'
insert  1  1  120 'x'
keep    1  2  98  'b'
keep    1  3  99  'c'
HUNK_END
```

### Ops after (with `--highlight=inline`)

```
HUNK  1  3  1  0  0
highlight  1  1  1  1  delete  500    ← decoration before delete
delete     1  1  97  'a'
highlight  1  1  1  1  insert  500   ← decoration before insert
insert     1  1  120 'x'
keep       1  2  98  'b'
keep       1  3  99  'c'
HUNK_END
```

### Known problems

**None.** This layer only inserts decorations and doesn't modify
content ops. It passes all tests because it doesn't affect end-state.

---

## Summary

| Layer                  | Test result (alone)   | Known problem                                                               |
| ---------------------- | --------------------- | --------------------------------------------------------------------------- |
| `reorder`              | **42/42** ✓           | None                                                                        |
| `overwrite`            | 1/5 ✗                 | Position walk doesn't handle `\n` deletes (advances on all `\n`)            |
| `indent_last`          | 1/5 ✗                 | Doesn't recompute `line` values (only adjusts `col`)                        |
| `line_delete_in_place` | 1/5 ✗                 | Decrement logic wrong (off-by-one); `line+1` assignment wrong after reorder |
| `skip_indent`          | 1/5 ✗                 | Marker interaction with `pace` is fragile                                   |
| `pace`                 | 5/5 ✓                 | None (only inserts delays)                                                  |
| `highlight`            | 5/5 ✓                 | None (only inserts decorations)                                             |

### Root cause of failures

Every layer except `reorder` has a position-walk that doesn't correctly
handle `\n` deletes. The correct behavior (from `reorder`):

- `\n` delete: DON'T advance `current_line` (join brings content to same line)
- `\n` keep/insert: advance `current_line` to next line

The other layers either:
- Advance on ALL `\n` ops (wrong for deletes) — `overwrite`
- Don't recompute `line` at all — `indent_last`
- Use a decrement heuristic that's off-by-one — `line_delete_in_place`
- Don't modify positions but rely on other layers being correct — `skip_indent`

### Recommended fix

Every layer that modifies ops should use the SAME position-walk logic
as `reorder`:
1. Walk forward through output
2. For non-`\n` ops: assign `(current_line, current_col)`
3. For `\n` keep/insert: advance `current_line`, reset `current_col`
4. For `\n` delete: DON'T advance (join)

This logic is in `ad_layer_reorder.c` lines 62-110. It should be
extracted into a shared function in `ad_layer_common.h` and called by
every layer after its transform.
