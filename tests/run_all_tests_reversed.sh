#!/usr/bin/env bash
# run_all_tests_reversed.sh — Run EVERY test case (minimal + examples)
# through the pipeline with file order REVERSED (new -> old) and report
# PASS/FAIL with L1/L2 diagnostics on failures.
#
# This exercises the symmetric property: if the pipeline transforms
# old -> new correctly, it should also transform new -> old correctly.
#
# Covers:
#   - tests/minimal/*/      (files: old, new — no extension)
#   - tests/examples/*/    (files: old.<ext>, new.<ext>)
#
# For each case:
#   - Compute ops from new -> old
#   - Post-process + pace
#   - Run animator with old=new-file; snapshot should equal `old` (the new target)
#   - On FAIL, run ad_l1l2 new old timed to locate L1/L2
#
# Usage: bash tests/run_all_tests_reversed.sh
#        bash tests/run_all_tests_reversed.sh 27_weird_insert   # one minimal case
#        bash tests/run_all_tests_reversed.sh 01_small_python   # one example case

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Collect all test directories (minimal first, then examples).
if [[ $# -ge 1 ]]; then
    cases=()
    for arg in "$@"; do
        if [[ -d "$ROOT/tests/minimal/$arg" ]]; then
            cases+=("$ROOT/tests/minimal/$arg")
        elif [[ -d "$ROOT/tests/examples/$arg" ]]; then
            cases+=("$ROOT/tests/examples/$arg")
        else
            echo "Unknown case: $arg" >&2
            exit 1
        fi
    done
else
    cases=( $(ls -d "$ROOT/tests/minimal"/*/ 2>/dev/null | sort) )
    cases+=( $(ls -d "$ROOT/tests/examples"/*/ 2>/dev/null | sort) )
fi

OUTDIR=/tmp/ad_reverse
rm -rf "$OUTDIR"
mkdir -p "$OUTDIR"

pass=0
fail=0
total=0

# Locate the old/new file pair inside a directory.
# For minimal/: files are named `old` and `new`.
# For examples/: files are named `old.<ext>` and `new.<ext>`.
find_pair() {
    local d="$1"
    local old="" new=""
    # Try minimal-style first (no extension)
    if [[ -f "$d/old" && -f "$d/new" ]]; then
        echo "$d/old|$d/new"
        return
    fi
    # Try examples-style with various extensions
    for ext in py txt go rs c ts sh yaml yml json xml html css js rb php java kt swift scala ex clj cl md toml lua Dockerfile Makefile R cs hs pl; do
        [[ -z "$old" && -f "$d/old.$ext" ]] && old="$d/old.$ext"
        [[ -z "$new" && -f "$d/new.$ext" ]] && new="$d/new.$ext"
    done
    if [[ -n "$old" && -n "$new" ]]; then
        echo "$old|$new"
    fi
}

for d in "${cases[@]}"; do
    d="${d%/}"
    pair=$(find_pair "$d")
    [[ -z "$pair" ]] && continue
    total=$((total + 1))
    name=$(basename "$d")

    OLD_A="${pair%%|*}"   # original old file
    NEW_A="${pair##*|}"   # original new file

    # REVERSED direction: transform new -> old
    OLD="$NEW_A"   # start from new
    NEW="$OLD_A"   # target is old

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
        printf "%-35s PASS  (raw: %5d lines, post: %5d lines)\n" \
            "$name" "$(wc -l < "$raw")" "$(wc -l < "$post")"
    else
        fail=$((fail + 1))
        printf "%-35s FAIL  (raw: %5d lines, post: %5d lines)\n" \
            "$name" "$(wc -l < "$raw" 2>/dev/null || echo '?')" "$(wc -l < "$post" 2>/dev/null || echo '?')"

        # Run L1/L2 to locate where the divergence begins
        l1l2_out=$("$ROOT/scripts/ad_l1l2" "$OLD" "$NEW" "$timed" 2>/dev/null || true)
        if [[ -n "$l1l2_out" ]]; then
            echo "    L1/L2:"
            echo "$l1l2_out" | sed 's/^/      /'
        else
            echo "    L1/L2: (no output — timed file may be empty or animator crashed)"
        fi

        echo "    diff (expected vs got), first 20 lines:"
        diff "$NEW" "$snap" 2>/dev/null | head -20 | sed 's/^/      /' || true
        echo ""
    fi
done

echo ""
echo "=== Reversed-direction results: $pass/$total passed, $fail failed ==="

# If everything passed, also run L1/L2 on every case for the audit table.
if [[ $fail -eq 0 ]]; then
    echo ""
    echo "=== L1/L2 audit on every reversed timed file ==="
    printf "%-35s %-6s %-6s %-8s %-8s\n" "CASE" "L1" "L2" "L2_HUNK" "L_TOTAL"
    for d in "${cases[@]}"; do
        d="${d%/}"
        pair=$(find_pair "$d")
        [[ -z "$pair" ]] && continue
        name=$(basename "$d")
        OLD_A="${pair%%|*}"
        NEW_A="${pair##*|}"
        timed="$OUTDIR/${name}.timed"
        [[ -f "$timed" ]] || continue
        out=$("$ROOT/scripts/ad_l1l2" "$NEW_A" "$OLD_A" "$timed" 2>/dev/null || true)
        l1=$(echo "$out" | awk -F= '/^L1=/ {print $2}')
        l2=$(echo "$out" | awk -F= '/^L2=/ {print $2}')
        l2hunk=$(echo "$out" | awk -F= '/^L2_HUNK=/ {print $2}')
        ltotal=$(echo "$out" | awk -F= '/^L_TOTAL=/ {print $2}')
        printf "%-35s %-6s %-6s %-8s %-8s\n" "$name" "${l1:-?}" "${l2:-?}" "${l2hunk:-?}" "${ltotal:-?}"
    done
fi

exit $((fail == 0 ? 0 : 1))
