#!/usr/bin/env bash
# run_minimal_tests.sh — Run each minimal test case through the pipeline
# and report PASS/FAIL with stage details.
#
# Usage: bash tests/run_minimal_tests.sh
#        bash tests/run_minimal_tests.sh 11_delete_last_line   # one case

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -ge 1 ]]; then
    cases=("$ROOT/tests/minimal/$1")
else
    cases=( $(ls -d "$ROOT/tests/minimal"/*/ 2>/dev/null | sort) )
fi

pass=0
fail=0

for d in "${cases[@]}"; do
    d="${d%/}"
    [[ -f "$d/old" && -f "$d/new" ]] || continue
    name=$(basename "$d")
    old="$d/old"
    new="$d/new"
    raw="$d/raw.txt"
    post="$d/post.txt"
    timed="$d/timed.txt"
    snap="$d/snap.txt"
    rm -f "$raw" "$post" "$timed" "$snap"

    # Run each stage
    "$ROOT/bin/ad_compute" "$old" "$new" "$raw" 2>/dev/null
    "$ROOT/bin/ad_postprocess" < "$raw" > "$post" 2>/dev/null
    "$ROOT/bin/ad_layer_pace" < "$post" > "$timed" 2>/dev/null
    "$ROOT/bin/ad" --no-display --speed 1000 --snapshot "$snap" "$old" < "$timed" 2>/dev/null

    # Compare final result
    if [[ -f "$snap" ]] && diff -q "$snap" "$new" >/dev/null 2>&1; then
        pass=$((pass + 1))
        printf "%-30s PASS  (raw: %4d lines, post: %4d lines)\n" \
            "$name" "$(wc -l < "$raw")" "$(wc -l < "$post")"
    else
        fail=$((fail + 1))
        printf "%-30s FAIL  (raw: %4d lines, post: %4d lines)\n" \
            "$name" "${raw_lines:-?}" "${post_lines:-?}"
        echo "  expected:"
        cat "$new" | sed 's/^/    /'
        echo "  got:"
        cat "$snap" 2>/dev/null | sed 's/^/    /' || echo "    (no output)"
        # Show first few lines of each stage
        echo "  stage 1 (raw):"
        head -5 "$raw" 2>/dev/null | sed 's/^/    /'
        echo "  stage 2 (post):"
        head -5 "$post" 2>/dev/null | sed 's/^/    /'
        echo "  stage 3 (timed):"
        head -5 "$timed" 2>/dev/null | sed 's/^/    /'
        echo ""
    fi
done

echo ""
echo "=== Results: $pass passed, $fail failed ==="
exit $((fail == 0 ? 0 : 1))
