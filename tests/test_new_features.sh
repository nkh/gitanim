#!/usr/bin/env bash
# Tests for smooth cursor movement (glide), distance-based speed,
# indent-last, flash delete-pacing, insert-pacing word, scroll modes,
# and colormap-new rendering.
#
# Usage: bash tests/test_new_features.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== New features tests ==="
echo ""

# Multi-hunk test files (2 hunks: line 1 and line 10)
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n' > /tmp/mh_old.txt
printf 'X\nb\nc\nd\ne\nf\ng\nh\ni\nY\n' > /tmp/mh_new.txt

# Single-hunk test files
printf 'def foo():\n    print("hello")\n    return None\n' > /tmp/il_old.txt
printf 'def bar():\n    x = 1\n' > /tmp/il_new.txt

DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/mh_old.txt /tmp/mh_new.txt /tmp/mh_raw.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < /tmp/mh_raw.txt > /tmp/mh_post.txt 2>/dev/null

DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/il_old.txt /tmp/il_new.txt /tmp/il_raw.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < /tmp/il_raw.txt > /tmp/il_post.txt 2>/dev/null

# --- Test 1: cursor glide emits glide ops ---
echo "Test 1: cursor glide emits glide ops"
"$ROOT/animator/bin/diffvim-pace" --cursor-glide-ms 100 < /tmp/mh_post.txt > /tmp/mh_timed.txt 2>/dev/null
n_glides=$(grep -c "^glide" /tmp/mh_timed.txt)
if [[ $n_glides -gt 0 ]]; then
    ok "cursor glide emits $n_glides glide ops"
else
    fail "no glide ops emitted"
fi

# --- Test 2: glide doesn't break output ---
echo "Test 2: glide doesn't break final output"
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/mh_out.txt /tmp/mh_old.txt < /tmp/mh_timed.txt 2>/dev/null
if diff -q /tmp/mh_new.txt /tmp/mh_out.txt >/dev/null 2>&1; then
    ok "glide produces correct output"
else
    fail "glide produces wrong output"
fi

# --- Test 3: distance-speed produces output ---
echo "Test 3: distance-speed adjusts delete delays"
"$ROOT/animator/bin/diffvim-pace" --distance-speed adaptive --distance-threshold 5 < /tmp/mh_post.txt > /tmp/mh_timed2.txt 2>/dev/null
if [[ -s /tmp/mh_timed2.txt ]]; then
    ok "distance-speed produces output"
else
    fail "distance-speed produces empty output"
fi

# --- Test 4: indent-last produces correct output ---
echo "Test 4: indent-last moves whitespace deletes last"
"$ROOT/animator/bin/diffvim-postprocess" --indent-last < /tmp/il_raw.txt > /tmp/il_post2.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < /tmp/il_post2.txt > /tmp/il_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/il_out.txt /tmp/il_old.txt < /tmp/il_timed.txt 2>/dev/null
if diff -q /tmp/il_new.txt /tmp/il_out.txt >/dev/null 2>&1; then
    ok "indent-last produces correct output"
else
    fail "indent-last produces wrong output"
fi

# --- Test 5: flash delete-pacing emits highlight ops ---
echo "Test 5: flash delete-pacing emits highlight ops"
"$ROOT/animator/bin/diffvim-pace" --delete-pacing flash < /tmp/il_post.txt > /tmp/flash_timed.txt 2>/dev/null
n_highlights=$(grep -c "^highlight" /tmp/flash_timed.txt)
if [[ $n_highlights -gt 0 ]]; then
    ok "flash mode emits $n_highlights highlight ops"
else
    fail "flash mode emits no highlight ops"
fi

# --- Test 6: flash produces correct output ---
echo "Test 6: flash produces correct output"
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/flash_out.txt /tmp/il_old.txt < /tmp/flash_timed.txt 2>/dev/null
if diff -q /tmp/il_new.txt /tmp/flash_out.txt >/dev/null 2>&1; then
    ok "flash produces correct output"
else
    fail "flash produces wrong output"
fi

# --- Test 7: insert-pacing word produces correct output ---
echo "Test 7: insert-pacing word produces correct output"
"$ROOT/animator/bin/diffvim-pace" --insert-pacing word < /tmp/mh_post.txt > /tmp/iw_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/iw_out.txt /tmp/mh_old.txt < /tmp/iw_timed.txt 2>/dev/null
if diff -q /tmp/mh_new.txt /tmp/iw_out.txt >/dev/null 2>&1; then
    ok "insert-pacing word produces correct output"
else
    fail "insert-pacing word produces wrong output"
fi

# --- Test 8: scroll mode zt is parsed ---
echo "Test 8: scroll mode zt is parsed without error"
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --scroll zt --snapshot /tmp/scroll_out.txt /tmp/mh_old.txt < /tmp/mh_timed.txt 2>/dev/null
if [[ $? -eq 0 ]]; then
    ok "scroll zt parsed and ran"
else
    fail "scroll zt failed"
fi

# --- Test 9: full pipeline with all new options ---
echo "Test 9: full pipeline with glide + distance-speed"
"$ROOT/animator/bin/diffvim-pace" --cursor-glide-ms 50 --distance-speed adaptive --distance-threshold 3 < /tmp/mh_post.txt > /tmp/all_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/all_out.txt /tmp/mh_old.txt < /tmp/all_timed.txt 2>/dev/null
if diff -q /tmp/mh_new.txt /tmp/all_out.txt >/dev/null 2>&1; then
    ok "glide + distance-speed produces correct output"
else
    fail "glide + distance-speed produces wrong output"
fi

# --- Test 10: launcher forwards --cursor-glide-ms ---
echo "Test 10: launcher forwards --cursor-glide-ms"
bash "$ROOT/animator/diffvim-pipeline" --no-display --speed 1000 --cursor-glide-ms 50 --snapshot /tmp/launch_out.txt /tmp/mh_old.txt /tmp/mh_new.txt 2>/dev/null
if [[ -f /tmp/launch_out.txt ]] && diff -q /tmp/mh_new.txt /tmp/launch_out.txt >/dev/null 2>&1; then
    ok "launcher forwards --cursor-glide-ms correctly"
else
    fail "launcher does not forward --cursor-glide-ms"
fi

# --- Test 11: launcher forwards --indent-last ---
echo "Test 11: launcher forwards --indent-last"
bash "$ROOT/animator/diffvim-pipeline" --no-display --speed 1000 --indent-last --snapshot /tmp/launch_il_out.txt /tmp/il_old.txt /tmp/il_new.txt 2>/dev/null
if [[ -f /tmp/launch_il_out.txt ]] && diff -q /tmp/il_new.txt /tmp/launch_il_out.txt >/dev/null 2>&1; then
    ok "launcher forwards --indent-last correctly"
else
    fail "launcher does not forward --indent-last"
fi

# --- Test 12: launcher forwards --delete-pacing flash ---
echo "Test 12: launcher forwards --delete-pacing flash"
bash "$ROOT/animator/diffvim-pipeline" --no-display --speed 1000 --delete-pacing flash --snapshot /tmp/launch_flash_out.txt /tmp/il_old.txt /tmp/il_new.txt 2>/dev/null
if [[ -f /tmp/launch_flash_out.txt ]] && diff -q /tmp/il_new.txt /tmp/launch_flash_out.txt >/dev/null 2>&1; then
    ok "launcher forwards --delete-pacing flash correctly"
else
    fail "launcher does not forward --delete-pacing flash"
fi

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
