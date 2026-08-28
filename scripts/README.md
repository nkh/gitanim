# scripts/

Helper scripts for debugging, testing, recording, and packaging. All
scripts are bash; none are compiled.

## Contents

- `ad_debug.sh` — interactive pipeline debugger
- `ad_debug_bundle.sh` — collect debug info into a tarball
- `ad_snapshot.sh` — per-op HTML snapshots
- `ad_record.sh` / `ad_replay.sh` — record and replay animations
- `ad_demo.sh` — demo runner with preset examples
- `ad_tune.sh` — interactive option tuner (tmux-based)
- `ad_suggest.sh` — suggest options for a given diff
- `ad_package.sh` — package the project for distribution
- `ad_compare` — generate diffs with all option combinations
- `ad_jogger` — generate test cases with various patterns
- `ad_tmux` — tmux-based animation launcher

## Usage

    bash scripts/ad_debug.sh old.py new.py
    bash scripts/ad_snapshot.sh old.py new.py
    bash scripts/ad_record.sh old.py new.py recording.txt
