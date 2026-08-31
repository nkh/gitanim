# Introduction

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `db72a00` (2026-08-30 08:35:56 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


**diffvim** animates a code diff in vim as if a human were typing it.

Given two versions of a file, ad_vim opens the old version in vim and
animates the transformation into the new version character by character.
The cursor glides between change locations with smooth ease-in-out
acceleration, and only the actually-changed characters are deleted and
re-typed — surrounding text is never touched.

## Three Implementations

| Implementation | Language | Vim Communication | Dependencies |
|---------------|----------|-------------------|--------------|
| `diffvim` | Bash + Vimscript | Native (timer_start) | Vim only |
| `ad_tmux` | Bash + tmux | tmux send-keys | tmux, diff, sed, awk |
| `ad_vim.pl` | Perl + tmux | tmux send-keys | Perl, tmux, diff |

## Key Features

- **Char-level diff** — only changed characters are touched (Patience / Patience algorithm)
- **Smooth cursor glide** — ease-in-out cubic between change locations
- **Interactive controls** — pause, skip, back, speed change at any time
- **Multi-file animation** — animate diffs across multiple files
- **Git replay** — animate a file's git history commit by commit
- **Plugin mode** — run as `:Diffvim` inside an existing vim
- **50+ CLI options** — speed, scroll, sign column, git blame, word diff,
  rapid-EOL delete, presets, and more
- **External compute tool** — a native C++ binary that pre-computes
  diffs 10-100x faster than vimscript Patience, for large files. Falls back
  to the embedded vimscript Patience (or Perl `compute_builtin.pl` for the
  pipeline) when the binary is missing.
- **Six built-in presets** — `default`, `fast-delete`, `review`,
  `ai-code`, `demo`, `presentation` for common use cases
- **Post-processing pipeline** — reorder, overwrite, indent_last,
  `delete_end_first`, `overwrite` to make the
  animation read naturally even on messy diffs

## Quick Example

```bash
# Animate a diff
./ad_vim old.py new.py

# Slow down for a presentation
./ad_vim --speed 0.5 --scroll zz old.py new.py

# Replay git history
./ad_vim --replay src/main.py --from HEAD~5

# Use a preset
./ad_vim --preset review --git-blame old.py new.py

# Use the C++ external compute tool for large files
bin/ad_compute old.py new.py /tmp/diff.txt
./ad_vim --precomputed /tmp/diff.txt old.py new.py

# Dry run (print diff without launching vim)
perl ad_vim.pl --dry-run old.py new.py
```

## Where to Go Next

- **New to diffvim?** Read the [Visual Guide](../VISUAL_GUIDE.md) —
  it explains graphically what ad_vim does, using ASCII drawings.
- **Want to install?** See [Installation](./installation.md).
- **Want a quick first run?** See [Quick Start](./quick-start.md).
- **Confused by all the options?** Try a [preset](./presets.md) first.
- **Need full reference?** See the [manpages](./manpages.md) or
  [Command-Line Options](./options.md).
