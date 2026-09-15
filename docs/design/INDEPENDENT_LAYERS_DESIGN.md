# Design: Independent Layers + Interactive Debug Mode

## Part 1: Making Layers Independent

### Problem

Layers depend on op CONTIGUITY — they look for patterns where ops are
ADJACENT in the stream. When layer A changes op order, it breaks the
contiguity that layer B needs.

| Layer | Pattern required | Why it breaks if reordered |
|-------|-----------------|--------------------------|
| split_in_place | `insert@col1+ + split_line` ADJACENT | Reorder puts deletes before inserts, breaking adjacency |
| line_delete_in_place | `JOIN_LINES + DELETE+` ADJACENT | Reorder puts deletes before joins, breaking adjacency |
| batch_whitespace | `insert(ws)+ ` CONSECUTIVE by col | Reorder puts deletes between inserts |
| reorder | Scans within SEGMENTS (boundaries = is_line_op) | Needs patterns already fixed, or it splits segments wrong |

### Root cause

Layers process ops SEQUENTIALLY and maintain STATE (a buffer of
pending ops). They match patterns by looking at ADJACENT ops. When
another layer changes the order, the adjacency is broken.

### Solution: scan-based pattern matching

Each layer should scan the ENTIRE op stream for its pattern, looking
at SEMANTIC meaning (which line, which col) rather than PHYSICAL
position in the stream.

#### split_in_place (scan-based)

Current: looks for `insert@col1+ ADJACENT WITH split_line(L, K)`
where K = insert_count + 1.

New: for each line L:
1. Find the split_line on L (scan all ops, find split_line with line=L)
2. Find all inserts on L that start at col 1 (scan all ops)
3. Check: split col == (last insert col) + 1
4. If match, move split_line to BEFORE the first insert, change col to 1
5. The inserts and split_line don't need to be adjacent in the stream

Implementation: collect all ops per line, then process per-line.

#### line_delete_in_place (scan-based)

Current: looks for `JOIN_LINES(L)` followed ADJACENTLY by `DELETE(L, col)+`.

New: for each JOIN_LINES(L):
1. Find all DELETE ops on line L that come AFTER the JOIN_LINES
2. Move those DELETEs to BEFORE the JOIN_LINES
3. Change line to L+1, adjust col (col - join_point + 1)

The DELETEs don't need to be adjacent to the JOIN_LINES — just on the
same line and after it in the stream.

#### batch_whitespace (scan-based)

Current: looks for CONSECUTIVE whitespace inserts (adjacent in stream
AND consecutive cols).

New: for each line L:
1. Find all whitespace inserts on L
2. Group them by consecutive COL values (not by stream position)
3. If a group has 2+ inserts, replace with batch_insert

Inserts on the same line with consecutive cols can be batched, even
if they're not adjacent in the stream (e.g., a delete between them
in the stream is fine — the batch_insert just inserts the whitespace,
the delete happens separately).

Wait — this doesn't work. If there's a delete BETWEEN the inserts
in the stream, the animator applies the delete at a specific col.
If the inserts are batched into one op, the animator inserts all
whitespace at once, then the delete happens at the wrong col.

So batch_whitespace DOES require the inserts to be consecutive in
the stream (not just by col). This means it can't be fully
independent of reorder.

BUT: if reorder puts deletes BEFORE inserts, the inserts are still
consecutive (just after the deletes). So batch_whitespace CAN run
after reorder — it just needs to scan the insert group (which is
after the deletes) for consecutive whitespace.

Conclusion: batch_whitespace can run in any order, but the
batching is only applied to consecutive inserts in the stream.
After reorder, the inserts are in a contiguous group — so
batch_whitespace works.

#### reorder (already scan-based)

Reorder scans within segments (ops between line boundaries). It
already handles all op types (via is_line_op and the catch-all in
write_op). No change needed.

### Implementation plan

1. Rewrite split_in_place to be scan-based (scan all ops per line)
2. Rewrite line_delete_in_place Pattern 2 to be scan-based
3. batch_whitespace already works in any order (inserts are consecutive
   after reorder, or before reorder if no deletes on the same line)
4. reorder already works in any order
5. Test: run all 4 orderings of split_in_place + line_delete_in_place
   + reorder + batch_whitespace, verify all produce correct output

---

## Part 2: Interactive Debug Mode for Layers

### What exists

- `ad_postprocess --ad-layer-keep-temps`: keeps intermediate files
  in temp mode (each layer reads/writes a file). Files are named
  `00_input.tsv`, `01_output.tsv`, etc.
- `ad_postprocess --ad-layer-dry-run`: prints the layer chain
- `ad_postprocess --ad-layer-profile`: per-layer timing to stderr
- `ad_debug.sh`: writes raw.txt, post.txt, timed.txt, snap.txt
  (stage-level, not layer-level)
- No layer has a `--debug` flag

### What's missing

1. Per-layer before/after files in PIPE mode (currently only in temp mode)
2. Per-layer logging (what pattern matched, what changed, why)
3. Interactive pause (pause after each layer, analyze before/after)
4. Integration with ad_debug.sh and ad_session

### Design

#### Per-layer before/after files

In PIPE mode, `ad_postprocess` chains layers via pipes. To capture
before/after for each layer, use `tee` to copy the stream at each
stage:

```
input.tsv → tee 00_input.tsv → layer1 → tee 01_after_layer1.tsv → layer2 → tee 02_after_layer2.tsv → ... → output.tsv
```

Implementation: in `ad_postprocess`, when `--ad-layer-keep-temps` is
set AND running in pipe mode, insert a `tee` between each layer.

Actually, simpler: in pipe mode, just run each layer separately
(like temp mode but with pipes):

```bash
# Instead of: layer1 < input | layer2 | layer3 > output
# Do: layer1 < input > 01.tsv; layer2 < 01.tsv > 02.tsv; layer3 < 02.tsv > output
# Then: diff 00_input.tsv 01.tsv  # what layer1 changed
```

This is essentially temp mode. The `--ad-layer-keep-temps` flag
already does this. We just need to make it work in all cases and
integrate it better.

#### Per-layer logging (--debug flag)

Add `--debug` flag to each layer. When set, the layer writes to stderr:

```
[ad_layer_split_in_place] HUNK 8 del=1 ins=13
[ad_layer_split_in_place]   Pattern: line 8, 24 inserts at col 1-24
[ad_layer_split_in_place]   split_line at col 25
[ad_layer_split_in_place]   Action: moved split_line before inserts, col 25 → 1
[ad_layer_split_in_place]   Result: 1 pattern reordered
```

Implementation: add a `debug_log(fmt, ...)` function to each layer.
Guard with `if (debug_mode)`.

#### Interactive pause (--interactive flag)

Add `--interactive` flag to `ad_postprocess`. When set:
1. Run each layer
2. After each layer, show a summary of changes (op count before/after,
   patterns matched)
3. Write before/after to temp files
4. Open `vimdiff before.tsv after.tsv` for visual comparison
5. Wait for user: Enter to continue, q to quit

Implementation: in `ad_postprocess`, when `--interactive` is set:
1. Switch to temp mode (each layer reads/writes files)
2. After each layer, run `vimdiff` on the before/after files
3. Wait for vimdiff to close, then continue

#### Integration with ad_debug.sh

Extend `ad_debug.sh` to support `--layer-debug`:
1. Pass `--ad-layer-keep-temps` to `ad_postprocess`
2. After running, print the temp directory path
3. Print a table: layer name, input ops, output ops, changes

#### Integration with ad_session

Add `--layer-debug` flag to `ad_session`:
1. Pass `--ad-layer-keep-temps` to `ad_gen_ops`
2. In the vim session, add `<leader>D` to open the before/after
   directory in a file browser

### Implementation plan

1. Add `--debug` flag to all layers (split_in_place,
   line_delete_in_place, reorder, batch_whitespace, etc.)
2. Add `debug_log()` function to `ad_layer_common.h`
3. Add logging to each layer's pattern detection and transformation
4. Extend `ad_postprocess --ad-layer-keep-temps` to work in pipe
   mode (run each layer separately, write before/after files)
5. Add `--interactive` flag to `ad_postprocess` (vimdiff between
   layers)
6. Extend `ad_debug.sh` with `--layer-debug` flag
7. Add `--layer-debug` to `ad_session`
8. Document the debug workflow in `docs/src/debugging.md`
