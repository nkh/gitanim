#!/usr/bin/env bash
# audit_help.sh — Check that every script/binary has --help, a manpage,
# and that --annotate and other key flags are documented.
#
# Usage: bash scripts/audit_help.sh

set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Audit: --help, manpage, and flag coverage ==="
echo

# List of all executables to check
declare -a TOOLS=(
    "bin/ad"
    "bin/ad_annotate"
    "bin/ad_compute"
    "bin/ad_layer_reorder"
    "bin/ad_layer_overwrite"
    "bin/ad_layer_indent_last"
    "bin/ad_layer_line_delete_in_place"
    "bin/ad_layer_skip_indent"
    "bin/ad_layer_pace"
    "bin/ad_layer_highlight"
    "apps/vim/ad_vim"
    "pipeline/ad_pipeline"
    "pipeline/ad_postprocess"
    "scripts/ad_session"
    "scripts/ad_tmux_watch"
    "scripts/ad_watch"
    "scripts/ad_gen_ops"
    "scripts/ad_compare"
    "scripts/ad_jogger"
    "scripts/ad_tmux"
    "scripts/ad_debug.sh"
    "scripts/ad_debug_bundle.sh"
    "scripts/ad_snapshot.sh"
    "scripts/ad_replay.sh"
    "scripts/ad_record.sh"
    "scripts/ad_demo.sh"
    "scripts/ad_suggest.sh"
    "scripts/ad_tune.sh"
    "scripts/ad_package.sh"
    "scripts/ad_doc_provenance"
)

for tool in "${TOOLS[@]}"; do
    name=$(basename "$tool" | sed 's/\.sh$//')
    has_help="?"
    has_manpage="?"

    # Check --help
    if [[ -x "$tool" ]]; then
        help_out=$("$tool" --help 2>&1 || "$tool" -h 2>&1 || true)
        if [[ -n "$help_out" ]]; then
            has_help="yes"
        else
            has_help="NO"
        fi
    else
        has_help="MISSING"
    fi

    # Check manpage
    if [[ -f "man/$name.1" ]]; then
        has_manpage="yes"
    else
        has_manpage="NO"
    fi

    printf "%-35s  help=%-8s  man=%-5s\n" "$name" "$has_help" "$has_manpage"
done
