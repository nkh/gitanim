#!/usr/bin/env bash
# dv_package.sh — Create a release tarball with pre-built binaries.
show_help() {
cat <<'HELP'
NAME
    dv_package.sh — Create a release tarball with pre-built binaries

SYNOPSIS
    dv_package.sh [-h|--help]
    dv_package.sh [version]

DESCRIPTION
    Builds the C binaries (compute, animator-c, postprocess, pace) from
    source, then archives them together with the Perl pipeline, the
    launcher scripts (diffvim, diffvim.pl, diffvim-tmux, diffvim-compare),
    the Vim plugin (plugin/, autoload/, completion/, man/, DiffVim/),
    the tests/examples/, the scripts/, README, CHANGELOG and LICENSE into a
    single distributable .tar.gz.

    The resulting tarball is written to /tmp/diffvim-<version>.tar.gz.

OPTIONS
    -h, --help     Show this help message and exit 0.
    version        Version string to embed in the tarball filename.
                   Defaults to "2.0" if not supplied.

EXAMPLES
    dv_package.sh
        Build the 2.0 release tarball at /tmp/diffvim-2.0.tar.gz.

    dv_package.sh 2.3.1
        Build the 2.3.1 release tarball at /tmp/diffvim-2.3.1.tar.gz.

    dv_package.sh --help
        Show this help message.
HELP
}

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

VERSION="${1:-2.0}"
TARBALL="/tmp/diffvim-${VERSION}.tar.gz"

echo "Building..."
make -C "$ROOT/compute" clean all
cd "$ROOT/animator/c"
cc -O2 -o ../bin/ad animator.c
cc -O2 -o ../bin/ad_postprocess postprocess.c
cc -O2 -o ../bin/ad_layer_pace ad_layer_pace.c
cd "$ROOT"

echo "Packaging..."
tar czf "$TARBALL" \
    bin/ad_compute \
    bin/ad \
    bin/ad_postprocess \
    bin/ad_layer_pace \
    animator/perl/ \
    animator/ad_pipeline \
    diffvim diffvim.pl diffvim-tmux diffvim-compare \
    plugin/ autoload/ completion/ man/ \
    DiffVim/ \
    tests/examples/ \
    scripts/ \
    README.md CHANGELOG.md LICENSE

echo "Created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
