# Configuration

`ad_vim` reads configuration from a single file at startup. The file is sourced as a bash script, so it can set any environment variable that the launcher recognizes.

## Config file location

Following the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/):

```
$XDG_CONFIG_HOME/ad/config
```

If `XDG_CONFIG_HOME` is unset, it defaults to `~/.config/`. So the default config path is:

```
~/.config/ad/config
```

There are no legacy fallback paths. The `~/.diffvimrc` file is no longer read.

## Creating the config file

```bash
mkdir -p ~/.config/ad
cat > ~/.config/ad/config <<'EOF'
# ad configuration

# Pacing
AD_DELETE_PACING=word
AD_INSERT_PACING=char
AD_PACING=uniform

# Highlight
AD_HIGHLIGHT_MODE=inline
AD_HIGHLIGHT_DURATION_MS=200

# Cursor
AD_CURSOR_GLIDE_MS=100

# Layer chain (convenience flags)
AD_INDENT_LAST=1
AD_OVERWRITE_MODE=1
EOF
```

## Available environment variables

All environment variables use the `AD_` prefix. There are no `DV_*` or `DIFFVIM_*` variants — those were removed in a hard cut.

### Pacing

| Variable | Default | Values |
|----------|---------|--------|
| `AD_DELETE_PACING` | `word` | `char`, `word`, `instant`, `rapid-eol`, `rapid-identical`, `accel`, `flash` |
| `AD_INSERT_PACING` | `char` | `char`, `word`, `accel` |
| `AD_PACING` | `uniform` | `uniform`, `adaptive`, `gaussian`, `review` |
| `AD_DELETE_SPEED` | `normal` | `slow`, `normal`, `fast`, `instant` |
| `AD_INSERT_SPEED` | `normal` | `slow`, `normal`, `fast` |
| `AD_DELETE_THRESHOLD` | `3` | Integer |
| `AD_GAUSSIAN_JITTER_PCT` | `20` | Integer (0-100) |

### Layer chain

These convenience flags enable specific postprocess layers:

| Variable | Default | Effect |
|----------|---------|--------|
| `AD_INDENT_LAST` | `0` | `1` enables the `ad_layer_indent_last` layer |
| `AD_OVERWRITE_MODE` | `0` | `1` enables the `ad_layer_overwrite` layer |
| `AD_LINE_DELETE_IN_PLACE` | `0` | `1` enables the `ad_layer_line_delete_in_place` layer |

For full control over the layer chain, use the `--ad-layer=<name>` flag on the command line. See [Plugin Layers](plugin-layers.md) for the plugin contract.

### Highlight / decoration

| Variable | Default | Values |
|----------|---------|--------|
| `AD_HIGHLIGHT_MODE` | `none` | `none`, `inline`, `word`, `hunk` |
| `AD_HIGHLIGHT_DURATION_MS` | `200` | Integer (ms) |
| `AD_DIM_UNCHANGED` | `0` | `1` dims unchanged anchor lines |
| `AD_DIM_UNCHANGED_PCT` | `60` | Integer (0-100) |
| `AD_FOLD_UNCHANGED` | `0` | `1` folds unchanged regions |
| `AD_CONTEXT_LINES` | `0` | Integer (lines of context to keep) |
| `AD_SIGN_COLUMN` | `0` | `1` places +/- signs in sign column |
| `AD_GIT_BLAME` | `0` | `1` inserts blame markers |

### Cursor movement

| Variable | Default | Values |
|----------|---------|--------|
| `AD_CURSOR_GLIDE_MS` | `0` | Integer (ms); `0` disables glide |
| `AD_CURSOR_GLIDE_SHOW_INTERMEDIATE` | `1` | `1` shows intermediate positions |
| `AD_DISTANCE_SPEED` | `off` | `adaptive`, `off` |
| `AD_DISTANCE_THRESHOLD` | `5` | Integer (lines) |
| `AD_DISTANCE_FAST_MULT` | `2.0` | Float |
| `AD_DISTANCE_SLOW_MULT` | `0.5` | Float |

### Timing

| Variable | Default | Description |
|----------|---------|-------------|
| `AD_TICK_MS` | `16` | Timer tick interval (~60fps) |
| `AD_TYPE_DELAY_MS` | `50` | Delay per character insert |
| `AD_DELETE_DELAY_MS` | `40` | Delay per character delete |
| `AD_HUNK_PAUSE_MS` | `250` | Pause between hunks |
| `AD_WORD_PAUSE_MS` | `150` | Pause between words |

### Animation behavior

| Variable | Default | Values |
|----------|---------|--------|
| `AD_LEFT_TO_RIGHT`` | `0` | `1` enables left-to-right diff mode |
| `AD_SPEED` | `1.0` | Float (speed multiplier) |
| `AD_SCROLL` | `zz` | `zz`, `zt`, `zb`, `none` |
| `AD_MAX_LINE_LEN` | `10000` | Integer |
| `AD_MAX_HUNK_CHARS` | `0` | Integer; `0` = no limit |

### Debug

| Variable | Default | Effect |
|----------|---------|--------|
| `AD_DEBUG_LAYERS` | `0` | `1` enables per-layer debug dumps in `/tmp/ad_debug/` |
| `AD_DUMP_INPUT` | unset | Path to dump layer input |
| `AD_DUMP_OUTPUT` | unset | Path to dump layer output |
| `AD_OLD_FILE` | unset | Path to old file (for layers that need it) |

## Command-line overrides

All environment variables can be overridden on the command line. Common patterns:

```bash
# Override pacing
ad_vim --delete-pacing char --insert-pacing word old.py new.py

# Override speed
ad_vim --speed 2.0 old.py new.py

# Enable a layer
ad_vim --indent-last old.py new.py

# Add an arbitrary layer (plugin system)
ad_vim --ad-layer=my_custom_layer old.py new.py
```

Run `ad_vim --help` for the full list of command-line options.

## Project-level config

A project can ship a config file at `.config/ad/config` in the repo. The launcher does NOT automatically source this — users who want it should symlink:

```bash
ln -s /path/to/repo/.config/ad/config ~/.config/ad/config
```

Or source it from their personal config:

```bash
# ~/.config/ad/config
[ -f /path/to/repo/.config/ad/config ] && source /path/to/repo/.config/ad/config
```

## See also

- [Plugin Layers](plugin-layers.md) — the `--ad-layer=<name>` plugin system
- [Contributing](contributing.md) — how to add a new layer
- [Command-Line Options](options.md) — full option reference
