# Layer Failure Analysis & Architecture Proposal

*Date: 2026-09-08*
*Generated using L1/L2 debugging tool (`scripts/ad_l1l2`)*

## Table of Contents

1. [How the Diff Algorithm Works](#1-how-the-diff-algorithm-works)
2. [The \n Delete Problem](#2-the-n-delete-problem)
3. [Layer-by-Layer Analysis](#3-layer-by-layer-analysis)
   - [ad_layer_reorder](#ad_layer_reorder)
   - [ad_layer_overwrite](#ad_layer_overwrite)
   - [ad_layer_indent_last](#ad_layer_indent_last)
   - [ad_layer_line_delete_in_place](#ad_layer_line_delete_in_place)
   - [ad_layer_skip_indent](#ad_layer_skip_indent)
   - [ad_layer_line_replace](#ad_layer_line_replace)
4. [Proposed Architecture Change](#4-proposed-architecture-change)
5. [How to Debug Each Layer](#5-how-to-debug-each-layer)
6. [Test Examples to Use](#6-test-examples-to-use)

---

## 1. How the Diff Algorithm Works

The diff engine (`bin/ad_compute`) uses a two-level approach:

### Level 1: Line-level Patience Diff

```
old_lines = ["def greet(name):", "    print(...)", "    return None"]
new_lines = []
```

The patience diff finds unique common lines as anchors, then recursively
diffs the ranges between anchors. The output is a sequence of line ops:

```
OP_DELETE(line 0)   ← "def greet(name):"
OP_DELETE(line 1)   ← "    print(...)"
OP_DELETE(line 2)   ← "    return None"
```

### Level 2: Char-level Diff Within Hunks

For each group of consecutive non-keep line ops, the diff engine creates
a **hunk**. It concatenates the old lines (joined with `\n`) and the new
lines (joined with `\n`), then runs a char-level diff on the resulting
strings:

```cpp
// From compute.cpp, lines 740-752:
string old_text, new_text;
for (int k = start; k < end; k++) {
    if (lops[k].type == OP_DELETE) {
        if (h.deleted_count > 0) old_text += '\n';  // ← \n between lines
        old_text += old_lines[lops[k].a_idx];
        h.deleted_count++;
    } else if (lops[k].type == OP_INSERT) {
        if (h.inserted_count > 0) new_text += '\n';  // ← \n between lines
        new_text += new_lines[lops[k].b_idx];
        h.inserted_count++;
    }
}
```

For our example:
- `old_text = "def greet(name):\n    print(\"Hello, \" + name)\n    return None"`
- `new_text = ""` (empty, new file is empty)

The char diff (`anchored_diff`) finds the longest common substring
between `old_text` and `new_text`. Since `new_text` is empty, there are
no common chars — everything is a delete.

The resulting char ops include `\n` (code 10) as regular chars:
```
delete 'd', delete 'e', delete 'f', ..., delete '\n', delete ' ', delete ' ', ...
```

### Op Emission

The diff engine then emits these char ops with `(line, col)` positions.
It walks through the ops, tracking `cur_line` and `cur_col`:

```cpp
int cur_line = adjusted_target;  // hunk's target line
int cur_col = 1;
for (auto& op : h.char_ops) {
    out << type << "\t" << cur_line << "\t" << cur_col << "\t" << code << "\n";
    if (op.code == 10) {  // \n
        if (op.type != OP_DELETE) {
            cur_line++;
            cur_col = 1;
        }
        // For \n delete: col stays (join brings content HERE)
    } else {
        if (op.type == OP_KEEP || op.type == OP_INSERT)
            cur_col++;
        // delete: col stays
    }
}
```

**Key behavior**: when the diff encounters a `\n delete`, it does NOT
advance `cur_line`. The `\n delete` means "join this line with the next".
The content of the next line is brought TO the current line. So subsequent
ops target the same `cur_line`.

---

## 2. The \n Delete Problem

### When does the algorithm decide to delete a \n?

The char-level diff treats `\n` as a regular character. When the old text
contains `\n` (because multiple lines were concatenated) and the new text
doesn't (or has fewer `\n`s), the diff emits `delete \n`.

**This happens whenever a hunk spans multiple old lines that get merged
into fewer new lines.** For example:

- Old: 3 lines → New: 0 lines (all deleted)
  - The `\n` between lines 1-2 and 2-3 are deleted as regular chars

- Old: 2 lines → New: 1 line (lines joined)
  - The `\n` between the two old lines is deleted

### Why this is problematic

The `\n delete` creates a problem for the animator: after joining two
lines, subsequent ops need to target the JOINED line (same line number),
not the next line. But the diff engine's `cur_line` doesn't advance on
`\n delete`, which is correct within a single hunk.

However, the `\n delete` creates issues for layers:

1. **The `\n delete` is interleaved with content deletes.** After
   deleting all chars of line 1, the `\n delete` joins lines 1 and 2.
   Then the content deletes for line 2 follow — but they're at the same
   `cur_line` as line 1 (because `cur_line` didn't advance). This is
   correct for the animator (the content IS on the joined line now), but
   it makes it hard for layers to know which "original line" an op
   belongs to.

2. **Layers that recompute positions (like the old reorder Pass 2) get
   confused.** They see all ops at the same line number and can't
   distinguish between "line 1 content" and "line 2 content that was
   joined into line 1".

3. **The `\n` handling is asymmetric.** `\n delete` doesn't advance
   `cur_line`, but `\n insert` does. This means the op stream's line
   numbers don't follow a simple pattern — they depend on the op type.

### Proposed solution: Don't use \n in char diff

Instead of concatenating lines with `\n` and running a char diff on the
result, the diff engine should:

1. **Diff each line pair independently.** For a hunk that deletes old
   lines 1-3 and inserts new lines 1-5, run char diffs on:
   - old line 1 vs new line 1
   - old line 2 vs new line 2
   - old line 3 vs new line 3
   - (new lines 4-5 are pure inserts)

2. **Handle line-level operations separately.** Line joins (delete \n)
   and line splits (insert \n) should be explicit line-level ops, not
   char-level ops. The diff engine should detect when lines are joined
   or split and emit:
   - `join_lines\t<L>` — join line L and L+1
   - `split_line\t<L>\t<col>` — split line L at col C

3. **OR: Keep the current approach but make it work correctly.** The
   current approach (concatenating with `\n` and char-diffing) CAN work
   if:
   - The diff engine produces correct positions (done — with
     `cumulative_line_shift`)
   - Layers don't recompute positions (done — removed Pass 2 from reorder)
   - Each layer that transforms ops also fixes positions for affected
     and subsequent ops

**The current approach works for the base case (no layers) — 42/42
examples pass. The failures are in layers that modify ops without
fixing positions.**

---

## 3. Layer-by-Layer Analysis

### ad_layer_reorder

**Status: ✓ Works (42/42)**

**What it does:** Reorders ops within each line segment — emits all
deletes first, then all inserts, then keeps. Boundaries (keeps and \n
ops) stay in place.

**What was fixed:** Removed Pass 2 (position recomputation). The layer
now only reorders ops, preserving positions from the diff engine.

**Remaining issues:** None. The layer is correct.

**How to test:**
```bash
bash tests/test_l1l2_layers.sh  # shows 42/42 for reorder
```

---

### ad_layer_overwrite

**Status: ✗ Fails (28/42, 14 failures)**

**What it does:** Detects adjacent `delete` + `insert` at the same
`(line, col)` and merges them into `overwrite_insert`. Only operates on
non-`\n` ops.

**The problem:** The layer has a **position recomputation pass** (lines
59-93 in `ad_layer_overwrite.c`) that rewrites ALL op positions. This
was designed for the old architecture where the diff engine produced
old-coords. Now that the diff engine produces correct positions, this
recomputation **corrupts** them.

**Specific failure:** The position walk (Pass 2) assigns positions based
on a cursor walk that doesn't account for `\n delete` properly. After a
`\n delete`, the walk's `current_line` doesn't advance, but subsequent
ops' positions should still be correct from the diff engine. The
recomputation overwrites them with wrong values.

**Proposed solution:** Remove the position recomputation pass, just like
was done for `ad_layer_reorder`. The layer should only merge ops, not
recompute positions. When merging `delete + insert` into
`overwrite_insert`, keep the original positions.

**What I tried:** Not yet — identified the issue but haven't removed
Pass 2 yet.

**How to debug:**
```bash
# Run L1/L2 on a specific failing example
bin/ad_compute tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py /tmp/raw.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_overwrite < /tmp/raw.tsv > /tmp/post.tsv
./scripts/ad_l1l2 tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py /tmp/post.tsv

# Compare ops before/after overwrite layer
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < /tmp/raw.tsv > /tmp/before.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_overwrite < /tmp/raw.tsv > /tmp/after.tsv
diff /tmp/before.tsv /tmp/after.tsv
```

**Test examples to use:**
- `01_small_python` (L1=0, L2=1) — simplest failure
- `04_shell_script` (L1=16, L2=17) — failure mid-file
- `40_large_csharp` (L1=0, L2=1) — fails at first line

---

### ad_layer_indent_last

**Status: ✓ Works (42/42)**

**What it does:** Moves leading whitespace deletes to AFTER content
deletes. Adjusts content ops' col by +n_indent.

**Why it works:** It correctly adjusts positions for the ops it moves.
The col adjustment is local to the line segment.

**Remaining issues:** None.

---

### ad_layer_line_delete_in_place

**Status: ✗ Fails (31/42, 11 failures)**

**What it does:** Reorders ops so that content is deleted BEFORE the `\n`
is deleted (line join happens after content removal). Two patterns:
1. **DELETE pattern:** `delete(\n)` + `delete(content)` + `delete(\n)` →
   `delete(content)` + `delete(\n)` (reorder)
2. **INSERT pattern:** `insert(content)` + `insert(\n)` → `insert(\n)` +
   `insert(content)` (reorder)

**The problem:** The layer modifies the ORDER of `\n delete` ops relative
to content ops. This changes which ops come before/after the `\n delete`.
After reordering, the positions of subsequent ops may be wrong because
the `\n delete` now happens at a different point in the sequence.

**Specific failure:** When the layer moves `delete(content)` before
`delete(\n)`, the content is deleted while it's still on its own line
(before the join). But the content ops' positions say they're on the
joined line (because the diff engine didn't advance `cur_line` for `\n
delete`). So the animator tries to delete content at the wrong line.

**Proposed solution:** When reordering, the layer must ALSO fix the
positions of the moved ops. If `delete(content)` is moved before
`delete(\n)`, its line number should be the ORIGINAL line (before the
join), not the joined line.

**What I tried:** Not yet — identified the issue but haven't implemented
a fix.

**How to debug:**
```bash
bin/ad_compute tests/examples/07_text_prose/old.txt tests/examples/07_text_prose/new.txt /tmp/raw.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < /tmp/raw.tsv > /tmp/before.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_delete_in_place < /tmp/raw.tsv > /tmp/after.tsv
./scripts/ad_l1l2 tests/examples/07_text_prose/old.txt tests/examples/07_text_prose/new.txt /tmp/after.tsv
diff /tmp/before.tsv /tmp/after.tsv | head -30
```

**Test examples to use:**
- `07_text_prose` (L1=5, L2=6) — simple, small file
- `41_large_ruby` (L1=0, L2=1) — fails at first line
- `42_large_huge_python` (L1=2, L2=3) — large file

---

### ad_layer_skip_indent

**Status: ✗ Fails (40/42, 2 failures)**

**What it does:** Detects indent-only hunks (all changes are whitespace)
and wraps them with delay markers for instant application. Does NOT
modify ops — only adds delay markers.

**The problem:** Since the layer doesn't modify ops, the failure must be
in the delay markers confusing the pace layer or the animator. The
`delay\t0\tindent_skip_start` and `delay\t<pause>\tindent_skip_end`
markers may not be handled correctly by the pace layer.

**Specific failure:** Only 2 examples fail (35_large_perl, 38_large_java).
These likely have indent-only hunks where the skip markers interfere with
the pace layer's delay computation.

**Proposed solution:** Investigate the interaction between skip_indent
markers and the pace layer. The pace layer may be adding delays AFTER
the skip markers, causing the animator to pause when it shouldn't.

**What I tried:** Not yet.

**How to debug:**
```bash
bin/ad_compute tests/examples/38_large_java/old.java tests/examples/38_large_java/new.java /tmp/raw.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_skip_indent < /tmp/raw.tsv > /tmp/post.tsv
./scripts/ad_l1l2 tests/examples/38_large_java/old.java tests/examples/38_large_java/new.java /tmp/post.tsv

# Check if skip markers are present
grep 'indent_skip' /tmp/post.tsv
```

**Test examples to use:**
- `38_large_java` — failing
- `35_large_perl` — failing

---

### ad_layer_line_replace

**Status: ✗ Fails (0/42, all fail)**

**What it does:** For any line that has at least one delete or insert,
collapses ALL its char ops into `delete_line` + `insert_line` (with the
final line text). Even a single-char change produces a full line
replacement.

**The problem:** The layer uses "virtual line" tracking to group ops by
their actual buffer line. But the virtual line tracking is wrong — when
a `\n delete` happens, the virtual line doesn't advance, so multiple
buffer lines' ops get grouped into one virtual line. The layer then emits
ONE `delete_line` + `insert_line` for what should be MULTIPLE lines.

**Specific failure (example 01):**
- Old: 3 lines, New: empty
- All 3 lines' ops are at virtual_line=1 (because `\n delete` doesn't
  advance virtual_line)
- Layer emits ONE `delete_line 1` + `insert_line 1` (empty)
- Animator deletes only line 1, leaves lines 2-3

**Root cause:** The virtual line tracking mirrors the diff engine's
`cur_line` behavior (don't advance on `\n delete`). But the layer needs
to track ACTUAL buffer lines, not the diff engine's walk position.

**Proposed solution:** The layer should simulate the buffer walk:
1. Track the current line as ops are processed
2. When a `\n keep` or `\n insert` is seen, advance to the next line
3. When a `\n delete` is seen, the NEXT line's content comes to the
   current line — but it's still a separate "original line" that needs
   its own `delete_line`
4. For each original line that has changes, emit `delete_line` +
   `insert_line`

**What I tried:**
1. Grouping by op's `line` field — failed because all ops say the same
   line after `\n delete`
2. Virtual line tracking — failed because virtual line doesn't advance
   on `\n delete`
3. Accumulating text per virtual line — failed for the same reason

**How to debug:**
```bash
bin/ad_compute tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py /tmp/raw.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_line_replace < /tmp/raw.tsv > /tmp/post.tsv
cat /tmp/post.tsv  # see what ops are emitted
./scripts/ad_l1l2 tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py /tmp/post.tsv
```

**Test examples to use:**
- `01_small_python` (L1=1, L2=2) — simplest, 3 lines → empty
- `02_large_python` (L1=0, L2=1) — larger, more complex

---

## 4. Proposed Architecture Change

### Current architecture

```
diff engine → [raw ops with \n as char ops]
    ↓
layers (reorder, overwrite, etc.) → [transformed ops]
    ↓
animator (dumb buffer, applies ops as-is)
```

### Problem

The diff engine treats `\n` as a regular character in the char diff.
This means `\n delete` (line join) and `\n insert` (line split) are
interleaved with content ops. Layers that want to operate per-line (like
line_replace, line_delete_in_place) have a hard time because they can't
easily determine which "original line" an op belongs to.

### Proposed change: Separate line-level and char-level ops

Instead of mixing `\n` into the char diff, the diff engine should:

1. **Run the line-level diff** (patience) — produces line ops:
   `KEEP line`, `DELETE line`, `INSERT line`

2. **For each line pair (old line vs new line)**, run a char-level diff.
   This produces char ops that are LOCAL to a single line — no `\n` chars.

3. **Emit line-level structure ops** for joins and splits:
   - `join_lines\t<L>` — join line L with L+1 (was `delete \n`)
   - `split_line\t<L>\t<col>` — split line L at col C (was `insert \n`)

4. **Op stream format:**
   ```
   HUNK <target> <del> <ins>
   keep    <line> <col> <code>     ← char-level ops (no \n)
   delete  <line> <col> <code>
   insert  <line> <col> <code>
   join_lines <line>               ← line-level ops (replaces delete \n)
   split_line  <line> <col>        ← replaces insert \n
   HUNK_END
   ```

### Benefits

- **No `\n` in char ops** — each op is purely about a single character
  on a single line. Layers don't need to handle `\n` specially.
- **Line joins/splits are explicit** — layers can easily detect them
  and handle them correctly.
- **Position tracking is simpler** — `cur_line` always advances after
  a `join_lines` or `split_line` op. No more "don't advance on \n
  delete" confusion.
- **Layers become simpler** — no need for virtual line tracking or
  position recomputation.

### Drawback

This is a significant change to the diff engine and requires updating
all layers and the animator to handle the new op types. But it would
eliminate the root cause of most layer bugs.

### Alternative: Keep current approach, fix layers individually

If the architecture change is too big, the alternative is to fix each
layer to correctly handle `\n` ops:

1. **overwrite**: Remove position recomputation pass (like reorder)
2. **line_delete_in_place**: Fix positions of moved ops
3. **skip_indent**: Fix interaction with pace layer
4. **line_replace**: Simulate buffer walk to track actual lines

This is less work but doesn't address the root cause.

---

## 5. How to Debug Each Layer

### General approach

1. **Run L1/L2** to find where the layer fails:
   ```bash
   bash tests/test_l1l2_layers.sh
   ```

2. **Compare ops before/after the layer:**
   ```bash
   bin/ad_compute old.py new.py /tmp/raw.tsv
   ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < /tmp/raw.tsv > /tmp/before.tsv
   ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_OVERWRITE < /tmp/raw.tsv > /tmp/after.tsv
   diff /tmp/before.tsv /tmp/after.tsv
   ```

3. **Use ad_session for interactive debugging:**
   ```bash
   ./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder --ad-layer=ad_layer_overwrite
   # Press F6 to snapshot, <leader>b to re-run L1/L2
   ```

4. **Use --ad-layer-keep-temps to see intermediate files:**
   ```bash
   ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_overwrite --ad-layer-keep-temps < /tmp/raw.tsv > /tmp/out.tsv
   ls /tmp/ad_postprocess_*/  # intermediate files
   ```

### Per-layer debugging

#### overwrite
```bash
# The issue is the position recomputation pass.
# Compare ops with and without the pass:
grep -v '^#' /tmp/before.tsv | head -20  # correct positions
grep -v '^#' /tmp/after.tsv | head -20   # corrupted positions
```

#### line_delete_in_place
```bash
# The issue is moved ops have wrong positions.
# Look for delete(\n) ops and check if content ops around them
# have correct line numbers:
grep 'delete.*10.*\\\\n' /tmp/after.tsv
```

#### skip_indent
```bash
# The issue is interaction with pace layer.
# Check if skip markers are present and correct:
grep 'indent_skip' /tmp/after.tsv
```

#### line_replace
```bash
# The issue is virtual line tracking.
# Check how many delete_line ops are emitted vs how many lines changed:
grep 'delete_line' /tmp/after.tsv | wc -l
grep 'insert_line' /tmp/after.tsv | wc -l
```

---

## 6. Test Examples to Use

### Simplest failing examples (for quick debugging)

| Layer | Example | L1 | L2 | Why |
|-------|---------|----|----|-----|
| overwrite | 01_small_python | 0 | 1 | 3 lines → empty, simplest |
| line_delete_in_place | 07_text_prose | 5 | 6 | Small text file |
| skip_indent | 38_large_java | — | — | Has indent-only hunks |
| line_replace | 01_small_python | 1 | 2 | 3 lines → empty |

### Large failing examples (for stress testing)

| Layer | Example | L1 | L2 | Lines |
|-------|---------|----|----|-------|
| overwrite | 42_large_huge_python | 3 | 4 | 1221 |
| line_delete_in_place | 42_large_huge_python | 2 | 3 | 1221 |
| skip_indent | 35_large_perl | — | — | 491 |
| line_replace | 42_large_huge_python | 0 | 1 | 1221 |

### Passing examples (to verify fixes don't break)

All 42 examples pass with:
- No layers (raw ops from diff engine)
- `ad_layer_reorder` only
- `ad_layer_reorder + ad_layer_indent_last`
