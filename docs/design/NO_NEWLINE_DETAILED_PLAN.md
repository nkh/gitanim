# Detailed Implementation Plan: Remove \n from Char Ops

*Branch: `refactor/no-newline-in-char-ops`*
*Date: 2026-09-09*

## Executive Summary

Currently the diff engine concatenates old/new lines with `\n` and
runs a single char-level diff. The `\n` chars become `keep \n`,
`delete \n`, `insert \n` ops. This creates problems: `\n delete` doesn't
advance `cur_line`, making position tracking asymmetric and confusing
for layers.

**Change:** Replace `\n` char ops with explicit line-level ops
(`keep_line`, `join_lines`, `split_line`). Char ops never contain
code 10. The diff engine runs per-line char diffs instead of one
big concatenated diff.

---

## Phase 1: Diff Engine Rewrite (C++)

### 1.1 What changes in `diff_engine/cpp/compute.cpp`

**Current flow (lines 740-774):**
```
for each hunk:
    old_text = concat old lines with '\n'
    new_text = concat new lines with '\n'
    char_ops = char_diff(old_text, new_text)  // \n is a regular char
    emit char_ops with (cur_line, cur_col)
```

**New flow:**
```
for each hunk:
    walk through line ops (KEEP/DELETE/INSERT)
    for each line op:
        if KEEP old_line L:
            emit keep_line L
        if DELETE old_line L (no matching insert):
            emit delete char ops for old_lines[L] content
            emit join_lines L  (join L with L+1, removing the line)
        if INSERT new_line M (no matching delete):
            emit split_line at current position
            emit insert char ops for new_lines[M] content
        if DELETE old_line L + INSERT new_line M (1:1 replacement):
            char_ops = char_diff(old_lines[L], new_lines[M])  // no \n!
            emit char_ops
            emit keep_line (advance to next line)
        if DELETE old_lines L1,L2 + INSERT new_line M (N:1 merge):
            char_ops = char_diff(old_lines[L1] + old_lines[L2], new_lines[M])
            but emit join_lines between L1 and L2 instead of delete \n
        if DELETE old_line L + INSERT new_lines M1,M2 (1:N split):
            char_ops = char_diff(old_lines[L], new_lines[M1] + new_lines[M2])
            but emit split_line between M1 and M2 instead of insert \n
```

### 1.2 New op types to emit

```
keep_line\t<L>                    ← line L unchanged, advance to L+1
join_lines\t<L>                   ← join line L with L+1 (delete the \n between them)
split_line\t<L>\t<col>            ← split line L at col C (insert a \n)
```

### 1.3 Position tracking in the new flow

```
cur_line = adjusted_target  (hunk's target line, adjusted by cumulative shift)
cur_col = 1

for each op:
    if char op (keep/delete/insert, code != 10):
        emit op with (cur_line, cur_col)
        if keep or insert: cur_col++
        if delete: cur_col stays
    if keep_line:
        emit keep_line with cur_line
        cur_line++
        cur_col = 1
    if join_lines:
        emit join_lines with cur_line
        // cur_line stays — joined content is on same line
        // cur_col stays — at end of line (where \n was)
    if split_line:
        emit split_line with (cur_line, cur_col)
        cur_line++
        cur_col = 1
```

**Key difference from current:** `join_lines` is an explicit op. The
animator sees it and knows "join these two lines". No more `delete \n`
mixed in with char deletes.

### 1.4 Hunk text construction changes

**Current (lines 740-752):**
```cpp
string old_text, new_text;
for (int k = start; k < end; k++) {
    if (lops[k].type == OP_DELETE) {
        if (h.deleted_count > 0) old_text += '\n';
        old_text += old_lines[lops[k].a_idx];
        h.deleted_count++;
    } else if (lops[k].type == OP_INSERT) {
        if (h.inserted_count > 0) new_text += '\n';
        new_text += new_lines[lops[k].b_idx];
        h.inserted_count++;
    }
}
```

**New:** Don't concatenate. Instead, pair up old/new lines and run
per-line char diffs. For N:M mappings (multiple old → multiple new),
use the existing `char_diff` on the concatenation but with a SPECIAL
marker for line boundaries that becomes `join_lines`/`split_line`
instead of `delete \n`/`insert \n`.

**Approach:** Keep the concatenation, but post-process the char_ops to
replace `\n` ops with line-level ops:

```cpp
// After char_diff produces char_ops (which may contain \n):
// Walk through char_ops, replacing \n ops with line-level ops.
vector<CharOp> final_ops;
for (auto& op : char_ops) {
    if (op.code == 10) {
        if (op.type == OP_KEEP) {
            // Replace with keep_line marker
            final_ops.push_back({OP_KEEP_LINE, 0});  // new op type
        } else if (op.type == OP_DELETE) {
            final_ops.push_back({OP_JOIN_LINES, 0});  // new op type
        } else if (op.type == OP_INSERT) {
            final_ops.push_back({OP_SPLIT_LINE, 0});  // new op type
        }
    } else {
        final_ops.push_back(op);
    }
}
```

**This is simpler than rewriting the hunk construction.** The char diff
stays the same. We just post-process its output to replace `\n` ops
with line-level ops.

### 1.5 Op type enum changes

**Current (`compute.cpp` line 33):**
```cpp
enum OpType { OP_KEEP, OP_DELETE, OP_INSERT };
```

**New:**
```cpp
enum OpType { OP_KEEP, OP_DELETE, OP_INSERT,
              OP_KEEP_LINE, OP_JOIN_LINES, OP_SPLIT_LINE };
```

### 1.6 Emission changes

**Current (lines 800-822):** emits `type\tline\tcol\tcode\tchar_repr`

**New:**
```cpp
for (auto& op : h.char_ops) {
    if (op.type == OP_KEEP_LINE) {
        out << "keep_line\t" << cur_line << "\n";
        cur_line++; cur_col = 1;
    } else if (op.type == OP_JOIN_LINES) {
        out << "join_lines\t" << cur_line << "\n";
        // cur_line stays, cur_col stays
    } else if (op.type == OP_SPLIT_LINE) {
        out << "split_line\t" << cur_line << "\t" << cur_col << "\n";
        cur_line++; cur_col = 1;
    } else {
        // Regular char op
        const char* type = op.type == OP_KEEP ? "keep" :
                           op.type == OP_DELETE ? "delete" : "insert";
        out << type << "\t" << cur_line << "\t" << cur_col << "\t"
            << op.code << "\t" << char_repr(op.code) << "\n";
        if (op.type == OP_KEEP || op.type == OP_INSERT) cur_col++;
    }
}
```

### 1.7 is_end_insert / is_end_delete handling

**Current (lines 754-772):** When `deleted_count == 0` (pure insert),
the diff engine prepends/appends `\n` to `new_text` to handle end-of-file
inserts. When `inserted_count == 0` (pure delete), it prepends/appends
`\n` to `old_text`.

**New:** These become `split_line` (for end-insert) or `join_lines`
(for end-delete). The post-processing step handles this automatically —
the `\n` that was prepended/appended becomes a `split_line` or
`join_lines` op.

### 1.8 cumulative_line_shift

**Current:** `cumulative_line_shift += h.inserted_count - h.deleted_count`

**New:** Same, but `inserted_count` and `deleted_count` still describe
LINE-level changes (how many lines inserted/deleted). The char ops
within the hunk don't affect the line count — only the line-level ops
(`keep_line`, `join_lines`, `split_line`) do.

### 1.9 Tests for Phase 1

```bash
# Verify diff engine produces correct ops (no \n in char ops):
bin/ad_compute tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py /tmp/ops.tsv
grep '	10	' /tmp/ops.tsv  # should find NOTHING (no code 10 in char ops)
grep 'keep_line\|join_lines\|split_line' /tmp/ops.tsv  # should find new op types

# Verify C animator (with new handlers) produces correct output:
# (Phase 2 needed first — animator must handle new ops)
```

### 1.10 Files changed in Phase 1

| File | Change |
|------|--------|
| `diff_engine/cpp/compute.cpp` | Add OP_KEEP_LINE/OP_JOIN_LINES/OP_SPLIT_LINE to enum. Post-process char_ops to replace \n ops with line-level ops. Update emission loop. |

---

## Phase 2: Animator Updates

### 2.1 C animator (`animator/c/ad.c`)

**Remove these `code == 10` handlers:**
- `keep_char(10)` (line 354) — was: advance cursor_l
- `delete_char(10)` (line 367) — was: join lines
- `insert_char(10)` (line 410) — was: split line
- `if (code == 10)` in the delete handler (line 762) — was: special \n delete path

**Add new op handlers in the main loop:**

```c
} else if (strcmp(cmd, "keep_line") == 0 && ntok >= 2) {
    /* keep_line\t<L> — advance to next line */
    int op_line = atoi(toks[1]);
    set_cursor(op_line, 1);
    cursor_l = op_line;  /* already set by set_cursor */
    /* Advance to next line */
    /* (keep_line is a no-op for the buffer — just advance cursor) */
    render();

} else if (strcmp(cmd, "join_lines") == 0 && ntok >= 2) {
    /* join_lines\t<L> — join line L with L+1 */
    int op_line = atoi(toks[1]);
    set_cursor(op_line, 1);
    /* Join: move next line's content to end of current line, delete next line */
    if (cursor_l < n_lines - 1) {
        char *cur = lines[cursor_l];
        char *next = lines[cursor_l + 1];
        int newlen = strlen(cur) + strlen(next) + 1;
        char *joined = malloc(newlen);
        strcpy(joined, cur);
        strcat(joined, next);
        free(lines[cursor_l]);
        free(lines[cursor_l + 1]);
        lines[cursor_l] = joined;
        for (int i = cursor_l + 1; i < n_lines - 1; i++)
            lines[i] = lines[i + 1];
        n_lines--;
    }
    /* disp_l/disp_c NOT updated — visual cursor stays put */
    mark_modified(cursor_l);
    render();

} else if (strcmp(cmd, "split_line") == 0 && ntok >= 3) {
    /* split_line\t<L>\t<col> — split line L at col C */
    int op_line = atoi(toks[1]);
    int op_col = atoi(toks[2]);
    set_cursor(op_line, op_col);
    /* Split: same as insert_char(10) was */
    int byte = char_to_byte(cursor_l, cursor_c);
    char *s = lines[cursor_l];
    char *before = strndup(s, byte);
    char *after = strdup(s + byte);
    free(lines[cursor_l]);
    lines[cursor_l] = before;
    ensure_lines_capacity(n_lines + 1);
    for (int i = n_lines; i > cursor_l + 1; i--)
        lines[i] = lines[i - 1];
    lines[cursor_l + 1] = after;
    n_lines++;
    cursor_l++;
    cursor_c = 0;
    disp_l = cursor_l;
    disp_c = cursor_c;
    mark_modified(cursor_l);
    render();
}
```

**Remove from `keep_char`:** the `if (code == 10)` branch — no longer needed
since `keep_line` is a separate op type.

**Remove from `delete_char`:** the `if (code == 10)` branch — replaced by
`join_lines` handler.

**Remove from `insert_char`:** the `if (code == 10)` branch — replaced by
`split_line` handler.

### 2.2 Vimscript animator (`apps/vim/ad_vim`)

**Remove these `code == 10` handlers:**
- `TimedKeepChar(10)` (line 1840) — was: advance cursor_l
- `TimedDeleteChar(10)` (line 1864) — was: join lines
- `TimedInsertChar(10)` (line 1891) — was: split line
- `if l:del_code != 10` check (line 1924) — was: skip set_cursor for \n delete
- `if l:skip_del_code != 10` check (line 2138) — in skip-to-next-hunk

**Add new op handlers in `TimedProcessBatch`:**

```vim
elseif l:cmd ==# 'keep_line' && len(l:parts) >= 2
    " keep_line\t<L> — advance to next line (no-op for buffer)
    let s:cur_l = str2nr(l:parts[1])
    let s:cur_c = 1

elseif l:cmd ==# 'join_lines' && len(l:parts) >= 2
    " join_lines\t<L> — join line L with L+1
    let s:cur_l = str2nr(l:parts[1])
    if s:cur_l < line('$')
        let l:cur = getline(s:cur_l)
        let l:next = getline(s:cur_l + 1)
        call setline(s:cur_l, l:cur . l:next)
        execute s:cur_l + 1 . 'delete _'
    endif
    let s:needs_redraw = 1

elseif l:cmd ==# 'split_line' && len(l:parts) >= 3
    " split_line\t<L>\t<col> — split line L at col C
    let s:cur_l = str2nr(l:parts[1])
    let s:cur_c = str2nr(l:parts[2])
    let l:line = getline(s:cur_l)
    let l:byte = byteidx(l:line, s:cur_c - 1)
    if l:byte < 0 | let l:byte = strlen(l:line) | endif
    let l:before = l:byte > 0 ? strpart(l:line, 0, l:byte) : ''
    let l:after = strpart(l:line, l:byte)
    call setline(s:cur_l, l:before)
    call append(s:cur_l, l:after)
    let s:cur_l += 1
    let s:cur_c = 1
    let s:needs_redraw = 1
```

### 2.3 Skip-to-next-hunk handler

In both animators, the skip-to-next-hunk code (which applies ops
instantly without rendering) needs to handle the new op types. Currently
it checks for `keep`/`delete`/`insert` — add `keep_line`/`join_lines`/
`split_line`.

### 2.4 Tests for Phase 2

```bash
# C animator (no layers):
pass=0; fail=0
for d in tests/examples/*/; do
    old=$(ls "$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$d"/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    bin/ad_compute "$old" "$new" /tmp/ops.tsv 2>/dev/null
    bin/ad --no-display --speed 1000 --snapshot /tmp/snap.txt "$old" < /tmp/ops.tsv 2>/dev/null
    diff -q "$new" /tmp/snap.txt && pass=$((pass+1)) || fail=$((fail+1))
done
echo "C animator: $pass pass, $fail fail"
# Expected: 42/42

# Vimscript animator (no layers):
pass=0; fail=0
for d in tests/examples/*/; do
    old=$(ls "$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$d"/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    bin/ad_compute "$old" "$new" /tmp/ops.tsv 2>/dev/null
    AD_SYNC=1 timeout 30 ./apps/vim/ad_vim "$old" "$new" --precomputed /tmp/ops.tsv --output /tmp/snap.txt --sync > /dev/null 2>&1
    diff -q "$new" /tmp/snap.txt && pass=$((pass+1)) || fail=$((fail+1))
done
echo "Vimscript: $pass pass, $fail fail"
# Expected: 42/42

# Property tests:
perl tests/test_property.pl
# Expected: 50/50
```

### 2.5 Files changed in Phase 2

| File | Change |
|------|--------|
| `animator/c/ad.c` | Add `keep_line`/`join_lines`/`split_line` handlers. Remove `code==10` branches from `keep_char`/`delete_char`/`insert_char`. Update skip-to-next-hunk. |
| `apps/vim/ad_vim` | Add `keep_line`/`join_lines`/`split_line` handlers in `TimedProcessBatch`. Remove `code==10` branches from `TimedKeepChar`/`TimedDeleteChar`/`TimedInsertChar`. Update skip-to-next-hunk. |

---

## Phase 3: Layer Updates

### 3.1 `layers/c/ad_layer_common.h` — Op parsing

**Add parsing for new op types:**

```c
static int ad_layer_parse_op(const char *line, Op *op) {
    op->text = NULL;
    // ... existing parsing for keep/delete/insert ...

    /* Try keep_line format: keep_line\t<line> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "keep_line") == 0) {
        strcpy(op->type, "keep_line");
        op->line = l; op->col = 0; op->code = 0;
        return 1;
    }
    /* Try join_lines format: join_lines\t<line> */
    if (sscanf(line, "%19s\t%d", type, &l) >= 2 &&
        strcmp(type, "join_lines") == 0) {
        strcpy(op->type, "join_lines");
        op->line = l; op->col = 0; op->code = 0;
        return 1;
    }
    /* Try split_line format: split_line\t<line>\t<col> */
    if (sscanf(line, "%19s\t%d\t%d", type, &l, &c) >= 3 &&
        strcmp(type, "split_line") == 0) {
        strcpy(op->type, "split_line");
        op->line = l; op->col = c; op->code = 0;
        return 1;
    }
    return 0;
}
```

**Update `ad_layer_write_op`:**

```c
static void ad_layer_write_op(Op *op) {
    if (strcmp(op->type, "keep_line") == 0) {
        printf("keep_line\t%d\n", op->line);
    } else if (strcmp(op->type, "join_lines") == 0) {
        printf("join_lines\t%d\n", op->line);
    } else if (strcmp(op->type, "split_line") == 0) {
        printf("split_line\t%d\t%d\n", op->line, op->col);
    } else if (strcmp(op->type, "insert_line") == 0) {
        // ... existing ...
    } else {
        // ... existing standard format ...
    }
}
```

### 3.2 `layers/c/ad_layer_reorder.c`

**Current:** Uses `code == AD_LAYER_CHAR_NEWLINE` to detect segment
boundaries.

**New:** Use `strcmp(type, "keep_line") == 0 || strcmp(type, "join_lines") == 0 || strcmp(type, "split_line") == 0` to detect segment boundaries.

**Simplification:** The position recomputation pass (already removed)
was the main issue. Now the layer just needs to check for the new op
types instead of `code == 10`.

### 3.3 `layers/c/ad_layer_overwrite.c`

**Current:** Checks `ops[i].code != AD_LAYER_CHAR_NEWLINE` to skip `\n` ops.

**New:** No `\n` ops exist. All char ops are non-`\n`. The check becomes
unnecessary — just merge any adjacent delete+insert at the same position.

**Also remove:** The position recomputation pass (lines 59-93) — same
bug as reorder had.

### 3.4 `layers/c/ad_layer_indent_last.c`

**Current:** Checks for `\n` as segment terminator.

**New:** Check for `keep_line`/`join_lines`/`split_line` as segment
terminators.

### 3.5 `layers/c/ad_layer_line_delete_in_place.c`

**Current:** Detects `delete \n` patterns and reorders them.

**New:** `join_lines` is already an explicit op. The layer's DELETE
pattern (`delete(\n)` + `delete(content)` → reorder) becomes: detect
`join_lines` + `delete(content)` and reorder to `delete(content)` +
`join_lines`. The position fix is simpler because `join_lines` carries
its own line number.

### 3.6 `layers/c/ad_layer_skip_indent.c`

**Current:** Checks `code == AD_LAYER_CHAR_NEWLINE` for whitespace detection.

**New:** Line ops (`keep_line`, `join_lines`, `split_line`) are not
whitespace. Check `strcmp(type, "keep_line") == 0` etc. instead.

### 3.7 `layers/c/ad_layer_pace.c`

**Current:** Many checks for `code == AD_LAYER_CHAR_NEWLINE`:
- Lines 394, 493, 584: skip `\n` deletes in AWD (accelerated word delete)
- Line 713: detect end of delete run
- Lines 790, 840: count `\n` inserts as changed lines
- Line 808: skip `\n` inserts in word pacing

**New:** Replace with checks for `join_lines` and `split_line`:
- `join_lines` replaces `delete \n` — same semantics (line join)
- `split_line` replaces `insert \n` — same semantics (line split)
- `keep_line` replaces `keep \n` — same semantics (line boundary)

### 3.8 `layers/c/ad_layer_highlight.c`

**Current:** Checks `code == AD_LAYER_CHAR_NEWLINE` for whitespace detection
(lines 262, 275).

**New:** Check for line op types instead.

### 3.9 `layers/c/ad_layer_line_replace.c`

**Current:** Virtual line tracking that mirrors the diff engine's
`cur_line` (don't advance on `\n delete`).

**New:** Line boundaries are explicit (`keep_line`, `join_lines`,
`split_line`). The layer can simply:
1. Walk ops, collecting char ops between line ops
2. Each group between line ops is one line
3. If the group has any delete or insert, emit `delete_line` + `insert_line`
4. Pass through `keep_line` unchanged
5. Convert `join_lines` to `delete_line` (the line is being removed)
6. Convert `split_line` to `insert_line` (a new line is being created)

**This is a MASSIVE simplification.** The virtual line tracking mess
goes away entirely.

### 3.10 Tests for Phase 3

```bash
# L1/L2 on all layer combinations:
bash tests/test_l1l2_layers.sh
# Expected: 42/42 for ALL combinations

# Standard tests:
bash tests/run_all_examples.sh  # 36/36
perl tests/test_property.pl     # 50/50
make test-layers                # all pass
make test-fuzz                  # 60/60
```

### 3.11 Files changed in Phase 3

| File | Change |
|------|--------|
| `layers/c/ad_layer_common.h` | Add parsing/writing for `keep_line`/`join_lines`/`split_line` |
| `layers/c/ad_layer_reorder.c` | Replace `code==NEWLINE` checks with line-op type checks |
| `layers/c/ad_layer_overwrite.c` | Remove `code!=NEWLINE` checks (all char ops are non-\n). Remove position recomputation pass. |
| `layers/c/ad_layer_indent_last.c` | Replace `code==NEWLINE` checks with line-op type checks |
| `layers/c/ad_layer_line_delete_in_place.c` | Replace `delete \n` detection with `join_lines` detection. Fix positions. |
| `layers/c/ad_layer_skip_indent.c` | Replace `code==NEWLINE` checks with line-op type checks |
| `layers/c/ad_layer_pace.c` | Replace all `code==NEWLINE` checks with line-op type checks |
| `layers/c/ad_layer_highlight.c` | Replace `code==NEWLINE` checks with line-op type checks |
| `layers/c/ad_layer_line_replace.c` | Simplify: use explicit line boundaries instead of virtual line tracking |

---

## Phase 4: Tooling and Perl Twins

### 4.1 `scripts/ad_annotate.c`

**Current:** Uses `CHAR_NEWLINE` (code 10) to detect line boundaries in
keep bundles and to split/join lines in the buffer simulation.

**New:**
- `keep \n` → `keep_line` — detect by type, not code
- `delete \n` → `join_lines` — detect by type
- `insert \n` → `split_line` — detect by type
- Buffer simulation: `join_lines` calls the join function, `split_line`
  calls the split function

### 4.2 `scripts/vim/ad_ops_syntax.vim`

**Add syntax rules:**

```vim
syn match adOpsKeepLine     "^keep_line\t"
syn match adOpsJoinLines    "^join_lines\t"
syn match adOpsSplitLine    "^split_line\t"

" Remove the old \n-specific match:
" syn match adOpsNewline    "^\(keep\|delete\|insert\|overwrite_insert\)\t\d\+\t\d\+\t10\t"
" (no longer needed — no code 10 in char ops)
```

### 4.3 Perl diff engine (`diff_engine/perl/compute.pl`)

Mirror the C++ changes: post-process char_ops to replace `\n` ops with
line-level ops.

### 4.4 Perl animator (`animator/perl/ad.pl`)

Add `keep_line`/`join_lines`/`split_line` handlers. Remove `code==10`
branches.

### 4.5 Perl layer twins

All Perl layer files need the same changes as their C counterparts:
- `layers/perl/ad_layer_reorder.pl`
- `layers/perl/ad_layer_overwrite.pl`
- `layers/perl/ad_layer_indent_last.pl`
- `layers/perl/ad_layer_line_delete_in_place.pl`
- `layers/perl/ad_layer_skip_indent.pl`
- `layers/perl/ad_layer_pace.pl`
- `layers/perl/ad_layer_highlight.pl`

### 4.6 `scripts/ad_l1l2`

No changes needed — it just runs the animator and compares output.

### 4.7 `scripts/vim/ad_session.vim`

No changes needed — it runs the animator externally.

### 4.8 Manpages

Update `man/ad_compute.1`, `man/ad.1`, and layer manpages to mention
the new op types.

### 4.9 Documentation

Update:
- `docs/design/VOCABULARY.md` — add `keep_line`, `join_lines`, `split_line`
- `docs/design/LAYERS_REFERENCE.md` — update op types
- `docs/design/DEVELOPING_A_LAYER.md` — update op types
- `docs/src/plugin-layers.md` — update op types
- `docs/design/NO_NEWLINE_IN_CHAR_OPS.md` — mark as implemented

### 4.10 Tests for Phase 4

```bash
# Perl diff engine produces same output as C++:
diff <(bin/ad_compute old.py new.py /dev/stdout 2>/dev/null) \
     <(perl diff_engine/perl/compute.pl old.py new.py 2>/dev/null)

# Perl animator produces same output as C:
bin/ad_compute old.py new.py /tmp/ops.tsv 2>/dev/null
bin/ad --no-display --snapshot /tmp/c_snap.txt old.py < /tmp/ops.tsv 2>/dev/null
perl animator/perl/ad.pl --no-display --snapshot /tmp/pl_snap.txt old.py < /tmp/ops.tsv 2>/dev/null
diff /tmp/c_snap.txt /tmp/pl_snap.txt
```

### 4.11 Files changed in Phase 4

| File | Change |
|------|--------|
| `scripts/ad_annotate.c` | Replace `CHAR_NEWLINE` checks with line-op type checks |
| `scripts/vim/ad_ops_syntax.vim` | Add syntax for new op types, remove old \n match |
| `diff_engine/perl/compute.pl` | Mirror C++ changes |
| `animator/perl/ad.pl` | Add new op handlers, remove code==10 |
| `layers/perl/ad_layer_*.pl` (7 files) | Mirror C layer changes |
| `man/ad_compute.1` | Document new op types |
| `man/ad.1` | Document new op types |
| `docs/design/VOCABULARY.md` | Add new op types |
| `docs/design/LAYERS_REFERENCE.md` | Update op types |
| `docs/design/DEVELOPING_A_LAYER.md` | Update op types |
| `docs/src/plugin-layers.md` | Update op types |

---

## Phase 5: Testing and Merge

### 5.1 Full test suite

```bash
make test           # all tests
make test-layers    # per-layer C/Perl parity
make test-minimal   # 25 minimal cases
make test-property  # 50 random property tests
make test-examples  # 42 examples through full pipeline
make test-fuzz      # 60 fuzz tests
```

### 5.2 L1/L2 on all layer combinations

```bash
bash tests/test_l1l2_layers.sh
# Expected: 42/42 for ALL combinations
```

### 5.3 Vimscript animator

```bash
# All 42 examples with --sync mode
pass=0; fail=0
for d in tests/examples/*/; do
    old=$(ls "$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$d"/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    bin/ad_compute "$old" "$new" /tmp/ops.tsv 2>/dev/null
    AD_SYNC=1 timeout 30 ./apps/vim/ad_vim "$old" "$new" --precomputed /tmp/ops.tsv --output /tmp/snap.txt --sync > /dev/null 2>&1
    diff -q "$new" /tmp/snap.txt && pass=$((pass+1)) || fail=$((fail+1))
done
echo "Vimscript: $pass pass, $fail fail"
# Expected: 42/42
```

### 5.4 C/Perl parity

```bash
# Diff engine parity
for d in tests/examples/*/; do
    old=$(ls "$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$d"/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    bin/ad_compute "$old" "$new" /tmp/c_ops.tsv 2>/dev/null
    perl diff_engine/perl/compute.pl "$old" "$new" /tmp/pl_ops.tsv 2>/dev/null
    diff -q /tmp/c_ops.tsv /tmp/pl_ops.tsv || echo "PARITY FAIL: $d"
done

# Animator parity
bin/ad --no-display --snapshot /tmp/c_snap.txt old.py < ops.tsv 2>/dev/null
perl animator/perl/ad.pl --no-display --snapshot /tmp/pl_snap.txt old.py < ops.tsv 2>/dev/null
diff /tmp/c_snap.txt /tmp/pl_snap.txt
```

### 5.5 Merge

```bash
git checkout main
git merge refactor/no-newline-in-char-ops
git push
```

---

## Complete File Change List

### C/C++ files (must change)

| # | File | Phase | What changes |
|---|------|-------|-------------|
| 1 | `diff_engine/cpp/compute.cpp` | 1 | Add enum values, post-process char_ops, update emission |
| 2 | `animator/c/ad.c` | 2 | Add 3 new op handlers, remove 3 `code==10` branches, update skip-hunk |
| 3 | `layers/c/ad_layer_common.h` | 3 | Add parsing/writing for 3 new op types |
| 4 | `layers/c/ad_layer_reorder.c` | 3 | Replace `code==NEWLINE` with line-op type checks |
| 5 | `layers/c/ad_layer_overwrite.c` | 3 | Remove `code!=NEWLINE` checks, remove position recomputation |
| 6 | `layers/c/ad_layer_indent_last.c` | 3 | Replace `code==NEWLINE` with line-op type checks |
| 7 | `layers/c/ad_layer_line_delete_in_place.c` | 3 | Replace `delete \n` with `join_lines` detection |
| 8 | `layers/c/ad_layer_skip_indent.c` | 3 | Replace `code==NEWLINE` with line-op type checks |
| 9 | `layers/c/ad_layer_pace.c` | 3 | Replace all `code==NEWLINE` with line-op type checks |
| 10 | `layers/c/ad_layer_highlight.c` | 3 | Replace `code==NEWLINE` with line-op type checks |
| 11 | `layers/c/ad_layer_line_replace.c` | 3 | Simplify: use explicit line boundaries |
| 12 | `scripts/ad_annotate.c` | 4 | Replace `CHAR_NEWLINE` with line-op type checks |

### Vimscript/Shell files (must change)

| # | File | Phase | What changes |
|---|------|-------|-------------|
| 13 | `apps/vim/ad_vim` | 2 | Add 3 new op handlers, remove 3 `code==10` branches |
| 14 | `scripts/vim/ad_ops_syntax.vim` | 4 | Add syntax for new op types |

### Perl files (must change — twins)

| # | File | Phase | What changes |
|---|------|-------|-------------|
| 15 | `diff_engine/perl/compute.pl` | 4 | Mirror C++ changes |
| 16 | `animator/perl/ad.pl` | 4 | Add new op handlers, remove code==10 |
| 17 | `layers/perl/ad_layer_reorder.pl` | 4 | Mirror C changes |
| 18 | `layers/perl/ad_layer_overwrite.pl` | 4 | Mirror C changes |
| 19 | `layers/perl/ad_layer_indent_last.pl` | 4 | Mirror C changes |
| 20 | `layers/perl/ad_layer_line_delete_in_place.pl` | 4 | Mirror C changes |
| 21 | `layers/perl/ad_layer_skip_indent.pl` | 4 | Mirror C changes |
| 22 | `layers/perl/ad_layer_pace.pl` | 4 | Mirror C changes |
| 23 | `layers/perl/ad_layer_highlight.pl` | 4 | Mirror C changes |

### Documentation files (must change)

| # | File | Phase | What changes |
|---|------|-------|-------------|
| 24 | `docs/design/VOCABULARY.md` | 4 | Add `keep_line`, `join_lines`, `split_line` |
| 25 | `docs/design/LAYERS_REFERENCE.md` | 4 | Update op types |
| 26 | `docs/design/DEVELOPING_A_LAYER.md` | 4 | Update op types |
| 27 | `docs/src/plugin-layers.md` | 4 | Update op types |
| 28 | `docs/design/NO_NEWLINE_IN_CHAR_OPS.md` | 5 | Mark as implemented |
| 29 | `docs/design/LAYER_FAILURE_ANALYSIS.md` | 5 | Update with fixed status |
| 30 | `man/ad_compute.1` | 4 | Document new op types |
| 31 | `man/ad.1` | 4 | Document new op types |

### Files that DON'T need changes

| File | Why no change needed |
|------|---------------------|
| `scripts/ad_l1l2` | Just runs animator + compares output |
| `scripts/ad_session` | Just runs animator externally |
| `scripts/vim/ad_session.vim` | Calls external tools, doesn't parse ops |
| `tests/run_all_examples.sh` | Compares output files, not ops |
| `tests/run_minimal_tests.sh` | Same |
| `tests/test_property.pl` | Same |
| `tests/test_l1l2_layers.sh` | Same |
| `pipeline/ad_postprocess` | Passes ops through, doesn't parse content |
| `pipeline/ad_pipeline` | Orchestrates, doesn't parse ops |
| `packaging/ad_write_vimconfig.sh` | Config, not ops |

### Total: 31 files to change (12 C/C++, 2 Vimscript, 9 Perl, 8 docs)

---

## New Op Type Reference

### `keep_line\t<L>`

**Replaces:** `keep\t<L>\t<col>\t10\t\n`

**Semantics:** Line L is unchanged. The animator advances to the next
line (cursor_l++). No buffer modification.

**Animator behavior:** `cursor_l = L; cursor_l++; cursor_c = 0;`

### `join_lines\t<L>`

**Replaces:** `delete\t<L>\t<col>\t10\t\n`

**Semantics:** Join line L with line L+1. The content of line L+1 is
appended to line L, and line L+1 is removed.

**Animator behavior:**
```
lines[L] = lines[L] + lines[L+1]
remove lines[L+1]
n_lines--
```

**Position tracking:** `cur_line` does NOT advance (joined content is
on the same line). `cur_col` stays at the end of line L (where the
join happened).

### `split_line\t<L>\t<col>`

**Replaces:** `insert\t<L>\t<col>\t10\t\n`

**Semantics:** Split line L at column C. The content before col C stays
on line L; the content from col C onward becomes a new line L+1.

**Animator behavior:**
```
before = lines[L][0:col]
after = lines[L][col:]
lines[L] = before
insert new line L+1 with content "after"
n_lines++
cursor_l = L+1
cursor_c = 0
```

**Position tracking:** `cur_line` advances to L+1. `cur_col` resets to 1.

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Post-processing misses edge cases | Medium | Diff produces wrong ops | Test all 42 examples + property tests |
| Layer simplification introduces bugs | Low | L1/L2 catches it | Run L1/L2 after each layer change |
| Perl twins fall behind | Medium | C/Perl parity fails | Do C first, port to Perl, test parity |
| Vimscript has edge cases | Medium | Vim tests fail | Test all 42 with --sync |
| Performance regression | Low | Slower diff | Per-line diff is actually faster (smaller inputs) |
| Existing tests break | Low | Need to update test fixtures | Tests compare output, not ops — should pass |

---

## Execution Order

```
Phase 1: compute.cpp          (1 file, ~100 lines changed)
  ↓ test: grep for code 10 in output (should be 0)
Phase 2: ad.c + ad_vim        (2 files, ~80 lines changed)
  ↓ test: 42/42 examples + 50/50 property (both animators)
Phase 3: 9 layer files        (9 files, mostly deletions/simplifications)
  ↓ test: L1/L2 42/42 for ALL layer combinations
Phase 4: ad_annotate + syntax + 9 Perl twins + 8 docs  (19 files)
  ↓ test: C/Perl parity, full test suite
Phase 5: merge                (0 files)
  ↓ test: everything passes on main
```

Each phase is independently testable. If a phase fails, the previous
phases still work.
