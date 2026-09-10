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

# Levenshtein edit distance between two strings.
# Uses awk for the DP matrix — option names are short, so the subprocess
# overhead is negligible for a one-shot suggestion lookup. Returns the
# distance on stdout (empty string -> length of the other string).
#
# Correct DP recurrence:
#   d[i][j] = min(d[i-1][j] + 1,            # deletion
#                d[i][j-1] + 1,            # insertion
#                d[i-1][j-1] + cost)       # substitution (0 if equal)
#   d[0][j] = j, d[i][0] = i
#
# Two rolling rows (prev, cur) keep memory at O(min(m,n)).
# The substitution cost is held in a variable named `subst` rather than
# `sub` because `sub` is a built-in awk function and mawk rejects it as
# a variable name.
_lev_distance() {
    awk -v a="$1" -v b="$2" 'BEGIN {
        alen = length(a); blen = length(b)
        if (alen == 0) { print blen; exit }
        if (blen == 0) { print alen; exit }
        # Initialise prev row: d[0][j] = j
        for (j = 0; j <= blen; j++) prev[j] = j
        for (i = 1; i <= alen; i++) {
            cur[0] = i  # d[i][0] = i
            ai = substr(a, i, 1)
            for (j = 1; j <= blen; j++) {
                cost = (ai == substr(b, j, 1)) ? 0 : 1
                del = prev[j] + 1
                ins = cur[j-1] + 1
                # NOTE: variable is `subst`, not `sub` — `sub` is a
                # built-in awk function and mawk rejects using it as
                # a variable name.
                subst = prev[j-1] + cost
                m = del
                if (ins < m) m = ins
                if (subst < m) m = subst
                cur[j] = m
            }
            for (j = 0; j <= blen; j++) prev[j] = cur[j]
        }
        print prev[blen]
    }'
}

dv_suggest_option() {
    local wrong="$1"
    shift
    local available=("$@")
    local best=""
    local best_dist=999
    # Strip leading "--" from the wrong option once; each candidate also
    # gets stripped so the common "--" prefix doesn't pad the distance.
    local w="${wrong#--}"

    for opt in "${available[@]}"; do
        local o="${opt#--}"
        local dist
        dist=$(_lev_distance "$w" "$o")
        if [[ $dist -lt $best_dist ]]; then
            best_dist=$dist
            best="$opt"
        fi
    done

    # Only suggest if the distance is small enough (within 50% of the
    # wrong option's length — same threshold the naive version used).
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
