#!/usr/bin/env bash
# dv_package.sh — Create a release tarball with pre-built binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-2.0}"
TARBALL="/tmp/diffvim-${VERSION}.tar.gz"

echo "Building..."
make -C "$ROOT/compute" clean all
cd "$ROOT/animator/c"
cc -O2 -o ../bin/diffvim-animator-c animator.c
cc -O2 -o ../bin/diffvim-postprocess postprocess.c
cc -O2 -o ../bin/diffvim-pace pace.c
cd "$ROOT"

echo "Packaging..."
tar czf "$TARBALL" \
    compute/bin/diffvim-compute-cpp \
    animator/bin/diffvim-animator-c \
    animator/bin/diffvim-postprocess \
    animator/bin/diffvim-pace \
    animator/perl/ \
    animator/diffvim-pipeline \
    diffvim diffvim.pl diffvim-tmux diffvim-compare \
    plugin/ autoload/ completion/ man/ \
    DiffVim/ \
    examples/ \
    scripts/ \
    README.md CHANGELOG.md LICENSE

echo "Created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
