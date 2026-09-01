# `ad_watch` — Interactive layer debugger

## Purpose

A minimal bash tool to live-preview how a set of ops transforms an old
file, so you can iterate on op lists in vim and see the result instantly.

## Usage

```bash
ad_watch <oldfile> <newfile> <opfile>
```

Three things are displayed in one terminal, top to bottom:
1. The old file (with line numbers)
2. The new file (with line numbers)
3. The result of applying the op file to the old file, diffed against
   the new file, piped through `diff-so-fancy` (if available, else
   plain `diff -u`)

## Display

```
═══ OLD (old.py) ═══
     1	#!/usr/bin/env python3
     2	def greet(name):
     3	    print("Hello, " + name)
     4	    return None

═══ NEW (new.py) ═══
     1	#!/usr/bin/env python3
     2	def greet(name):
     3	    print("Hi, " + name)
     4	    return None

═══ DIFF (new vs old+ops) ═══
[output of: diff -u new <(apply ops to old) | diff-so-fancy]
[or: ERROR: <parse error message>]
```

## Refresh mechanism

The display refreshes **only when the op file is modified** — not on
an interval. This avoids wasted CPU and gives zero-latency refresh.

### Primary: `inotifywait` (Linux)

```bash
inotifywait --quiet --monitor --event modify --format "%w%f" "$opfile" \
| while read change; do
    display
done
```

- `inotifywait` is in `inotify-tools` (standard on Linux).
- Event-driven: runs exactly when the file changes.
- Zero latency, zero idle CPU.

**Why not `watch -n1`:** `watch` runs every 1 second regardless of
changes — wastes CPU, has up to 1 second latency.

### Fallback: `stat` mtime polling (no dependencies)

If `inotifywait` is not installed, the script falls back to polling
the file's mtime with `stat`:

```bash
last_mtime=""
while true; do
    current_mtime=$(stat -c %Y "$opfile" 2>/dev/null || echo 0)
    if [ "$current_mtime" != "$last_mtime" ]; then
        last_mtime="$current_mtime"
        display
    fi
    sleep 0.2
done
```

- Uses only `stat` (coreutils — always available).
- 0.2s polling interval (responsive, low CPU).
- Compares mtime — only re-runs display when file actually changed.

### Alternative (not implemented): vim `BufWritePost`

The user mentioned a vim-based alternative:

```vim
:au BufWritePost <buffer> :silent !tmux send-keys -t other-pane 'display' Enter
```

This works but has issues:
1. The result needs to go in another tmux pane (requires tmux
   integration — `tmux send-keys` etc.)
2. Vim's `BufWritePost` is per-buffer, so you'd need to set it up
   each time.
3. Couples the tool to vim + tmux.

**Not implemented.** The `inotifywait`/`stat` approach is cleaner:
decoupled from the editor, no tmux integration needed.

## Applying ops to old file

Uses the **real animator** (`bin/ad`) — not a custom applier:

```bash
bin/ad --no-display --speed 1000 --snapshot /tmp/ad_watch_result.txt "$oldfile" < "$opfile"
```

Then:
```bash
diff -u "$newfile" /tmp/ad_watch_result.txt | diff-so-fancy
```

If the animator fails (parse error, etc.), capture stderr and display
it in the DIFF section instead of the diff output.

## Line numbers

Use `cat -n` (standard Unix):

```bash
cat -n "$oldfile"
cat -n "$newfile"
```

## Op file format

Standard V2 TSV (what layers produce). Lines starting with `#` are
comments and ignored by layers. This lets you comment out ops to
test partial sequences:

```
# Test: delete 'Hello' and insert 'Hi'
HUNK	3	1	1	0	0
delete	3	9	72	'H'
delete	3	10	101	'e'
delete	3	11	108	'l'
delete	3	12	108	'l'
delete	3	13	111	'o'
# delete	3	14	34	'"'    ← commented out to test
insert	3	9	72	'H'
insert	3	10	105	'i'
HUNK_END
```

## Error handling

When the op file has errors (malformed TSV, invalid op type, etc.):
- The animator (`bin/ad`) exits non-zero and prints to stderr.
- Capture stderr and display it in the DIFF section:

```
═══ DIFF (new vs old+ops) ═══
ERROR: ad animator failed:
  Line 5: invalid op type 'delet'
  (expected: keep, delete, insert, overwrite_insert)
```

No vim-side validation — errors are shown when the op list is applied.

## Separate script: `ad_gen_ops`

A **separate script** generates the op file from old + new + layer chain:

```bash
ad_gen_ops <oldfile> <newfile> [--ad-layer=<name>]... > opfile.tsv
```

Runs `compute → postprocess (with specified layers) → pace` and writes
the timed ops to stdout. You then edit the output in vim and watch
with `ad_watch`.

Keeps `ad_watch` minimal (just display) and `ad_gen_ops` focused on
generation.

## Vim syntax highlighting

A standalone vim syntax file (`scripts/vim/ad_ops_syntax.vim`) with
**no dependencies** (no plugins, no filetype autodetection). Load it
on the command line:

```bash
vim -S /path/to/ad_ops_syntax.vim opfile.tsv
```

Colors:
- Comments (`#...`) → Comment (gray)
- Op types (`keep`, `delete`, `insert`, `overwrite_insert`) → Type (green)
- `HUNK` / `HUNK_END` → Statement (yellow)
- `\n` (code 10) → Special (magenta)
- Numbers → Number (cyan)
- Char repr (`'a'`) → String (red)
- `delay` ops → PreProc (purple)

No plugins, no `~/.vim/` setup — just `vim -S <file>`.

## Workflow

```bash
# Terminal 1: generate initial ops, then watch
ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder > /tmp/ops.tsv
ad_watch old.py new.py /tmp/ops.tsv

# Terminal 2: edit ops with syntax highlighting
vim -S /path/to/ad_ops_syntax.vim /tmp/ops.tsv
# :w to save — terminal 1 refreshes instantly (inotifywait) or within
# 0.2s (stat fallback)
```

## Dependencies

- `cat -n` (coreutils — always available)
- `diff -u` (diffutils — always available)
- `diff-so-fancy` (optional — falls back to plain `diff -u`)
- `bin/ad` (the real animator — in this repo)
- `inotifywait` (inotify-tools — optional, falls back to `stat` polling)
- `stat` (coreutils — always available, used by fallback)
- `vim` (for editing, with optional syntax file)
- `tmux` (for side-by-side terminals — user's setup)

## What the script does NOT do

- No `watch` (interval-based polling).
- No custom TUI / no curses.
- No custom op applier (uses real animator).
- No vim plugins / no autodetection.
- No statistics / no profiling.
- No test export / no templates.
- No multi-pane TUI layout.

## File structure

```
scripts/
  ad_watch              — the watch script (minimal bash)
  ad_gen_ops            — generates op file from old+new+layers
  vim/ad_ops_syntax.vim — standalone syntax file for vim
```

## Acceptance criteria

1. `ad_watch old.py new.py opfile.tsv` displays old, new, and diff.
2. Refreshes **only when opfile is modified**, not on an interval.
3. Editing opfile in vim and saving (`:w`) causes refresh (instant
   with `inotifywait`, ≤0.2s with `stat` fallback).
4. Comments (`#`) in opfile are ignored.
5. Parse errors in opfile are shown in the DIFF section.
6. Uses the real animator (`bin/ad`) — not a custom applier.
7. No hard dependencies beyond standard Unix tools. `diff-so-fancy`
   and `inotifywait` are optional (graceful fallback).
8. `vim -S ad_ops_syntax.vim opfile.tsv` colors the ops (no plugins).
9. `ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder > opfile.tsv`
   generates the initial ops.

## Alternative: vim `BufWritePost` (not implemented)

For completeness, the vim-based alternative is:

```vim
" In vim, while editing opfile.tsv in tmux pane 1:
:au BufWritePost <buffer> :silent !tmux send-keys -t :0.1 'bash display.sh' Enter
```

Where `display.sh` is the body of `ad_watch`'s `display` function.

**Not implemented** because:
- Couples to vim + tmux.
- Requires manual tmux pane setup.
- `BufWritePost` is per-buffer, must be re-set each session.
- The `inotifywait`/`stat` approach is editor-agnostic and works in
  any terminal without tmux integration.

---

## Examples

### Example 1: Simple word replacement

**old.txt:**
```
hello world
```

**new.txt:**
```
hello universe
```

**Generate ops and watch:**
```bash
ad_gen_ops old.txt new.txt --ad-layer=ad_layer_reorder > /tmp/ops.tsv
ad_watch old.txt new.txt /tmp/ops.tsv
```

**Ops file (after generation):**
```
# diffvim timed ops v2
HUNK	1	1	1	0	0
keep	1	1	104	'h'
keep	1	2	101	'e'
keep	1	3	108	'l'
keep	1	4	108	'l'
keep	1	5	111	'o'
keep	1	6	32	space
delete	1	7	119	'w'
delete	1	7	111	'o'
delete	1	7	114	'r'
delete	1	7	108	'l'
delete	1	7	100	'd'
insert	1	7	117	'u'
insert	1	8	110	'n'
insert	1	9	105	'i'
insert	1	10	118	'v'
insert	1	11	101	'e'
insert	1	12	114	'r'
insert	1	13	115	's'
insert	1	14	101	'e'
HUNK_END
```

**Expected display:**
```
═══ OLD (old.txt) ═══
     1	hello world

═══ NEW (new.txt) ═══
     1	hello universe

═══ DIFF (new vs old+ops) ═══
✓ Files are identical — ops produce the correct result.
```

### Example 2: Line deletion (join)

**old.txt:**
```
A
B
C
```

**new.txt:**
```
A
C
```

**Generate ops and watch:**
```bash
ad_gen_ops old.txt new.txt --ad-layer=ad_layer_reorder > /tmp/ops.tsv
ad_watch old.txt new.txt /tmp/ops.tsv
```

### Example 3: Using tmux launcher

```bash
# Inside a tmux session:
ad_tmux_watch old.txt new.txt /tmp/ops.tsv --ad-layer=ad_layer_reorder
```

This opens a new tmux window with:
- Left pane: `ad_watch` (auto-refreshes)
- Right pane: `vim` with syntax highlighting (edit ops, `:w` to refresh)

### Example 4: Editing ops to test changes

Start `ad_watch` in one terminal, then edit the ops file in vim:

```bash
# Terminal 1:
ad_watch old.txt new.txt /tmp/ops.tsv

# Terminal 2:
vim -S scripts/vim/ad_ops_syntax.vim /tmp/ops.tsv
```

Comment out some ops to see the effect:
```
HUNK	1	1	1	0	0
keep	1	1	104	'h'
keep	1	2	101	'e'
# delete	1	3	108	'l'    ← commented out
insert	1	3	88	'X'
HUNK_END
```

Save (`:w`) — terminal 1 refreshes instantly showing the new result.

### Example 5: Keeping delay ops

By default, `ad_watch` strips delay ops. To keep them:

```bash
ad_watch --show-delays old.txt new.txt /tmp/ops.tsv
```

### Example 6: One-shot display (for testing)

```bash
ad_watch --once old.txt new.txt /tmp/ops.tsv
```

Displays once and exits — useful for scripts and testing.

### Example 7: Multiple layers

```bash
ad_gen_ops old.py new.py \
    --ad-layer=ad_layer_reorder \
    --ad-layer=ad_layer_indent_last \
    --ad-layer=ad_layer_line_delete_in_place > /tmp/ops.tsv

ad_watch old.py new.py /tmp/ops.tsv
```
