#!/usr/bin/env bash
# dv_debug_bundle.sh — Generate a debug bundle for reporting issues.
#
# Usage: dv_debug_bundle.sh <oldfile> <newfile> [description]
#        dv_debug_bundle.sh -h | --help
#
# Creates a tar.gz containing everything needed to debug an issue:
# - Binary MD5s (compute, postprocess, pace, animator, decorate)
# - Input files (old, new)
# - Pipeline stage outputs (raw, post, timed, decorated)
# - Settings used
# - System info (OS, vim version, git commit)
# - User description of the problem
#
# Non-interactive: description is passed as the 3rd argument.

show_help() {
cat <<'HELP'
NAME
    dv_debug_bundle.sh — Generate a debug bundle for reporting diffvim issues

SYNOPSIS
    dv_debug_bundle.sh [-h|--help]
    dv_debug_bundle.sh <oldfile> <newfile> [description]

DESCRIPTION
    Runs the full diffvim pipeline (compute → postprocess → pace →
    decorate → animator) on the given old/new file pair, then packages
    every intermediate stage output, the binary MD5s, the active
    settings, system info, and the user-supplied problem description
    into a single tar.gz archive.

    The resulting bundle contains everything a maintainer needs to
    reproduce and debug an issue — no need to manually collect logs
    or run multiple commands.

    The bundle is written to /tmp/diffvim_debug_<timestamp>.tar.gz
    and the path is printed to stdout.

OPTIONS
    -h, --help              Show this help message and exit 0.
    <oldfile>               Path to the original/source file.
    <newfile>               Path to the target file.
    [description]           Optional free-text description of the
                            problem (default: "No description provided.").

BUNDLE CONTENTS
    The tar.gz archive contains the following files:

    old.txt                 Copy of the input old file.
    new.txt                 Copy of the input new file.
    raw_ops.txt             Stage 1 — compute output (raw diff ops).
    post_ops.txt            Stage 2 — postprocess output.
    timed_ops.txt           Stage 3 — pace output (timed ops).
    decorated_ops.txt      Stage 4 — decorate output (if available).
    animator_output.txt     Final animator output buffer.
    output_diff.txt         Diff between expected (newfile) and actual.
    binary_md5s.txt         MD5 checksums of all pipeline binaries.
    settings.conf           Default diffvim launcher settings.
    system_info.txt         OS, vim, perl, gcc, git commit/branch.
    description.txt         User-supplied problem description.
    op_counts.txt           Op counts per stage + \\n delete counts.
    *_stderr.txt            stderr captured from each pipeline stage.

EXAMPLES
    dv_debug_bundle.sh old.py new.py
        Generate a bundle with the default description.

    dv_debug_bundle.sh old.py new.py "Cursor jumps to wrong line after \\n delete"
        Generate a bundle with a specific problem description.

    dv_debug_bundle.sh tests/examples/02_large_python/old.py \\
                         tests/examples/02_large_python/new.py \\
                         "Line 7 shows 'O operation.' instead of 'O'"
        Reproduce the scattered-LCS bug for the maintainer.

OUTPUT
    /tmp/diffvim_debug_<YYYYMMDD_HHMMSS>.tar.gz

EXIT STATUS
    0   Bundle created successfully.
    1   Invalid arguments or pipeline failure.

SEE ALSO
    diffvim(1), ad_compute(1), ad(1),
    snapshot_per_op(1)
HELP
}

# Handle -h/--help BEFORE set -euo pipefail (so we don't fail on unset
# OLD/NEW when the user just wants help).
for arg in "$@"; do
    case "$arg" in
        -h|--help)
            show_help
            exit 0
            ;;
    esac
done

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -lt 2 ]]; then
    echo "dv_debug_bundle.sh: error: requires <oldfile> and <newfile>" >&2
    echo "Usage: dv_debug_bundle.sh <oldfile> <newfile> [description]" >&2
    echo "       dv_debug_bundle.sh -h | --help   for full help" >&2
    exit 1
fi

OLD="${1:?}"
NEW="${2:?}"
DESCRIPTION="${3:-No description provided.}"

# Validate files exist
if [[ ! -f "$OLD" ]]; then
    echo "dv_debug_bundle.sh: error: old file does not exist: $OLD" >&2
    exit 1
fi
if [[ ! -f "$NEW" ]]; then
    echo "dv_debug_bundle.sh: error: new file does not exist: $NEW" >&2
    exit 1
fi

WORKDIR=$(mktemp -d)
BUNDLE_NAME="diffvim_debug_$(date +%Y%m%d_%H%M%S)"
BUNDLE_DIR="$WORKDIR/$BUNDLE_NAME"
mkdir -p "$BUNDLE_DIR"

echo "dv_debug_bundle.sh: generating debug bundle..." >&2

# 1. Copy input files
cp "$OLD" "$BUNDLE_DIR/old.txt"
cp "$NEW" "$BUNDLE_DIR/new.txt"

# 2. Run pipeline with DEFAULT settings (same as launcher)
export --left-to-right
"$ROOT/bin/ad_compute" "$OLD" "$NEW" "$BUNDLE_DIR/raw_ops.txt" 2>"$BUNDLE_DIR/compute_stderr.txt"
"$ROOT/bin/ad_postprocess" < "$BUNDLE_DIR/raw_ops.txt" > "$BUNDLE_DIR/post_ops.txt" 2>"$BUNDLE_DIR/postprocess_stderr.txt"
"$ROOT/bin/ad_layer_pace" --delete-pacing word --insert-pacing char < "$BUNDLE_DIR/post_ops.txt" > "$BUNDLE_DIR/timed_ops.txt" 2>"$BUNDLE_DIR/pace_stderr.txt"

# 3. Run decorate if available
if [[ -f "$ROOT/bin/ad_layer_highlight" ]]; then
    "$ROOT/bin/ad_layer_highlight" < "$BUNDLE_DIR/timed_ops.txt" > "$BUNDLE_DIR/decorated_ops.txt" 2>"$BUNDLE_DIR/decorate_stderr.txt"
fi

# 4. Run animator
"$ROOT/bin/ad" --no-display --speed 1000 --snapshot "$BUNDLE_DIR/animator_output.txt" "$OLD" < "$BUNDLE_DIR/timed_ops.txt" 2>"$BUNDLE_DIR/animator_stderr.txt"

# 5. Binary MD5s
{
    echo "# Binary MD5s"
    echo "compute-cpp: $(md5sum "$ROOT/bin/ad_compute" | awk '{print $1}')"
    echo "postprocess: $(md5sum "$ROOT/bin/ad_postprocess" | awk '{print $1}')"
    echo "pace: $(md5sum "$ROOT/bin/ad_layer_pace" | awk '{print $1}')"
    echo "animator-c: $(md5sum "$ROOT/bin/ad" | awk '{print $1}')"
    echo "decorate: $(md5sum "$ROOT/bin/ad_layer_highlight" | awk '{print $1}')"
} > "$BUNDLE_DIR/binary_md5s.txt"

# 6. Settings
{
    echo "# diffvim launcher default settings"
    echo "AD_LEFT_TO_RIGHT=1"
    echo "AD_DELETE_PACING=word"
    echo "AD_INSERT_PACING=char"
    echo "AD_OP_ORDER=optimize"
    echo "AD_PACING=uniform"
    echo "AD_HIGHLIGHT=none"
    echo "# (all other settings are defaults — see set_config for details)"
} > "$BUNDLE_DIR/settings.conf"

# 7. System info
{
    echo "# System info"
    echo "OS: $(uname -a)"
    echo "Vim: $(vim --version 2>/dev/null | head -1 || echo 'not found')"
    echo "Perl: $(perl --version 2>/dev/null | head -2 | tail -1 || echo 'not found')"
    echo "GCC: $(gcc --version 2>/dev/null | head -1 || echo 'not found')"
    echo "Git commit: $(cd "$ROOT" && git log --oneline -1 2>/dev/null || echo 'unknown')"
    echo "Git branch: $(cd "$ROOT" && git branch --show-current 2>/dev/null || echo 'unknown')"
    echo "Date: $(date)"
} > "$BUNDLE_DIR/system_info.txt"

# 8. User description
echo "$DESCRIPTION" > "$BUNDLE_DIR/description.txt"

# 9. Diff comparison
diff "$NEW" "$BUNDLE_DIR/animator_output.txt" > "$BUNDLE_DIR/output_diff.txt" 2>&1 || true

# 10. Op counts
{
    echo "# Op counts per stage"
    echo "raw: $(grep -v "^#\|^$" "$BUNDLE_DIR/raw_ops.txt" | wc -l)"
    echo "post: $(grep -v "^#\|^$" "$BUNDLE_DIR/post_ops.txt" | wc -l)"
    echo "timed: $(grep -v "^#\|^$" "$BUNDLE_DIR/timed_ops.txt" | wc -l)"
    if [[ -f "$BUNDLE_DIR/decorated_ops.txt" ]]; then
        echo "decorated: $(grep -v "^#\|^$" "$BUNDLE_DIR/decorated_ops.txt" | wc -l)"
    fi
    echo ""
    echo "# \\n deletes per stage"
    echo "raw: $(awk -F'\t' '/^delete/ && $4==10' "$BUNDLE_DIR/raw_ops.txt" | wc -l)"
    echo "post: $(awk -F'\t' '/^delete/ && $4==10' "$BUNDLE_DIR/post_ops.txt" | wc -l)"
    echo "timed: $(awk -F'\t' '/^delete/ && $4==10' "$BUNDLE_DIR/timed_ops.txt" | wc -l)"
} > "$BUNDLE_DIR/op_counts.txt"

# 11. Create tarball
TARBALL="/tmp/${BUNDLE_NAME}.tar.gz"
tar -czf "$TARBALL" -C "$WORKDIR" "$BUNDLE_NAME"
rm -rf "$WORKDIR"

echo "dv_debug_bundle.sh: bundle created at $TARBALL" >&2
echo "Contents:"
echo "  old.txt, new.txt              — input files"
echo "  raw_ops.txt                   — Stage 1 (compute output)"
echo "  post_ops.txt                  — Stage 2 (postprocess output)"
echo "  timed_ops.txt                 — Stage 3 (pace output)"
echo "  decorated_ops.txt             — Stage 4 (decorate output)"
echo "  animator_output.txt           — Final animator output"
echo "  output_diff.txt               — Diff between expected and actual"
echo "  binary_md5s.txt               — MD5s of all binaries"
echo "  settings.conf                 — Settings used"
echo "  system_info.txt               — OS, vim, perl, gcc versions"
echo "  description.txt               — User description of the problem"
echo "  op_counts.txt                 — Op counts and \\n delete counts"
echo "  *_stderr.txt                  — stderr from each stage"
echo ""
echo "To share: send $TARBALL"
