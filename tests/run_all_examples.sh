#!/usr/bin/env bash
# run_all_examples.sh — Run every example through the full pipeline.
#
# This is the canonical end-to-end test corpus. Each subdirectory of
# tests/examples/ contains an `old.<ext>` and `new.<ext>` file pair.
# We run each through:
#   ad_compute → ad_postprocess → ad_layer_pace → ad
# and verify the final buffer matches `new.<ext>`.
#
# Usage: bash tests/run_all_examples.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pass=0
fail=0
total=0
errors=()

for d in "$ROOT"/tests/examples/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    old=""; new=""
    for ext in py txt go rs c ts sh yaml yml json xml html css js rb php java kt swift scala ex cl md toml lua Dockerfile Makefile R; do
        [[ -z "$old" && -f "$d/old.$ext" ]] && old="$d/old.$ext"
        [[ -z "$new" && -f "$d/new.$ext" ]] && new="$d/new.$ext"
    done
    [[ -z "$old" || -z "$new" ]] && continue
    total=$((total + 1))

    raw="/tmp/ad_ex_raw.txt"
    post="/tmp/ad_ex_post.txt"
    timed="/tmp/ad_ex_timed.txt"
    snap="/tmp/ad_ex_snap.txt"

    "$ROOT/bin/ad_compute" "$old" "$new" "$raw" 2>/dev/null
    "$ROOT/pipeline/bin/ad_postprocess" --ad-layer=ad_layer_reorder < "$raw" > "$post" 2>/dev/null
    "$ROOT/bin/ad_layer_pace" < "$post" > "$timed" 2>/dev/null
    "$ROOT/bin/ad" --no-display --speed 1000 --snapshot "$snap" "$old" < "$timed" 2>/dev/null

    if diff -q "$snap" "$new" >/dev/null 2>&1; then
        pass=$((pass + 1))
        printf "%-35s PASS\n" "$name"
    else
        fail=$((fail + 1))
        errors+=("$name")
        printf "%-35s FAIL\n" "$name"
    fi
done

echo ""
echo "=== Results: $pass/$total passed ==="
if [[ ${#errors[@]} -gt 0 ]]; then
    echo "Failed examples:"
    for e in "${errors[@]}"; do
        echo "  - $e"
    done
    exit 1
fi
exit 0
