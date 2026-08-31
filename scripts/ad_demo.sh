#!/usr/bin/env bash
# dv_demo.sh — Run demo animations for common use cases.
show_help() {
cat <<'HELP'
NAME
    dv_demo.sh — Run demo animations for common use cases

SYNOPSIS
    dv_demo.sh [-h|--help]

DESCRIPTION
    Runs three pre-configured ad_vim animations end-to-end through the
    ad_pipeline driver (compute → postprocess → pace → animator)
    in --no-display mode, so no terminal animator UI is shown — the
    pipeline simply runs to completion and prints progress.

    The demos exercised are:
      1. Small Python      — tests/examples/01_small_python   (speed 2)
      2. Python Classes    — tests/examples/32_python_classes  (speed 2)
      3. Large Python      — tests/examples/33_large_python    (speed 5)

    Use this script to smoke-test the pipeline after a build, or as a
    quick "does it work?" check.

OPTIONS
    -h, --help     Show this help message and exit 0.
                   This script takes no other arguments.

EXAMPLES
    dv_demo.sh
        Run all three demo animations.

    dv_demo.sh --help
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

echo "=== Demo 1: Small Python ==="
"$ROOT/pipeline/ad_pipeline" --no-display --speed 2 "$ROOT/tests/examples/01_small_python/old.py" "$ROOT/tests/examples/01_small_python/new.py"

echo ""
echo "=== Demo 2: Python Classes ==="
"$ROOT/pipeline/ad_pipeline" --no-display --speed 2 "$ROOT/tests/examples/32_python_classes/old.py" "$ROOT/tests/examples/32_python_classes/new.py"

echo ""
echo "=== Demo 3: Large Python ==="
"$ROOT/pipeline/ad_pipeline" --no-display --speed 5 "$ROOT/tests/examples/33_large_python/old.py" "$ROOT/tests/examples/33_large_python/new.py"

echo ""
echo "Demos complete."
