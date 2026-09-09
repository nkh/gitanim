#!/usr/bin/env bash
# ad_layer_line_delete_in_place.sh — Delete content BEFORE joining lines.
#
# Bash implementation using a pipeline of Unix tools:
#   1. grep splits the stream: comments → stdout immediately,
#      op lines → temp file for processing
#   2. awk runs a state machine on the op lines, detecting:
#      join_lines(L) + delete(content at col 1) + join_lines(L)
#      and reordering to: delete(content at L+1) + join(L+1)
#   3. cat reassembles the header + processed ops
#
# Two modes: --mode batch (default) or --mode=interleaved
#
# Usage: ad_layer_line_delete_in_place.sh [--mode batch|interleaved] < ops.tsv

set -euo pipefail

MODE="batch"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)        MODE="$2"; shift 2 ;;
        --mode=*)      MODE="${1#--mode=}"; shift ;;
        --help|-h)
            echo "ad_layer_line_delete_in_place.sh — delete content before joining lines"
            echo "Usage: ad_layer_line_delete_in_place.sh [--mode batch|interleaved] < ops.tsv"
            echo ""
            echo "Pipeline: grep (split stream) → awk (detect+reorder pattern) → cat (reassemble)"
            exit 0 ;;
        *) shift ;;
    esac
done

# Interleaved = pass-through
if [[ "$MODE" == "interleaved" ]]; then
    cat
    exit 0
fi

# Save input so we can split it
INPUT=$(mktemp)
trap "rm -f '$INPUT'" EXIT
cat > "$INPUT"

# Step 1: Extract and output comment/header lines immediately
grep '^#' "$INPUT" 2>/dev/null || true

# Step 2: Process op lines (non-comment) with awk state machine
# The awk detects join_lines + delete(content@col1) + join_lines
# and reorders: content at line+1, join at line+1, joiner re-iterated
awk -F'\t' '
BEGIN { state = "normal"; buf_n = 0; buf_join_line = 0 }

# HUNK boundaries — flush buffer, pass through
/^HUNK\t/ { if (buf_n > 0) flush(); print; next }
/^HUNK_END/ { if (buf_n > 0) flush(); print; next }

# Empty lines — pass through
/^$/ { next }

# Comment lines — pass through (should not reach here due to grep filter)
/^#/ { next }

# Main op processing
{
    type = $1

    if (state == "normal") {
        if (type == "join_lines") {
            # Save joiner, start buffering
            state = "after_join"
            buf_join_line = $2
            buf[0] = $0
            buf_n = 1
        } else {
            print
        }
    } else if (state == "after_join") {
        if (type == "delete" && $3 == "1") {
            # Content delete at col 1 — buffer it
            state = "in_content"
            buf[buf_n++] = $0
        } else {
            # Not content delete — flush and emit
            flush()
            print
        }
    } else if (state == "in_content") {
        if (type == "delete" && $3 == "1") {
            # More content deletes
            buf[buf_n++] = $0
        } else if (type == "join_lines") {
            # Pattern complete! Reorder:
            # 1. Emit content deletes at line+1 (buf[1..buf_n-1])
            for (i = 1; i < buf_n; i++) {
                nf = split(buf[i], d, "\t")
                d[2] = buf_join_line + 1
                line = d[1]
                for (j = 2; j <= nf; j++) line = line "\t" d[j]
                print line
            }
            # 2. Emit trailing join at line+1
            print "join_lines\t" (buf_join_line + 1)

            # 3. Reset: keep joiner (buf[0]) for re-iteration
            buf_n = 1
            state = "after_join"
        } else {
            # Not trailing join — flush unchanged
            flush()
            print
        }
    }
}

END { if (buf_n > 0) flush() }

function flush() {
    for (i = 0; i < buf_n; i++) print buf[i]
    buf_n = 0
    state = "normal"
}
' "$INPUT"

# Step 3: Done — header was output by grep, ops by awk
# The pipeline is: grep (header) → stdout, awk (ops) → stdout
