#!/usr/bin/env bash
# dv_record.sh — Record an animation's timed op stream for later replay.
# Usage: dv_record.sh oldfile newfile recording.dv
show_help() {
cat <<'HELP'
NAME
    dv_record.sh — Record an animation's timed op stream for later replay

SYNOPSIS
    dv_record.sh [-h|--help]
    dv_record.sh <oldfile> <newfile> <recording.dv>

DESCRIPTION
    Runs the diffvim compute + postprocess + pace pipeline on an
    old/new file pair and writes the resulting TIMED op stream (with
    delay, keep, delete, insert ops) to a recording file. The
    recording can then be replayed by dv_replay.sh without needing
    the original new file — only the old file (initial buffer) is
    needed at replay time.

    Intermediate files are written to /tmp/dv_raw.txt and
    /tmp/dv_post.txt (overwritten each run).

OPTIONS
    -h, --help       Show this help message and exit 0.
    <oldfile>        Path to the original/source file (initial buffer).
    <newfile>         Path to the target file the animation should reach.
    <recording.dv>    Path where the timed op stream will be saved.

EXAMPLES
    dv_record.sh examples/01_small_python/old.py \
                examples/01_small_python/new.py \
                /tmp/my_recording.dv
        Record the animation that transforms old.py into new.py,
        saving the timed op stream to /tmp/my_recording.dv.

    dv_replay.sh examples/01_small_python/old.py /tmp/my_recording.dv
        (After recording) replay the animation. See dv_replay.sh --help.
HELP
}

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

OLD="$1"; NEW="$2"; RECORDING="$3"

"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" /tmp/dv_raw.txt 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < /tmp/dv_raw.txt > /tmp/dv_post.txt 2>/dev/null
"$ROOT/animator/bin/pp_pace" < /tmp/dv_post.txt > "$RECORDING"
echo "Recording saved to $RECORDING ($(wc -l < "$RECORDING") ops)"
echo "Replay with: dv_replay.sh $OLD recording.dv"
