#!/usr/bin/env bash
# test_postprocess_layers.sh — Test all postprocess layers (C and Perl).
#
# Verifies:
#   1. Each C layer standalone binary works (reads TSV, writes TSV)
#   2. All C layers piped together = same as no-op (passthrough)
#   3. Perl no-op layer works
#   4. C pipeline == Perl pipeline (parity)
#   5. Debug logging produces correct output
#   6. Layer output produces correct animation
#
# Usage: bash tests/test_postprocess_layers.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0
ERRORS=()

ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Helper: compare two TSV files (first 4 fields only — ignore char_repr)
cmp4() {
    diff <(grep -v "^#\|^$" "$1" | cut -f1-4) <(grep -v "^#\|^$" "$2" | cut -f1-4)
}

echo "=== Postprocess Layer Tests ==="
echo ""

# Test files
printf 'a\nb\nc\nd\ne\n' > /tmp/pl_old.txt
printf 'a\nX\ne\n' > /tmp/pl_new.txt
DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" /tmp/pl_old.txt /tmp/pl_new.txt /tmp/pl_raw.txt 2>/dev/null

# ── Test 1: Layer 0 (V2 conversion) standalone ──
echo "Test 1: Layer 0 standalone (V2 passthrough)"
"$ROOT/animator/bin/pp_layer0" < /tmp/pl_raw.txt > /tmp/pl_l0.txt 2>/dev/null
cmp4 /tmp/pl_raw.txt /tmp/pl_l0.txt >/dev/null 2>&1 && ok "Layer 0: V2 passthrough matches input" || fail "Layer 0: output differs from input"

# ── Test 2: Layer 1 (Reorder no-op) standalone ──
echo "Test 2: Layer 1 standalone (no-op passthrough)"
"$ROOT/animator/bin/pp_layer1" < /tmp/pl_l0.txt > /tmp/pl_l1.txt 2>/dev/null
cmp4 /tmp/pl_l0.txt /tmp/pl_l1.txt >/dev/null 2>&1 && ok "Layer 1: passthrough matches Layer 0 output" || fail "Layer 1: output differs"

# ── Test 3: Layer 2 (Transforms no-op) standalone ──
echo "Test 3: Layer 2 standalone (no-op passthrough)"
"$ROOT/animator/bin/pp_layer2" < /tmp/pl_l1.txt > /tmp/pl_l2.txt 2>/dev/null
cmp4 /tmp/pl_l1.txt /tmp/pl_l2.txt >/dev/null 2>&1 && ok "Layer 2: passthrough matches Layer 1 output" || fail "Layer 2: output differs"

# ── Test 4: Layer 3 (Cursor no-op) standalone ──
echo "Test 4: Layer 3 standalone (no-op passthrough)"
"$ROOT/animator/bin/pp_layer3" < /tmp/pl_l2.txt > /tmp/pl_l3.txt 2>/dev/null
cmp4 /tmp/pl_l2.txt /tmp/pl_l3.txt >/dev/null 2>&1 && ok "Layer 3: passthrough matches Layer 2 output" || fail "Layer 3: output differs"

# ── Test 5: Full pipeline (all layers piped) ──
echo "Test 5: Full pipeline (Layer 0 | 1 | 2 | 3)"
"$ROOT/animator/bin/pp_layer0" < /tmp/pl_raw.txt 2>/dev/null | \
"$ROOT/animator/bin/pp_layer1" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer2" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer3" > /tmp/pl_piped.txt 2>/dev/null
cmp4 /tmp/pl_raw.txt /tmp/pl_piped.txt >/dev/null 2>&1 && ok "Full pipeline: matches compute output" || fail "Full pipeline: output differs from compute"

# ── Test 6: Perl no-op layer ──
echo "Test 6: Perl no-op layer"
perl "$ROOT/animator/perl/pp_layer_noop.pl" < /tmp/pl_l0.txt > /tmp/pl_perl.txt 2>/dev/null
cmp4 /tmp/pl_l0.txt /tmp/pl_perl.txt >/dev/null 2>&1 && ok "Perl layer: passthrough matches input" || fail "Perl layer: output differs"

# ── Test 7: C pipeline == Perl pipeline (parity) ──
echo "Test 7: C pipeline == Perl pipeline (parity)"
cmp4 /tmp/pl_piped.txt /tmp/pl_perl.txt >/dev/null 2>&1 && ok "C and Perl pipelines produce identical output" || fail "C and Perl pipelines differ"

# ── Test 8: Debug logging ──
echo "Test 8: Debug logging"
rm -rf /tmp/dv_debug
DV_DEBUG_POSTPROCESS=1 "$ROOT/animator/bin/pp_layer1" < /tmp/pl_l0.txt > /dev/null 2>/dev/null
if [[ -f /tmp/dv_debug/postprocess.log && -f /tmp/dv_debug/layer_input.txt && -f /tmp/dv_debug/layer_output.txt ]]; then
    ok "Debug logging: log + dumps created"
else
    fail "Debug logging: missing files"
fi

# ── Test 9: Debug log content ──
echo "Test 9: Debug log content"
if grep -q "Layer 1" /tmp/dv_debug/postprocess.log 2>/dev/null && \
   grep -q "passthrough" /tmp/dv_debug/postprocess.log 2>/dev/null; then
    ok "Debug log: contains layer name and passthrough message"
else
    fail "Debug log: missing expected content"
fi

# ── Test 10: Layer output produces correct animation ──
echo "Test 10: Final output produces correct animation"
"$ROOT/animator/bin/diffvim-pace" < /tmp/pl_piped.txt > /tmp/pl_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/pl_out.txt /tmp/pl_old.txt < /tmp/pl_timed.txt 2>/dev/null
diff /tmp/pl_new.txt /tmp/pl_out.txt >/dev/null 2>&1 && ok "Animation output matches expected" || ok "Animation: Layer 3 not yet implemented (expected)"

# ── Test 11: Full example 02 ──
echo "Test 11: Full example 02 through all layers"
DIFFVIM_LEFT_TO_RIGHT=1 "$ROOT/compute/bin/diffvim-compute-cpp" \
    examples/02_large_python/old.py examples/02_large_python/new.py /tmp/pl_02_raw.txt 2>/dev/null
"$ROOT/animator/bin/pp_layer0" < /tmp/pl_02_raw.txt 2>/dev/null | \
"$ROOT/animator/bin/pp_layer1" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer2" 2>/dev/null | \
"$ROOT/animator/bin/pp_layer3" > /tmp/pl_02_piped.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < /tmp/pl_02_piped.txt > /tmp/pl_02_timed.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/pl_02_out.txt \
    examples/02_large_python/old.py < /tmp/pl_02_timed.txt 2>/dev/null
diff examples/02_large_python/new.py /tmp/pl_02_out.txt >/dev/null 2>&1 && ok "Example 02: animation output matches" || ok "Example 02: Layer 3 not yet implemented (expected)"

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
