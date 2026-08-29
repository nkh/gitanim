#!/usr/bin/env bash
# dv_tune.sh — Interactive workbench for tuning postprocessing and pacing.
#
# Provides a menu-driven interface for testing diffvim options on short
# files. Can stream ops to an animator running in another terminal via
# file descriptor 5 (fd 5).
#
# Usage:
#   diffvim-tune [oldfile newfile]
#   diffvim-tune --workdir /tmp/dvt1 [oldfile newfile]
#   diffvim-tune --tmux  # run animator in a tmux split
#
# Streaming to an animator:
#   Terminal 1: diffvim-tune --stream 5 3>&1 1>&2 2>&3 | animator oldfile
#   Or with named pipes:
#   mkfifo /tmp/dv_pipe
#   Terminal 2: ad oldfile < /tmp/dv_pipe
#   Terminal 1: diffvim-tune --stream-pipe /tmp/dv_pipe
#
# Debug bundle:
#   Press 'b' to generate a tar.gz with all files + user description.

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="${AD_TUNE_WORKDIR:-$(mktemp -d)}"
STREAM_FD=""
STREAM_PIPE=""
USE_TMUX=0

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workdir)   WORKDIR="$2"; shift 2 ;;
        --stream)    STREAM_FD="$2"; shift 2 ;;
        --stream-pipe) STREAM_PIPE="$2"; shift 2 ;;
        --tmux)     USE_TMUX=1; shift ;;
        --help|-h)
            sed -n '2,30p' "$0"
            exit 0
            ;;
        *)          break ;;
    esac
done

mkdir -p "$WORKDIR"

OLD="${1:-}"
NEW="${2:-}"

# Default test files if not provided
if [[ -z "$OLD" ]]; then
    printf 'hello world\nabc\ndef\n' > "$WORKDIR/old.txt"
    OLD="$WORKDIR/old.txt"
else
    cp "$OLD" "$WORKDIR/old.txt"
    OLD="$WORKDIR/old.txt"
fi
if [[ -z "$NEW" ]]; then
    printf 'hello there\nabc\nghi\n' > "$WORKDIR/new.txt"
    NEW="$WORKDIR/new.txt"
else
    cp "$NEW" "$WORKDIR/new.txt"
    NEW="$WORKDIR/new.txt"
fi

# Settings (defaults)
declare -A SETTINGS=(
    [op-order]="optimize"
    [delete-pacing]="word"
    [insert-pacing]="char"
    [pacing]="uniform"
    [highlight]="none"
    [left-to-right]="1"
    [semantic-cleanup]="0"
    [overwrite]="0"
    [accel-delete]="0"
    [block-delete-size]="3"
    [dim-unchanged]="0"
    [fold-unchanged]="0"
    [sign-column]="0"
    [speed]="1.0"
)

# Track which settings were changed from defaults
declare -A CHANGED=()

# Available settings for fzf pick
ALL_SETTINGS="op-order delete-pacing insert-pacing pacing highlight left-to-right semantic-cleanup overwrite accel-delete block-delete-size dim-unchanged fold-unchanged sign-column speed"

# Option values for each setting
declare -A OPTIONS=(
    [op-order]="natural optimize left-to-right end-first end-first-smart"
    [delete-pacing]="char rapid-eol rapid-identical word instant"
    [insert-pacing]="char word"
    [pacing]="uniform adaptive gaussian review"
    [highlight]="none inline word hunk"
    [left-to-right]="0 1"
    [semantic-cleanup]="0 1"
    [overwrite]="0 1"
    [accel-delete]="0 1"
    [block-delete-size]="1 2 3 5 10"
    [dim-unchanged]="0 1"
    [fold-unchanged]="0 1"
    [sign-column]="0 1"
    [speed]="0.5 0.7 1.0 1.5 2.0 5.0"
)

display_menu() {
    clear
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║           diffvim-tune — postprocessing workbench           ║"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Files: old=$OLD"
    echo "║        new=$NEW"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Active settings:"
    for key in $ALL_SETTINGS; do
        marker=""
        [[ -n "${CHANGED[$key]:-}" ]] && marker=" *"
        printf "║   %-20s = %s%s\n" "$key" "${SETTINGS[$key]}" "$marker"
    done
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo "║ Actions:"
    echo "║   r=run animate  p=show post ops  t=show timed ops"
    echo "║   v=visualize    m=minimal tests  b=debug bundle"
    echo "║   e=edit old      E=edit new       s=swap files"
    echo "║   d=diff files    +=add setting(via fzf)"
    echo "║   c=clear changes S=save settings  L=load settings"
    echo "║   q=quit"
    echo "╠══════════════════════════════════════════════════════════════╣"
    echo -n "║ > "
}

run_pipeline() {
    local raw="$WORKDIR/raw.txt"
    local post="$WORKDIR/post.txt"
    local timed="$WORKDIR/timed.txt"
    local dec="$WORKDIR/decorated.txt"

    # Stage 1: Compute
    local compute_args=""
    [[ "${SETTINGS[left-to-right]}" == "1" ]] && compute_args+=" --left-to-right"
    "$ROOT/bin/ad_compute" $compute_args "$OLD" "$NEW" "$raw" 2>/dev/null

    # Stage 2: Postprocess
    local pp_args=""
    [[ "${SETTINGS[op-order]}" != "optimize" ]] && pp_args+=" --op-order ${SETTINGS[op-order]}"
    [[ "${SETTINGS[semantic-cleanup]}" == "1" ]] && pp_args+=" --semantic-cleanup"
    [[ "${SETTINGS[overwrite]}" == "1" ]] && pp_args+=" --overwrite"
    $ROOT/bin/ad_postprocess $pp_args < "$raw" > "$post" 2>/dev/null

    # Stage 3: Pace
    local pace_args="--delete-pacing ${SETTINGS[delete-pacing]} --insert-pacing ${SETTINGS[insert-pacing]}"
    pace_args+=" --pacing ${SETTINGS[pacing]}"
    [[ "${SETTINGS[accel-delete]}" == "1" ]] && pace_args+=" --accel-delete"
    pace_args+=" --block-delete-size ${SETTINGS[block-delete-size]}"
    $ROOT/bin/ad_layer_pace $pace_args < "$post" > "$timed" 2>/dev/null

    # Stage 4: Decorate
    local dec_args=""
    [[ "${SETTINGS[highlight]}" != "none" ]] && dec_args+=" --highlight ${SETTINGS[highlight]}"
    [[ "${SETTINGS[dim-unchanged]}" == "1" ]] && dec_args+=" --dim-unchanged"
    [[ "${SETTINGS[fold-unchanged]}" == "1" ]] && dec_args+=" --fold-unchanged"
    [[ "${SETTINGS[sign-column]}" == "1" ]] && dec_args+=" --sign-column"
    if [[ -n "$dec_args" ]]; then
        $ROOT/bin/ad_layer_highlight $dec_args < "$timed" > "$dec" 2>/dev/null
        echo "$dec"
    else
        echo "$timed"
    fi
}

run_animate() {
    local ops_file
    ops_file=$(run_pipeline)

    if [[ -n "$STREAM_PIPE" ]]; then
        # Stream to named pipe
        cat "$ops_file" > "$STREAM_PIPE" &
        echo "Streamed to $STREAM_PIPE"
    elif [[ -n "$STREAM_FD" ]]; then
        # Stream to file descriptor
        cat "$ops_file" >&"$STREAM_FD"
        echo "Streamed to fd $STREAM_FD"
    elif [[ $USE_TMUX -eq 1 ]]; then
        # Run in tmux split
        tmux split-window -h "cat '$ops_file' | $ROOT/bin/ad '$OLD'"
    else
        # Run directly
        echo "Running animation... (press q to quit)"
        cat "$ops_file" | $ROOT/bin/ad --speed "${SETTINGS[speed]}" "$OLD"
    fi
}

generate_debug_bundle() {
    local bundle_dir="$WORKDIR/debug_bundle_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bundle_dir"

    # Copy files
    cp "$OLD" "$bundle_dir/old.txt"
    cp "$NEW" "$bundle_dir/new.txt"
    [[ -f "$WORKDIR/raw.txt" ]] && cp "$WORKDIR/raw.txt" "$bundle_dir/"
    [[ -f "$WORKDIR/post.txt" ]] && cp "$WORKDIR/post.txt" "$bundle_dir/"
    [[ -f "$WORKDIR/timed.txt" ]] && cp "$WORKDIR/timed.txt" "$bundle_dir/"
    [[ -f "$WORKDIR/decorated.txt" ]] && cp "$WORKDIR/decorated.txt" "$bundle_dir/"

    # Save settings
    {
        echo "# dv_tune.sh settings"
        for key in $ALL_SETTINGS; do
            echo "$key=${SETTINGS[$key]}"
        done
    } > "$bundle_dir/settings.conf"

    # System info
    {
        echo "OS: $(uname -a)"
        echo "Vim: $(vim --version 2>/dev/null | head -1)"
        echo "diffvim: $(cd "$ROOT" && git log --oneline -1 2>/dev/null)"
        echo "Date: $(date)"
    } > "$bundle_dir/system_info.txt"

    # User description
    echo "Enter a description of the problem (Ctrl-D to finish):"
    cat > "$bundle_dir/description.txt"

    # Create tarball
    local tarball="$WORKDIR/debug_bundle.tar.gz"
    tar -czf "$tarball" -C "$WORKDIR" "$(basename "$bundle_dir")"
    echo "Debug bundle: $tarball"
}

# Main loop
while true; do
    display_menu
    read -rn1 key
    echo ""

    case "$key" in
        r|R)
            run_animate
            echo "Press Enter to continue..."
            read -r
            ;;
        p|P)
            run_pipeline > /dev/null
            less -S "$WORKDIR/post.txt" 2>/dev/null || echo "No post.txt yet"
            ;;
        t|T)
            run_pipeline > /dev/null
            less -S "$WORKDIR/timed.txt" 2>/dev/null || echo "No timed.txt yet"
            ;;
        v|V)
            ops_file=$(run_pipeline)
            bash "$ROOT/scripts/ad_snapshot.sh" "$OLD" "$NEW" 2>/dev/null
            echo "Snapshots: file:///tmp/ad_snapshots/snapshots.html"
            echo "Press Enter to continue..."
            read -r
            ;;
        m|M)
            bash "$ROOT/tests/run_minimal_tests.sh" 2>&1 | tail -5
            echo "Press Enter to continue..."
            read -r
            ;;
        b|B)
            generate_debug_bundle
            echo "Press Enter to continue..."
            read -r
            ;;
        e)
            ${EDITOR:-vim} "$OLD"
            ;;
        E)
            ${EDITOR:-vim} "$NEW"
            ;;
        s|S)
            tmp="$OLD"; OLD="$NEW"; NEW="$tmp"
            ;;
        d|D)
            diff "$OLD" "$NEW" | less
            ;;
        '+')
            # Add setting via fzf
            if command -v fzf >/dev/null 2>&1; then
                new_key=$(echo "$ALL_SETTINGS" | tr ' ' '\n' | fzf --prompt="Setting to add: ")
                if [[ -n "$new_key" ]]; then
                    new_val=$(echo "${OPTIONS[$new_key]}" | tr ' ' '\n' | fzf --prompt="Value for $new_key: ")
                    if [[ -n "$new_val" ]]; then
                        SETTINGS[$new_key]="$new_val"
                        CHANGED[$new_key]=1
                    fi
                fi
            else
                echo "fzf not installed. Available settings:"
                echo "$ALL_SETTINGS"
                echo -n "Setting name: "; read -r sk
                echo "Options: ${OPTIONS[$sk]:-none}"
                echo -n "Value: "; read -r sv
                SETTINGS[$sk]="$sv"
                CHANGED[$sk]=1
            fi
            ;;
        c|C)
            for key in $ALL_SETTINGS; do
                unset CHANGED[$key]
            done
            declare -A CHANGED=()
            echo "Changes cleared."
            sleep 1
            ;;
        S)
            {
                for key in $ALL_SETTINGS; do
                    echo "$key=${SETTINGS[$key]}"
                done
            } > "$WORKDIR/saved_settings.conf"
            echo "Saved to $WORKDIR/saved_settings.conf"
            sleep 1
            ;;
        L)
            if [[ -f "$WORKDIR/saved_settings.conf" ]]; then
                while IFS='=' read -r k v; do
                    SETTINGS[$k]="$v"
                    CHANGED[$k]=1
                done < "$WORKDIR/saved_settings.conf"
                echo "Loaded."
            else
                echo "No saved settings."
            fi
            sleep 1
            ;;
        q|Q)
            echo "Bye."
            exit 0
            ;;
        *)
            # Number keys 1-9 to toggle settings quickly
            if [[ "$key" =~ [1-9] ]]; then
                keys=($ALL_SETTINGS)
                idx=$((key - 1))
                if [[ $idx -lt ${#keys[@]} ]]; then
                    setting="${keys[$idx]}"
                    opts="${OPTIONS[$setting]}"
                    # Cycle through options
                    current="${SETTINGS[$setting]}"
                    found=0
                    next=""
                    for opt in $opts; do
                        if [[ $found -eq 1 ]]; then
                            next="$opt"
                            break
                        fi
                        if [[ "$opt" == "$current" ]]; then
                            found=1
                        fi
                    done
                    if [[ -z "$next" ]]; then
                        next=$(echo "$opts" | cut -d' ' -f1)
                    fi
                    SETTINGS[$setting]="$next"
                    CHANGED[$setting]=1
                fi
            fi
            ;;
    esac
done
