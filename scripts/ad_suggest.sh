#!/usr/bin/env bash
# dv_suggest.sh — Shared "did you mean?" suggestion function.
# Source this from diffvim, ad_pipeline, and dv_snapshot_per_op.sh.
#
# Usage: dv_suggest_option "--wrong-option" "option1 option2 option3"
# Prints: "Did you mean: --option2?" to stderr

dv_suggest_option() {
    local wrong="$1"
    shift
    local available=("$@")
    local best=""
    local best_dist=999
    
    for opt in "${available[@]}"; do
        # Simple Levenshtein-like distance: count character differences
        local dist=0
        local i=0
        local w="${wrong#--}"  # strip --
        local o="${opt#--}"
        local len=${#w}
        local olen=${#o}
        [[ $olen -gt $len ]] && len=$olen
        for ((i=0; i<len; i++)); do
            local wc="${w:$i:1}"
            local oc="${o:$i:1}"
            [[ "$wc" != "$oc" ]] && ((dist++))
        done
        if [[ $dist -lt $best_dist ]]; then
            best_dist=$dist
            best="$opt"
        fi
    done
    
    # Only suggest if the distance is small enough (within 50% of the option length)
    local threshold=$(( ${#wrong} / 2 ))
    if [[ $best_dist -le $threshold && -n "$best" ]]; then
        echo "  Did you mean: $best?" >&2
    fi
}

# The full list of valid options (shared across all tools)
DV_ALL_OPTIONS=(
    --speed --tick-ms --type-delay-ms --delete-delay-ms --hunk-pause-ms --word-pause-ms
    --pacing --gaussian-jitter-pct --pause-after-lines --pause-after-threshold --pause-after-ms
    --delete-pacing --delete-speed --delete-threshold
    --insert-pacing --insert-speed
    --accel-delete --accel-delete-start-ms --accel-delete-min-ms --accel-delete-accel
    --block-delete-size --pause-before-delete-ms --pause-after-delete-ms
    --flash-pause-ms --flash-highlight-ms
    --cursor-glide-ms --cursor-glide-show-intermediate
    --distance-speed --distance-threshold --distance-fast-mult --distance-slow-mult
    --op-order --semantic-cleanup --indent-aware --indent-last --overwrite --stream
    --highlight --highlight-color --highlight-duration-ms
    --dim-unchanged --dim-unchanged-pct --fold-unchanged --context
    --sign-column --git-blame --max-hunk-chars --theme
    --diff-stat --diff-highlight --bell --scroll
    --line-numbers --progress --verbose --dry-run
    --word-diff --no-optimize-sequence --left-to-right --no-left-to-right
    --output --snapshot --no-display --no-vimrc
    --speed --help --version --preset
)
