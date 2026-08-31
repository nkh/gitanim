# Debugging Guide for Postprocess Layers

This guide shows how to debug the postprocess pipeline using the
standalone layer binaries and the bash orchestrator.

## Architecture

The postprocess pipeline is now a chain of standalone binaries:

```
compute → ad_layer_overwrite (optional) → ad_layer_indent_last (optional) → ad_layer_noop → output
```

Each layer reads V2 TSV from stdin and writes V2 TSV to stdout.
The bash orchestrator (`bin/ad_postprocess`) chains them.

## Tools

| Tool | What it does |
|------|-------------|
| `ad_layer_noop` | Reorder ops + position adjustment |
| `ad_layer_indent_last` | Move indent deletes to end of line |
| `ad_layer_overwrite` | Merge delete+insert pairs |
| `ad_layer_adjust` | Standalone position adjustment |
| `ad_layer_line_delete_in_place` | Delete lines on their own line (disabled) |
| `ad` | Apply ops to old file → snapshot |

## Debug Techniques

### 1. Inspect ops at each stage

Pipe raw ops through each layer separately, saving the output:

```bash
AD_LEFT_TO_RIGHT=1 bin/ad_compute old.py new.py raw.txt 2>/dev/null

# See raw ops
cat raw.txt | grep -v '^#'

# Run overwrite, see output
bin/ad_layer_overwrite < raw.txt > after_overwrite.txt
cat after_overwrite.txt | grep -v '^#'

# Run indent-last, see output  
bin/ad_layer_indent_last < after_overwrite.txt > after_indent.txt
cat after_indent.txt | grep -v '^#'

# Run reorder+adjust, see output
bin/ad_layer_noop < after_indent.txt > final.txt
cat final.txt | grep -v '^#'
```

### 2. Compare input vs output of a layer

```bash
diff <(cat input.txt | grep -v '^#') <(ad_layer_noop < input.txt | grep -v '^#')
```

### 3. Validate with the animator

Apply the ops to the old file and check if the result matches:

```bash
ad_layer_noop < raw.txt > post.txt
ad_layer_pace < post.txt > timed.txt
ad --no-display --speed 1000 --snapshot snap.txt old.py < timed.txt
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
ad --no-display --speed 1000 old.py < traced.txt

# View each buffer state
for f in /tmp/trace_*.txt; do
    echo "=== $f ==="
    cat "$f"
done
```

### 5. Debug logging

Set `AD_DEBUG_LAYERS=1` to get debug dumps:

```bash
AD_DEBUG_LAYERS=1 ad_layer_noop < raw.txt > post.txt 2>/dev/null
cat /tmp/ad_debug/postprocess.log
```

### 6. Filter to a specific hunk

If only one hunk is broken, extract it:

```bash
# Extract hunk 2
awk '/^HUNK\t2\t/{show=1} show; /^HUNK_END/{if(show) exit}' raw.txt > hunk2.txt
ad_layer_noop < hunk2.txt
```

## Debugging --indent-last

When --indent-last breaks, the issue is usually position adjustment.
After indent-last moves indent deletes to the end of a line, the
content ops' columns may be wrong.

```bash
# Compare with and without --indent-last
AD_OLD_FILE=old.py bin/ad_compute old.py new.py raw.txt 2>/dev/null

# Without indent-last (should work)
ad_layer_noop < raw.txt > post_no.txt
ad_layer_pace < post_no.txt > timed_no.txt
ad --no-display --speed 1000 --snapshot snap_no.txt old.py < timed_no.txt
diff snap_no.txt new.py  # should match

# With indent-last (may break)
ad_layer_indent_last < raw.txt > after_il.txt
ad_layer_noop < after_il.txt > post_il.txt
ad_layer_pace < post_il.txt > timed_il.txt
ad --no-display --speed 1000 --snapshot snap_il.txt old.py < timed_il.txt
diff snap_il.txt new.py  # may differ

# Find which hunk differs
diff post_no.txt post_il.txt
```

## Debugging --overwrite

When --overwrite breaks, it's usually because the merged overwrite_insert
op has wrong positions.

```bash
# Compare raw vs overwrite output
ad_layer_overwrite < raw.txt > after_ow.txt
diff <(grep -v '^#' raw.txt) <(grep -v '^#' after_ow.txt)
```

## Common Issues

### "Line number is wrong after a join"

The position adjustment in ad_layer_noop handles joins. If a line is
fully deleted and its content appears on the previous line, check
that ad_layer_noop's adjust_positions is running (it always runs).

### "Snapshot doesn't match"

1. Check if the raw ops (from compute) are correct
2. Check each layer's output
3. Use the animator to validate at each stage
4. Compare the failing stage's output with the working stage's output
