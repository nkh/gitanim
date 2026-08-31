# scripts/lib/ad_route.sh — Shared option routing for ad_vim, ad_pipeline,
# ad_snapshot.sh, and ad_tmux.
#
# Source this file from any script that needs to route CLI options to
# the pipeline stages:
#
#   source "$(dirname "$0")/lib/ad_route.sh"
#
# Then call:
#   ad_route_option "$opt" "$val" COMPUTE_ARGS POSTPROCESS_ARGS PACE_ARGS DECORATE_ARGS ANIMATOR_ARGS
#
# The function inspects the option name and appends it to the correct
# array (by reference, using nameref).

# Route a single option to the appropriate stage's args array.
# Usage: ad_route_option OPT VAL COMPUTE_ARGS POSTPROCESS_ARGS PACE_ARGS DECORATE_ARGS ANIMATOR_ARGS
# All array names are passed by nameref (bash 4.3+).
ad_route_option() {
    local opt="$1"
    local val="$2"
    local -n _ra_compute="$3"
    local -n _ra_postprocess="$4"
    local -n _ra_pace="$5"
    local -n _ra_decorate="$6"
    local -n _ra_animator="$7"

    case "$opt" in
        # Compute options
        --word-diff|--no-optimize-sequence)
            _ra_compute+=("$opt")
            [[ -n "$val" ]] && _ra_compute+=("$val")
            ;;
        # Postprocess (layer) options
        --indent-last|--overwrite|--line-delete-in-place)
            _ra_postprocess+=("--ad-layer=ad_layer_${opt#--}")
            ;;
        --ad-layer=*|--ad-layer-path=*|--ad-layer-arg=*|--ad-layer-passthrough=*)
            _ra_postprocess+=("$opt")
            ;;
        --ad-layer|--ad-layer-path|--ad-layer-arg)
            _ra_postprocess+=("$opt")
            [[ -n "$val" ]] && _ra_postprocess+=("$val")
            ;;
        # Pace options
        --delete-pacing|--insert-pacing|--delete-speed|--insert-speed|\
        --delete-threshold|--pacing|--gaussian-jitter-pct|\
        --pause-after-lines|--pause-after-threshold|--pause-after-ms|\
        --accel-delete|--accel-delete-start-ms|--accel-delete-min-ms|--accel-delete-accel|\
        --block-delete-size|--pause-before-delete-ms|--pause-after-delete-ms|\
        --flash-pause-ms|--flash-highlight-ms|\
        --cursor-glide-ms|--cursor-glide-show-intermediate|\
        --distance-speed|--distance-threshold|--distance-fast-mult|--distance-slow-mult|\
        --hunk-pause-ms|--type-delay-ms|--delete-delay-ms|--word-pause-ms)
            _ra_pace+=("$opt")
            [[ -n "$val" ]] && _ra_pace+=("$val")
            ;;
        # Decorate (highlight) options
        --highlight|--highlight-color|--highlight-duration-ms|\
        --dim-unchanged|--dim-unchanged-pct|-D|\
        --fold-unchanged|--context|--sign-column|--git-blame|\
        --max-hunk-chars|--theme|-t)
            _ra_decorate+=("$opt")
            [[ -n "$val" ]] && _ra_decorate+=("$val")
            ;;
        # Animator options
        --diff-stat|--diff-highlight|--bell|--scroll|--line-numbers|--progress|--speed)
            _ra_animator+=("$opt")
            [[ -n "$val" ]] && _ra_animator+=("$val")
            ;;
        *)
            # Unknown option — default to animator
            _ra_animator+=("$opt")
            [[ -n "$val" ]] && _ra_animator+=("$val")
            ;;
    esac
}
