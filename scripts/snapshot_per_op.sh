#!/usr/bin/env bash
# snapshot_per_op.sh — Take a snapshot of the buffer after every op
# and produce an HTML visualization in LIST format.
#
# Usage:
#   bash scripts/snapshot_per_op.sh <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --show-keep <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --show-pacing <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --context 3 <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --frame-op <oldfile> <newfile>
#   bash scripts/snapshot_per_op.sh --font-size 16 <oldfile> <newfile>
#
# Options:
#   --show-keep      Show keep ops (default: hidden). When hidden, each
#                    delete/insert entry still shows the buffer state
#                    (the result after the op was applied).
#   --show-pacing    Include delay ops in the output (default: excluded)
#   --context N      Show only N lines of context around the changed line
#                    (default: -1 = show whole buffer; 0 = show only the line)
#   --frame-op       Show a frame/border around each op entry (default: off)
#   --font-size N    Font size in px (default: 14)
#
# Output: /tmp/dv_snapshots/snapshots.html
# Open in browser: file:///tmp/dv_snapshots/snapshots.html

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SHOW_PACING=0
SHOW_KEEP=0
CONTEXT=-1
FRAME_OP=0
FONT_SIZE=14

while [[ $# -gt 0 ]]; do
    case "$1" in
        --show-pacing)   SHOW_PACING=1; shift ;;
        --show-keep)     SHOW_KEEP=1; shift ;;
        --context)       CONTEXT="$2"; shift 2 ;;
        --context=*)     CONTEXT="${1#--context=}"; shift ;;
        --frame-op)      FRAME_OP=1; shift ;;
        --font-size)     FONT_SIZE="$2"; shift 2 ;;
        --font-size=*)   FONT_SIZE="${1#--font-size=}"; shift ;;
        *)               break ;;
    esac
done

OLD="${1:?Usage: snapshot_per_op.sh [options] <oldfile> <newfile>}"
NEW="${2:?Usage: snapshot_per_op.sh [options] <oldfile> <newfile>}"

OUTDIR=/tmp/dv_snapshots
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

# Run the C pipeline
RAW="$OUTDIR/raw.txt"; POST="$OUTDIR/post.txt"; TIMED="$OUTDIR/timed.txt"
echo "Running pipeline (compute → postprocess → pace)..." >&2
"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" "$RAW" 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < "$RAW" > "$POST" 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < "$POST" > "$TIMED" 2>/dev/null

# Inject snapshot after every keep/delete/insert
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

echo "Running animator ($total_snaps ops)..." >&2
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 \
    "$OLD" < "$INJECTED" 2>/dev/null || true

# Build HTML
echo "Building HTML..." >&2
HTML="$OUTDIR/snapshots.html"

if [[ $FRAME_OP -eq 1 ]]; then
    ENTRY_CSS="margin-bottom: 8px; padding: 8px; background: #2d2d2d; border-left: 3px solid #555;"
else
    ENTRY_CSS="margin-bottom: 4px; padding: 2px 0;"
fi

{
    echo '<!DOCTYPE html>'
    echo '<html><head><meta charset="utf-8">'
    echo '<title>diffvim snapshots — '"$OLD"' → '"$NEW"'</title>'
    echo '<style>'
    echo "  body { font-family: \"SF Mono\", \"Monaco\", \"Menlo\", \"Consolas\", monospace; background: #1e1e1e; color: #d4d4d4; margin: 0; padding: 1em; font-size: ${FONT_SIZE}px; }"
    echo "  .entry { ${ENTRY_CSS} }"
    if [[ $FRAME_OP -eq 1 ]]; then
        echo '  .entry.keep    { border-left-color: #6a9955; }'
        echo '  .entry.delete  { border-left-color: #f44747; }'
        echo '  .entry.insert  { border-left-color: #b5cea8; }'
        echo '  .entry.delay   { border-left-color: #808080; background: #252525; }'
        echo '  .entry.meta    { border-left-color: #569cd6; background: #252526; }'
    fi
    echo "  .op-header { font-size: ${FONT_SIZE}px; margin-bottom: 2px; display: flex; gap: 1em; flex-wrap: wrap; }"
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
    echo "  .buffer { background: #1e1e1e; padding: 4px 8px; font-size: ${FONT_SIZE}px; line-height: 1.5; white-space: pre; overflow-x: auto; border: 1px solid #3c3c3c; }"
    echo '  .buffer-empty { color: #808080; font-style: italic; padding: 6px 10px; }'
    echo "  .line-num { display: inline-block; width: 50px; color: #858585; text-align: right; padding-right: 10px; user-select: none; border-right: 1px solid #3c3c3c; margin-right: 10px; }"
    echo '  .line-highlight { background: #264f78; }'
    echo '  .char-keep   { background: #3a6a3a; color: #fff; }'
    echo '  .char-delete { background: #8b0000; color: #fff; text-decoration: line-through; }'
    echo '  .char-insert { background: #2d7a2d; color: #fff; font-weight: bold; }'
    echo "  h1 { font-size: ${FONT_SIZE}px; color: #fff; }"
    echo "  .summary { margin-bottom: 1em; padding: 0.8em; background: #2d2d2d; border: 1px solid #555; font-size: ${FONT_SIZE}px; }"
    echo '  .summary b { color: #9cdcfe; }'
    echo '</style></head><body>'
    echo '<h1>diffvim — per-op snapshots</h1>'
    echo '<div class="summary">'
    echo "  <b>OLD:</b> $OLD<br>"
    echo "  <b>NEW:</b> $NEW<br>"
    echo "  <b>Snaps:</b> $total_snaps<br>"
    echo "  <b>Pacing:</b> $([ $SHOW_PACING -eq 1 ] && echo 'shown' || echo 'hidden')<br>"
    echo "  <b>Keeps:</b> $([ $SHOW_KEEP -eq 1 ] && echo 'shown' || echo 'hidden')<br>"
    echo "  <b>Context:</b> $([ $CONTEXT -eq -1 ] && echo 'whole buffer' || ([ $CONTEXT -eq 0 ] && echo 'changed line' || echo \"${CONTEXT} lines\"))<br>"
    echo "  <b>Font:</b> ${FONT_SIZE}px, <b>Frame:</b> $([ $FRAME_OP -eq 1 ] && echo on || echo off)"
    echo '</div>'

    snap_idx=0
    op_count=0

    while IFS=$'\t' read -r f1 f2 f3 f4 f5 rest; do
        [[ -z "$f1" || "$f1" == \#* ]] && continue

        op_class=""; op_type_label=""; op_pos=""; op_char=""; op_detail=""
        op_line=""; op_col=""; show_entry=0; show_buffer=0

        if [[ "$f1" == "HUNK" ]]; then
            op_class="meta"; op_type_label="HUNK"
            op_detail="target=$f2 del=$f3 ins=$f4 end_ins=$f5 end_del=$rest"
            show_entry=1; show_buffer=0
        elif [[ "$f1" == "HUNK_END" ]]; then
            op_class="meta"; op_type_label="HUNK_END"
            show_entry=1; show_buffer=0
        elif [[ "$f1" == "delay" ]]; then
            [[ $SHOW_PACING -eq 0 ]] && continue
            op_class="delay"; op_type_label="delay"; op_detail="${f2}ms (${f3})"
            show_entry=1; show_buffer=0
        elif [[ "$f1" == "keep" ]]; then
            op_class="keep"; op_type_label="keep"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 '$f5'"
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            if [[ $SHOW_KEEP -eq 1 ]]; then
                show_entry=1; show_buffer=1
            else
                show_entry=0; show_buffer=0
            fi
        elif [[ "$f1" == "delete" ]]; then
            op_class="delete"; op_type_label="delete"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 '$f5'"
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            show_entry=1; show_buffer=1
        elif [[ "$f1" == "insert" ]]; then
            op_class="insert"; op_type_label="insert"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 '$f5'"
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            show_entry=1; show_buffer=1
        else
            continue
        fi

        [[ $show_entry -eq 0 ]] && { op_count=$((op_count + 1)); continue; }

        echo "<div class='entry ${op_class}'>"
        echo "  <div class='op-header'>"
        echo "    <span class='op-num'>#${op_count}</span>"
        echo "    <span class='op-type ${op_class}'>${op_type_label}</span>"
        [[ -n "$op_line" ]] && echo "    <span class='op-pos'>line ${op_line}, col ${op_col}</span>"
        [[ -n "$op_char" ]] && echo "    <span class='op-char'>${op_char}</span>"
        [[ -n "$op_detail" ]] && echo "    <span class='op-detail'>${op_detail}</span>"
        echo "  </div>"

        if [[ $show_buffer -eq 1 && -f "$snap_file" ]]; then
            echo "  <div class='buffer'>"
            # Render buffer with line numbers + highlight the specific char
            awk -v hl_line="$op_line" -v hl_col="$op_col" -v context="$CONTEXT" -v op_type="$f1" '
                BEGIN { n = 0 }
                { lines[++n] = $0 }
                END {
                    if (context == -1) { start = 1; end = n }
                    else if (context == 0) { start = hl_line; end = hl_line }
                    else {
                        start = hl_line - context; end = hl_line + context
                        if (start < 1) start = 1; if (end > n) end = n
                    }
                    for (i = start; i <= end; i++) {
                        gsub(/&/, "\\&amp;", lines[i])
                        gsub(/</, "\\&lt;", lines[i])
                        gsub(/>/, "\\&gt;/", lines[i])
                        if (lines[i] == "") lines[i] = " "
                        if (i == hl_line) {
                            line = lines[i]; len = length(line)
                            before = substr(line, 1, hl_col - 1)
                            if (hl_col <= len) {
                                target = substr(line, hl_col, 1)
                                after = substr(line, hl_col + 1)
                                if (op_type == "delete")
                                    printf "<span class=\"line-num\">%d</span>%s<span class=\"char-delete\">%s</span>%s\n", i, before, target, after
                                else if (op_type == "insert")
                                    printf "<span class=\"line-num\">%d</span>%s<span class=\"char-insert\">%s</span>%s\n", i, before, target, after
                                else if (op_type == "keep")
                                    printf "<span class=\"line-num\">%d</span>%s<span class=\"char-keep\">%s</span>%s\n", i, before, target, after
                                else
                                    printf "<span class=\"line-num\">%d</span><span class=\"line-highlight\">%s</span>\n", i, lines[i]
                            } else {
                                if (op_type == "insert")
                                    printf "<span class=\"line-num\">%d</span>%s<span class=\"char-insert\">[append]</span>\n", i, line
                                else
                                    printf "<span class=\"line-num\">%d</span><span class=\"line-highlight\">%s</span>\n", i, lines[i]
                            }
                        } else {
                            printf "<span class=\"line-num\">%d</span>%s\n", i, lines[i]
                        }
                    }
                }
            ' "$snap_file"
            echo "  </div>"
        fi
        echo "</div>"
        op_count=$((op_count + 1))
    done < "$TIMED"

    echo '</body></html>'
} > "$HTML"

echo "Wrote $HTML" >&2
echo "Open with: file://$HTML" >&2
echo "Total entries: $op_count, snapshots: $snap_idx" >&2
