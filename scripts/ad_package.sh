#!/usr/bin/env bash
# ad_package.sh — Create a release tarball with pre-built binaries.
show_help() {
cat <<'HELP'
NAME
    ad_package.sh — Create a release tarball with pre-built binaries

SYNOPSIS
    ad_package.sh [-h|--help]
    ad_package.sh [version]

DESCRIPTION
    Builds all C binaries via `make`, then archives them together with
    the Perl fallbacks, the pipeline scripts, the vim application,
    the completion files, manpages, tests/examples/, scripts/, README,
    CHANGELOG and LICENSE into a single distributable .tar.gz.

    The resulting tarball is written to /tmp/ad-<version>.tar.gz.

OPTIONS
    -h, --help     Show this help message and exit 0.
    version        Version string to embed in the tarball filename.
                   Defaults to "2.0" if not supplied.

EXAMPLES
    ad_package.sh
        Build the 2.0 release tarball at /tmp/ad-2.0.tar.gz.

    ad_package.sh 2.3.1
        Build the 2.3.1 release tarball at /tmp/ad-2.3.1.tar.gz.

    ad_package.sh --help
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
TARBALL="/tmp/ad-${VERSION}.tar.gz"

echo "Building..."
cd "$ROOT"
make

echo "Packaging..."
tar czf "$TARBALL" \
    bin/ \
    diff_engine/perl/ \
    layers/perl/ \
    animator/perl/ \
    pipeline/ \
    apps/vim/ \
    completion/ \
    man/ \
    tests/examples/ \
    scripts/ \
    README.md CHANGELOG.md LICENSE

echo "Created: $TARBALL ($(du -h "$TARBALL" | cut -f1))"
