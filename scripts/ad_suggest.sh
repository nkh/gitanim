#!/usr/bin/env bash
# dv_suggest.sh — Shared "did you mean?" suggestion function.
# Source this from diffvim, ad_pipeline, and dv_snapshot_per_op.sh.
#
# Usage: dv_suggest_option "--wrong-option" "option1 option2 option3"
# Prints: "Did you mean: --option2?" to stderr
#
# When run directly (not sourced), accepts --help/-h to print this help.

# Handle --help/-h when invoked directly (not sourced).
# Sourcing detection: $0 != script name when sourced from another script.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --help|-h)
            cat <<'HELP'
ad_suggest.sh — Shared "did you mean?" suggestion library

Usage:
  Source from another script:
    source scripts/ad_suggest.sh
    dv_suggest_option "--wrong-option" "--opt1 --opt2 --opt3"
    # Prints "  Did you mean: --opt2?" to stderr if a close match is found

  Run directly (mostly for inspection):
    ad_suggest.sh --help       # this message

The library exports:
  dv_suggest_option <wrong> <available...>
      Compare <wrong> to each option in <available...>, print the closest
      match to stderr if its edit distance is within (len(wrong) / 2).
  DV_ALL_OPTIONS
      Array of all known ad_vim/ad_pipeline option names. Used as the
      default comparison set.

This is a library, not a standalone CLI tool. It is sourced by ad_vim,
ad_pipeline, ad_snapshot.sh, etc. to provide "Did you mean?" messages
when the user types an unrecognized option.
HELP
            exit 0
            ;;
        *)
            echo "ad_suggest.sh: a sourceable library, not a standalone tool." >&2
            echo "Run 'ad_suggest.sh --help' for more information." >&2
            exit 1
            ;;
    esac
fi

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
    --speed --delete-delay-ms --hunk-pause-ms --word-pause-ms
    --pacing --gaussian-jitter-pct --pause-after-lines --pause-after-threshold --pause-after-ms
    --delete-pacing --delete-speed --delete-threshold
    --insert-pacing --insert-speed
    --accel-delete --accel-delete-start-ms --accel-delete-min-ms --accel-delete-accel
    --block-delete-size --pause-before-delete-ms --pause-after-delete-ms
    --flash-pause-ms --flash-highlight-ms
    --cursor-glide-ms --cursor-glide-show-intermediate
    --distance-speed --distance-threshold --distance-fast-mult --distance-slow-mult
    --indent-last --overwrite --line-delete-in-place --ad-layer --ad-layer-path --list-layers
    --highlight --highlight-color --highlight-duration-ms
    --dim-unchanged --dim-unchanged-pct --fold-unchanged --context
    --sign-column --git-blame --max-hunk-chars --theme --max-line-len
    --diff-stat --diff-highlight --bell --scroll --line-numbers --progress
    --verbose --dry-run --word-diff --no-display --sync --no-vimrc
    --output --snapshot --help --version --preset --algorithm --annotate
    --step-mode --no-startup-pause --startup-pause --startup-feedback
    --language --sign-column --log-mode --log-file --no-log-timing --debug
    --multi --replay --git-rev --keep-dirty --precomputed
)
