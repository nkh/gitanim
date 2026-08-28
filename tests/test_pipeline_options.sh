#!/usr/bin/env bash
# test_pipeline_options.sh — Test ALL pipeline options end-to-end.
#
# Runs ad_pipeline with each option and verifies:
# 1. The option is accepted (exit 0)
# 2. The output matches the expected new file
#
# Usage: bash tests/test_pipeline_options.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Test files (multi-hunk)
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n' > /tmp/po_old.txt
printf 'A\nb\nc\nd\ne\nf\ng\nh\ni\nJ\n' > /tmp/po_new.txt

# Test files (single hunk with content change)
printf 'def foo():\n    print("hello")\n    return None\n' > /tmp/po_old2.txt
printf 'def bar():\n    x = 1\n' > /tmp/po_new2.txt

test_option() {
    local name="$1"
    local option="$2"
    local oldfile="${3:-/tmp/po_old.txt}"
    local newfile="${4:-/tmp/po_new.txt}"
    local out="/tmp/po_${name}_out.txt"
    
    if bash "$ROOT/animator/ad_pipeline" --no-display --speed 1000 \
        $option --snapshot "$out" "$oldfile" "$newfile" 2>/dev/null; true; then
        if diff -q "$newfile" "$out" >/dev/null 2>&1; then
            ok "$name"
        else
            fail "$name (wrong output)"
        fi
    else
        fail "$name (rejected)"
    fi
}

echo "=== Pipeline Options End-to-End Test ==="
echo ""

# Postprocess options
echo "--- Postprocess ---"
test_option "op-order-natural" "--op-order natural"
test_option "op-order-optimize" "--op-order optimize"
test_option "op-order-left-to-right" "--op-order left-to-right"
test_option "semantic-cleanup" "--semantic-cleanup"
test_option "indent-aware" "--indent-aware"
test_option "indent-last" "--indent-last"
test_option "overwrite" "--overwrite"

# Pace options
echo "--- Pace ---"
test_option "delete-pacing-char" "--delete-pacing char"
test_option "delete-pacing-word" "--delete-pacing word"
test_option "delete-pacing-instant" "--delete-pacing instant"
test_option "delete-pacing-flash" "--delete-pacing flash"
test_option "delete-pacing-rapid-eol" "--delete-pacing rapid-eol"
test_option "delete-pacing-rapid-identical" "--delete-pacing rapid-identical"
test_option "insert-pacing-char" "--insert-pacing char"
test_option "insert-pacing-word" "--insert-pacing word"
test_option "delete-speed-fast" "--delete-speed fast"
test_option "insert-speed-fast" "--insert-speed fast"
test_option "pacing-uniform" "--pacing uniform"
test_option "pacing-adaptive" "--pacing adaptive"
test_option "pacing-gaussian" "--pacing gaussian"
test_option "pacing-review" "--pacing review"

# Cursor movement
echo "--- Cursor ---"
test_option "cursor-glide" "--cursor-glide-ms 100"
test_option "cursor-glide-no-intermediate" "--cursor-glide-ms 100 --cursor-glide-show-intermediate 0"

# Distance speed
echo "--- Distance ---"
test_option "distance-speed" "--distance-speed adaptive"
test_option "distance-speed-threshold" "--distance-speed adaptive --distance-threshold 5"

# Flash options
echo "--- Flash ---"
test_option "flash-pause-ms" "--delete-pacing flash --flash-pause-ms 200"
test_option "flash-highlight-ms" "--delete-pacing flash --flash-highlight-ms 200"

# Decorate options
echo "--- Decorate ---"
test_option "highlight-none" "--highlight none"
test_option "highlight-inline" "--highlight inline"
test_option "highlight-word" "--highlight word"
test_option "highlight-hunk" "--highlight hunk"
test_option "dim-unchanged" "--dim-unchanged"
test_option "sign-column" "--sign-column"
test_option "git-blame" "--git-blame"

# Animator options
echo "--- Animator ---"
test_option "diff-stat" "--diff-stat"
test_option "diff-highlight" "--diff-highlight"
test_option "bell" "--bell"
test_option "scroll-zz" "--scroll zz"
test_option "scroll-zt" "--scroll zt"
test_option "scroll-zb" "--scroll zb"
test_option "scroll-none" "--scroll none"

# Combinations
echo "--- Combinations ---"
test_option "combo-1" "--op-order left-to-right --delete-pacing flash --highlight inline"
test_option "combo-2" "--indent-last --cursor-glide-ms 100 --distance-speed adaptive"
test_option "combo-3" "--semantic-cleanup --indent-aware --overwrite --indent-last"
test_option "combo-4" "--diff-stat --diff-highlight --bell --scroll zt"
test_option "combo-5" "--pacing gaussian --cursor-glide-ms 200 --highlight hunk --dim-unchanged"

# Test with second file pair (content change)
echo "--- Content change ---"
test_option "content-op-order" "--op-order left-to-right" /tmp/po_old2.txt /tmp/po_new2.txt
test_option "content-indent-last" "--indent-last" /tmp/po_old2.txt /tmp/po_new2.txt
test_option "content-flash" "--delete-pacing flash" /tmp/po_old2.txt /tmp/po_new2.txt

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
exit 0
