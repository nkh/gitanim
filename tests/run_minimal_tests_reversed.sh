#!/usr/bin/env bash
# run_minimal_tests_reversed.sh — Run each minimal test case through the
# pipeline with file order REVERSED (new -> old) and report PASS/FAIL.
#
# This exercises the symmetric property: if the pipeline transforms
# old -> new correctly, it should also transform new -> old correctly.
#
# For each case under tests/minimal/*/:
#   - Compute ops from new -> old
#   - Post-process + pace
#   - Run animator with old=new-file, ops produce buffer that should equal `old`
#   - Compare snap vs `old`
#   - On FAIL, run ad_l1l2 new old timed to locate L1/L2
#
# Usage: bash tests/run_minimal_tests_reversed.sh
#        bash tests/run_minimal_tests_reversed.sh 27_weird_insert   # one case

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -ge 1 ]]; then
    cases=("$ROOT/tests/minimal/$1")
else
    cases=( $(ls -d "$ROOT/tests/minimal"/*/ 2>/dev/null | sort) )
fi

OUTDIR=/tmp/ad_reverse
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

pass=0
fail=0

for d in "${cases[@]}"; do
    d="${d%/}"
    [[ -f "$d/old" && -f "$d/new" ]] || continue
    name=$(basename "$d")

    # REVERSED order: transform new -> old
    OLD="$d/new"   # was: $d/old
    NEW="$d/old"   # was: $d/new

    raw="$OUTDIR/${name}.raw"
    post="$OUTDIR/${name}.post"
    timed="$OUTDIR/${name}.timed"
    snap="$OUTDIR/${name}.snap"
    rm -f "$raw" "$post" "$timed" "$snap"

    "$ROOT/bin/ad_compute" "$OLD" "$NEW" "$raw" 2>/dev/null
    "$ROOT/pipeline/ad_postprocess" --ad-layer=ad_layer_reorder < "$raw" > "$post" 2>/dev/null
    "$ROOT/bin/ad_layer_pace" < "$post" > "$timed" 2>/dev/null
    "$ROOT/bin/ad" --no-display --speed 1000 --snapshot "$snap" "$OLD" < "$timed" 2>/dev/null

    if [[ -f "$snap" ]] && diff -q "$snap" "$NEW" >/dev/null 2>&1; then
        pass=$((pass + 1))
        printf "%-30s PASS  (raw: %4d lines, post: %4d lines)\n" \
            "$name" "$(wc -l < "$raw")" "$(wc -l < "$post")"
    else
        fail=$((fail + 1))
        printf "%-30s FAIL  (raw: %4d lines, post: %4d lines)\n" \
            "$name" "$(wc -l < "$raw" 2>/dev/null || echo '?')" "$(wc -l < "$post" 2>/dev/null || echo '?')"

        # Run L1/L2 to locate where the divergence begins
        l1l2_out=$("$ROOT/scripts/ad_l1l2" "$OLD" "$NEW" "$timed" 2>/dev/null || true)
        if [[ -n "$l1l2_out" ]]; then
            echo "    L1/L2:"
            echo "$l1l2_out" | sed 's/^/      /'
        else
            echo "    L1/L2: (no output — timed file may be empty or animator crashed)"
        fi

        echo "    expected (old, target):"
        cat "$NEW" 2>/dev/null | head -10 | sed 's/^/      /'
        echo "    got (snap):"
        cat "$snap" 2>/dev/null | head -10 | sed 's/^/      /' || echo "      (no output)"
        echo "    diff:"
        diff "$NEW" "$snap" 2>/dev/null | head -20 | sed 's/^/      /' || true
        echo ""
    fi
done

echo ""
echo "=== Reversed-direction results: $pass passed, $fail failed ==="
exit $((fail == 0 ? 0 : 1))
