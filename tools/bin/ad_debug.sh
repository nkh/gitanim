#!/usr/bin/env bash
# dv_debug.sh — Debugging tool for the diffvim pipeline.
#
# Takes old and new files, displays each pipeline stage AND writes
# the stage files to disk so you can inspect them with any tool:
#   /tmp/ad_debug/raw.txt     — Stage 1 (compute output)
#   /tmp/ad_debug/post.txt    — Stage 2 (postprocess output)
#   /tmp/ad_debug/timed.txt   — Stage 3 (pace output)
#   /tmp/ad_debug/snap.txt     — Stage 4 (animator final buffer)
#
# Usage: dv_debug.sh <oldfile> <newfile>
#        dv_debug.sh --keep <oldfile> <newfile>     (don't clear /tmp/ad_debug first)
#
# Useful commands after running:
#   less -S /tmp/ad_debug/post.txt        # view with tabs visible
#   cat -A /tmp/ad_debug/raw.txt | head  # show tabs as ^I
#   wc -l /tmp/ad_debug/*.txt             # line counts
#   diff /tmp/ad_debug/snap.txt <new>    # final comparison

show_help() {
cat <<'HELP'
NAME
    dv_debug.sh — Debugging tool for the diffvim pipeline

SYNOPSIS
    dv_debug.sh [-h|--help]
    dv_debug.sh [--keep] <oldfile> <newfile>

DESCRIPTION
    Takes an old and new file, runs the full diffvim pipeline (compute →
    postprocess → pace → animator) stage by stage, prints diagnostic
    information to the terminal, AND writes the intermediate output of
    each stage to disk under /tmp/ad_debug/ so you can inspect it with
    any external tool (less, cat -A, diff, wc, etc.).

    Stage files produced:
      /tmp/ad_debug/raw.txt    — Stage 1 (ad_compute output)
      /tmp/ad_debug/post.txt   — Stage 2 (ad_postprocess output)
      /tmp/ad_debug/timed.txt  — Stage 3 (ad_layer_pace output)
      /tmp/ad_debug/snap.txt   — Stage 4 (ad final buffer)

    The script then compares the animator's final buffer (snap.txt)
    against the new file and reports either a MATCH or a MISMATCH
    (printing the diff in the latter case).

OPTIONS
    -h, --help     Show this help message and exit 0.
    --keep         Do not clear /tmp/ad_debug/ before running. Useful
                   when you want to compare stage files across runs.
    <oldfile>      Path to the original/source file (initial buffer).
    <newfile>      Path to the target file the animation should produce.

EXAMPLES
    dv_debug.sh tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py
        Run the debugger on a small Python example, clearing any previous
        /tmp/ad_debug/ contents first.

    dv_debug.sh --keep old.txt new.txt
        Run the debugger but keep the existing /tmp/ad_debug/ contents.

    Useful follow-up commands after running:
        less -S /tmp/ad_debug/post.txt        # view with tabs visible
        cat -A /tmp/ad_debug/raw.txt | head   # show tabs as ^I
        wc -l /tmp/ad_debug/*.txt              # line counts per stage
        diff /tmp/ad_debug/snap.txt new.txt    # final comparison
HELP
}

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Handle -h/--help before any other argument processing
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# Optional --keep flag: don't clear the output directory
KEEP=0
if [[ "${1:-}" == "--keep" ]]; then
    KEEP=1
    shift
fi

OLD="${1:?Usage: dv_debug.sh <oldfile> <newfile>}"
NEW="${2:?Usage: dv_debug.sh <oldfile> <newfile>}"

OUTDIR=/tmp/ad_debug
if [[ $KEEP -eq 0 ]]; then
    rm -rf "$OUTDIR"
fi
mkdir -p "$OUTDIR"

RAW="$OUTDIR/raw.txt"
POST="$OUTDIR/post.txt"
TIMED="$OUTDIR/timed.txt"
SNAP="$OUTDIR/snap.txt"

echo "══════════════════════════════════════════════════════════════"
echo " diffvim pipeline debugger"
echo "══════════════════════════════════════════════════════════════"
echo ""
echo "Stage files written to: $OUTDIR/"
echo "  raw.txt    — Stage 1 (compute output)"
echo "  post.txt   — Stage 2 (postprocess output)"
echo "  timed.txt  — Stage 3 (pace output)"
echo "  snap.txt   — Stage 4 (animator final buffer)"
echo ""

echo "─── INPUT FILES ──────────────────────────────────────────────"
echo "OLD: $OLD"
cat -n "$OLD"
echo ""
echo "NEW: $NEW"
cat -n "$NEW"
echo ""

echo "─── STAGE 1: RAW DIFF OPS (compute) ──────────────────────────"
"$ROOT/bin/ad_compute" "$OLD" "$NEW" "$RAW" 2>&1
echo ""
echo "  → $(wc -l < "$RAW") lines written to $RAW"
echo "  → Header:"
head -1 "$RAW"
echo ""
echo "  → First 30 lines:"
head -30 "$RAW" | cat -n
echo ""

echo "─── STAGE 2: POST-PROCESSED OPS (postprocess) ───────────────"
"$ROOT/bin/ad_postprocess" < "$RAW" > "$POST" 2>&1 || true
echo "  → $(wc -l < "$POST") lines written to $POST"
echo "  → Header:"
head -1 "$POST"
echo ""
echo "  → First 30 lines:"
head -30 "$POST" | cat -n
echo ""

echo "─── STAGE 3: TIMED OPS (pace) ───────────────────────────────"
"$ROOT/bin/ad_layer_pace" < "$POST" > "$TIMED" 2>&1 || true
echo "  → $(wc -l < "$TIMED") lines written to $TIMED"
echo "  → Header:"
head -3 "$TIMED"
echo ""
echo "  → First 30 lines:"
head -30 "$TIMED" | cat -n
echo ""

echo "─── STAGE 4: ANIMATOR RESULT ────────────────────────────────"
"$ROOT/bin/ad" --no-display --speed 1000 --snapshot "$SNAP" "$OLD" < "$TIMED" 2>&1 || true
echo "  → $(wc -l < "$SNAP" 2>/dev/null || echo 0) lines written to $SNAP"
echo ""

echo "─── RESULT COMPARISON ────────────────────────────────────────"
echo "Expected (new file):"
cat -n "$NEW"
echo ""
echo "Actual (animator output):"
cat -n "$SNAP" 2>/dev/null || echo "  (no output file)"
echo ""

if [[ -f "$SNAP" ]] && diff -q "$SNAP" "$NEW" >/dev/null 2>&1; then
    echo "✓ MATCH — animator output matches new file"
else
    echo "✗ MISMATCH — differences:"
    diff "$NEW" "$SNAP" 2>/dev/null || true
fi
echo ""
echo "─── END ──────────────────────────────────────────────────────"
echo ""
echo "Stage files are in: $OUTDIR/"
echo "Useful commands:"
echo "  less -S $OUTDIR/post.txt       # view with tabs"
echo "  cat -A $OUTDIR/raw.txt | head  # show tabs as ^I"
echo "  wc -l $OUTDIR/*.txt             # line counts"
echo "  diff $OUTDIR/snap.txt $NEW     # final comparison"
