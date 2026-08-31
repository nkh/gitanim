# Postprocess transformations

The postprocess stage (`ad_postprocess`) reads raw char ops
from the compute stage and produces the op stream that the pace
stage will time. It is **the most important stage for animation
quality** — it determines what the animator will actually do.

This document describes every transformation the postprocess
applies, with examples. **Always-on transformations** are applied
by default; **option-dependent transformations** are only applied
when the corresponding flag is given.

## Output format

The postprocess output is v2 TSV (tab-separated values):

```
# ad_vim post-processed v2
# semantic_cleanup 0
# indent_aware 0
# optimize_sequence 1
# hunk_count N
HUNK    <target>        <del>   <ins>   <end_ins>       <end_del>
keep    <line>  <col>   <code>  <char_repr>
delete  <line>  <col>   <code>  <char_repr>
insert  <line>  <col>   <code>  <char_repr>
HUNK_END
```

Positions (line, col) are **1-indexed**. The postprocess OWNS
positioning — the animator reads `(line, col)` from each op and
moves the cursor there before applying the op.

## Always-on transformations

These are applied by default, with no flags needed.

### 1. Per-op (line, col) position computation

Every op gets a `(line, col)` position. The postprocess walks the
ops and simulates the cursor:

- `keep` advances col by 1 (or, for `\n`, advances line and resets col to 1)
- `insert` advances col by 1 (or, for `\n`, advances line and resets col to 1)
- `delete` does NOT advance col (the next char shifts into this position)
- `\n` (code 10) always advances line and resets col

**Example:**

Raw input (from compute):
```
HUNK    2       1       1       0       0
keep    2       1       104     'h'
keep    2       2       101     'e'
delete  2       3       108     'l'
insert  2       3       112     'p'
keep    2       4       112     'p'
keep    2       5       111     'o'
```

The postprocess passes through these positions unchanged (the
compute already emits them in v2 format). The animator reads
them and moves the cursor before each op.

### 2. Op reordering (optimize_sequence, on by default)

Within each "line group" (a sequence of ops terminated by a `\n`
op), the postprocess reorders ops to look like a human editing:

1. **Content deletes first** (delete 'a', delete 'b', ...)
2. **`\n` deletes** (if any)
3. **Inserts** (insert 'x', insert 'y', ...)

Keeps stay in their original position (they don't move).

**Example — without optimize:**
```
keep    2       1       104     'h'
insert  2       2       112     'p'     ← insert before delete (wrong visual)
delete  2       2       101     'e'
keep    2       3       108     'l'
```

**Example — with optimize (default):**
```
keep    2       1       104     'h'
delete  2       2       101     'e'     ← delete first
insert  2       2       112     'p'     ← then insert
keep    2       3       108     'l'
```

This makes the animation look like: keep 'h', delete 'e', insert 'p',
keep 'l' — a natural "replace e with p" visual.

### 3. \n delete last within a line group

When a line is being deleted, the content deletes come first (emptying
the line), then the `\n` delete removes the empty line.

**Example — delete the line "def":**
```
delete  3       1       100     'd'     ← content first
delete  3       1       101     'e'
delete  3       1       102     'f'
delete  3       1       10      \n      ← \n last (line is now empty, can be removed)
```

### 4. End-delete hunk fix (for "delete last line")

When the last line of the file is being deleted, the compute
generates `delete \n, delete content` (the `\n` that precedes the
last line, then the last line's content). The postprocess:

1. Detects the pattern: first op is `delete \n` in an `is_end_delete` hunk
2. Reorders: content deletes first, then `\n` delete
3. Redirects the `\n` delete to `(target_line - 1, 1)` — joining the
   PREVIOUS line with the now-empty last line

**Example — old `"line1\nline2\nline3\n"`, new `"line1\nline2\n"`**

Raw input from compute:
```
HUNK    3       1       0       0       1
delete  3       1       10      \n       ← delete \n first (v1 ordering)
delete  4       1       108     'l'    ← delete 'l' on line 4 (the "line3")
delete  4       1       105     'i'
delete  4       1       110     'n'
delete  4       1       101     'e'
delete  4       1       51      '3'
```

Postprocess output:
```
HUNK    3       1       0       0       1
delete  3       1       108     'l'    ← content first (on line 3)
delete  3       1       105     'i'
delete  3       1       110     'n'
delete  3       1       101     'e'
delete  3       1       51      '3'
delete  2       1       10      \n       ← \n redirected to line 2 (joins line 2 with empty line 3)
```

The animator just applies these ops — no special "last line" handling
needed.

### 5. Hunk end_insert / end_delete flags passed through

The HUNK line carries `end_ins` and `end_del` flags:
- `end_ins=1` — pure insertion at EOF (no need to position cursor, just append)
- `end_del=1` — pure deletion at EOF (the last-line fix above applies)

These flags are computed by the compute stage and passed through
unchanged by the postprocess.

## Option-dependent transformations

These are only applied when the corresponding flag is given.

### `[REMOVED: --semantic-cleanup]` (or `--transform semantic-cleanup`)

Merges adjacent `delete X` + `insert X` pairs (where the chars are
identical) into a single `keep X` op. Also merges `insert X` + `delete X`.

**Example:**
```
# Input:
delete  2       3       108     'l'
insert  2       3       108     'l'

# After semantic-cleanup:
keep    2       3       108     'l'
```

Useful when the diff algorithm produces redundant delete+insert
pairs that cancel out. Off by default.

### `[REMOVED: --indent-aware]` (or `--transform indent-aware`)

Treats indent-only changes (whitespace at start of line) as keeps.
Useful when only the indentation changed (e.g., Python code that
got re-indented).

**Example — old `"    foo"`, new `"\tfoo"`:**
```
# Without [REMOVED: --indent-aware]:
delete  1       1       32      space
delete  1       2       32      space
delete  1       3       32      space
delete  1       4       32      space
insert  1       1       9       \t
insert  1       1       9       \t
keep    1       5       102     'f'

# With [REMOVED: --indent-aware]:
keep    1       1       32      space     ← all converted to keeps
keep    1       2       32      space
keep    1       3       32      space
keep    1       4       32      space
keep    1       1       9       \t
keep    1       1       9       \t
keep    1       5       102     'f'
```

Off by default. Note: the current implementation has a bug — it
checks `$has_del && $has_del` instead of `$has_del && $has_ins`
in the Perl version, so it may not trigger correctly. See the
source for details.

### `[REMOVED: --op-order] natural` (or `--transform op-order:natural`)

Disables op reordering. The ops are emitted in the raw order from
the compute stage, with positions but no reordering.

**Example:**
```
# With [REMOVED: --op-order] optimize (default):
keep    2       1       104     'h'
delete  2       2       101     'e'     ← delete first
insert  2       2       112     'p'     ← then insert
keep    2       3       108     'l'

# With [REMOVED: --op-order] natural:
keep    2       1       104     'h'
insert  2       2       112     'p'     ← raw order
delete  2       2       101     'e'
keep    2       3       108     'l'
```

Useful for debugging — shows what the compute stage actually produced.

### `[REMOVED: --op-order] left-to-right`

Sorts ops within each line by column position: keeps, then deletes,
then inserts. (Different from `optimize` which puts deletes before
inserts within change regions.)

### `[REMOVED: --op-order] end-first` / `[REMOVED: --op-order] end-first-smart`

Detects trailing deletes at the end of a line and moves them BEFORE
the inserts. Useful when a line has both end-deletes and inserts —
deleting the end first looks more natural.

### `[REMOVED: --op-order] overwrite`

Transforms delete+insert sequences into in-place overwrites. The
current implementation just calls `optimize_line` (a no-op alias).
A full implementation would replace `delete 'a' insert 'b'` with a
single "overwrite 'a' with 'b'" op, but the v2 op format doesn't
have an overwrite op type — kept as a placeholder.

### `--transform op-order:MODE`

Same as `[REMOVED: --op-order] MODE`. Multiple `--transform` flags can be
given — they're applied in order.

### `--stream`

Enables streaming mode: reads one hunk at a time and emits it
immediately, without buffering the whole input. Useful for
piped workflows where you want to start the pace stage before
compute is done.

## Transform composition

Transforms are applied in this order:

1. **semantic_cleanup** (if `[REMOVED: --semantic-cleanup]`)
2. **indent_aware** (if `[REMOVED: --indent-aware]`)
3. **op_order** (always — `optimize` by default, `natural` if `[REMOVED: --op-order] natural`)
4. **overwrite** (if `--overwrite`)

The always-on transformations (positioning, end-delete fix) are
applied AFTER the optional transforms, during the output emission phase.

## How to test each transformation

The `tests/minimal/` directory has test cases that exercise each
transformation:

| Test case | Transformation exercised |
|-----------|--------------------------|
| `01_simple_replace` | Op reordering (deletes before inserts) |
| `04_word_replace` | Op reordering for a whole word |
| `05_delete_to_eol` | Content deletes + \n delete last |
| `08_line_replace` | Mixed deletes + inserts + keep \n |
| `09_delete_middle_line` | `\n` delete that joins two lines |
| `11_delete_last_line` | End-delete hunk fix |
| `15_join_two_lines` | `\n` delete (pure join) |
| `16_split_line` | Insert `\n` (split) |
| `17_multi_line_delete` | Multiple `\n` deletes that join lines |
| `18_indent_change` | `[REMOVED: --indent-aware]` (when enabled) |
| `20_unicode` | UTF-8 handling |
| `21_empty_old` | Pure inserts (end-insert hunk) |
| `22_empty_new` | Pure deletes (end-delete hunk) |

Run a single case:
```bash
bash scripts/dv_debug.sh tests/minimal/15_join_two_lines/old \
                          tests/minimal/15_join_two_lines/new
```

Then inspect `/tmp/ad_debug/post.txt` to see the transformation
in action.

## What the postprocess does NOT do

- **Does NOT insert delays** — that's the pace stage's job
- **Does NOT modify op codes** — only reorders and repositions
- **Does NOT add or remove ops** — only the `semantic_cleanup`
  transform merges canceling pairs, and `indent_aware` converts
  deletes/inserts to keeps. Otherwise the op count is preserved.
- **Does NOT handle cursor movement** — the animator moves the
  cursor based on each op's (line, col). The postprocess just
  emits the right (line, col) for each op.

## Common bugs and where to look

### "Animation looks like everything happens at once"

Check `post.txt`:
- Are there content deletes? They should come before inserts.
- Are `\n` deletes at the end of their line group?

### "The next line's content jumps up onto the current line"

This is a symptom of `\n` deletes happening BEFORE content deletes
on the joined line. Check `post.txt`:
- Are `\n` deletes coming LAST in their line group (after content deletes)?
- The 4-sweep reorder in Layer 1 should already handle this.
- Is the line `delete \n` op at the right position?

### "The last line isn't being deleted"

Check:
- Is the hunk's `end_del=1` flag set in `raw.txt`?
- Is the first op in the hunk `delete \n`?
- Is the `\n delete` redirected to `(line-1, 1)` in `post.txt`?

### "Positions are all wrong"

Check `raw.txt` — the compute stage emits positions. If they're
wrong there, it's a compute bug. If they're right in `raw.txt` but
wrong in `post.txt`, it's a postprocess bug.

### "An op outside a HUNK block is being skipped"

The postprocess prints a WARNING when ops appear outside any HUNK
block. Check your `raw.txt` for missing HUNK/HUNK_END boundaries.
