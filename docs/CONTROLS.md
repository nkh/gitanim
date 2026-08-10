# User Controls

This document describes all user controls available during the animation.

---

## Controls Summary

| Key       | Action                                      | Available in          |
| --------- | ------------------------------------------- | --------------------- |
| `Space`   | Pause / resume the animation                | All implementations   |
| `n`       | Skip current hunk (apply instantly)         | All implementations   |
| `b`       | Back to previous hunk (revert and restart)  | All implementations   |
| `q`       | Stop animation (leave buffer for editing)   | All implementations   |
| `?`       | Show help                                   | `diffvim` only        |

Controls are active at **any moment** during the animation — even
mid-typing, mid-glide, or between hunks. The animation loop checks for
user input between every step (~16ms granularity).

---

## `Space` — Pause / Resume

Toggles the animation between paused and running states.

**When paused:**
- The animation freezes at the current position
- A message is displayed: `diffvim: PAUSED (Space=resume n=skip b=back q=quit)`
- The cursor stays where it was when pause was pressed
- User input is still processed (you can press `n`, `b`, `q` while paused)

**When resumed:**
- The animation continues from where it was paused
- A message is displayed: `diffvim: resumed`

**Implementation detail:** In `diffvim` (Vimscript), pause sets a flag
that the timer callback checks. In `diffvim-tmux` and `diffvim.pl`,
pause sets a `$paused` variable that the animation loop checks; when
paused, the loop sleeps in 50ms increments instead of advancing the
animation.

---

## `n` — Skip Current Hunk

Applies the current hunk **instantly** (no char-by-char animation) and
moves to the next hunk.

**What happens:**
1. If the animation is in the "moving" phase (cursor gliding), the
   cursor jumps instantly to the glide destination.
2. All remaining char ops in the current hunk are applied with no
   delay between them (they're sent as a batch of Ex commands).
3. The hunk index advances.
4. A message is displayed: `diffvim: skipped to hunk 3/7`
5. The next hunk begins normally (with cursor glide).

**When paused:** `n` still works — it applies the current hunk
instantly and then resumes the animation (clears the paused flag).

**When between hunks (phase = idle):** `n` has no effect (there's no
"current hunk" to skip). Use `Space` to resume if paused.

**When animation is done:** `n` has no effect. A message is displayed:
`diffvim: already done`.

---

## `b` — Back to Previous Hunk

Reverts the buffer to the state **before** the current hunk started,
then restarts the current hunk's animation from the beginning.

**What happens:**
1. The hunk index decrements.
2. The buffer is restored from a snapshot taken before the current
   hunk. (Snapshots are saved before each hunk starts.)
3. The cursor is restored to its position at the snapshot time.
4. The phase is set to `idle`, so the animation loop will start the
   hunk again (with cursor glide, char-by-char typing, etc.).
5. A message is displayed: `diffvim: back to hunk 2/7`

**At the first hunk:** If you press `b` at the first hunk (hunk index
0), it restores the snapshot taken before hunk 0 — effectively
restarting the entire animation from the beginning.

**Snapshot mechanism:**
- `diffvim` (Vimscript): snapshots are stored in vimscript list
  variables (`s:state.snapshots`). Each snapshot contains the buffer
  lines, cursor position, hunk index, and line offset.
- `diffvim-tmux` / `diffvim.pl`: snapshots are saved to temp files
  (`$WORKDIR/snaps/N`). Each snapshot contains the buffer lines
  (written by `DvSaveSnap`). Cursor position and line offset are
  stored in the orchestrator's variables.

**Limitation:** The snapshot history is linear — if you go back and
then skip forward, the skipped-over snapshots are still valid, but if
you go back and then go back again, the timeline branches (later
snapshots are discarded).

---

## `q` — Quit Animation

Stops the animation and leaves the buffer in its current state for
editing.

**What happens:**
1. The animation loop exits.
2. The user-input mappings (`Space`, `n`, `b`, `q`) are removed
   (`diffvim` only; in tmux implementations, the mappings remain but
   are harmless).
3. A message is displayed: `diffvim: animation stopped. Buffer left
   in current state.`
4. The buffer is a normal vim buffer — you can `:w`, `:wq`, edit, etc.

**After quitting:**
- In `diffvim`: vim remains open with the buffer. You can quit vim
  normally with `:q` or `:wq`.
- In `diffvim-tmux` / `diffvim.pl`: vim remains open in the tmux
  pane. The orchestrator process waits for vim to exit (detected via
  the `VimLeave` autocmd writing `vimleft` to the FIFO).

**Quitting vim directly:** You can also quit vim at any time with
`:qa!` or `:wq`. The orchestrator detects this and cleans up.

---

## `?` — Show Help (`diffvim` only)

Displays the current hunk index and a summary of available keys.

**Output:**
```
diffvim: hunk 3/7  | Space=pause  n=next  b=back  q=quit  ?=help
```

This is useful for checking progress without pausing the animation.

**Not available in tmux implementations** because the status line
already shows the hunk progress (via `:echo` messages).

---

## Interaction Between Controls

### Pause + Skip

If you press `Space` (pause) and then `n` (skip):
1. The current hunk is applied instantly
2. The paused flag is **cleared** (skip implies resume)
3. The next hunk starts normally

### Pause + Back

If you press `Space` (pause) and then `b` (back):
1. The buffer is restored to the previous snapshot
2. The paused flag is **cleared** (back implies resume)
3. The previous hunk starts animating from the beginning

### Skip + Back

If you skip several hunks and then press `b`:
1. The buffer is restored to the snapshot before the **current** hunk
2. The current hunk restarts from the beginning

You can press `b` multiple times to go back multiple hunks.

### Back at the Beginning

If you press `b` at the first hunk:
1. The buffer is restored to the initial state (before any hunks were
   applied)
2. The animation restarts from the first hunk

---

## Key Mapping Details

### `diffvim` (Vimscript)

Mappings are defined with `nnoremap <buffer> <silent>`:

```vim
nnoremap <buffer> <silent> <Space> :call <SID>TogglePause()<CR>
nnoremap <buffer> <silent> n       :call <SID>SkipCurrent()<CR>
nnoremap <buffer> <silent> b       :call <SID>Back()<CR>
nnoremap <buffer> <silent> q       :call <SID>Quit()<CR>
nnoremap <buffer> <silent> ?       :call <SID>ShowHelp()<CR>
```

The `<buffer>` flag ensures the mappings only apply to the diffvim
buffer, not other buffers. The `<silent>` flag prevents the command
from being echoed to the status line.

### `diffvim-tmux` / `diffvim.pl` (FIFO-based)

Mappings write single-character commands to a named pipe (FIFO):

```vim
nnoremap <buffer> <silent> <Space> :call writefile(['p'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> n       :call writefile(['n'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> b       :call writefile(['b'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> q       :call writefile(['q'], g:dv_ctrl, 'a')<CR>
```

The orchestrator reads the FIFO non-blocking between animation steps:

```bash
# Bash (diffvim-tmux):
while IFS= read -t 0.001 -u 3 -r cmd; do
    case "$cmd" in
        p) paused=$(( 1 - paused )) ;;
        n) skip_current ;;
        b) go_back ;;
        q) stopped=1 ;;
    esac
done
```

```perl
# Perl (diffvim.pl):
my $buf = '';
while (1) {
    my $data = '';
    my $n = sysread($fifo_fh, $data, 4096);
    last unless defined($n) && $n > 0;
    $buf .= $data;
}
for my $cmd (split //, $buf) {
    next if $cmd eq "\n";
    if    ($cmd eq 'p') { $paused = !$paused; }
    elsif ($cmd eq 'n') { skip_current(); }
    elsif ($cmd eq 'b') { go_back(); }
    elsif ($cmd eq 'q') { $stopped = 1; }
}
```

---

## Customizing Key Mappings

### `diffvim` (Vimscript)

The mappings are defined in the generated vimscript. To customize,
edit the `diffvim` script and change the `nnoremap` lines near the end
of the embedded vimscript.

Alternatively, after the animation starts, you can add your own
mappings in vim:

```vim
:nnoremap <buffer> <F5> :call <SID>TogglePause()<CR>
```

### `diffvim-tmux` / `diffvim.pl` (FIFO-based)

The mappings are defined in the vimscript engine file (`engine.vim`).
To customize, modify the `write_engine()` function in the bash/perl
script and change the `nnoremap` lines.

You can also add custom mappings that write different commands to the
FIFO, then extend the `handle_user_input()` function to handle them.
