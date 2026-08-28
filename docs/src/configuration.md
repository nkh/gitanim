# Configuration

## Environment Variables

All timing values can be set via environment variables. Command-line
options override environment variables, which override built-in defaults.

| Variable | Default | Description |
|----------|---------|-------------|
| `AD_TICK_MS` | `16` | Animation frame interval (~60fps) |
| `AD_TYPE_DELAY_MS` | `50` | Delay between typed characters (ms) |
| `AD_DELETE_DELAY_MS` | `40` | Delay between deleted characters (ms) |
| `AD_MOVE_MIN_MS` | `250` | Minimum cursor glide duration (ms) |
| `AD_MOVE_MAX_MS` | `1600` | Maximum cursor glide duration (ms) |
| `AD_MOVE_MS_PER_UNIT` | `6` | Milliseconds per unit of glide distance |
| `AD_HUNK_PAUSE_MS` | `250` | Pause between hunks (ms) |
| `AD_WORD_PAUSE_MS` | `150` | Pause after instant word (ms) |
| `DIFFVIM_RAPID_EOL_DELAY_MS` | `80` | Delay for rapid end-of-line deletion (ms) |
| `DIFFVIM_RAPID_EOL_MIN_CHARS` | `3` | Min trailing chars to trigger rapid EOL |
| `DIFFVIM_HIGHLIGHT_WORD_COLOR` | `Search` | Highlight group for `--highlight-word` |
| `DIFFVIM_HIGHLIGHT_WORD_DURATION_MS` | `300` | Word highlight duration in ms |
| `DIFFVIM_HIGHLIGHT_WORD_MIN_CHARS` | `2` | Min word length to highlight |
| `DIFFVIM_SPEED` | `1.0` | Speed multiplier (same as --speed) |
| `DIFFVIM_MAX_LINE_LEN` | `10000` | Warn threshold for long lines |
| `DIFFVIM_KEEP_DIRTY` | unset | Set to `1` to leave buffer modified (`:q!` required) |

## Presets

### Presentation Mode (slow, dramatic)

```bash
export AD_TYPE_DELAY_MS=80
export AD_DELETE_DELAY_MS=60
export AD_MOVE_MIN_MS=400
export AD_MOVE_MAX_MS=3000
export AD_MOVE_MS_PER_UNIT=10
export AD_HUNK_PAUSE_MS=500
```

### Quick Review Mode (fast)

```bash
export AD_TYPE_DELAY_MS=10
export AD_DELETE_DELAY_MS=10
export AD_MOVE_MIN_MS=50
export AD_MOVE_MAX_MS=300
export AD_MOVE_MS_PER_UNIT=3
export AD_HUNK_PAUSE_MS=50
```

### Debug Mode (very slow, visible char ops)

```bash
export AD_TYPE_DELAY_MS=200
export AD_DELETE_DELAY_MS=150
export AD_MOVE_MIN_MS=500
export AD_MOVE_MAX_MS=5000
export AD_MOVE_MS_PER_UNIT=15
export AD_HUNK_PAUSE_MS=1000
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

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
