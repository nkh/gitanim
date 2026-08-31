# Configuration

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `db72a00` (2026-08-30 08:35:56 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


`ad_vim` and `ad_pipeline` read configuration from a single file at startup, with CLI flags overriding per-invocation. **There are no environment variables.**

## Config file location

Following the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/):

```
$XDG_CONFIG_HOME/ad/config
```

If `XDG_CONFIG_HOME` is unset, it defaults to `~/.config/`. So the default config path is:

```
~/.config/ad/config
```

A system-wide defaults file can be installed at `/etc/ad/config` (see `packaging/etc-ad-config` for a template). The user config file overrides system defaults.

## Precedence

1. `/etc/ad/config` — system-wide defaults (lowest priority)
2. `~/.config/ad/config` — user config
3. CLI flags — per-invocation (highest priority)

No environment variables. No `~/.diffvimrc` fallback. No `DV_*` or `DIFFVIM_*` vars.

## Creating the config file

```bash
mkdir -p ~/.config/ad
cat > ~/.config/ad/config <<'EOF'
# ad configuration — sourced as bash by ad_vim and ad_pipeline

# Pacing
DELETE_PACING=word
INSERT_PACING=char
PACING=uniform

# Highlight
HIGHLIGHT_MODE=inline
HIGHLIGHT_DURATION_MS=200

# Cursor
CURSOR_GLIDE_MS=100

# Layer chain (convenience flags)
INDENT_LAST=1
OVERWRITE_MODE=1
EOF
```

The config file is sourced as bash, so it can set any variable that the launcher recognizes. Variable names use UPPER_CASE (without the `AD_` prefix — the launcher reads them as plain bash variables).

## Available CLI flags

All options can be set via CLI flag OR via the config file. The CLI flag always wins.

### Pacing

| CLI flag               | Config var         | Default   | Values                                                                      |
| ---------------------- | ------------------ | --------- | --------------------------------------------------------------------------- |
| `--delete-pacing MODE` | `DELETE_PACING`    | `word`    | `char`, `word`, `instant`, `rapid-eol`, `rapid-identical`, `accel`, `flash` |
| `--insert-pacing MODE` | `INSERT_PACING`    | `char`    | `char`, `word`, `accel`                                                     |
| `--pacing MODE`        | `PACING`           | `uniform` | `uniform`, `adaptive`, `gaussian`, `review`                                 |
| `--delete-speed SPEED` | `DELETE_SPEED`     | `normal`  | `slow`, `normal`, `fast`, `instant`                                         |
| `--insert-speed SPEED` | `INSERT_SPEED`     | `normal`  | `slow`, `normal`, `fast`                                                    |
| `--delete-threshold N` | `DELETE_THRESHOLD` | `3`       | integer                                                                     |

### Layer chain

These convenience flags enable specific postprocess layers:

| CLI flag                 | Config var             | Default   | Effect                                                             |
| ------------------------ | ---------------------- | --------- | ------------------------------------------------------------------ |
| `--indent-last`          | `INDENT_LAST`          | `0`       | `1` enables the `ad_layer_indent_last` layer                       |
| `--overwrite`            | `OVERWRITE_MODE`       | `0`       | `1` enables the `ad_layer_overwrite` layer                         |
| `--line-delete-in-place` | `LINE_DELETE_IN_PLACE` | `0`       | `1` enables the `ad_layer_line_delete_in_place` layer              |
| `--ad-layer=NAME`        | —                      | —         | Add any layer to the chain (see [Plugin Layers](plugin-layers.md)) |
| `--ad-layer-path=DIR`    | —                      | —         | Add a directory to the layer search path                           |

### Animation behavior

| CLI flag             | Config var       | Default   | Values                   |
| -------------------- | ---------------- | --------- | ------------------------ |
| `--speed N`          | `SPEED`          | `1.0`     | float (speed multiplier) |
| `--scroll MODE`      | `SCROLL`         | `zz`      | `zz`, `zt`, `zb`, `none` |
| `--max-line-len N`   | `MAX_LINE_LEN`   | `10000`   | integer                  |
| `--max-hunk-chars N` | `MAX_HUNK_CHARS` | `0`       | integer; `0` = no limit  |

### Cursor movement

| CLI flag                             | Config var           | Default                          | Values                           |            |
| ------------------------------------ | -------------------- | -------------------------------- | -------------------------------- | ---------- |
| `--cursor-glide-ms N`                | `CURSOR_GLIDE_MS`    | `0`                              | integer (ms); `0` disables glide |            |
| `--cursor-glide-show-intermediate 0\ | 1`                   | `CURSOR_GLIDE_SHOW_INTERMEDIATE` | `1`                              | `0` or `1` |
| `--distance-speed MODE`              | `DISTANCE_SPEED`     | `off`                            | `adaptive`, `off`                |            |
| `--distance-threshold N`             | `DISTANCE_THRESHOLD` | `5`                              | integer (lines)                  |            |
| `--distance-fast-mult N`             | `DISTANCE_FAST_MULT` | `2.0`                            | float                            |            |
| `--distance-slow-mult N`             | `DISTANCE_SLOW_MULT` | `0.5`                            | float                            |            |

### Decoration

| CLI flag                    | Config var              | Default   | Values                           |
| --------------------------- | ----------------------- | --------- | -------------------------------- |
| `--highlight MODE`          | `HIGHLIGHT_MODE`        | `none`    | `none`, `inline`, `word`, `hunk` |
| `--highlight-duration-ms N` | `HIGHLIGHT_DURATION_MS` | `200`     | integer (ms)                     |
| `--dim-unchanged`           | `DIM_UNCHANGED`         | `0`       | `0` or `1`                       |
| `--dim-unchanged-pct N`     | `DIM_UNCHANGED_PCT`     | `60`      | integer (0-100)                  |
| `--context N`               | `CONTEXT_LINES`         | `0`       | integer (lines of context)       |
| `--fold-unchanged`          | `FOLD_UNCHANGED`        | `0`       | `0` or `1`                       |
| `--sign-column`             | `SIGN_COLUMN`           | `0`       | `0` or `1`                       |
| `--git-blame`               | `GIT_BLAME`             | `0`       | `0` or `1`                       |

### Output

| CLI flag          | Config var   | Default   | Values     |
| ----------------- | ------------ | --------- | ---------- |
| `--output FILE`   | `OUTPUT`     | —         | file path  |
| `--snapshot FILE` | `SNAPSHOT`   | —         | file path  |
| `--keep-dirty`    | `KEEP_DIRTY` | `0`       | `0` or `1` |

### Misc

| CLI flag          | Config var   | Default       | Values                           |
| ----------------- | ------------ | ------------- | -------------------------------- |
| `--theme MODE`    | `THEME`      | —             | `dark`, `light`, `high-contrast` |
| `--log-mode MODE` | `LOG_MODE`   | —             | mode                             |
| `--log-file FILE` | `LOG_FILE`   | `diffvim.log` | file path                        |
| `--debug`         | `DEBUG_MODE` | `0`           | `0` or `1`                       |

### Compute (diff engine)

| CLI flag                 | Default   | Effect                                             |
| ------------------------ | --------- | -------------------------------------------------- |
| `--semantic-cleanup`     | off       | Merge adjacent delete+insert pairs that cancel out |
| `--word-diff`            | off       | Use word-level diff                                |
| `--optimize-sequence`    | on        | Enable op-sequence optimization                    |
| `--no-optimize-sequence` | —         | Disable op-sequence optimization                   |

## Command-line overrides

All config variables can be overridden on the command line. Examples:

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
- `man ad_vim` — manpage
- `ad_vim --help` — built-in help
