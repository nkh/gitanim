#!/usr/bin/env bash
# snapshot_per_op.sh — Take a snapshot of the buffer after every op
# and produce an HTML visualization in LIST format (top-to-bottom).
#
# This is for DEBUGGING the animation. It shows the buffer state
# after every op, so you can see exactly what the animator is doing
# and spot where it goes wrong visually.
#
# Usage:
#   bash scripts/snapshot_per_op.sh <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --show-pacing <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh tests/minimal/15_join_two_lines/old \
#                                  tests/minimal/15_join_two_lines/new
#
# Options:
#   --show-pacing   Include delay ops in the output (default: excluded)
#
# Output: /tmp/dv_snapshots/snapshots.html
# Open in browser: file:///tmp/dv_snapshots/snapshots.html

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SHOW_PACING=0
if [[ "${1:-}" == "--show-pacing" ]]; then
    SHOW_PACING=1
    shift
fi

OLD="${1:?Usage: snapshot_per_op.sh [--show-pacing] <oldfile> <newfile>}"
NEW="${2:?Usage: snapshot_per_op.sh [--show-pacing] <oldfile> <newfile>}"

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

# Run the animator with the injected stream
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 \
    "$OLD" < "$INJECTED" 2>/dev/null || true

# Build the HTML
HTML="$OUTDIR/snapshots.html"
{
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="utf-8">'
    echo '<title>diffvim snapshots — '"$OLD"' → '"$NEW"'</title>'
    echo '<style>'
    echo '  body { font-family: "SF Mono", "Monaco", "Menlo", "Consolas", monospace; background: #1e1e1e; color: #d4d4d4; margin: 0; padding: 1em; }'
    echo '  .entry { margin-bottom: 8px; padding: 8px; background: #2d2d2d; border-left: 3px solid #555; }'
    echo '  .entry.keep    { border-left-color: #6a9955; }'
    echo '  .entry.delete  { border-left-color: #f44747; }'
    echo '  .entry.insert  { border-left-color: #b5cea8; }'
    echo '  .entry.delay   { border-left-color: #808080; background: #252525; }'
    echo '  .entry.meta    { border-left-color: #569cd6; background: #252526; }'
    echo '  .op-header { font-size: 12px; margin-bottom: 4px; display: flex; gap: 1em; }'
    echo '  .op-num    { color: #858585; min-width: 60px; }'
    echo '  .op-type   { font-weight: bold; min-width: 70px; }'
    echo '  .op-type.keep    { color: #6a9955; }'
    echo '  .op-type.delete  { color: #f44747; }'
    echo '  .op-type.insert  { color: #b5cea8; }'
    echo '  .op-type.delay   { color: #808080; }'
    echo '  .op-type.meta    { color: #569cd6; }'
    echo '  .op-pos    { color: #9cdcfe; min-width: 120px; }'
    echo '  .op-char   { color: #ce9178; }'
    echo '  .op-detail { color: #dcdcaa; }'
    echo '  .buffer { background: #1e1e1e; padding: 6px 10px; font-size: 12px; line-height: 1.4; white-space: pre; overflow-x: auto; border: 1px solid #3c3c3c; }'
    echo '  .buffer-empty { color: #808080; font-style: italic; }'
    echo '  h1 { font-size: 16px; color: #fff; }'
    echo '  .summary { margin-bottom: 1em; padding: 0.8em; background: #2d2d2d; border: 1px solid #555; font-size: 13px; }'
    echo '  .summary b { color: #9cdcfe; }'
    echo '  .toggle { cursor: pointer; color: #569cd6; text-decoration: underline; }'
    echo '</style></head><body>'
    echo '<h1>diffvim — per-op snapshots</h1>'
    echo '<div class="summary">'
    echo "  <b>OLD:</b> $OLD<br>"
    echo "  <b>NEW:</b> $NEW<br>"
    echo "  <b>Snapshots:</b> $total_snaps<br>"
    echo "  <b>Pacing:</b> $([ $SHOW_PACING -eq 1 ] && echo 'shown' || echo 'hidden (use --show-pacing to display)')"
    echo '</div>'

    snap_idx=0
    op_count=0
    while IFS=$'\t' read -r f1 f2 f3 f4 f5 rest; do
        [[ -z "$f1" || "$f1" == \#* ]] && continue

        op_class=""
        op_type_label=""
        op_pos=""
        op_char=""
        op_detail=""
        show_buffer=0

        if [[ "$f1" == "HUNK" ]]; then
            op_class="meta"
            op_type_label="HUNK"
            op_detail="target=$f2 del=$f3 ins=$f4 end_ins=$f5 end_del=$rest"
            show_buffer=0
        elif [[ "$f1" == "HUNK_END" ]]; then
            op_class="meta"
            op_type_label="HUNK_END"
            show_buffer=0
        elif [[ "$f1" == "delay" ]]; then
            # Skip delays unless --show-pacing
            if [[ $SHOW_PACING -eq 0 ]]; then
                continue
            fi
            op_class="delay"
            op_type_label="delay"
            op_detail="${f2}ms (${f3})"
            show_buffer=0
        elif [[ "$f1" == "keep" ]]; then
            op_class="keep"
            op_type_label="keep"
            op_pos="(${f2},${f3})"
            op_char="code=$f4 '$f5'"
            show_buffer=1
        elif [[ "$f1" == "delete" ]]; then
            op_class="delete"
            op_type_label="delete"
            op_pos="(${f2},${f3})"
            op_char="code=$f4 '$f5'"
            show_buffer=1
        elif [[ "$f1" == "insert" ]]; then
            op_class="insert"
            op_type_label="insert"
            op_pos="(${f2},${f3})"
            op_char="code=$f4 '$f5'"
            show_buffer=1
        else
            continue
        fi

        echo "<div class='entry ${op_class}'>"
        echo "  <div class='op-header'>"
        echo "    <span class='op-num'>#${op_count}</span>"
        echo "    <span class='op-type ${op_class}'>${op_type_label}</span>"
        [[ -n "$op_pos" ]] && echo "    <span class='op-pos'>${op_pos}</span>"
        [[ -n "$op_char" ]] && echo "    <span class='op-char'>${op_char}</span>"
        [[ -n "$op_detail" ]] && echo "    <span class='op-detail'>${op_detail}</span>"
        echo "  </div>"

        if [[ $show_buffer -eq 1 ]]; then
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            if [[ -f "$snap_file" ]]; then
                echo "  <div class='buffer'>"
                sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$snap_file" | \
                    awk 'BEGIN{ORS=""} {print; print "\n"}'
                echo "  </div>"
            else
                echo "  <div class='buffer buffer-empty'>(no snapshot)</div>"
            fi
        fi
        echo "</div>"
        op_count=$((op_count + 1))
    done < "$TIMED"

    echo '</body></html>'
} > "$HTML"

echo "Wrote $HTML"
echo "Open with: file://$HTML"
echo "Total entries: $op_count, snapshots: $snap_idx"
