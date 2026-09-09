#!/usr/bin/env bash
# ad_layer_line_delete_in_place.awk — Delete content BEFORE joining lines.
#
# Implemented as a pipeline of Unix tools:
#   1. sed extracts sections between HUNK markers
#   2. awk processes each section, detecting the pattern:
#      join_lines(L) + delete(content at col 1) + join_lines(L)
#   3. Reorders: delete(content at L+1) + join(L+1) + [joiner re-iterated]
#
# Two modes: --mode batch (default) or --mode=interleaved
#
# Usage: ad_layer_line_delete_in_place.awk [--mode batch|interleaved] < ops.tsv
#
# Pipeline approach:
#   - Pass through comments and HUNK headers unchanged
#   - Within each HUNK, detect and reorder the pattern
#   - Use paste/sed for line manipulation

set -euo pipefail

MODE="batch"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)        MODE="$2"; shift 2 ;;
        --mode=*)      MODE="${1#--mode=}"; shift ;;
        --help|-h)
            cat <<'HELP'
ad_layer_line_delete_in_place.awk — delete content before joining lines

Usage: ad_layer_line_delete_in_place.awk [--mode batch|interleaved] < ops.tsv

Options:
  --mode batch        Delete all content first, then join all (default)
  --mode interleaved  Pass-through (diff engine's natural output)
  --help, -h          Show this help

Pipeline: sed (section extraction) → awk (pattern detection) → paste (reassembly)
HELP
            exit 0 ;;
        *) shift ;;
    esac
done

# Interleaved = pass-through
if [[ "$MODE" == "interleaved" ]]; then
    cat
    exit 0
fi

# Batch mode: single awk pass with state machine
# The awk script reads all lines, detects the pattern, and reorders.
# It uses a "pending" buffer: when it sees join_lines, it starts
# buffering. If the buffered content is followed by another join_lines,
# it reorders. Otherwise, it flushes the buffer unchanged.
awk '
BEGIN { state = "normal"; buf_n = 0 }

# Pass through comments, empty lines
/^#/ { if (buf_n > 0) flush(); print; next }
/^$/ { if (buf_n > 0) flush(); print; next }

# HUNK boundaries — flush and pass through
/^HUNK\t/ { if (buf_n > 0) flush(); print; next }
/^HUNK_END/ { if (buf_n > 0) flush(); print; next }

# Main processing
{
    # Split into fields
    n = split($0, f, "\t")
    type = f[1]

    if (state == "normal") {
        if (type == "join_lines") {
            # Start buffering — potential pattern start
            state = "after_join"
            buf[buf_n++] = $0
            buf_join_line = f[2]
        } else {
            print
        }
    } else if (state == "after_join") {
        if (type == "delete" && f[3] == "1") {
            # Content delete at col 1 — keep buffering
            state = "in_content"
            buf[buf_n++] = $0
        } else {
            # Not a content delete — flush buffer unchanged, emit this
            flush()
            print
        }
    } else if (state == "in_content") {
        if (type == "delete" && f[3] == "1") {
            # More content deletes
            buf[buf_n++] = $0
        } else if (type == "join_lines") {
            # Pattern complete!
            # Emit content deletes at line+1 (skip the first buf entry = joiner)
            for (i = 1; i < buf_n; i++) {
                split(buf[i], d, "\t")
                d[2] = buf_join_line + 1
                # Reconstruct line preserving all fields
                line = d[1]
                for (j = 2; j <= length(d); j++) {
                    if (d[j] != "") line = line "\t" d[j]
                }
                # Actually, split already consumed tabs. Rebuild properly.
                # Count fields from original
                nf = split(buf[i], d, "\t")
                d[2] = buf_join_line + 1
                line = d[1]
                for (j = 2; j <= nf; j++) line = line "\t" d[j]
                print line
            }
            # Emit trailing join_lines at line+1
            print "join_lines\t" (buf_join_line + 1)

            # Reset: keep the joiner (buf[0]) for re-iteration
            buf_n = 0
            buf[buf_n++] = buf[0]  # the joiner
            state = "after_join"
        } else {
            # Not a trailing join — flush unchanged
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
'
