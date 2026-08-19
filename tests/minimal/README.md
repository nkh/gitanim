# Minimal test cases for debugging the diffvim pipeline

Each subdirectory contains an `old` and `new` file designed to exercise
one specific transformation. Use them to isolate where a bug is.

## Quick start

```bash
cd /home/z/my-project/gitanim

# Run the debugger on one case:
bash scripts/dv_debug.sh tests/minimal/01_simple_replace/old \
                          tests/minimal/01_simple_replace/new

# Or run the full pipeline and check the output:
./animator/diffvim-pipeline tests/minimal/01_simple_replace/old \
                              tests/minimal/01_simple_replace/new

# Run ALL minimal cases (script coming soon):
for d in tests/minimal/*/; do
    echo "=== $d ==="
    bash scripts/dv_debug.sh "$d/old" "$d/new" 2>&1 | tail -3
done
```

## What each case tests

| # | Directory | What it tests |
|---|-----------|---------------|
| 01 | `01_simple_replace` | One char replaced mid-line (no \n involved) |
| 02 | `02_simple_insert` | One char inserted mid-line (no \n involved) |
| 03 | `03_simple_delete` | One char deleted mid-line (no \n involved) |
| 04 | `04_word_replace` | A whole word replaced |
| 05 | `05_delete_to_eol` | Delete from cursor to end of line |
| 06 | `06_insert_at_eol` | Insert at end of line |
| 07 | `07_insert_at_bol` | Insert at beginning of line |
| 08 | `08_line_replace` | One line completely replaced (delete + insert + \n keep) |
| 09 | `09_delete_middle_line` | A whole line removed (not first, not last) |
| 10 | `10_delete_first_line` | The first line removed |
| 11 | `11_delete_last_line` | The last line removed |
| 12 | `12_insert_line_at_end` | A new line appended at EOF |
| 13 | `13_insert_line_at_start` | A new line inserted at the top |
| 14 | `14_insert_line_in_middle` | A new line inserted between existing lines |
| 15 | `15_join_two_lines` | Two lines joined into one (delete \n between them) |
| 16 | `16_split_line` | One line split into two (insert \n in the middle) |
| 17 | `17_multi_line_delete` | Multiple lines deleted in a row |
| 18 | `18_indent_change` | Only indentation changed |
| 19 | `19_trailing_whitespace` | Trailing whitespace added/removed |
| 20 | `20_unicode` | Unicode chars (é, ✓, emoji) inserted/deleted |
| 21 | `21_empty_old` | Empty old file, non-empty new file |
| 22 | `22_empty_new` | Non-empty old file, empty new file |
| 23 | `23_identical_files` | Old and new are identical (no ops) |
| 24 | `24_pure_add_at_eof` | Pure addition at EOF (no \n delete) |
| 25 | `25_complex_mix` | Multiple changes interleaved in one hunk |

## What to look for in the post-processed output

The post-processed file (`post.txt`) is the most important stage to
debug — it shows what the animator will actually do.

### Per-op (line, col) sanity

Each `keep`, `delete`, `insert` op carries `(line, col)`. Walk through
them mentally:

```
HUNK	2	1	1	0	0          ← hunk at line 2, 1 del, 1 ins
keep	2	1	104	'h'          ← cursor at (2,1), keep 'h', advance to col 2
keep	2	2	101	'e'          ← cursor at (2,2), keep 'e', advance to col 3
delete	2	3	108	'l'          ← cursor at (2,3), delete 'l' (col stays)
delete	2	3	108	'l'          ← cursor at (2,3), delete 'l' (col stays)
insert	2	3	112	'p'          ← cursor at (2,3), insert 'p' (advance to col 4)
keep	2	4	112	'p'          ← cursor at (2,4), keep 'p' (already inserted)
keep	2	5	111	'o'          ← cursor at (2,5), keep 'o'
HUNK_END
```

Check:
- `keep` ops should advance col by 1 each time
- `insert` ops should advance col by 1 each time
- `delete` ops should NOT advance col (the next char shifts in)
- `\n` (code 10) advances line, resets col to 1
- The hunk target line + (inserts - deletes) of \n = next hunk's target

### Ordering: deletes before inserts

Within a line group, content deletes should come BEFORE content inserts.
This makes the animation look like the human is deleting the old text
first, then typing the new text.

```
# Good: deletes first
delete	2	3	108	'l'
delete	2	3	108	'l'
insert	2	3	112	'p'
insert	2	3	114	'r'

# Bad: inserts first (wrong visual order)
insert	2	3	112	'p'
insert	2	3	114	'r'
delete	2	3	108	'l'
delete	2	3	108	'l'
```

### \n delete placement

A `delete \n` should come AFTER content deletes within the same line,
so the line content is emptied before the line is removed.

```
# Good: content first, \n last
delete	3	1	100	'd'
delete	3	1	101	'e'
delete	3	1	102	'f'
delete	3	1	10	\n

# Bad: \n first (the line is removed before its content)
delete	3	1	10	\n
delete	3	1	100	'd'
delete	3	1	101	'e'
delete	3	1	102	'f'
```

### Ghost-line pattern (delete \n that joins)

When a `delete \n` would join two lines, the postprocess redirects
the next line's content deletes to `(line+1, 1)` BEFORE the \n delete:

```
# Old: "hello world\nfoo"   New: "hello foo"
# Postprocess output:
keep	1	1	104	'h'          ← keep "hello "
...
keep	1	7	32	space
delete	2	1	119	'w'          ← delete 'w' on line 2 (not line 1!)
delete	2	1	111	'o'          ← delete 'o' on line 2
...
delete	2	1	100	'd'          ← delete 'd' on line 2
delete	2	1	10	\n           ← then delete \n (joining empty line 2 with line 1)
keep	2	1	102	'f'          ← cursor back on (joined) line 1, keep 'foo'
```

Without this fix, the next line's content would visually jump up onto
the current line before being deleted.

## What to look for in the timed output

The timed file (`timed.txt`) is what the animator reads. Check:
- Each `delay\t<ms>\t<type>` line — type should be `char`, `word`,
  `hunk`, `awd_slow`, `awd_fast`, or `awd_skip`
- Delays should be reasonable (50ms for normal typing, 40ms for
  delete, 250ms between hunks)
- The `--speed N` flag divides each delay by N
