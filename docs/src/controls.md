# Controls

During animation, the following keys are active in vim normal mode.

## Basic Controls

| Key | Action |
|-----|--------|
| `Space` | Pause / resume the animation |
| `n` | Skip current hunk (apply instantly, move to next) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation (leave buffer for editing) |

## Speed Controls

| Key | Action |
|-----|--------|
| `+` | Speed up (multiply speed by 1.5) |
| `-` | Slow down (divide speed by 1.5) |
| `=` | Reset speed to 1.0x |

## Granular Navigation

| Key | Action |
|-----|--------|
| `B` (Shift-B) | Go back one char op |
| `N` (Shift-N) | Skip to next file (multi-file mode) |
| `Ctrl-B` | Go back to the beginning |
| `Ctrl-N` | Skip to the end |

## Undo/Redo

| Key | Action |
|-----|--------|
| `u` | Undo last hunk (revert to previous snapshot) |
| `Ctrl-r` | Redo hunk |

## Help

| Key | Action |
|-----|--------|
| `?` | Toggle full-screen help overlay |

## Step Mode

When launched with `--step-mode`, `Space` advances one char op at a time
instead of toggling pause/resume. This is useful for detailed inspection
of the diff.

## Progress Display

A progress message is shown in the vim status line:

```
diffvim: hunk 3/7 (42%) | speed 2.3x | PAUSED
```

This shows:
- Current hunk index and total
- Percentage complete
- Current speed multiplier (if not 1.0x)
- PAUSED indicator (when paused)
