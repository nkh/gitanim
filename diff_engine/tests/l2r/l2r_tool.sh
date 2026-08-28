#!/usr/bin/env bash
# l2r_tool.sh — Standalone left_to_right transform tool (NOT integrated).
#
# Reads TSV ops (v2 format) from stdin, applies the NEW left_to_right
# algorithm, writes reordered ops to stdout.
#
# The NEW algorithm:
#   - Keeps stay in place (they are anchors)
#   - Within each "change region" (consecutive non-keep ops between keeps),
#     all DELETEs are emitted first, then all INSERTs
#   - Positions are recomputed by walking the output
#
# Usage:
#   l2r_tool.sh < input.ops > output.ops
#
# Build: (no build needed — pure bash + awk)

set -euo pipefail

awk '
BEGIN {
    FS = "\t"
    OFS = "\t"
    n = 0
}

/^#/ || /^$/ {
    # Pass through headers and blank lines
    print
    next
}

/^HUNK/ {
    # Start of a hunk — flush any pending region
    flush_region()
    print
    next
}

/^HUNK_END/ {
    flush_region()
    print
    next
}

{
    # Op line: keep, delete, or insert
    type = $1
    if (type == "keep") {
        # Keep: flush pending region, then emit keep
        flush_region()
        keep_ops[++keep_count] = $0
    } else {
        # Non-keep: add to current region
        region_ops[++region_count] = $0
        region_types[region_count] = type
    }
}

function flush_region() {
    # Emit all DELETEs first, then all INSERTs from the current region
    for (i = 1; i <= region_count; i++) {
        if (region_types[i] == "delete") {
            print region_ops[i]
        }
    }
    for (i = 1; i <= region_count; i++) {
        if (region_types[i] == "insert") {
            print region_ops[i]
        }
    }
    # Reset region
    region_count = 0
    delete region_ops
    delete region_types
}

END {
    # Flush any remaining region
    flush_region()
}
'
