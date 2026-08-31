# Controls

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


During animation, the following keys are active in vim normal mode.

## Basic Controls

| Key | Action |
|-----|--------|
| `Space` | Pause / resume the animation |
| `n` | Skip current hunk (apply instantly, then pause for review) |
| `b` | Back to previous hunk (revert and restart) |
| `q` | Stop animation — by default `:q` then quits; use `--keep-dirty` to require `:q!` |

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

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
