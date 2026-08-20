# Postprocessing/pacing debug interface — analysis

## The need

When working on postprocessing and pacing, we need to:
1. Quickly switch between test files (old/new pairs)
2. See current settings (which options are active)
3. Change settings quickly (op-order, delete-pacing, etc.)
4. See the result immediately (post-processed ops, timed ops)
5. Generate a debug bundle when something goes wrong

Currently this workflow is:
```bash
# Edit test files
vim /tmp/old.txt /tmp/new.txt
# Run pipeline with options
./compute/bin/diffvim-compute-cpp /tmp/old.txt /tmp/new.txt /tmp/raw.txt
./animator/bin/diffvim-postprocess --op-order optimize < /tmp/raw.txt > /tmp/post.txt
./animator/bin/diffvim-pace --delete-pacing word < /tmp/post.txt > /tmp/timed.txt
# Inspect
less -S /tmp/post.txt
# Run animation
./diffvim --speed 2 /tmp/old.txt /tmp/new.txt
# Debug
bash scripts/dv_debug.sh /tmp/old.txt /tmp/new.txt
```

This is slow and repetitive. We need a faster loop.

## Proposed solution: `diffvim-tune` interactive script

A bash-based interactive tool that provides a menu-driven interface for
tuning postprocessing and pacing.

### Design

```
┌─────────────────────────────────────────────────────────────────┐
│ diffvim-tune — postprocessing/pacing workbench                  │
├─────────────────────────────────────────────────────────────────┤
│ Files:  old=/tmp/old.txt  new=/tmp/new.txt                      │
│         (e=edit old, E=edit new, s=swap, d=diff)               │
├─────────────────────────────────────────────────────────────────┤
│ Settings:                                                       │
│   [1] op-order       = optimize                                 │
│   [2] delete-pacing  = word                                     │
│   [3] insert-pacing  = char                                     │
│   [4] left-to-right  = 1                                        │
│   [5] semantic-cleanup = 0                                     │
│   [6] indent-aware   = 0                                       │
│   [7] speed          = 1.0                                     │
├─────────────────────────────────────────────────────────────────┤
│ Actions:                                                        │
│   r = run pipeline + animate in vim                             │
│   p = show post-processed ops                                  │
│   t = show timed ops                                            │
│   v = visualize per-op snapshots (HTML)                         │
│   m = run minimal test suite                                    │
│   b = generate debug bundle                                    │
│   q = quit                                                      │
├─────────────────────────────────────────────────────────────────┤
│ > _                                                             │
└─────────────────────────────────────────────────────────────────┘
```

### Implementation

```bash
#!/usr/bin/env bash
# diffvim-tune — interactive postprocessing/pacing workbench
#
# Usage: diffvim-tune [oldfile newfile]
#   If no files given, uses tests/minimal/01_simple_replace/

# State stored in /tmp/dv_tune/
#   settings.conf  — current settings (sourced)
#   old.txt        — current old file
#   new.txt        — current new file
#   raw.txt        — last compute output
#   post.txt       — last postprocess output
#   timed.txt      — last pace output
#   debug_bundle/  — last debug bundle
```

### Key features

1. **Quick file switching** — press a number to load a minimal test case,
   or `e`/`E` to edit old/new in vim

2. **Live settings** — press 1-7 to toggle/cycle settings, see them
   change immediately

3. **Pipeline output** — `p` shows post-processed ops in `less`,
   `t` shows timed ops

4. **Quick animation** — `r` runs the full pipeline + vim animation

5. **HTML visualization** — `v` runs `snapshot_per_op.sh` and opens
   the browser

6. **Debug bundle** — `b` collects:
   - old/new files
   - raw.txt, post.txt, timed.txt
   - settings.conf
   - dv_debug.sh output
   - snapshot HTML
   - System info (vim version, OS, etc.)
   Into a tar.gz that can be shared

### Debug bundle format

```
dv_debug_bundle_20260820_153000.tar.gz
├── old.txt
├── new.txt
├── raw.txt
├── post.txt
├── timed.txt
├── settings.conf
├── dv_debug_output.txt
├── snapshots.html
├── system_info.txt
└── diffvim_version.txt
```

### Why this is better than manual commands

| Manual | diffvim-tune |
|--------|-------------|
| 5 commands to change settings + re-run | 2 keystrokes |
| Must remember all option names | Menu shows options |
| Must remember file paths | Menu loads test cases |
| No way to compare settings | Settings shown live |
| Debug info scattered across /tmp | One bundle command |

### Stability considerations

- Settings stored in a sourced config file (not inline)
- Test files copied to /tmp (originals never modified)
- All intermediate files in one directory (/tmp/dv_tune/)
- Debug bundle is self-contained (no external dependencies)
- Works with both C and Perl pipelines (toggleable)

### What it should NOT do

- Not a full TUI (no ncurses/ratatui) — bash menu is sufficient
- Not a replacement for the test suite — it's a development tool
- Not a permanent feature — it's for tuning, not for end users

## Recommendation

**Build `diffvim-tune` as a bash script** (not a full TUI). It should:
1. Live in `scripts/diffvim-tune`
2. Use a simple numbered menu (no ncurses)
3. Source settings from a config file
4. Generate debug bundles on demand
5. Be documented in `docs/DEBUGGING.md`

This gives us:
- Fast iteration on postprocessing/pacing
- Quick file switching between test cases
- One-command debug bundle generation
- No external dependencies (bash + vim + existing tools)
