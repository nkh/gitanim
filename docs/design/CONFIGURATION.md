# Configuration

This document describes all configuration options for the `ad_vim`
family of tools.

---

## Environment Variables

All three implementations read timing configuration from environment
variables. These control the animation speed and feel.

### Timing Variables

| Variable                    | Default | Description                              |
| --------------------------- | ------- | ---------------------------------------- |
| `AD_TICK_MS`           | `16`    | Animation frame interval (~60fps)        |
| `AD_TYPE_DELAY_MS`     | `50`    | Delay between typed characters (ms)      |
| `AD_DELETE_DELAY_MS`   | `40`    | Delay between deleted characters (ms)    |
| `AD_MOVE_MIN_MS`       | `250`   | Minimum cursor-glide duration (ms)       |
| `AD_MOVE_MAX_MS`       | `1600`  | Maximum cursor-glide duration (ms)       |
| `AD_MOVE_MS_PER_UNIT`  | `6`     | Milliseconds per unit of glide distance  |
| `AD_HUNK_PAUSE_MS`     | `250`   | Pause between hunks (ms)                 |
| `AD_WORD_PAUSE_MS`     | `150`   | Pause after instant word (ms)            |
| `config var: RAPID_EOL_DELAY_MS`| `80`    | Delay for rapid end-of-line deletion (ms)|
| `config var: RAPID_EOL_MIN_CHARS`| `3`    | Min trailing chars to trigger rapid EOL  |
| `config var: HIGHLIGHT_WORD_COLOR`| `Search`| Highlight group for `--highlight-word` |
| `config var: HIGHLIGHT_WORD_DURATION_MS`| `300`| Word highlight duration (ms)          |
| `config var: HIGHLIGHT_WORD_MIN_CHARS`| `2`| Min word length to highlight            |
| `config var: KEEP_DIRTY`        | unset   | Set to `1` to leave buffer modified      |

### Detailed Descriptions

#### `AD_TICK_MS` (default: 16)

The interval at which the animation loop checks for user input and
advances the animation. At 16ms, this is approximately 60fps.

- **Lower** = smoother animation but higher CPU usage
- **Higher** = coarser animation but lower CPU usage

Only used by `ad_tmux` and `ad_vim.pl`. The `ad_vim`
(Vimscript) implementation uses vim's `timer_start()` which has its
own tick interval (also configurable via this variable).

#### `AD_TYPE_DELAY_MS` (default: 50)

The delay after each inserted character. This controls how fast
characters appear when typing.

- **Lower** = faster typing (try 10 for very fast)
- **Higher** = slower typing (try 80 for presentations)

#### `AD_DELETE_DELAY_MS` (default: 40)

The delay after each deleted character. Usually set slightly lower
than `TYPE_DELAY_MS` because deletion feels faster than typing.

#### `AD_MOVE_MIN_MS` (default: 250)

The minimum duration of a cursor glide between change locations.
Even if the distance is very short, the glide will take at least
this long.

#### `AD_MOVE_MAX_MS` (default: 1600)

The maximum duration of a cursor glide. Even if the distance is very
large (e.g., moving from line 1 to line 500), the glide will take at
most this long.

#### `AD_MOVE_MS_PER_UNIT` (default: 6)

Controls how glide duration scales with distance. The glide duration
is calculated as:

```
distance = abs(delta_lines) * 80 + abs(delta_columns)
duration = distance * MOVE_MS_PER_UNIT
duration = clamp(duration, MOVE_MIN_MS, MOVE_MAX_MS)
```

Lines are weighted 80x more than columns because moving between lines
feels like a larger visual jump.

- **Lower** = faster glides (try 3 for snappy movement)
- **Higher** = slower glides (try 12 for dramatic movement)

#### `AD_HUNK_PAUSE_MS` (default: 250)

The pause between finishing one hunk and starting the next. This
gives the viewer a moment to register the completed change before the
cursor starts moving to the next location.

#### `config var: RAPID_EOL_DELAY_MS` (default: 80)

When `--rapid-eol-delete` is on (the default), a trailing run of deletes
(cursor at end of line, all remaining text being deleted) is applied in
one shot followed by this single delay. Lower values make tail-of-line
deletions feel faster. Set to the same as `AD_DELETE_DELAY_MS` to
make rapid EOL feel like a single char delete.

#### `config var: RAPID_EOL_MIN_CHARS` (default: 3)

Minimum number of trailing characters required to trigger rapid end-of-line
deletion. Runs shorter than this are animated char by char, preserving
the visual detail of small edits. Set to a large number (e.g., 9999) to
effectively disable rapid EOL without using `--no-rapid-eol-delete`.

#### `config var: KEEP_DIRTY` (default: unset)

Set to `1` to leave the buffer marked as modified after the animation
finishes. By default ad_vim runs `:set nomodified` so that `:q` quits
cleanly; with `config var: KEEP_DIRTY=1` the user must type `:q!` to quit.
Equivalent to the `--keep-dirty` command-line flag.

#### `config var: HIGHLIGHT_WORD_COLOR` (default: Search)

Vim highlight group used by `--highlight-word` to highlight the word at
the cursor before each change. Common choices: `Search` (default, yellow),
`Visual` (blue), `IncSearch` (yellow, search-match style), `DiffAdd`
(green), `DiffDelete` (red), `DiffChange` (cyan).

#### `config var: HIGHLIGHT_WORD_DURATION_MS` (default: 300)

How long the word highlight stays visible, in milliseconds. Lower values
make the highlight flash briefly (good for fast animation); higher values
leave it visible longer (useful with `--step-mode` or slow speeds).

#### `config var: HIGHLIGHT_WORD_MIN_CHARS` (default: 2)

Minimum word length to trigger word highlighting. Words shorter than this
are not highlighted (they change too fast to be worth the visual flash).
Set to `1` to highlight every single-char change.

---

## Vimscript Configuration (`ad_vim` only)

The `ad_vim` (Vimscript) implementation also supports a `g:diffvim`
dictionary in your vimrc for persistent configuration:

```vim
" In ~/.vimrc
let g:diffvim = {
    \ 'type_delay_ms': 50,
    \ 'delete_delay_ms': 30,
    \ 'move_min_ms': 300,
    \ 'move_max_ms': 2000,
    \ 'move_ms_per_unit': 8,
    \ 'hunk_pause_ms': 250,
    \ 'tick_ms': 20,
    \ }
```

This is read before the animation starts. Environment variables
override these values if set.

---

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

### Default (balanced)

```bash
unset AD_TICK_MS AD_TYPE_DELAY_MS AD_DELETE_DELAY_MS \
      AD_MOVE_MIN_MS AD_MOVE_MAX_MS AD_MOVE_MS_PER_UNIT \
      AD_HUNK_PAUSE_MS
```

---

## Command-Line Options

All three implementations share a common set of CLI options. Run
`ad_vim --help` for the full list. Key options include:

```bash
ad_vim [--speed N] [--output FILE] [--scroll zz|zt|zb|none]
        [--multi] [--replay] [--from REV] [--to REV] [--git-rev REV..REV]
        [--step-mode] [--adaptive-timing] [--rapid-eol-delete]
        [--no-rapid-eol-delete] [--rapid-eol-delay-ms N] [--rapid-eol-min-chars N]
        [--keep-dirty] [--sign-column] [--git-blame] [--highlight-hunk]
        [--dry-run] [--version] [--help]
        <oldfile> <newfile>
```

The `--rapid-eol-delete` family controls whether trailing-line deletions
are applied in one rapid shot (default: on). The `--keep-dirty` flag
leaves the buffer modified so `:q!` is required to quit. See
`docs/src/options.md` for the full option reference.

---

## Tmux Configuration

`ad_tmux` and `ad_vim.pl` create tmux sessions/windows. The
session name is `ad_vim-<PID>` (e.g., `ad_vim-12345`).

### Window size

When running outside an existing tmux session, the window size defaults
to the terminal size (`$COLUMNS` x `$LINES`). To override:

```bash
COLUMNS=120 LINES=40 ./ad_tmux old.py new.py
```

### Inside tmux

If you're already inside a tmux session, `ad_tmux` and
`ad_vim.pl` create a new **window** in the current session (instead
of a new session). This means:

- The animation runs in a new window you can switch to/from
- Detaching from tmux doesn't kill the animation
- You can use `tmux kill-window` to stop the animation

### Tmux options that affect animation

These tmux options can affect the animation smoothness:

```bash
# Increase tmux's escape-time (default 10ms can cause issues)
tmux set-option -g escape-time 50

# Ensure focus events are enabled (for better vim integration)
tmux set-option -g focus-events on
```

---

## Vim Configuration

### Vim flags used

All implementations launch vim with these flags:

| Flag         | Purpose                                              |
| ------------ | ---------------------------------------------------- |
| `-N`         | No compatible mode (use Vim defaults, not Vi)        |
| `-u NONE`    | Don't load vimrc (clean environment)                 |
| `-n`         | No swap file (prevents "swap file found" prompts)   |
| `-c 'source ...'` | Source the engine vimscript after opening the file |

### Why `-u NONE`?

Loading the user's vimrc can cause issues:

- Custom mappings might conflict with ad_vim's mappings
- Plugins might interfere with the animation
- Settings like `set noshowcmd` or `set shortmess` might hide
  important messages

If you want to use your vimrc, remove `-u NONE` from the script, but
be aware that conflicts may occur.

### Recommended vim settings for animation

If you remove `-u NONE`, add these to your vimrc for best results:

```vim
" Don't show mode in status line (ad_vim manages it)
set noshowmode

" Show partial commands
set showcmd

" Don't ring the bell
set visualbell t_vb=

" Enable file type detection (for syntax highlighting)
filetype plugin indent on
syntax on
```

---

## Debugging

### Verbose mode

To debug issues, set these environment variables:

```bash
# Enable bash debugging (ad_tmux)
bash -x ./ad_tmux old.py new.py

# Enable Perl warnings (ad_vim.pl)
perl -w ad_vim.pl old.py new.py

# Enable Perl trace
PERL5OPT=-d:Trace perl ad_vim.pl old.py new.py
```

### Capturing the vim pane

To see what vim is displaying during the animation:

```bash
# In a separate terminal, capture the pane every second
while true; do
    tmux capture-pane -t ad_vim-12345 -p > /tmp/pane_$(date +%s).txt
    sleep 1
done
```

### Inspecting the engine file

The vimscript engine is written to a temp file. To inspect it:

```bash
# For ad_tmux, the engine is at $WORKDIR/engine.vim
# Find it:
find /tmp/ad_vim.* -name engine.vim 2>/dev/null

# For ad_vim.pl, the engine is at $workdir/engine.vim (tempdir)
find /tmp/dv* -name engine.vim 2>/dev/null
```

### Common issues

#### "tmux command failed"

This usually means the tmux session hasn't started yet or has already
exited. Check:

```bash
tmux list-sessions
```

#### Ex command text appears in the buffer

This is the known race condition in `ad_tmux` and `ad_vim.pl`.
See [Architecture > Known Limitations](../README.md#known-limitations)
and [Improvement #1](../IMPROVEMENTS.md).

Workaround: increase `AD_TICK_MS` and the type/delete delays:

```bash
AD_TICK_MS=50 \
AD_TYPE_DELAY_MS=100 \
AD_DELETE_DELAY_MS=100 \
./ad_tmux old.py new.py
```

#### "Found a swap file"

This happens if vim was killed unexpectedly and a swap file remains.
Fix: use `-n` (no swap), or delete the swap file:

```bash
rm /path/to/.filename.swp
```

The `ad_vim.pl` implementation already uses `-n`. For `ad_tmux`,
add `-n` to the vim command in the script.

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
