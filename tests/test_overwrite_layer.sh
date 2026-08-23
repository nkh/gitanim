#!/usr/bin/env bash
# test_overwrite_layer.sh — Test the overwrite transform layer.
#
# Verifies:
#   1. Overwrite merges adjacent delete+insert at same position
#   2. Without overwrite, ops pass through unchanged
#   3. Both with/without overwrite produce correct animation output
#   4. op-debug inserts debug ops into the stream
#   5. Debug logging produces correct files
#
# Usage: bash tests/test_overwrite_layer.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== Overwrite Layer Tests ==="
echo ""

# Test 1: "hallo" → "hplo" (delete 'a', delete 'l', insert 'p')
printf 'hallo\n' > /tmp/ow_old.txt
printf 'hplo\n' > /tmp/ow_new.txt
DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/ow_old.txt /tmp/ow_new.txt /tmp/ow_raw.txt 2>/dev/null

echo "Test 1: Overwrite merges adjacent delete+insert"
"$ROOT/animator/bin/pp_layer0" < /tmp/ow_raw.txt 2>/dev/null | "$ROOT/animator/bin/pp_overwrite" 2>/dev/null > /tmp/ow_v2.txt
n_ow=$(grep -c "overwrite_insert" /tmp/ow_v2.txt 2>/dev/null); n_ow=${n_ow:-0}
if [[ "$n_ow" -gt 0 ]]; then
    ok "Overwrite produced $n_ow overwrite_insert op(s)"
else
    fail "No overwrite_insert ops produced"
fi

echo "Test 2: Without overwrite, no overwrite_insert ops"
"$ROOT/animator/bin/pp_layer0" < /tmp/ow_raw.txt 2>/dev/null > /tmp/ow_no.txt
n_no=$(grep "overwrite_insert" /tmp/ow_no.txt 2>/dev/null | wc -l)
if [[ "$n_no" -eq 0 ]]; then
    ok "Without overwrite: 0 overwrite_insert ops (correct)"
else
    fail "Without overwrite: found overwrite_insert ops (should be 0)"
fi

echo "Test 3: Animation WITH overwrite produces correct output"
"$ROOT/animator/bin/pp_layer0" < /tmp/ow_raw.txt 2>/dev/null | \
"$ROOT/animator/bin/pp_overwrite" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer3" 2>/dev/null | \
"$ROOT/animator/bin/diffvim-pace" > /tmp/ow_timed_ow.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/ow_out_ow.txt /tmp/ow_old.txt < /tmp/ow_timed_ow.txt 2>/dev/null
diff /tmp/ow_new.txt /tmp/ow_out_ow.txt >/dev/null 2>&1 && ok "Animation WITH overwrite matches" || fail "Animation WITH overwrite doesn't match"

echo "Test 4: Animation WITHOUT overwrite produces correct output"
"$ROOT/animator/bin/pp_layer0" < /tmp/ow_raw.txt 2>/dev/null | \
"$ROOT/animator/bin/pp_layer3" 2>/dev/null | \
"$ROOT/animator/bin/diffvim-pace" > /tmp/ow_timed_no.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/ow_out_no.txt /tmp/ow_old.txt < /tmp/ow_timed_no.txt 2>/dev/null
diff /tmp/ow_new.txt /tmp/ow_out_no.txt >/dev/null 2>&1 && ok "Animation WITHOUT overwrite matches" || fail "Animation WITHOUT overwrite doesn't match"

echo "Test 5: op-debug inserts debug ops"
DV_OP_DEBUG=1 "$ROOT/animator/bin/pp_layer0" < /tmp/ow_raw.txt 2>/dev/null | \
DV_OP_DEBUG=1 "$ROOT/animator/bin/pp_overwrite" 2>/dev/null > /tmp/ow_debug.txt
n_debug=$(grep "^debug" /tmp/ow_debug.txt 2>/dev/null | wc -l)
if [[ "$n_debug" -gt 0 ]]; then
    ok "op-debug produced $n_debug debug op(s)"
else
    fail "op-debug produced 0 debug ops"
fi

echo "Test 6: Debug logging produces files"
rm -rf /tmp/dv_debug
DV_DEBUG_POSTPROCESS=1 "$ROOT/animator/bin/pp_overwrite" < /tmp/ow_v2.txt > /dev/null 2>/dev/null
if [[ -f /tmp/dv_debug/postprocess.log ]]; then
    ok "Debug log created"
else
    fail "Debug log not created"
fi

echo "Test 7: Debug log contains merge info"
if grep -q "merge" /tmp/dv_debug/postprocess.log 2>/dev/null; then
    ok "Debug log contains merge info"
else
    fail "Debug log missing merge info"
fi

echo "Test 8: Non-adjacent delete+insert NOT merged"
# "hello" → "helpo": delete 'l' at (1,3), keep 'l' at (1,3), insert 'p' at (1,4)
# delete and insert are NOT adjacent (keep between them)
printf 'hello\n' > /tmp/ow3_old.txt
printf 'helpo\n' > /tmp/ow3_new.txt
DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/ow3_old.txt /tmp/ow3_new.txt /tmp/ow3_raw.txt 2>/dev/null
"$ROOT/animator/bin/pp_layer0" < /tmp/ow3_raw.txt 2>/dev/null | "$ROOT/animator/bin/pp_overwrite" 2>/dev/null > /tmp/ow3_v2.txt
n_ow3=$(grep "overwrite_insert" /tmp/ow3_v2.txt 2>/dev/null | wc -l)
if [[ "$n_ow3" -eq 0 ]]; then
    ok "Non-adjacent delete+insert: 0 merges (correct)"
else
    fail "Non-adjacent delete+insert: $n_ow3 merges (should be 0)"
fi

echo "Test 9: Multiple adjacent pairs merged"
# "abc" → "xyz": delete a, insert x, delete b, insert y, delete c, insert z
printf 'abc\n' > /tmp/ow4_old.txt
printf 'xyz\n' > /tmp/ow4_new.txt
DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/ow4_old.txt /tmp/ow4_new.txt /tmp/ow4_raw.txt 2>/dev/null
"$ROOT/animator/bin/pp_layer0" < /tmp/ow4_raw.txt 2>/dev/null | "$ROOT/animator/bin/pp_overwrite" 2>/dev/null > /tmp/ow4_v2.txt
n_ow4=$(grep "overwrite_insert" /tmp/ow4_v2.txt 2>/dev/null | wc -l)
if [[ "$n_ow4" -ge 1 ]]; then
    ok "Multiple pairs: $n_ow4 overwrite_insert ops"
else
    fail "Multiple pairs: $n_ow4 merges (expected >= 1)"
fi

echo "Test 10: Multiple pairs animation correct"
"$ROOT/animator/bin/pp_layer0" < /tmp/ow4_raw.txt 2>/dev/null | \
"$ROOT/animator/bin/pp_overwrite" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer3" 2>/dev/null | \
"$ROOT/animator/bin/diffvim-pace" > /tmp/ow4_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/ow4_out.txt /tmp/ow4_old.txt < /tmp/ow4_timed.txt 2>/dev/null
diff /tmp/ow4_new.txt /tmp/ow4_out.txt >/dev/null 2>&1 && ok "Multiple pairs animation matches" || fail "Multiple pairs animation doesn't match"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for e in "${ERRORS[@]}"; do echo "  - $e"; done
    exit 1
fi
exit 0
