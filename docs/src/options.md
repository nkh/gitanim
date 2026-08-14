# Command-Line Options

All three implementations support these options (unless noted):

## Core Options

### `--speed N`
Speed multiplier. `0.5` = half speed, `2` = double speed, `5` = 5x speed.
All timing delays are divided by this value.

Also settable via `DIFFVIM_SPEED` environment variable.

### `--output FILE`
After the animation completes, write the buffer to FILE and quit vim.
Also works with `q` (quit) — the buffer is written before stopping.

### `--scroll zz|zt|zb|none`
Scroll the cursor to the specified position during animation:
- `zz` — center cursor on screen
- `zt` — cursor at top of screen
- `zb` — cursor at bottom of screen
- `none` — don't force scroll (default)

### `--multi`
Treat arguments as `old:new` pairs for multi-file animation.
After finishing one file, the animation transitions to the next.

```bash
diffvim --multi old1.py:new1.py old2.py:new2.py
```

### `--context N`
Fold unchanged regions longer than 2*N lines, keeping N lines of context
around each hunk. Default: 0 (no folding).

## Diff Options

### `--parser perl|diff2html` *(diffvim.pl only)*
Diff parser to use:
- `perl` — pure-Perl LCS (default, no deps)
- `diff2html` — shells out to `diff2html -f json` CLI

### `--word-diff`
Use word-level diff instead of char-level. Groups changes by word
(non-space sequences), producing more natural typing patterns.

### `--max-hunk-chars N`
If a hunk has more than N changed characters, skip the char-by-char
animation and apply the entire hunk instantly.

### `--max-word-chars N`
If a contiguous word (non-space chars terminated by space/newline) has
<= N characters, type the entire word instantly, then pause.

### `--word-pause-ms N`
Pause in milliseconds after an instant word is applied (only relevant
with `--max-word-chars`). Default: 150.

### `--max-line-len N`
Warn if any line exceeds N characters (char-level diff may be slow).
Default: 10000.

## Git Options

### `--replay`
Animate git history for the given file(s). For each commit in the range,
extracts the old version and animates the transformation to the next commit.

```bash
diffvim --replay src/main.py
diffvim --replay src/main.py --from v1.0 --to HEAD
```

### `--from REV`
Git revision to start replay from. Default: `HEAD~5`.

### `--to REV`
Git revision to end replay at. Default: `HEAD`.

### `--git-rev REV..REV`
Animate a git commit range using `REV..REV` syntax.

```bash
diffvim --git-rev HEAD~3..HEAD src/main.py
```

### `--git-blame`
Show git blame information for each changed line.

## Animation Options

### `--step-mode`
Space advances one char op at a time instead of toggling pause/resume,
for detailed inspection.

### `--adaptive-timing`
Automatically slow down for complex hunks (many char ops close together)
and speed up for simple ones.

### `--rapid-eol-delete` *(default: on)*
When the cursor is at the end of the line and all the text after the cursor
is being deleted, apply those deletes in one rapid shot rather than one char
at a time. This makes tail-of-line deletions feel snappy instead of
laborious.

The single rapid delay is governed by `--rapid-eol-delay-ms` (default 80ms)
and the minimum trailing-char threshold by `--rapid-eol-min-chars`
(default 3).

```bash
# Default behavior — rapid EOL on
diffvim old.py new.py

# Disable rapid EOL (delete one char at a time)
diffvim --no-rapid-eol-delete old.py new.py

# Tune: 50ms delay, only trigger for 5+ trailing chars
diffvim --rapid-eol-delay-ms 50 --rapid-eol-min-chars 5 old.py new.py
```

### `--no-rapid-eol-delete`
Disable rapid end-of-line deletion. Every character is deleted individually
with `DIFFVIM_DELETE_DELAY_MS` between deletes.

### `--rapid-eol-delay-ms N`
Delay in milliseconds for a rapid end-of-line deletion (default: 80).
The whole trailing run of deletes is applied in one shot, followed by this
delay. Lower values make tail deletions feel faster.

### `--rapid-eol-min-chars N`
Minimum number of trailing characters required to trigger rapid end-of-line
deletion (default: 3). Runs shorter than this are animated char by char,
preserving the visual detail of small edits.

### `--keep-dirty`
Leave the buffer marked as modified after the animation finishes (or after
the user presses `q`). By default diffvim runs `:set nomodified` so that
`:q` quits cleanly; with `--keep-dirty` the user must type `:q!` to quit.

```bash
# Default: ':q' quits cleanly
diffvim old.py new.py

# Keep buffer modified; ':q!' required
diffvim --keep-dirty old.py new.py
```

The startup config echo shows which mode is active:
`keep_dirty=off(:q)` or `keep_dirty=on(:q!)`.

### `--highlight-word`
Highlight the word at the cursor position before each delete or insert op
is applied. Finer-grained than `--highlight-hunk`: instead of highlighting
the whole hunk region (a line range), `--highlight-word` highlights just
the token (maximal run of non-whitespace chars) that is about to change.

Useful for following the animation on long lines where the eye needs help
locking onto the exact word being modified. The highlight is shown for
`--highlight-word-duration-ms` milliseconds (default: 300), then cleared.
Words shorter than `--highlight-word-min-chars` (default: 2) are not
highlighted.

```bash
# Highlight the word at cursor before each change
diffvim --highlight-word old.py new.py

# Use Visual group, 500ms duration, highlight words of 3+ chars
diffvim --highlight-word \
  --highlight-word-color Visual \
  --highlight-word-duration-ms 500 \
  --highlight-word-min-chars 3 \
  old.py new.py
```

### `--highlight-word-color COLOR`
Vim highlight group for word highlighting. Default: `Search`. Also:
`Visual`, `IncSearch`, `DiffAdd`, `DiffDelete`, `DiffChange`.

### `--highlight-word-duration-ms N`
Word highlight duration in milliseconds. Default: 300. Lower values make
the highlight flash briefly; higher values leave it visible longer (useful
with `--step-mode` or slow animation speeds).

### `--highlight-word-min-chars N`
Minimum word length (in characters) to trigger word highlighting.
Default: 2. Words shorter than this are not highlighted (they change too
fast to be worth the visual flash). Set to 1 to highlight every single-char
change.

### `--sign-column`
Show `+`/`-` signs in vim's sign column to indicate deleted/added lines.

### `--left-to-right` (default: on)
Sort ops within each line so deletes and inserts go from left to right,
never jumping around. Whitespace deletes come after non-whitespace deletes.
Use `--no-left-to-right` to disable.

### `--word-accel`
When inserting or deleting a word character by character, start slowly
and accelerate, then pause slightly. Total time equals uniform char-by-char.
Deletion is 20% faster by default (configurable via `--word-accel-delete-pct`).

### `--rapid-identical-chars`
Accelerate deletion of identical character runs (like `-----------`)
exponentially. Options: `--rapid-identical-min` (5), `--rapid-identical-accel` (50).

### `--adaptive-word-delete`
Word-by-word line deletion: few chars slow, then word by word accelerating,
then rest rapid. Options: `--adaptive-word-delete-start-chars` (3),
`-start-ms` (80), `-min-ms` (15), `-accel` (85), `-word-pause-ms` (100).

### `--auto-precompute`
Automatically run the external compute tool and use a temp file for
`--precomputed`. Uses `DIFFVIM_COMPUTE_TOOL` (default: c) or `--compute-tool`.

### `--preset NAME`
Apply named preset: `fast-delete`, `review`, `present`, `ai-code`, `custom`.
Multiple presets can be comma-separated. Also set via `DIFFVIM_PRESET`.

### `--log-mode 1|2`
Generate a log file without starting vim. Mode 1: markers. Mode 2: progressive
(3 lines per char op). Use `--log-file FILE` to set output path.
Use `--no-log-timing` to disable timing info in the log.

## Utility Options

### `--no-tmux` *(diffvim.pl only)*
Run vim directly in the terminal (no tmux wrapper). Simpler single-shot
use, but no FIFO-based user input.

### `--dry-run`
Compute and print the diff ops without launching vim. Useful for
debugging parser issues.

```bash
perl diffvim.pl --dry-run old.py new.py
```

### `--version` / `-V`
Print version, parser info, and dependency versions.

### `--help` / `-h`
Show help message and exit.
