#!/usr/bin/env bash
# dv_replay.sh — Replay a recorded animation.
# Usage: dv_replay.sh oldfile recording.dv
show_help() {
cat <<'HELP'
NAME
    dv_replay.sh — Replay a recorded animation

SYNOPSIS
    dv_replay.sh [-h|--help]
    dv_replay.sh <oldfile> <recording.dv>

DESCRIPTION
    Replays a timed op stream previously recorded by dv_record.sh.
    Loads the old file into the animator as the initial buffer, then
    feeds the timed op stream through ad (in
    --no-display mode at speed 1000, with --snapshot) so that the
    final buffer state is written to /tmp/ad_replay_$$.txt.

    This is the counterpart to dv_record.sh: the recording captures
    the timed ops, and this script replays them.

OPTIONS
    -h, --help          Show this help message and exit 0.
    <oldfile>           Path to the original/source file used as the
                        initial buffer (same file passed to dv_record.sh).
    <recording.dv>      Path to a recording file produced by dv_record.sh.

EXAMPLES
    dv_replay.sh tests/examples/01_small_python/old.py /tmp/my_recording.dv
        Replay the recording, writing the final buffer to
        /tmp/ad_replay_$$.txt.

    dv_record.sh old.py new.py /tmp/my_recording.dv
        (Companion command) record the animation first.
HELP
}

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

OLD="$1"; RECORDING="$2"
"$ROOT/bin/ad" --no-display --speed 1000 --snapshot /tmp/ad_replay_$$.txt "$OLD" < "$RECORDING"
echo "Replay complete. Output: /tmp/ad_replay_$$.txt"
