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

### `--sign-column`
Show `+`/`-` signs in vim's sign column to indicate deleted/added lines.

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
