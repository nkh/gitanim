#!/usr/bin/env bash
# ad_layer_line_delete_in_place.sh — Delete content BEFORE joining lines.
#
# Bash version. Uses sed/awk for text processing.
# Produces the same output as the C version.
#
# Two modes: --mode batch (default) or --mode=interleaved
#
# Pattern: join_lines(L) + delete(content at col 1) + join_lines(L)
# Batch:       delete(content at L+1) + join(L+1), joiner re-iterated
# Interleaved: pass-through
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
            exit 0 ;;
        *) shift ;;
    esac
done

# Interleaved = pass-through
if [[ "$MODE" == "interleaved" ]]; then
    cat
    exit 0
fi

# Batch mode: read all lines, process with state machine
# State: NORMAL (emit as-is) or IN_PATTERN (saw join_lines, collecting deletes)

awk -F'\t' '
BEGIN { state = "normal"; pending_join = ""; buf_count = 0 }

# Comments and headers: flush buffer, pass through
/^#/ || /^$/ {
    flush_buffer()
    print
    next
}

/^HUNK/ || /^HUNK_END/ {
    flush_buffer()
    print
    next
}

# Main op processing
{
    type = $1

    if (state == "normal") {
        if (type == "join_lines") {
            # Start of potential pattern
            state = "after_join"
            pending_join = $0
            pending_line = $2
        } else {
            print
        }
    } else if (state == "after_join") {
        if (type == "delete" && $3 == "1") {
            # Content delete at col 1 — buffer it
            buf[buf_count++] = $0
            state = "in_content"
        } else {
            # Not a content delete — flush join + this op
            print pending_join
            print
            state = "normal"
            pending_join = ""
            buf_count = 0
        }
    } else if (state == "in_content") {
        if (type == "delete" && $3 == "1") {
            # More content deletes — keep buffering
            buf[buf_count++] = $0
        } else if (type == "join_lines") {
            # Pattern complete: join + content + join
            # Emit content at line+1
            for (i = 0; i < buf_count; i++) {
                split(buf[i], d, "\t")
                d[2] = pending_line + 1
                # Reconstruct line (may have 5+ fields)
                line = d[1]
                for (f = 2; f <= NF_fields; f++) line = line "\t" d[f]
                # But we dont know NF for buffered lines... use split count
                nfields = split(buf[i], d, "\t")
                d[2] = pending_line + 1
                line = d[1]
                for (f = 2; f <= nfields; f++) line = line "\t" d[f]
                print line
            }
            # Emit second join at line+1
            print "join_lines\t" (pending_line + 1)

            # Keep the first join (pending_join) for re-iteration
            # Reset state but keep pending_join
            buf_count = 0
            state = "after_join"
            # pending_join and pending_line stay the same
        } else {
            # Not a trailing join — flush everything
            print pending_join
            for (i = 0; i < buf_count; i++) print buf[i]
            print
            state = "normal"
            pending_join = ""
            buf_count = 0
        }
    }
}

END { flush_buffer() }

function flush_buffer() {
    if (state == "after_join" || state == "in_content") {
        print pending_join
        for (i = 0; i < buf_count; i++) print buf[i]
        state = "normal"
        pending_join = ""
        buf_count = 0
    }
}
' 2>/dev/null
