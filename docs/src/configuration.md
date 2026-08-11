# Configuration

## Environment Variables

All timing values can be set via environment variables. Command-line
options override environment variables, which override built-in defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| `DIFFVIM_TICK_MS` | `16` | Animation frame interval (~60fps) |
| `DIFFVIM_TYPE_DELAY_MS` | `35` | Delay between typed characters (ms) |
| `DIFFVIM_DELETE_DELAY_MS` | `25` | Delay between deleted characters (ms) |
| `DIFFVIM_MOVE_MIN_MS` | `200` | Minimum cursor glide duration (ms) |
| `DIFFVIM_MOVE_MAX_MS` | `1400` | Maximum cursor glide duration (ms) |
| `DIFFVIM_MOVE_MS_PER_UNIT` | `6` | Milliseconds per unit of glide distance |
| `DIFFVIM_HUNK_PAUSE_MS` | `180` | Pause between hunks (ms) |
| `DIFFVIM_WORD_PAUSE_MS` | `150` | Pause after instant word (ms) |
| `DIFFVIM_SPEED` | `1.0` | Speed multiplier (same as --speed) |
| `DIFFVIM_MAX_LINE_LEN` | `10000` | Warn threshold for long lines |

## Presets

### Presentation Mode (slow, dramatic)

```bash
export DIFFVIM_TYPE_DELAY_MS=80
export DIFFVIM_DELETE_DELAY_MS=60
export DIFFVIM_MOVE_MIN_MS=400
export DIFFVIM_MOVE_MAX_MS=3000
export DIFFVIM_MOVE_MS_PER_UNIT=10
export DIFFVIM_HUNK_PAUSE_MS=500
```

### Quick Review Mode (fast)

```bash
export DIFFVIM_TYPE_DELAY_MS=10
export DIFFVIM_DELETE_DELAY_MS=10
export DIFFVIM_MOVE_MIN_MS=50
export DIFFVIM_MOVE_MAX_MS=300
export DIFFVIM_MOVE_MS_PER_UNIT=3
export DIFFVIM_HUNK_PAUSE_MS=50
```

### Debug Mode (very slow, visible char ops)

```bash
export DIFFVIM_TYPE_DELAY_MS=200
export DIFFVIM_DELETE_DELAY_MS=150
export DIFFVIM_MOVE_MIN_MS=500
export DIFFVIM_MOVE_MAX_MS=5000
export DIFFVIM_MOVE_MS_PER_UNIT=15
export DIFFVIM_HUNK_PAUSE_MS=1000
```

## Vimscript Configuration (diffvim only)

The `diffvim` implementation also supports a `g:diffvim` dictionary in
your vimrc for persistent configuration:

```vim
let g:diffvim = {
    \ 'type_delay_ms': 50,
    \ 'delete_delay_ms': 30,
    \ 'move_min_ms': 300,
    \ 'move_max_ms': 2000,
    \ 'scroll': 'zz',
    \ 'max_word_chars': 5,
    \ }
```

Priority: vimrc `g:diffvim` > env vars > built-in defaults.

## Using the `set_config` Helper

The repo includes a `set_config` script with common presets:

```bash
source set_config
diffvim old.py new.py
```

## Tmux Configuration

When running inside tmux, these options can affect animation smoothness:

```bash
# Increase tmux's escape-time (default 10ms can cause issues)
tmux set-option -g escape-time 50

# Ensure focus events are enabled
tmux set-option -g focus-events on
```
