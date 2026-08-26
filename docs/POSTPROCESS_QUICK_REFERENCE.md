# Postprocess Quick Reference

Compact reference for `animator/c/postprocess.c` operations.
See `POSTPROCESS_OPERATIONS.md` for full detail.

---

### Header Rewriting
Rewrites input header lines to v2 output format.
- Walk collected header lines on stdout.
- `# diffvim raw diff` / `# diffvim precomputed` → `# diffvim post-processed v2`.
- `# semantic_cleanup N` → reflect `do_semantic`.
- `# indent_aware N` → reflect `do_indent`.
- `# optimize_sequence N` → reflect `op_order_optimize`.
- `# hunk_count N` → recompute from `n_hunks`.
- `# word_diff` / `# left_to_right` → pass through verbatim.
- Unknown headers → silently dropped.
- **Trigger:** default (always, batch mode).

### Hunk Emission
Emits per-hunk header and trailer lines.
- For each hunk print `HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>`.
- Walk that hunk's ops through the emit loop.
- Print `HUNK_END`.
- After all hunks print one trailing blank line.
- **Trigger:** default (always).

### optimize_line (4-sweep reorder)
Reorders ops within each line group via 4 sweeps.
- Split ops into change regions delimited by `keep` ops.
- Within each region, flush in 4 sweeps:
  1. Content deletes (`code != 10`).
  2. Content inserts (`code != 10`).
  3. `\n` deletes (`code == 10`).
  4. `\n` inserts (`code == 10`).
- Emit `keep` ops in place between regions.
- Single-op line groups copied verbatim.
- **Trigger:** default (`--op-order optimize`; cleared by `natural`).

### left_to_right_line
Stable 3-pass partition of each line group.
- Sweep 1: emit all `keep` ops in original order.
- Sweep 2: emit all `delete` ops in original order (incl. `\n`).
- Sweep 3: emit all `insert` ops in original order.
- No `\n` special-casing; trailing `\n` delete stays at end of delete sweep.
- **Trigger:** `--op-order left-to-right`.

### end_first_line
Currently identical to `optimize_line`.
- Call `optimize_line(in, count, out)` first.
- Compute `last_non_nl = (in[count-1].code == 10) ? count-2 : n_out-1`.
- Check `out[last_non_nl].type == "delete"` — body is empty (comment only).
- Multi-line handling not yet implemented.
- **Trigger:** `--op-order end-first` (also `end-first-smart`).

### indent_last_transform
Moves leading-whitespace deletes to end of full-line delete.
- Skip if any non-`\n` `keep` or `insert` present (not a pure delete).
- Scan leading run of `delete` ops with `code == 32` or `9` → `indent_end`.
- No leading whitespace → no-op (copy verbatim).
- Rebuild output in 3 sweeps:
  1. Content deletes (from `indent_end` to end, excluding `\n`).
  2. Indentation deletes (leading whitespace run).
  3. `\n` delete (emitted last).
- **Trigger:** `--indent-last`.

### semantic_cleanup
Merges canceling adjacent `delete`+`insert` pairs into `keep`.
- Linear scan from `i = 0`.
- `delete[i]` + `insert[i+1]` same `code` → emit `keep` with that code, `i += 2`.
- `insert[i]` + `delete[i+1]` same `code` → emit `keep` with that code, `i += 2`.
- Else copy `in[i]`, `i += 1`.
- Runs before all other transforms.
- **Trigger:** `--semantic-cleanup`.

### overwrite_transform
Marks adjacent `delete`+`insert` as in-place overwrite.
- Linear scan over final ops.
- If `delete` (code != 10) immediately followed by `insert` (code != 10):
  - Keep the `delete` as-is.
  - Rewrite the `insert` op's `type` to `overwrite_insert`.
  - Advance `i` by 1 (skip the consumed insert).
- Else copy op verbatim.
- Codes need not match — position-based, not value-based.
- **Trigger:** `--overwrite`.

### line_offset Accounting
Carries net newline delta across hunks.
- Initialize `line_offset = 0` before hunk loop.
- Each hunk starts `cur_line = target + line_offset`.
- Track `newl_ins` / `newl_del` during the hunk's emit loop.
- After each hunk: `line_offset += newl_ins - newl_del`.
- **Trigger:** default (always, batch and streaming).

### Per-op Cursor Simulation
Walks final ops, computes `(line, col)` per op.
- State: `cur_line`, `cur_col = 1`, `line_has_content`, `newl_ins`, `newl_del`.
- `keep` code != 10: emit, `cur_col++`, `line_has_content = 1`.
- `keep` code == 10: emit, `cur_line++; cur_col = 1`, reset content.
- `delete` code != 10: emit, cursor unchanged.
- `delete` code == 10: emit `delete \n` at `(cur_line, cur_col)`, advance `cur_line++` if `line_has_content`, else stay; `newl_del++`, `line_has_content = 0`.
- `insert` code != 10: emit, `cur_col++`.
- `insert` code == 10: emit, `cur_line++; cur_col = 1; newl_ins++`.
- `overwrite_insert`: same as `insert` for cursor; emits type string `overwrite_insert`.
- Emit format: `op\t<type>\t<line>\t<col>\t<code>\t<char_repr>`.
- **Trigger:** default (always).

---

## Summary Table

| Operation | Trigger | Reorders | Affected Ops |
|---|---|---|---|
| Header rewriting | default | — (header lines only) | none (metadata) |
| Hunk emission | default | — (structural) | none (framing) |
| `optimize_line` | default (`--op-order optimize`) | within line groups, 4 sweeps | deletes, inserts, `\n` deletes, `\n` inserts |
| `left_to_right_line` | `--op-order left-to-right` | within line groups, 3 sweeps | keeps, then deletes, then inserts |
| `end_first_line` | `--op-order end-first` | identical to `optimize_line` | (same as optimize) |
| `indent_last_transform` | `--indent-last` | moves leading ws deletes to end | deletes in all-delete line groups |
| `semantic_cleanup` | `--semantic-cleanup` | merges adjacent pairs | `delete`+`insert` same code → `keep` |
| `overwrite_transform` | `--overwrite` | rewrites type, no reorder | adjacent `delete`+`insert` → `overwrite_insert` |
| `line_offset` accounting | default | — (cursor base) | `cur_line` per hunk |
| Per-op cursor simulation | default | — (computes positions) | every op |

## Pipeline Order (batch)

```
raw ops
  → [if --semantic-cleanup]      semantic_cleanup
  → [if op_order_optimize]       reorder_hunk_ops
      ├── left-to-right | end-first | optimize | natural
      └── [if --indent-last]    indent_last_transform
  → [if --overwrite]             overwrite_transform
  → emit loop:
        └── per-op cursor sim
```

## Streaming Caveats

`--stream` mode (`stream_process` → `process_one_hunk`) skips:
- `overwrite_transform`

Header `# hunk_count` emitted as `-1`. `end_del` / `end_ins` flags parsed but ignored.
