# Multi-File Animation

diffvim can animate diffs across multiple files in a single session. This is
useful for reviewing a commit that touches several files, or for presenting
a refactoring that spans multiple modules.

---

## Usage

### Basic multi-file mode

```bash
diffvim --multi old1.py:new1.py old2.py:new2.py old3.py:new3.py
```

Each argument is an `old:new` pair (colon-separated, absolute or relative
paths). diffvim animates them in order: file 1, then file 2, then file 3.

### With git replay

```bash
# Animate the last 5 commits of multiple files
diffvim --replay src/main.py src/utils.py src/config.py

# Specific commit range
diffvim --replay src/main.py src/utils.py --from v1.0 --to HEAD
```

### Mixed options

```bash
# Multi-file with speed and highlighting
diffvim --multi old1.py:new1.py old2.py:new2.py \
    --speed 0.8 --highlight-hunk --sign-column
```

---

## How It Works

1. diffvim resolves all file pairs at startup.
2. For each pair, it computes the diff and animates it.
3. Between files, a "next file" message is shown briefly.
4. State (hunk index, cursor, line offset) is reset between pairs.
5. After the last file, the animation completes normally.

---

## Controls During Multi-File Animation

All the normal controls work during multi-file animation:

| Key | Action |
|-----|--------|
| `Space` | Pause / resume |
| `n` | Skip to next hunk (or next file if at last hunk) |
| `b` | Back to previous hunk |
| `q` | Stop animation |
| `+`/`-` | Speed up / slow down |

When you press `n` at the last hunk of the current file, diffvim
automatically advances to the next file.

---

## Using External Compute Tools with Multi-File

For large multi-file diffs, pre-computing the diffs with the external
compute tools dramatically speeds up startup:

### Sequential pre-computation

```bash
#!/bin/bash
# Pre-compute all diffs, then animate
WORKDIR=$(mktemp -d)
PAIRS=("old1.py:new1.py" "old2.py:new2.py" "old3.py:new3.py")
PC_FILES=()

for pair in "${PAIRS[@]}"; do
    old="${pair%%:*}"
    new="${pair##*:}"
    pc="$WORKDIR/$(basename $old).diff"
    compute/bin/diffvim-compute-cpp "$old" "$new" "$pc"
    PC_FILES+=("$old:$new:$pc")
done

# Run diffvim with --precomputed for each pair
# (diffvim --precomputed currently takes a single file; for multi-file,
#  use the wrapper script or run sequentially)
for triple in "${PC_FILES[@]}"; do
    old="${triple%%:*}"
    rest="${triple#*:}"
    new="${rest%%:*}"
    pc="${rest##*:}"
    ./diffvim --precomputed "$pc" "$old" "$new"
done

rm -rf "$WORKDIR"
```

### Parallel pre-computation (fastest)

```bash
#!/bin/bash
# Pre-compute all diffs in parallel, then animate
WORKDIR=$(mktemp -d)
PAIRS=("old1.py:new1.py" "old2.py:new2.py" "old3.py:new3.py")

# Launch all compute tools in parallel
PIDS=()
for pair in "${PAIRS[@]}"; do
    old="${pair%%:*}"
    new="${pair##*:}"
    pc="$WORKDIR/$(basename $old).diff"
    compute/bin/diffvim-compute-cpp "$old" "$new" "$pc" &
    PIDS+=($!)
done

# Wait for all to finish
for pid in "${PIDS[@]}"; do
    wait $pid
done

# Now animate (diffs are ready)
echo "All diffs computed. Starting animation..."
# ... run diffvim for each pair
```

**Speedup**: For N files, parallel pre-computation takes `max(compute_time)`
instead of `sum(compute_time)`. For 10 files × 100ms each, that's 100ms
instead of 1000ms.

---

## Tips for Multi-File Review

1. **Use `--startup-feedback`** to see which file is being computed:
   ```bash
   diffvim --multi old1.py:new1.py old2.py:new2.py --startup-feedback
   ```

2. **Use `--output`** to save each result:
   ```bash
   # After each file's animation, the result is written
   diffvim --multi old1.py:new1.py old2.py:new2.py --output results/
   ```

3. **Use `--speed 2`** for quick multi-file review:
   ```bash
   diffvim --multi old1.py:new1.py old2.py:new2.py --speed 2
   ```

4. **Use `--dim-unchanged`** to focus on changed lines across files:
   ```bash
   diffvim --multi old1.py:new1.py old2.py:new2.py --dim-unchanged
   ```
