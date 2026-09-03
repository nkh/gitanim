# ad_layer_groups.sh — Parse layer group files for ad debugging scripts.
#
# File format:
#   # comment
#   default                    ← first non-comment line = active group name
#
#   default                    ← group definition
#   ad_layer_reorder
#
#   debug_full                 ← another group
#   ad_layer_reorder
#   ad_layer_indent_last
#
# To switch groups: edit the first line, save. Ops regenerate.

# Parse a layer group file.
# Usage: ad_layers_parse <file>
# Reads the first non-comment line as the active group name,
# then finds that group's layers (after the selector + blank line).
# Output: AD_LAYERS_ARRAY, AD_LAYERS_RESULT, AD_LAYERS_GROUP
# Returns: 0 on success, 1 if file not found or group not found
ad_layers_parse() {
    local file="$1"
    AD_LAYERS_RESULT=""
    AD_LAYERS_ARRAY=()
    AD_LAYERS_GROUP=""

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    # Read all lines into array
    local lines=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        lines+=("$line")
    done < "$file"

    # Step 1: Find active group name (first non-comment, non-blank line)
    local active_group=""
    local selector_idx=-1
    local i
    for i in "${!lines[@]}"; do
        local line="${lines[$i]}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [[ -n "$line" ]]; then
            active_group="$line"
            selector_idx=$i
            break
        fi
    done

    if [[ -z "$active_group" ]]; then
        return 1
    fi
    AD_LAYERS_GROUP="$active_group"

    # Step 2: Find the group definition STARTING AFTER the selector line.
    # Skip the selector line and any blank lines after it, then look for
    # the group definition.
    local in_group=0
    local found=0
    for ((i = selector_idx + 1; i < ${#lines[@]}; i++)); do
        local line="${lines[$i]}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Empty line = group separator
        if [[ -z "$line" ]]; then
            if [[ $in_group -eq 1 && $found -eq 1 ]]; then
                break
            fi
            in_group=0
            continue
        fi

        # Group name or layer?
        if [[ $in_group -eq 0 ]]; then
            if [[ "$line" == "$active_group" ]]; then
                in_group=1
                found=1
            else
                in_group=1
                found=0
            fi
            continue
        fi

        # Layer name
        if [[ $found -eq 1 ]]; then
            AD_LAYERS_ARRAY+=("$line")
        fi
    done

    if [[ $found -eq 1 ]]; then
        AD_LAYERS_RESULT="${AD_LAYERS_ARRAY[*]}"
        return 0
    else
        return 1
    fi
}

# Build --ad-layer= args from a parsed group.
ad_layers_to_args() {
    AD_LAYER_ARGS=()
    for layer in "${AD_LAYERS_ARRAY[@]}"; do
        AD_LAYER_ARGS+=("--ad-layer=$layer")
    done
}

AD_LAYERS_DEFAULT_FILE=".ad_layers"
