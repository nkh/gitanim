#!/usr/bin/env bash
# dv_record.sh — Record an animation's timed op stream for later replay.
# Usage: dv_record.sh oldfile newfile recording.dv
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OLD="$1"; NEW="$2"; RECORDING="$3"

"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" /tmp/dv_raw.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < /tmp/dv_raw.txt > /tmp/dv_post.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < /tmp/dv_post.txt > "$RECORDING"
echo "Recording saved to $RECORDING ($(wc -l < "$RECORDING") ops)"
echo "Replay with: dv_replay.sh $OLD recording.dv"
