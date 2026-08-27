# Debugging Guide for Postprocess Layers

This guide shows how to debug the postprocess pipeline using the
standalone layer binaries and the bash orchestrator.

## Architecture

The postprocess pipeline is now a chain of standalone binaries:

```
compute → pp_overwrite (optional) → pp_indent_last (optional) → pp_layer1 → output
```

Each layer reads V2 TSV from stdin and writes V2 TSV to stdout.
The bash orchestrator (`animator/bin/diffvim-postprocess`) chains them.

## Tools

| Tool | What it does |
|------|-------------|
| `pp_layer1` | Reorder ops + position adjustment |
| `pp_indent_last` | Move indent deletes to end of line |
| `pp_overwrite` | Merge delete+insert pairs |
| `pp_adjust` | Standalone position adjustment |
| `pp_line_delete_in_place` | Delete lines on their own line (disabled) |
| `diffvim-animator-c` | Apply ops to old file → snapshot |

## Debug Techniques

### 1. Inspect ops at each stage

Pipe raw ops through each layer separately, saving the output:

```bash
DIFFVIM_LEFT_TO_RIGHT=1 compute/bin/diffvim-compute-cpp old.py new.py raw.txt 2>/dev/null

# See raw ops
cat raw.txt | grep -v '^#'

# Run overwrite, see output
animator/bin/pp_overwrite < raw.txt > after_overwrite.txt
cat after_overwrite.txt | grep -v '^#'

# Run indent-last, see output  
animator/bin/pp_indent_last < after_overwrite.txt > after_indent.txt
cat after_indent.txt | grep -v '^#'

# Run reorder+adjust, see output
animator/bin/pp_layer1 < after_indent.txt > final.txt
cat final.txt | grep -v '^#'
```

### 2. Compare input vs output of a layer

```bash
diff <(cat input.txt | grep -v '^#') <(pp_layer1 < input.txt | grep -v '^#')
```

### 3. Validate with the animator

Apply the ops to the old file and check if the result matches:

```bash
pp_layer1 < raw.txt > post.txt
diffvim-pace < post.txt > timed.txt
diffvim-animator-c --no-display --speed 1000 --snapshot snap.txt old.py < timed.txt
diff snap.txt new.py
```

If they match, the ops are valid. If not, the layer broke something.

### 4. Per-op buffer trace

Inject a snapshot op after each op to see the buffer state at each step:

```bash
# Create a timed stream with snapshots
awk '/^(keep|delete|insert|overwrite_insert)\t/ {
    print
    print "snapshot\t/tmp/trace_" NR ".txt"
    next
}
{ print }
' post.txt > traced.txt

# Run the animator
diffvim-animator-c --no-display --speed 1000 old.py < traced.txt

# View each buffer state
for f in /tmp/trace_*.txt; do
    echo "=== $f ==="
    cat "$f"
done
```

### 5. Debug logging

Set `DV_DEBUG_POSTPROCESS=1` to get debug dumps:

```bash
DV_DEBUG_POSTPROCESS=1 pp_layer1 < raw.txt > post.txt 2>/dev/null
cat /tmp/dv_debug/postprocess.log
```

### 6. Filter to a specific hunk

If only one hunk is broken, extract it:

```bash
# Extract hunk 2
awk '/^HUNK\t2\t/{show=1} show; /^HUNK_END/{if(show) exit}' raw.txt > hunk2.txt
pp_layer1 < hunk2.txt
```

## Debugging --indent-last

When --indent-last breaks, the issue is usually position adjustment.
After indent-last moves indent deletes to the end of a line, the
content ops' columns may be wrong.

```bash
# Compare with and without --indent-last
DV_OLD_FILE=old.py compute/bin/diffvim-compute-cpp old.py new.py raw.txt 2>/dev/null

# Without indent-last (should work)
pp_layer1 < raw.txt > post_no.txt
diffvim-pace < post_no.txt > timed_no.txt
diffvim-animator-c --no-display --speed 1000 --snapshot snap_no.txt old.py < timed_no.txt
diff snap_no.txt new.py  # should match

# With indent-last (may break)
pp_indent_last < raw.txt > after_il.txt
pp_layer1 < after_il.txt > post_il.txt
diffvim-pace < post_il.txt > timed_il.txt
diffvim-animator-c --no-display --speed 1000 --snapshot snap_il.txt old.py < timed_il.txt
diff snap_il.txt new.py  # may differ

# Find which hunk differs
diff post_no.txt post_il.txt
```

## Debugging --overwrite

When --overwrite breaks, it's usually because the merged overwrite_insert
op has wrong positions.

```bash
# Compare raw vs overwrite output
pp_overwrite < raw.txt > after_ow.txt
diff <(grep -v '^#' raw.txt) <(grep -v '^#' after_ow.txt)
```

## Common Issues

### "Line number is wrong after a join"

The position adjustment in pp_layer1 handles joins. If a line is
fully deleted and its content appears on the previous line, check
that pp_layer1's adjust_positions is running (it always runs).

### "Snapshot doesn't match"

1. Check if the raw ops (from compute) are correct
2. Check each layer's output
3. Use the animator to validate at each stage
4. Compare the failing stage's output with the working stage's output
