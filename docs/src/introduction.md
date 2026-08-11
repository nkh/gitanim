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

- **Char-level diff** — only changed characters are touched (LCS algorithm)
- **Smooth cursor glide** — ease-in-out cubic between change locations
- **Interactive controls** — pause, skip, back, speed change at any time
- **Multi-file animation** — animate diffs across multiple files
- **Git replay** — animate a file's git history commit by commit
- **Plugin mode** — run as `:Diffvim` inside an existing vim
- **20+ CLI options** — speed, scroll, sign column, git blame, word diff, etc.

## Quick Example

```bash
# Animate a diff
./diffvim old.py new.py

# Slow down for a presentation
./diffvim --speed 0.5 --scroll zz old.py new.py

# Replay git history
./diffvim --replay src/main.py --from HEAD~5

# Dry run (print diff without launching vim)
perl diffvim.pl --dry-run old.py new.py
```
