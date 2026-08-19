#!/usr/bin/env bash
# snapshot_per_op.sh — Take a snapshot of the buffer after every op
# and produce an HTML visualization in LIST format.
#
# Usage:
#   bash scripts/snapshot_per_op.sh <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --show-pacing <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --context 3 <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --context 0 <oldfile> <newfile>
#
# Options:
#   --show-pacing   Include delay ops in the output (default: excluded)
#   --context N     Show only N lines of context around the changed line
#                   (default: -1 = show whole buffer; 0 = show only the line)
#
# Output: /tmp/dv_snapshots/snapshots.html
# Open in browser: file:///tmp/dv_snapshots/snapshots.html

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SHOW_PACING=0
CONTEXT=-1  # -1 = whole buffer, 0 = just the line, N = N lines around

while [[ $# -gt 0 ]]; do
    case "$1" in
        --show-pacing)
            SHOW_PACING=1
            shift
            ;;
        --context)
            CONTEXT="$2"
            shift 2
            ;;
        --context=*)
            CONTEXT="${1#--context=}"
            shift
            ;;
        *)
            break
            ;;
    esac
done

OLD="${1:?Usage: snapshot_per_op.sh [--show-pacing] [--context N] <oldfile> <newfile>}"
NEW="${2:?Usage: snapshot_per_op.sh [--show-pacing] [--context N] <oldfile> <newfile>}"

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

# Also record the op's (line, col) for each snapshot so we can highlight
# the right line in the HTML.
OP_POSITIONS="$OUTDIR/op_positions.txt"
> "$OP_POSITIONS"
snap_idx=0
while IFS=$'\t' read -r f1 f2 f3 f4 f5 rest; do
    if [[ "$f1" == "keep" || "$f1" == "delete" || "$f1" == "insert" ]]; then
        echo -e "${f1}\t${f2}\t${f3}\t${f4}\t${f5}"
        snap_idx=$((snap_idx + 1))
    fi
done < "$TIMED" > "$OP_POSITIONS"

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
    echo '  .op-header { font-size: 12px; margin-bottom: 4px; display: flex; gap: 1em; flex-wrap: wrap; }'
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
    echo '  .buffer { background: #1e1e1e; padding: 0; font-size: 12px; line-height: 1.4; white-space: pre; overflow-x: auto; border: 1px solid #3c3c3c; }'
    echo '  .buffer-empty { color: #808080; font-style: italic; padding: 6px 10px; }'
    echo '  .line-num { display: inline-block; width: 40px; color: #858585; text-align: right; padding-right: 10px; user-select: none; border-right: 1px solid #3c3c3c; margin-right: 10px; }'
    echo '  .line-content { display: inline; }'
    echo '  .line-highlight { background: #264f78; }'
    echo '  .line-highlight-delete { background: #5a1d1d; }'
    echo '  .line-highlight-insert { background: #1e3a1e; }'
    echo '  .cursor-marker { background: #ffd700; color: #000; font-weight: bold; }'
    echo '  h1 { font-size: 16px; color: #fff; }'
    echo '  .summary { margin-bottom: 1em; padding: 0.8em; background: #2d2d2d; border: 1px solid #555; font-size: 13px; }'
    echo '  .summary b { color: #9cdcfe; }'
    echo '</style></head><body>'
    echo '<h1>diffvim — per-op snapshots</h1>'
    echo '<div class="summary">'
    echo "  <b>OLD:</b> $OLD<br>"
    echo "  <b>NEW:</b> $NEW<br>"
    echo "  <b>Snapshots:</b> $total_snaps<br>"
    echo "  <b>Pacing:</b> $([ $SHOW_PACING -eq 1 ] && echo 'shown' || echo 'hidden (use --show-pacing)')<br>"
    echo "  <b>Context:</b> $([ $CONTEXT -eq -1 ] && echo 'whole buffer' || ([ $CONTEXT -eq 0 ] && echo 'changed line only' || echo \"${CONTEXT} lines around\"))"
    echo '</div>'

    snap_idx=0
    op_count=0
    # Read op_positions in parallel
    exec 3<"$OP_POSITIONS"
    while IFS=$'\t' read -r f1 f2 f3 f4 f5 rest; do
        [[ -z "$f1" || "$f1" == \#* ]] && continue

        op_class=""
        op_type_label=""
        op_pos=""
        op_char=""
        op_detail=""
        show_buffer=0
        op_line=""

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
            op_line="$f2"
            show_buffer=1
        elif [[ "$f1" == "delete" ]]; then
            op_class="delete"
            op_type_label="delete"
            op_pos="(${f2},${f3})"
            op_char="code=$f4 '$f5'"
            op_line="$f2"
            show_buffer=1
        elif [[ "$f1" == "insert" ]]; then
            op_class="insert"
            op_type_label="insert"
            op_pos="(${f2},${f3})"
            op_char="code=$f4 '$f5'"
            op_line="$f2"
            show_buffer=1
        else
            continue
        fi

        echo "<div class='entry ${op_class}'>"
        echo "  <div class='op-header'>"
        echo "    <span class='op-num'>#${op_count}</span>"
        echo "    <span class='op-type ${op_class}'>${op_type_label}</span>"
        [[ -n "$op_pos" ]] && echo "    <span class='op-pos'>line ${op_line}, col ${f3:-?}</span>"
        [[ -n "$op_char" ]] && echo "    <span class='op-char'>${op_char}</span>"
        [[ -n "$op_detail" ]] && echo "    <span class='op-detail'>${op_detail}</span>"
        echo "  </div>"

        if [[ $show_buffer -eq 1 ]]; then
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            if [[ -f "$snap_file" ]]; then
                echo "  <div class='buffer'>"
                # Render with line numbers and highlight
                # HTML-escape each line, add line number, highlight the op's line
                awk -v highlight="$op_line" -v context="$CONTEXT" '
                    BEGIN {
                        # Read all lines into array
                        n = 0
                    }
                    {
                        lines[++n] = $0
                    }
                    END {
                        # Determine range to print
                        if (context == -1) {
                            start = 1
                            end = n
                        } else if (context == 0) {
                            start = highlight
                            end = highlight
                        } else {
                            start = highlight - context
                            end = highlight + context
                            if (start < 1) start = 1
                            if (end > n) end = n
                        }
                        for (i = start; i <= end; i++) {
                            # HTML-escape the line
                            gsub(/&/, "\\&amp;", lines[i])
                            gsub(/</, "\\&lt;", lines[i])
                            gsub(/>/, "\\&gt;/", lines[i])
                            # Replace empty lines with a space so they render
                            if (lines[i] == "") lines[i] = " "
                            # Highlight the op line
                            cls = ""
                            if (i == highlight) cls = " class=\"line-highlight\""
                            printf "<span class=\"line-num\">%d</span><span%s>%s</span>\n", i, cls, lines[i]
                        }
                    }
                ' "$snap_file"
                echo "  </div>"
            else
                echo "  <div class='buffer buffer-empty'>(no snapshot)</div>"
            fi
        fi
        echo "</div>"
        op_count=$((op_count + 1))
    done < "$TIMED"
    exec 3<&-

    echo '</body></html>'
} > "$HTML"

echo "Wrote $HTML"
echo "Open with: file://$HTML"
echo "Total entries: $op_count, snapshots: $snap_idx"
