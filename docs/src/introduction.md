# Introduction

**diffvim** animates a code diff in vim as if a human were typing it.

Given two versions of a file, diffvim opens the old version in vim and
animates the transformation into the new version character by character.
The cursor glides between change locations with smooth ease-in-out
acceleration, and only the actually-changed characters are deleted and
re-typed — surrounding text is never touched.

## Three Implementations

| Implementation | Language | Vim Communication | Dependencies |
|---------------|----------|-------------------|--------------|
| `diffvim` | Bash + Vimscript | Native (timer_start) | Vim only |
| `diffvim-tmux` | Bash + tmux | tmux send-keys | tmux, diff, sed, awk |
| `diffvim.pl` | Perl + tmux | tmux send-keys | Perl, tmux, diff |

## Key Features

- **Char-level diff** — only changed characters are touched (LCS / Myers / Patience algorithm)
- **Smooth cursor glide** — ease-in-out cubic between change locations
- **Interactive controls** — pause, skip, back, speed change at any time
- **Multi-file animation** — animate diffs across multiple files
- **Git replay** — animate a file's git history commit by commit
- **Plugin mode** — run as `:Diffvim` inside an existing vim
- **50+ CLI options** — speed, scroll, sign column, git blame, word diff,
  indent-aware, semantic cleanup, rapid-EOL delete, presets, and more
- **External compute tools** — C, C++, Rust, and Go binaries that
  pre-compute diffs 10-100x faster than vimscript LCS, for large files
- **Six built-in presets** — `default`, `fast-delete`, `review`,
  `ai-code`, `demo`, `presentation` for common use cases
- **Post-processing pipeline** — `optimize_sequence`, `left_to_right`,
  `semantic_cleanup`, `delete_end_first`, `overwrite` to make the
  animation read naturally even on messy diffs

## Quick Example

```bash
# Animate a diff
./diffvim old.py new.py

# Slow down for a presentation
./diffvim --speed 0.5 --scroll zz old.py new.py

# Replay git history
./diffvim --replay src/main.py --from HEAD~5

# Use a preset
./diffvim --preset review --git-blame old.py new.py

# Use the Rust external compute tool for large files
./diffvim-precomputed --tool rust old.py new.py

# Dry run (print diff without launching vim)
perl diffvim.pl --dry-run old.py new.py
```

## Where to Go Next

- **New to diffvim?** Read the [Visual Guide](../VISUAL_GUIDE.md) —
  it explains graphically what diffvim does, using ASCII drawings.
- **Want to install?** See [Installation](./installation.md).
- **Want a quick first run?** See [Quick Start](./quick-start.md).
- **Confused by all the options?** Try a [preset](./presets.md) first.
- **Need full reference?** See the [manpages](./manpages.md) or
  [Command-Line Options](./options.md).
