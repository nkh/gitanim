#!/usr/bin/env bash
# snapshot_per_op.sh — Take a snapshot of the buffer after every op
# and produce an HTML visualization.
#
# This is for DEBUGGING the animation. It shows the buffer state
# after every op, so you can see exactly what the animator is doing
# and spot where it goes wrong visually.
#
# Usage:
#   bash scripts/snapshot_per_op.sh <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh tests/minimal/15_join_two_lines/old \
#                                  tests/minimal/15_join_two_lines/new
#
# Output: /tmp/dv_snapshots/snapshots.html
# Open it in a browser: file:///tmp/dv_snapshots/snapshots.html

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD="${1:?Usage: snapshot_per_op.sh <oldfile> <newfile>}"
NEW="${2:?Usage: snapshot_per_op.sh <oldfile> <newfile>}"

OUTDIR=/tmp/dv_snapshots
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

# Run the C pipeline to get the timed ops
RAW="$OUTDIR/raw.txt"
POST="$OUTDIR/post.txt"
TIMED="$OUTDIR/timed.txt"
"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" "$RAW" 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < "$RAW" > "$POST" 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < "$POST" > "$TIMED" 2>/dev/null

# Inject a snapshot op after every keep/delete/insert op.
INJECTED="$OUTDIR/timed_injected.txt"
> "$INJECTED"
idx=0
while IFS= read -r line; do
    echo "$line" >> "$INJECTED"
    first_field=$(echo "$line" | cut -f1)
    if [[ "$first_field" == "keep" || "$first_field" == "delete" || "$first_field" == "insert" ]]; then
        printf 'snapshot\t%s/snap_%04d.txt\n' "$OUTDIR" "$idx" >> "$INJECTED"
        idx=$((idx + 1))
    fi
done < "$TIMED"
total_snaps=$idx
echo "Injected $total_snaps snapshot ops"

# Run the animator with the injected stream — it writes a snapshot
# file after every op.
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 \
    "$OLD" < "$INJECTED" 2>/dev/null || true

# Verify snapshots were written
actual_snaps=$(ls "$OUTDIR"/snap_*.txt 2>/dev/null | wc -l)
echo "Wrote $actual_snaps snapshot files"

# Now build the HTML by walking the timed stream and pairing each op
# with its snapshot.
HTML="$OUTDIR/snapshots.html"
{
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="utf-8">'
    echo '<title>diffvim snapshots — '"$OLD"' → '"$NEW"'</title>'
    echo '<style>'
    echo '  body { font-family: monospace; background: #1e1e1e; color: #d4d4d4; margin: 1em; }'
    echo '  .snapshot { display: inline-block; vertical-align: top; margin: 5px; padding: 5px; background: #2d2d2d; border: 1px solid #555; min-width: 300px; }'
    echo '  .op-info { font-size: 11px; color: #9cdcfe; margin-bottom: 4px; }'
    echo '  .buffer { background: #1e1e1e; padding: 5px; font-size: 12px; line-height: 1.2; white-space: pre; min-height: 1em; }'
    echo '  .op-keep    { color: #6a9955; }'
    echo '  .op-delete  { color: #f44747; }'
    echo '  .op-insert  { color: #b5cea8; }'
    echo '  .op-delay   { color: #808080; }'
    echo '  .op-meta    { color: #569cd6; }'
    echo '  h1 { font-size: 16px; }'
    echo '  .summary { margin-bottom: 1em; padding: 0.5em; background: #2d2d2d; }'
    echo '</style></head><body>'
    echo '<h1>diffvim snapshots</h1>'
    echo '<div class="summary">'
    echo "  <b>OLD:</b> $OLD<br>"
    echo "  <b>NEW:</b> $NEW<br>"
    echo "  <b>Snapshots:</b> $total_snaps"
    echo '</div>'

    snap_idx=0
    op_count=0
    while IFS=$'\t' read -r f1 f2 f3 f4 f5 rest; do
        [[ -z "$f1" || "$f1" == \#* ]] && continue

        op_class=""
        op_type="$f1"
        op_detail=""

        if [[ "$f1" == "HUNK" ]]; then
            op_class="op-meta"
            op_detail="HUNK target=$f2 del=$f3 ins=$f4"
            echo "<div class='snapshot'>"
            echo "  <div class='op-info ${op_class}'>#${op_count} [HUNK] ${op_detail}</div>"
            echo "  <div class='buffer'>(hunk start — no buffer change)</div>"
            echo "</div>"
            op_count=$((op_count + 1))
            continue
        elif [[ "$f1" == "HUNK_END" ]]; then
            op_class="op-meta"
            echo "<div class='snapshot'>"
            echo "  <div class='op-info ${op_class}'>#${op_count} [HUNK_END]</div>"
            echo "  <div class='buffer'>(hunk end — no buffer change)</div>"
            echo "</div>"
            op_count=$((op_count + 1))
            continue
        elif [[ "$f1" == "delay" ]]; then
            op_class="op-delay"
            op_detail="delay ${f2}ms (${f3})"
            echo "<div class='snapshot'>"
            echo "  <div class='op-info ${op_class}'>#${op_count} [delay] ${op_detail}</div>"
            echo "  <div class='buffer'>(no buffer change)</div>"
            echo "</div>"
            op_count=$((op_count + 1))
            continue
        elif [[ "$f1" == "keep" ]]; then
            op_class="op-keep"
            op_detail="keep ($f2,$f3) code=$f4 '$f5'"
        elif [[ "$f1" == "delete" ]]; then
            op_class="op-delete"
            op_detail="delete ($f2,$f3) code=$f4 '$f5'"
        elif [[ "$f1" == "insert" ]]; then
            op_class="op-insert"
            op_detail="insert ($f2,$f3) code=$f4 '$f5'"
        else
            continue
        fi

        snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
        snap_idx=$((snap_idx + 1))

        echo "<div class='snapshot'>"
        echo "  <div class='op-info ${op_class}'>#${op_count} ${op_detail}</div>"

        if [[ -f "$snap_file" ]]; then
            echo "  <div class='buffer'>"
            # HTML-escape and preserve newlines
            sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$snap_file" | \
                awk 'BEGIN{ORS=""} {print; print "\n"}'
            echo "  </div>"
        else
            echo "  <div class='buffer'>(no snapshot)</div>"
        fi
        echo "</div>"
        op_count=$((op_count + 1))
    done < "$TIMED"

    echo '</body></html>'
} > "$HTML"

echo "Wrote $HTML"
echo "Open with: file://$HTML"
echo "Total ops: $op_count, snapshots: $snap_idx"
