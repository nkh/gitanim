# scripts/

Debugging, testing, and verification scripts for the diffvim pipeline.

## Files

### Debugging

- `dv_debug.sh` — Run all 4 pipeline stages on a file pair, print
  summary, and write stage files to `/tmp/ad_debug/` for inspection.
  Usage: `bash scripts/dv_debug.sh <old> <new>`

- `snapshot_per_op.sh` — Take a snapshot of the buffer after every
  op and produce an HTML visualization (list format).
  Usage: `bash scripts/snapshot_per_op.sh [--show-pacing] <old> <new>`
  Output: `/tmp/ad_snapshots/snapshots.html`

- `dv_demo.sh` — Run a demo animation on example files.

- `dv_record.sh` — Record an animation to a video file.

- `dv_replay.sh` — Replay a pre-computed timed op stream.

- `dv_package.sh` — Package the project for distribution.

### Testing

- `verify_md5.sh` — Round-trip MD5 verification. Runs all 42 example
  pairs through both the C and Perl pipelines, compares output MD5
  with the new file's MD5.
  Usage: `bash tests/verify_md5.sh`

- `test_vimscript_animator.sh` — Test the vimscript animator (inside
  vim) headless. Extracts the engine, patches it to be synchronous,
  runs in `vim -e -s -n`.
  Usage: `bash tests/test_vimscript_animator.sh [example_dir]`

- `verify_md5.pl` — Perl version of MD5 verification (sequential).
- `verify_md5_parallel.pl` — Perl parallel version.
- `verify_md5_cont.pl` — Continuous verification.
- `run_vim_correctness_fast.pl` — Fast vim correctness test.

## Quick start

```bash
# Debug a specific file pair:
bash scripts/dv_debug.sh old.py new.py

# Visualize every op:
bash scripts/snapshot_per_op.sh old.py new.py
# Then open: file:///tmp/ad_snapshots/snapshots.html

# Run full test suite:
bash tests/verify_md5.sh
bash tests/test_vimscript_animator.sh

# Run minimal test cases:
bash ../tests/run_minimal_tests.sh
```

## Output directories

- `/tmp/ad_debug/` — Stage files from `dv_debug.sh`
  - `raw.txt` — Stage 1 (compute output)
  - `post.txt` — Stage 2 (postprocess output)
  - `timed.txt` — Stage 3 (pace output)
  - `snap.txt` — Stage 4 (animator final buffer)

- `/tmp/ad_snapshots/` — Per-op snapshots from `snapshot_per_op.sh`
  - `snap_0000.txt`, `snap_0001.txt`, ... — Buffer state after each op
  - `snapshots.html` — Combined HTML visualization

## Related

- `../docs/DEBUGGING.md` — Full debugging guide
- `../tests/` — Test suites and minimal test cases
