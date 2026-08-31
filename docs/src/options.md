# Command-Line Options

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


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

### Compute tool selection

The C++ compute tool `bin/ad_compute` is the default.
`diffvim` searches for it in `bin/ad_compute `, `/usr/local/bin/`, and
`~/.local/bin/`. If found, the diff is pre-computed before launching
vim (10-100x faster than the in-vim Patience for large files). If not
found, ad_vim falls back to the embedded vimscript Patience
(`s:LineDiff` / `s:CharDiff` in `autoload/diffvim/engine.vim`) with a
warning on stderr. (The `--tool` flag that used to select between
C/C++/Rust/Go compute tools was removed in the refactor — there's only
one compute implementation now.)

For `ad_pipeline`, the fallback is the pure-Perl
`compute/perl/compute_builtin.pl` wrapper.

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

### `--algorithm patience` / `-a`
Line-level diff algorithm (default: `patience`). (Myers was removed in the
refactor: it OOMs on 15K-line files and produces the same op count as
Patience.)

---

## Deletion Pacing

### `--delete-pacing MODE`
Deletion strategy. Default: `word` (char→word→rapid progression with
acceleration).

| Mode              | Description                                          |
| ----------------- | ---------------------------------------------------- |
| `char`            | One char at a time (no acceleration)                 |
| `rapid-eol`       | Rapid shot at end of line                            |
| `rapid-identical` | Accelerate identical char runs (---, ===)            |
| `accel`           | Accelerate through long runs (slow→fast→slow)        |
| `word`            | Word-by-word with acceleration (default)             |
| `instant`         | All strategies enabled (fastest)                     |

### `--delete-speed MODE`
Deletion speed: `slow|normal|fast|instant` (default: `normal`).
`fast` halves all delete delays; `instant` sets them to 1ms.

### `--delete-threshold N`
Minimum chars to trigger rapid/word modes (default: 3).

```bash
ad_vim --delete-pacing word old.py new.py
ad_vim --delete-pacing instant --delete-speed fast old.py new.py
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
ad_vim --insert-pacing word old.py new.py
ad_vim --insert-pacing accel --insert-speed fast old.py new.py
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
ad_vim --pacing gaussian old.py new.py
ad_vim --pacing review old.py new.py
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
ad_vim --highlight inline old.py new.py
ad_vim --highlight hunk --dim-unchanged old.py new.py
```

---

