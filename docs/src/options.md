# Command-Line Options

## Core Options

### `--speed N` / `-s`
Speed multiplier. `0.5` = half speed, `2` = double, `5` = 5x. All
timing delays are divided by this value.

### `--output FILE` / `-o`
Write the animation result to FILE after the animation completes, then
quit vim automatically.

### `--context N` / `-c`
Fold unchanged regions longer than 2*N lines, keeping N lines of
context around each hunk. Default: 0 (no folding). Use `--context 0`
to fold all unchanged regions.

### `--max-hunk-chars N`
If a hunk has more than N changed characters, skip the char-by-char
animation and apply the entire hunk instantly.

### `--scroll zz|zt|zb|none`
Scroll cursor to center (`zz`), top (`zt`), bottom (`zb`), or no
scrolling (`none`). Default: `zz`.

### `--multi` / `-m`
Treat arguments as `old:new` pairs for multi-file animation.

### `--replay` / `-r`
Animate git history for the given file(s).

### `--git-rev REV..REV` / `-R`
Animate a git commit range (e.g. `HEAD~3..HEAD`).

### `--dry-run` / `-d`
Print diff hunks without launching vim.

### `--word-diff` / `-w`
Use word-level diff (groups changes by word tokens).

### `--step-mode`
Space advances one char op at a time (starts paused).

### `--sign-column`
Show +/- signs in vim's sign column during animation.

### `--git-blame` / `-g`
Show git blame for the target line of each hunk.

### `--max-line-len N`
Warn threshold for long lines (default: 10000).

### `--keep-dirty`
Leave buffer modified after animation; require `:q!` to quit.

### `--no-vimrc` / `-N`
Don't load user's `~/.vimrc` (isolated vim).

### `--precomputed FILE`
Use pre-computed diff from FILE (see `compute/` directory).

### `--preset NAME` / `-p`
Apply named preset: `fast-delete`, `review`, `demo`, `ai-code`, or
`custom`.

### `--theme dark|light|high-contrast` / `-t`
Color scheme for highlights.

### `--version` / `-V`
Print version and exit.

### `--help` / `-h`
Show help and exit.

---

## Diff Algorithm

### `--algorithm lcs|myers|patience` / `-a`
Line-level diff algorithm (default: `lcs`).

### `--semantic-cleanup` / `-S`
Merge adjacent delete+insert pairs that cancel out, reducing
unnecessary typing.

### `--indent-aware` / `-i`
Normalize indentation before line-level diff, so lines that differ
only in indentation are treated as "keep" at the line level.

---

## Op Order (Post-Processing)

### `--op-order MODE`
Controls how char ops within a line are ordered. Default: `optimize`.

| Mode              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `natural`         | No post-processing (raw LCS order)                   |
| `optimize`        | Deletes before inserts (default)                     |
| `left-to-right`   | Keeps, then deletes, then inserts per line           |
| `end-first`       | Trailing deletes before inserts                      |
| `end-first-smart` | Trailing deletes + word batching                     |
| `overwrite`       | In-place replacement instead of delete+insert        |

```bash
diffvim --op-order left-to-right old.py new.py
diffvim --op-order end-first-smart old.py new.py
```

---

## Deletion Pacing

### `--delete-pacing MODE`
Deletion strategy. Default: `rapid-eol`.

| Mode              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `char`            | One char at a time (no acceleration)                 |
| `rapid-eol`       | Rapid shot at end of line (default)                  |
| `rapid-identical` | Accelerate identical char runs (---, ===)            |
| `accel`           | Accelerate through long runs (slow→fast→slow)        |
| `word`            | Word-by-word with acceleration                       |
| `instant`         | All strategies enabled (fastest)                     |

### `--delete-speed MODE`
Deletion speed: `slow|normal|fast|instant` (default: `normal`).
`fast` halves all delete delays; `instant` sets them to 1ms.

### `--delete-threshold N`
Minimum chars to trigger rapid/word modes (default: 3).

```bash
diffvim --delete-pacing word old.py new.py
diffvim --delete-pacing instant --delete-speed fast old.py new.py
```

---

## Insertion Pacing

### `--insert-pacing MODE`
Insertion strategy. Default: `char`.

| Mode    | Description                                          |
| ------- | ---------------------------------------------------- |
| `char`  | One char at a time (default)                         |
| `word`  | Batch short words (<=8 chars) instantly              |
| `accel` | Accelerate char-by-char inserts (slow→fast→pause)   |

### `--insert-speed MODE`
Insertion speed: `slow|normal|fast` (default: `normal`).

```bash
diffvim --insert-pacing word old.py new.py
diffvim --insert-pacing accel --insert-speed fast old.py new.py
```

---

## Timing

### `--pacing MODE`
Timing mode. Default: `uniform`.

| Mode       | Description                                          |
| ---------- | ---------------------------------------------------- |
| `uniform`  | Fixed delays, no jitter (default)                    |
| `adaptive` | Slow down in complex regions                         |
| `gaussian` | Add human-like timing jitter                         |
| `review`   | Pause every 5 lines in large hunks                   |

```bash
diffvim --pacing gaussian old.py new.py
diffvim --pacing review old.py new.py
```

---

## Highlighting

### `--highlight MODE`
Highlight mode. Default: `none`.

| Mode     | Description                                          |
| -------- | ---------------------------------------------------- |
| `none`   | No highlighting (default)                            |
| `inline` | Paint freshly typed/deleted chars (200ms fade)       |
| `word`   | Highlight the word at cursor before change           |
| `hunk`   | Highlight the entire hunk before animating           |

### `--highlight-color COLOR`
Highlight group (default: `DiffChange`).

### `--highlight-duration-ms N`
Highlight duration in ms (default: 1000).

### `--dim-unchanged` / `-D`
Dim unchanged anchor lines to draw eye to changes.

### `--dim-unchanged-pct N`
Dimming percentage 0-100 (default: 60).

```bash
diffvim --highlight inline old.py new.py
diffvim --highlight hunk --dim-unchanged old.py new.py
```

---

## Environment Variables

All options can be set via `DIFFVIM_<OPTION_NAME>` environment
variables. For example:

```bash
DIFFVIM_OP_ORDER=left-to-right diffvim old.py new.py
DIFFVIM_DELETE_PACING=word diffvim old.py new.py
DIFFVIM_PACING=gaussian diffvim old.py new.py
DIFFVIM_HIGHLIGHT=inline diffvim old.py new.py
```

Core timing env vars:

| Variable                  | Default | Description                          |
| ------------------------- | ------- | ------------------------------------ |
| `DIFFVIM_TICK_MS`         | 16      | Animation frame interval (~60fps)    |
| `DIFFVIM_TYPE_DELAY_MS`   | 50      | Delay between typed characters       |
| `DIFFVIM_DELETE_DELAY_MS` | 40      | Delay between deleted characters     |
| `DIFFVIM_MOVE_MIN_MS`     | 250     | Minimum cursor glide duration        |
| `DIFFVIM_MOVE_MAX_MS`     | 1600    | Maximum cursor glide duration        |
| `DIFFVIM_HUNK_PAUSE_MS`   | 250     | Pause between hunks                  |
