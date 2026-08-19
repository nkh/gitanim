#!/usr/bin/env bash
# dv_demo.sh — Run demo animations for common use cases.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Demo 1: Small Python ==="
"$ROOT/animator/diffvim-pipeline" --no-display --speed 2 "$ROOT/examples/01_small_python/old.py" "$ROOT/examples/01_small_python/new.py"

echo ""
echo "=== Demo 2: Python Classes ==="
"$ROOT/animator/diffvim-pipeline" --no-display --speed 2 "$ROOT/examples/32_python_classes/old.py" "$ROOT/examples/32_python_classes/new.py"

echo ""
echo "=== Demo 3: Large Python ==="
"$ROOT/animator/diffvim-pipeline" --no-display --speed 5 "$ROOT/examples/33_large_python/old.py" "$ROOT/examples/33_large_python/new.py"

echo ""
echo "Demos complete."
