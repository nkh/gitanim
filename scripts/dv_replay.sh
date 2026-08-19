#!/usr/bin/env bash
# dv_replay.sh — Replay a recorded animation.
# Usage: dv_replay.sh oldfile recording.dv
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD="$1"; RECORDING="$2"
"$ROOT/animator/bin/diffvim-animator-c" --no-display --speed 1000 --snapshot /tmp/dv_replay_out.txt "$OLD" < "$RECORDING"
echo "Replay complete. Output: /tmp/dv_replay_out.txt"
