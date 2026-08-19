# Intermediary File Formats

All intermediary files in the diffvim pipeline use **TSV (tab-separated values)**. Every file ends with a blank line.

## 1. Raw Diff Format (compute output)

Produced by `diffvim-compute-cpp`. Contains char-level diff ops with positions.

```
# diffvim raw diff v2
# algorithm patience
# semantic_cleanup 0
# word_diff 0
# indent_aware 0
# optimize_sequence 1
# left_to_right 0
# hunk_count N

HUNK	<target_line>	<del_count>	<ins_count>	<is_end_insert>	<is_end_delete>
keep	<line>	<col>	<char_code>	<char_repr>
delete	<line>	<col>	<char_code>	<char_repr>
insert	<line>	<col>	<char_code>	<char_repr>
HUNK_END
...
<blank line>
```

### Fields

| Field | Description |
|-------|-------------|
| `target_line` | 1-indexed line in the old file where the hunk starts |
| `del_count` | Number of lines deleted in this hunk |
| `ins_count` | Number of lines inserted in this hunk |
| `is_end_insert` | 1 if this hunk appends content at end of file |
| `is_end_delete` | 1 if this hunk truncates the end of the file |
| `line` | 1-indexed line number in the buffer |
| `col` | 1-indexed column (character position, not byte) |
| `char_code` | Unicode code point (e.g., 65 for 'A', 10 for newline) |
| `char_repr` | Human-readable: `'A'`, `space`, `\n`, `\t`, `\r` |

### Position tracking

- **keep** and **insert**: advance col by 1
- **delete**: col stays the same (next char slides into position)
- **`\n` (code 10)**: advances line by 1, resets col to 1

### Char representations

| Code | Repr | Description |
|------|------|-------------|
| 10 | `\n` | Newline |
| 9 | `\t` | Tab |
| 13 | `\r` | Carriage return |
| 32 | `space` | Space character |
| 33-126 | `'x'` | Printable ASCII, single-quoted |
| other | `<code>` | Non-ASCII: just the code number |

## 2. Post-Processed Format (postprocess output)

Produced by `diffvim-postprocess`. Same format as raw diff, with ops reordered/transformed and positions recomputed.

```
# diffvim post-processed v2
# semantic_cleanup 0
# optimize_sequence 1
# hunk_count N

HUNK	<target_line>	<del_count>	<ins_count>	<is_end_insert>	<is_end_delete>
keep	<line>	<col>	<char_code>	<char_repr>
delete	<line>	<col>	<char_code>	<char_repr>
insert	<line>	<col>	<char_code>	<char_repr>
HUNK_END
...
<blank line>
```

### What postprocess does

- **Op ordering** (`--transform op-order:optimize`): reorders ops within each line — content deletes before \n deletes, deletes before inserts
- **Semantic cleanup** (`--transform semantic-cleanup`): merges adjacent delete+insert pairs that cancel out
- **Ghost-line fix**: when `delete \n` and the line has kept content, and the next ops are content deletes not followed by keeps, repositions the content deletes to (line+1, 1) and the \n delete to (line+1)

## 3. Timed Ops Format (pace output)

Produced by `diffvim-pace`. Same ops as post-processed, with **delay lines inserted between them**. Pace does NOT modify, reorder, or add any ops — it only inserts delays.

```
# diffvim timed ops v2
# delete_pacing word
# insert_pacing char

HUNK	<target_line>	<del_count>	<ins_count>	<is_end_insert>	<is_end_delete>
keep	<line>	<col>	<char_code>	<char_repr>
delay	<ms>	<type>
delete	<line>	<col>	<char_code>	<char_repr>
delay	<ms>	<type>
delay	<ms>	<type>
HUNK_END
delay	<ms>	<type>
...
<blank line>
```

### Delay format

```
delay	<milliseconds>	<type>
```

Delays have **no position** — they apply after whatever op preceded them. Multiple delays can follow each other.

### Delay types

| Type | Description | When inserted |
|------|-------------|---------------|
| `char` | Per-character (normal typing speed) | After each keep or insert |
| `word` | After completing a word | After a batch of inserts forming a word |
| `hunk` | Between hunks | After HUNK_END, before next HUNK |
| `awd_slow` | AWD: initial slow chars | First 3 chars of a delete run (AWD phase 2) |
| `awd_fast` | AWD: accelerated word batches | After word batches in a delete run (AWD phase 3) |
| `awd_skip` | AWD: spaces deleted instantly | After deleting spaces (AWD phase 1) |

### What pace does

- Reads post-processed ops
- Inserts `delay` lines between ops based on the pacing options
- Passes through all ops **unchanged** — no modification, no reordering, no batching
- Outputs the same ops with delays inserted

## 4. Debugging

Use `scripts/dv_debug.sh` to see all stages:

```bash
scripts/dv_debug.sh oldfile newfile
```

This shows:
1. Input files (with line numbers)
2. Raw diff ops
3. Post-processed ops
4. Timed ops
5. Animator output vs expected result (with match/mismatch indicator)
