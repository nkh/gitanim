# ad_layer_groups.sh — Parse layer group files for ad debugging scripts.
#
# Source this from ad_session, ad_tmux_watch, etc.
#
# Format:
#   # comment
#   group_name
#   layer1
#   layer2
#
#   group_name_2
#   layerA
#   layerB

# Parse a layer group file and extract layers for a given group.
# Usage: ad_layers_parse <file> <group_name>
# Output: AD_LAYERS_ARRAY, AD_LAYERS_RESULT
# Returns: 0 on success, 1 if file/group not found
ad_layers_parse() {
    local file="$1"
    local group="$2"
    AD_LAYERS_RESULT=""
    AD_LAYERS_ARRAY=()

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    local in_group=0
    local found=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments only (NOT blank lines — blank lines are group separators)
        [[ "$line" =~ ^[[:space:]]*# ]] && continue

        # Trim whitespace
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        # Empty line = group separator
        if [[ -z "$line" ]]; then
            if [[ $in_group -eq 1 && $found -eq 1 ]]; then
                break  # End of our group
            fi
            in_group=0
            continue
        fi

        # First non-blank line after separator = group name
        if [[ $in_group -eq 0 ]]; then
            if [[ "$line" == "$group" ]]; then
                in_group=1
                found=1
            else
                in_group=1  # In a different group, skip
                found=0
            fi
            continue
        fi

        # In a group — collect layer names
        if [[ $found -eq 1 ]]; then
            AD_LAYERS_ARRAY+=("$line")
        fi
    done < "$file"

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
AD_LAYERS_DEFAULT_GROUP="default"
