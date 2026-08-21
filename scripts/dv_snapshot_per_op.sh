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
#   --no-buffer-frame  Remove the thin frame around the buffer (default: on)
#   --font-size N    Font size in px (default: 14)
#
# Output: /tmp/dv_snapshots/snapshots.html
# Open in browser: file:///tmp/dv_snapshots/snapshots.html

show_help() {
cat <<'HELP'
NAME
    dv_snapshot_per_op.sh — Per-op HTML snapshot visualizer for diffvim

SYNOPSIS
    dv_snapshot_per_op.sh [-h|--help]
    dv_snapshot_per_op.sh [options] <oldfile> <newfile>

DESCRIPTION
    Runs the diffvim pipeline (compute → postprocess → pace) on an
    old/new file pair, then takes a snapshot of the animator's buffer
    after every keep / delete / insert op and renders all those
    snapshots into a single browsable HTML page (one entry per op,
    with the changed character highlighted).

    The HTML page is written to /tmp/dv_snapshots/snapshots.html —
    open it in a browser to step through the animation op-by-op.

OPTIONS
    -h, --help              Show this help message and exit 0.
    --show-keep             Show keep ops (default: hidden). When
                            hidden, each delete/insert entry still
                            shows the buffer state (the result after
                            the op was applied).
    --show-pacing           Include delay ops in the output
                            (default: excluded).
    --context N             Show only N lines of context around the
                            changed line (default: -1 = show whole
                            buffer; 0 = show only the changed line).
    --frame-op              Show a frame/border around each op entry
                            (default: off).
    --no-buffer-frame       Remove the thin frame around the buffer
                            (default: on — frame is shown).
    --font-size N           Font size in px (default: 14).
    --trace                 Enable the op-tracing debugging UI: each op
                            gets a "📋 Copy" button. Clicking it appends
                            the op's TSV line to a bottom panel (20% of
                            viewport height, fixed). The bottom panel has
                            a "Copy to clipboard" button that copies all
                            collected ops as TSV text — useful for
                            reporting exactly which ops cause a bug.
    <oldfile>               Path to the original/source file.
    <newfile>               Path to the target file.

EXAMPLES
    dv_snapshot_per_op.sh examples/01_small_python/old.py \
                          examples/01_small_python/new.py
        Build a full-buffer, default-styled HTML visualization.

    dv_snapshot_per_op.sh --show-keep --show-pacing old.txt new.txt
        Include keep ops and delay ops in the visualization.

    dv_snapshot_per_op.sh --context 3 old.txt new.txt
        Show only 3 lines of context around each change.

    dv_snapshot_per_op.sh --frame-op --font-size 16 old.txt new.txt
        Render with per-op frames and a 16px font.

    dv_snapshot_per_op.sh --no-buffer-frame old.txt new.txt
        Render without the thin buffer border.

    dv_snapshot_per_op.sh --trace old.txt new.txt
        Enable the tracing UI: click ops to collect them in the
        bottom panel, then copy to clipboard for bug reports.

OUTPUT
    /tmp/dv_snapshots/snapshots.html
    Open with: file:///tmp/dv_snapshots/snapshots.html
HELP
}

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SHOW_PACING=0
SHOW_KEEP=0
CONTEXT=-1
FRAME_OP=0
BUFFER_FRAME=1
FONT_SIZE=14
TRACE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)                       show_help; exit 0 ;;
        --show-pacing|--show_pacing)     SHOW_PACING=1; shift ;;
        --show-keep|--show_keep)         SHOW_KEEP=1; shift ;;
        --context)                       CONTEXT="$2"; shift 2 ;;
        --context=*)                     CONTEXT="${1#--context=}"; shift ;;
        --frame-op|--frame_op)           FRAME_OP=1; shift ;;
        --no-buffer-frame|--no_buffer_frame)  BUFFER_FRAME=0; shift ;;
        --font-size)                     FONT_SIZE="$2"; shift 2 ;;
        --font-size=*)                   FONT_SIZE="${1#--font-size=}"; shift ;;
        --trace)                         TRACE=1; shift ;;
        --*)  echo "ERROR: unknown option '$1'" >&2
              echo "Valid options: -h/--help, --show-pacing, --show-keep, --context N, --frame-op, --no-buffer-frame, --font-size N, --trace" >&2
              exit 1 ;;
        *)    break ;;
    esac
done

OLD="${1:?Usage: dv_snapshot_per_op.sh [options] <oldfile> <newfile>}"
NEW="${2:?Usage: dv_snapshot_per_op.sh [options] <oldfile> <newfile>}"

# Validate files exist
if [[ ! -f "$OLD" ]]; then
    echo "ERROR: old file does not exist: $OLD" >&2
    exit 1
fi
if [[ ! -f "$NEW" ]]; then
    echo "ERROR: new file does not exist: $NEW" >&2
    exit 1
fi

OUTDIR=/tmp/dv_snapshots
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

# Run the C pipeline
RAW="$OUTDIR/raw.txt"; POST="$OUTDIR/post.txt"; TIMED="$OUTDIR/timed.txt"
echo "Running pipeline (compute → postprocess → pace)..." >&2
if ! "$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" "$RAW" 2>"$OUTDIR/compute_stderr.txt"; then
    echo "ERROR: compute stage failed:" >&2
    cat "$OUTDIR/compute_stderr.txt" >&2
    exit 1
fi
echo "  compute: $(wc -l < "$RAW") ops" >&2
if ! "$ROOT/animator/bin/diffvim-postprocess" < "$RAW" > "$POST" 2>"$OUTDIR/postprocess_stderr.txt"; then
    echo "ERROR: postprocess stage failed:" >&2
    cat "$OUTDIR/postprocess_stderr.txt" >&2
    exit 1
fi
echo "  postprocess: $(wc -l < "$POST") ops" >&2
if ! "$ROOT/animator/bin/diffvim-pace" < "$POST" > "$TIMED" 2>"$OUTDIR/pace_stderr.txt"; then
    echo "ERROR: pace stage failed:" >&2
    cat "$OUTDIR/pace_stderr.txt" >&2
    exit 1
fi
echo "  pace: $(wc -l < "$TIMED") ops" >&2

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
    # Inline SVG favicon — a green "+" / red "-" / blue "→" diff glyph,
    # so the browser tab shows a recognizable icon for snapshot pages.
    # Using data URI so the single .html file is self-contained (no external
    # asset dependency, works from file:// URLs).
    echo '<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2032%2032%22%3E%3Crect%20width%3D%2232%22%20height%3D%2232%22%20rx%3D%226%22%20fill%3D%22%231e1e1e%22%2F%3E%3Ctext%20x%3D%224%22%20y%3D%2223%22%20font-family%3D%22monospace%22%20font-size%3D%2218%22%20font-weight%3D%22bold%22%3E%3Ctspan%20fill%3D%22%236a9955%22%3E%2B%3C%2Ftspan%3E%3Ctspan%20fill%3D%22%23f44747%22%3E-%3C%2Ftspan%3E%3Ctspan%20fill%3D%22%23569cd6%22%3E%E2%86%92%3C%2Ftspan%3E%3C%2Ftext%3E%3C%2Fsvg%3E">'
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
    echo '  .op-num    { color: #6a6a6a; min-width: 60px; }'
    echo '  .op-type   { font-weight: bold; min-width: 70px; }'
    echo '  .op-type.keep    { color: #6a9955; }'
    echo '  .op-type.delete  { color: #c46666; }'
    echo '  .op-type.insert  { color: #7cc77c; }'
    echo '  .op-type.delay   { color: #808080; }'
    echo '  .op-type.meta    { color: #569cd6; }'
    echo '  .op-pos    { color: #6a8aa8; min-width: 120px; }'
    echo '  .op-char   { color: #9a7a5a; }'
    echo '  .op-detail { color: #8a8060; }'
    if [[ $BUFFER_FRAME -eq 1 ]]; then
        echo "  .buffer { background: #1e1e1e; padding: 4px 8px; font-size: ${FONT_SIZE}px; line-height: 1.5; white-space: pre; overflow-x: auto; border: 1px solid #3c3c3c; }"
    else
        echo "  .buffer { background: #1e1e1e; padding: 4px 8px; font-size: ${FONT_SIZE}px; line-height: 1.5; white-space: pre; overflow-x: auto; }"
    fi
    echo '  .buffer-empty { color: #808080; font-style: italic; padding: 6px 10px; }'
    echo "  .line-num { display: inline-block; width: 50px; color: #858585; text-align: right; padding-right: 10px; user-select: none; border-right: 1px solid #3c3c3c; margin-right: 10px; }"
    echo '  .line-highlight { background: #264f78; }'
    echo '  .char-keep   { background: #3a6a3a; color: #fff; }'
    echo '  .char-delete { background: #6b3030; color: #ddd; }'
    echo '  .char-insert { background: #2d9a2d; color: #fff; font-weight: bold; }'
    echo "  h1 { font-size: ${FONT_SIZE}px; color: #fff; }"
    echo "  .summary { margin-bottom: 1em; padding: 0.8em; background: #2d2d2d; border: 1px solid #555; font-size: ${FONT_SIZE}px; }"
    echo '  .summary b { color: #9cdcfe; }'
    if [[ $TRACE -eq 1 ]]; then
        echo '  /* --- Trace UI --- */'
        echo '  body { padding-bottom: 22vh; } /* leave room for trace panel */'
        echo '  .trace-btn { cursor: pointer; background: #264f78; color: #fff; border: 1px solid #569cd6; border-radius: 3px; padding: 2px 8px; font-size: 12px; font-family: inherit; margin-left: 1em; }'
        echo '  .trace-btn:hover { background: #3a6fa8; }'
        echo '  .trace-btn.traced { background: #6a9955; border-color: #6a9955; }'
        echo '  #trace-panel { position: fixed; bottom: 0; left: 0; right: 0; height: 20vh; background: #1a1a1a; border-top: 2px solid #569cd6; display: flex; flex-direction: column; z-index: 9999; }'
        echo '  #trace-header { display: flex; align-items: center; gap: 1em; padding: 4px 12px; background: #2d2d2d; border-bottom: 1px solid #555; flex-shrink: 0; }'
        echo '  #trace-header b { color: #569cd6; }'
        echo '  #trace-count { color: #9cdcfe; min-width: 80px; }'
        echo '  .trace-action-btn { cursor: pointer; background: #264f78; color: #fff; border: 1px solid #569cd6; border-radius: 3px; padding: 4px 12px; font-size: 13px; font-family: inherit; }'
        echo '  .trace-action-btn:hover { background: #3a6fa8; }'
        echo '  .trace-action-btn.danger { background: #6b3030; border-color: #f44747; }'
        echo '  .trace-action-btn.danger:hover { background: #8b4040; }'
        echo '  #trace-body { flex: 1; overflow: auto; padding: 4px 12px; font-size: 13px; white-space: pre; }'
        echo '  .trace-op { padding: 1px 0; }'
        echo '  .trace-op .op-remove { cursor: pointer; color: #f44747; margin-right: 8px; }'
        echo '  .trace-op .op-remove:hover { color: #ff6666; }'
        echo '  .trace-op .op-tsv { color: #d4d4d4; }'
    fi
    echo '</style></head><body>'
    echo '<h1>diffvim — per-op snapshots</h1>'
    echo '<div class="summary">'
    echo "  <b>OLD:</b> $OLD<br>"
    echo "  <b>NEW:</b> $NEW<br>"
    echo "  <b>Snaps:</b> $total_snaps<br>"
    echo "  <b>Pacing:</b> $([ $SHOW_PACING -eq 1 ] && echo 'shown' || echo 'hidden')<br>"
    echo "  <b>Keeps:</b> $([ $SHOW_KEEP -eq 1 ] && echo 'shown' || echo 'hidden')<br>"
    echo "  <b>Context:</b> $([ $CONTEXT -eq -1 ] && echo 'whole buffer' || ([ $CONTEXT -eq 0 ] && echo 'changed line' || echo \"${CONTEXT} lines\"))<br>"
    echo "  <b>Font:</b> ${FONT_SIZE}px, <b>Frame:</b> $([ $FRAME_OP -eq 1 ] && echo on || echo off), <b>Buffer frame:</b> $([ $BUFFER_FRAME -eq 1 ] && echo on || echo off), <b>Trace:</b> $([ $TRACE -eq 1 ] && echo 'on — click 📋 to collect ops' || echo off)"
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
            # HUNK_END is never shown — either another HUNK follows or it's the end
            continue
        elif [[ "$f1" == "delay" ]]; then
            [[ $SHOW_PACING -eq 0 ]] && continue
            op_class="delay"; op_type_label="delay"; op_detail="${f2}ms (${f3})"
            show_entry=1; show_buffer=0
        elif [[ "$f1" == "keep" ]]; then
            op_class="keep"; op_type_label="keep"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 $f5"
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            if [[ $SHOW_KEEP -eq 1 ]]; then
                show_entry=1; show_buffer=1
            else
                show_entry=0; show_buffer=0
            fi
        elif [[ "$f1" == "delete" ]]; then
            op_class="delete"; op_type_label="delete"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 $f5"
            snap_file="$OUTDIR/snap_$(printf '%04d' $snap_idx).txt"
            snap_idx=$((snap_idx + 1))
            show_entry=1; show_buffer=1
        elif [[ "$f1" == "insert" ]]; then
            op_class="insert"; op_type_label="insert"
            op_line="$f2"; op_col="$f3"; op_char="code=$f4 $f5"
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
        if [[ $TRACE -eq 1 ]]; then
            # The raw TSV line from the timed ops file for this op.
            tsv_line="${f1}"
            [[ -n "$f2" ]] && tsv_line+=$'\t'"${f2}"
            [[ -n "$f3" ]] && tsv_line+=$'\t'"${f3}"
            [[ -n "$f4" ]] && tsv_line+=$'\t'"${f4}"
            [[ -n "$f5" ]] && tsv_line+=$'\t'"${f5}"
            # Store TSV in a data- attribute (double-quoted, so single
            # quotes in char_repr like 'd' are safe). HTML-escape &,
            # <, >, " only. The JS reads it via getAttribute and
            # decodes entities with a textarea trick.
            tsv_escaped=$(printf '%s' "$tsv_line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
            echo "    <button class='trace-btn' onclick='traceCopy(this)' data-op-num='${op_count}' data-tsv=\"${tsv_escaped}\" title='Copy this op to the trace panel below'>📋 Copy</button>"
        fi
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
                        gsub(/>/, "\\&gt;", lines[i])
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

    if [[ $TRACE -eq 1 ]]; then
        cat <<'TRACE_HTML'
<div id="trace-panel">
  <div id="trace-header">
    <b>📋 Trace Panel</b>
    <span id="trace-count">0 ops collected</span>
    <button class="trace-action-btn" onclick="copyToClipboard()" title="Copy all collected ops as TSV text to the system clipboard">Copy to clipboard</button>
    <button class="trace-action-btn" onclick="downloadFile()" title="Download collected ops as a .tsv file">Download .tsv</button>
    <button class="trace-action-btn danger" onclick="clearTrace()" title="Clear all collected ops">Clear</button>
  </div>
  <div id="trace-body"></div>
</div>
<script>
(function() {
    var collected = [];

    // Exposed globally for the onclick handlers
    window.traceCopy = function(btn) {
        var opNum = btn.getAttribute('data-op-num');
        var rawTsv = btn.getAttribute('data-tsv');
        // Decode HTML entities back to real characters
        var txt = document.createElement('textarea');
        txt.innerHTML = rawTsv;
        var tsv = txt.value;
        // Check if already collected
        for (var i = 0; i < collected.length; i++) {
            if (collected[i].num === opNum) {
                // Already collected — remove it
                collected.splice(i, 1);
                btn.classList.remove('traced');
                btn.textContent = '📋 Copy';
                render();
                return;
            }
        }
        // Add it — prefix with the op index so the maintainer knows
        // exactly which op in the sequence is problematic
        var indexedTsv = '@' + opNum + '\t' + tsv;
        collected.push({num: opNum, tsv: indexedTsv});
        btn.classList.add('traced');
        btn.textContent = '✓ Traced';
        render();
    };

    window.copyToClipboard = function() {
        if (collected.length === 0) {
            alert('No ops collected yet. Click the 📋 Copy button on ops above to collect them.');
            return;
        }
        var text = collected.map(function(op) { return op.tsv; }).join('\n') + '\n';
        // Use the Clipboard API if available, fallback to execCommand
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function() {
                flashBtn('Copied ' + collected.length + ' ops to clipboard!');
            }).catch(function() {
                fallbackCopy(text);
            });
        } else {
            fallbackCopy(text);
        }
    };

    window.downloadFile = function() {
        if (collected.length === 0) {
            alert('No ops collected yet.');
            return;
        }
        var text = collected.map(function(op) { return op.tsv; }).join('\n') + '\n';
        var blob = new Blob([text], {type: 'text/tab-separated-values'});
        var url = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = url;
        a.download = 'traced_ops.tsv';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    };

    window.clearTrace = function() {
        collected = [];
        var btns = document.querySelectorAll('.trace-btn');
        btns.forEach(function(btn) {
            btn.classList.remove('traced');
            btn.textContent = '📋 Copy';
        });
        render();
    };

    window.removeOp = function(num) {
        for (var i = 0; i < collected.length; i++) {
            if (collected[i].num === num) {
                collected.splice(i, 1);
                break;
            }
        }
        // Reset the button for this op
        var btn = document.querySelector('.trace-btn[data-op-num="' + num + '"]');
        if (btn) {
            btn.classList.remove('traced');
            btn.textContent = '📋 Copy';
        }
        render();
    };

    function render() {
        var body = document.getElementById('trace-body');
        var count = document.getElementById('trace-count');
        count.textContent = collected.length + ' op' + (collected.length !== 1 ? 's' : '') + ' collected';
        if (collected.length === 0) {
            body.innerHTML = '<div style="color:#666;font-style:italic;">Click the 📋 Copy button on any op above to collect it here.</div>';
        } else {
            var html = '';
            for (var i = 0; i < collected.length; i++) {
                var op = collected[i];
                var tsvEsc = op.tsv.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
                // Convert tabs to visible → for display, but keep them in the actual data
                var tsvDisplay = tsvEsc.replace(/\t/g, ' → ');
                html += '<div class="trace-op"><span class="op-remove" onclick="removeOp(\'' + op.num + '\')" title="Remove this op">✕</span><span class="op-num">#' + op.num + '</span> <span class="op-tsv">' + tsvDisplay + '</span></div>';
            }
            body.innerHTML = html;
        }
    }

    function fallbackCopy(text) {
        var ta = document.createElement('textarea');
        ta.value = text;
        ta.style.position = 'fixed';
        ta.style.left = '-9999px';
        document.body.appendChild(ta);
        ta.select();
        try { document.execCommand('copy'); flashBtn('Copied!'); }
        catch(e) { alert('Clipboard not available. Use Download .tsv instead.'); }
        document.body.removeChild(ta);
    }

    function flashBtn(msg) {
        var btns = document.querySelectorAll('.trace-action-btn');
        if (btns.length > 0) {
            var orig = btns[0].textContent;
            btns[0].textContent = msg;
            setTimeout(function() { btns[0].textContent = orig; }, 2000);
        }
    }

    render(); // initial render
})();
</script>
TRACE_HTML
    fi

    echo '</body></html>'
} > "$HTML"

echo "Wrote $HTML" >&2
echo "Open with: file://$HTML" >&2
echo "Total entries: $op_count, snapshots: $snap_idx" >&2
