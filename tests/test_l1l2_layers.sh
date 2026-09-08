#!/usr/bin/env bash
# test_l1l2_layers.sh — Run L1/L2 check on all examples with various
# layer combinations. Reports which layer combos produce correct ops.
#
# Usage: bash tests/test_l1l2_layers.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Layer combinations to test
COMBOS=(
    "ad_layer_reorder"
    "ad_layer_reorder ad_layer_overwrite"
    "ad_layer_reorder ad_layer_indent_last"
    "ad_layer_reorder ad_layer_line_delete_in_place"
    "ad_layer_reorder ad_layer_skip_indent"
    "ad_layer_line_replace"
)

total_pass=0
total_fail=0

for combo in "${COMBOS[@]}"; do
    pass=0
    fail=0
    for d in "$ROOT"/tests/examples/*/; do
        name=$(basename "$d")
        old=$(ls "$d"/old.* 2>/dev/null | head -1)
        new=$(ls "$d"/new.* 2>/dev/null | head -1)
        [[ -z "$old" || -z "$new" ]] && continue

        "$ROOT/bin/ad_compute" "$old" "$new" /tmp/l1l2_raw.tsv 2>/dev/null
        args=""
        for layer in $combo; do args="$args --ad-layer=$layer"; done
        "$ROOT/pipeline/ad_postprocess" $args < /tmp/l1l2_raw.tsv > /tmp/l1l2_post.tsv 2>/dev/null
        result=$("$ROOT/scripts/ad_l1l2" "$old" "$new" /tmp/l1l2_post.tsv 2>/dev/null)
        l2=$(echo "$result" | grep '^L2=' | cut -d= -f2)

        if [[ "$l2" == "0" ]]; then
            pass=$((pass + 1))
        else
            fail=$((fail + 1))
        fi
    done
    total_pass=$((total_pass + pass))
    total_fail=$((total_fail + fail))
    printf "%-55s %2d pass, %2d fail\n" "[$combo]" "$pass" "$fail"
done

echo ""
echo "=== Total: $total_pass pass, $total_fail fail ==="
exit $((total_fail == 0 ? 0 : 1))
