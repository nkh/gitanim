#!/usr/bin/env bash
# dv_debug.sh — Debugging tool for the diffvim pipeline.
#
# Takes old and new files, displays each pipeline stage:
#   1. Input files
#   2. Raw diff ops (from compute)
#   3. Post-processed ops (from postprocess)
#   4. Timed ops (from pace)
#   5. Result of applying ops (animator output vs expected)
#
# Usage: dv_debug.sh <oldfile> <newfile>

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

OLD="${1:?Usage: dv_debug.sh <oldfile> <newfile>}"
NEW="${2:?Usage: dv_debug.sh <oldfile> <newfile>}"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

RAW="$WORKDIR/raw.txt"
POST="$WORKDIR/post.txt"
TIMED="$WORKDIR/timed.txt"
SNAP="$WORKDIR/snap.txt"

echo "══════════════════════════════════════════════════════════════"
echo " diffvim pipeline debugger"
echo "══════════════════════════════════════════════════════════════"
echo ""

echo "─── INPUT FILES ──────────────────────────────────────────────"
echo "OLD: $OLD"
cat -n "$OLD"
echo ""
echo "NEW: $NEW"
cat -n "$NEW"
echo ""

echo "─── STAGE 1: RAW DIFF OPS (compute) ──────────────────────────"
"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" "$RAW" 2>&1
echo ""
cat "$RAW"
echo ""

echo "─── STAGE 2: POST-PROCESSED OPS (postprocess) ───────────────"
"$ROOT/animator/bin/diffvim-postprocess" < "$RAW" > "$POST" 2>&1
cat "$POST"
echo ""

echo "─── STAGE 3: TIMED OPS (pace) ───────────────────────────────"
"$ROOT/animator/bin/diffvim-pace" < "$POST" > "$TIMED" 2>&1
cat "$TIMED"
echo ""

echo "─── STAGE 4: ANIMATOR RESULT ────────────────────────────────"
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot "$SNAP" "$OLD" < "$TIMED" 2>&1
echo ""

echo "─── RESULT COMPARISON ────────────────────────────────────────"
echo "Expected (new file):"
cat -n "$NEW"
echo ""
echo "Actual (animator output):"
cat -n "$SNAP"
echo ""

if diff -q "$SNAP" "$NEW" >/dev/null 2>&1; then
    echo "✓ MATCH — animator output matches new file"
else
    echo "✗ MISMATCH — differences:"
    diff "$SNAP" "$NEW" || true
fi
echo ""
echo "─── END ──────────────────────────────────────────────────────"
