# Architecture

This document describes the architecture of the three `diffvim`
implementations and how they compare.

---

## Overview

All three implementations share the same conceptual pipeline:

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐     ┌──────────┐
│  Diff       │ ──▶ │  Hunk        │ ──▶ │  Char-level     │ ──▶ │ Animate  │
│  Computation│     │  Grouping    │     │  patience Diff       │     │ in Vim   │
└─────────────┘     └──────────────┘     └─────────────────┘     └──────────┘
     │                                                                  │
     │  ┌──────────────────────────────────────────────────────────────┘
     │  │
     ▼  ▼
┌─────────────┐     ┌──────────────┐
│  User Input │ ◀── │  Animation   │
│  (FIFO /    │     │  Loop        │
│   timer)    │     │              │
└─────────────┘     └──────────────┘
```

1. **Diff computation** — compare old and new files, produce a list of
   line-level operations (keep / delete / insert)
2. **Hunk grouping** — group consecutive non-keep operations into hunks
3. **Char-level patience diff** — within each hunk, compute the minimal set
   of character operations (keep / delete / insert)
4. **Animate in vim** — open the old file in vim, then animate the
   transformation by sending commands to vim

The key architectural difference between implementations is **how the
animation loop communicates with vim** and **where the animation state
lives**.

---

## Implementation 1: `diffvim` (Bash + Vimscript)

### Architecture

```
┌─────────────────────────────────────────────┐
│  Bash launcher                              │
│  ┌────────────────────────────────────────┐ │
│  │  1. Parse arguments                    │ │
│  │  2. Generate vimscript file            │ │
│  │  3. Launch vim with the script         │ │
│  └────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│  Vim (single process)                       │
│  ┌────────────────────────────────────────┐ │
│  │  Vimscript engine (loaded via -c)      │ │
│  │                                        │ │
│  │  ┌──────────────┐  ┌────────────────┐  │ │
│  │  │ Diff logic   │  │ Animation loop │  │ │
│  │  │ (patience, hunks, │  │ (timer_start)  │  │ │
│  │  │  char ops)   │  │                │  │ │
│  │  └──────────────┘  └───────┬────────┘  │ │
│  │                            │           │ │
│  │  ┌─────────────────────────▼────────┐  │ │
│  │  │  Buffer manipulation             │  │ │
│  │  │  (setline, cursor, append)       │  │ │
│  │  └──────────────────────────────────┘  │ │
│  │                                        │ │
│  │  ┌────────────────────────────────────┐ │ │
│  │  │  User input (normal-mode mappings) │ │ │
│  │  │  (Space/n/b/q/? → s:functions)    │ │ │
│  │  └────────────────────────────────────┘ │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Key characteristics

- **Single process** — everything runs inside vim. Bash is just a launcher.
- **`timer_start()` drives the animation** — vim's built-in timer
  mechanism calls a callback every ~16ms, which advances the animation
  by one step.
- **User input is native** — normal-mode mappings call vimscript
  functions directly. No FIFO, no inter-process communication.
- **No race conditions** — because everything runs in a single vim
  process, there are no timing issues between the animation loop and
  user input.
- **Cursor tracking** — vim's normal-mode cursor can't go past the last
  character of a line (it's clamped to `len(line)`). The engine tracks
  a "logical cursor position" in script variables (`s:cur_l`, `s:cur_c`)
  that can exceed the line length, enabling insert/delete at end-of-line.

### Communication flow

```
User presses 'n'
       │
       ▼
vim normal-mode mapping fires
       │
       ▼
s:SkipCurrent() called
       │
       ├── stops the timer
       ├── applies remaining char ops instantly
       ├── updates hunk_idx
       └── restarts the timer
```

### Pros

- No external dependencies (just vim)
- No race conditions (single process)
- Smooth animation (timer-based, not sleep-based)
- User input is instant (native vim mappings)

### Cons

- Diff logic is in Vimscript (harder to test and debug)
- No parser pluggability
- All state is in vimscript variables (lost on crash)

---

## Implementation 2: `diffvim-tmux` (Bash + tmux)

### Architecture

```
┌─────────────────────────────────────────────┐
│  Bash orchestrator                          │
│  ┌────────────────────────────────────────┐ │
│  │  1. Parse arguments                    │ │
│  │  2. Compute diff (diff + sed + awk)    │ │
│  │  3. Build hunk data (associative arrays)│ │
│  │  4. Set up tmux session + FIFO         │ │
│  │  5. Launch vim in tmux pane            │ │
│  │  6. Run animation loop (background)    │ │
│  │  7. Attach to tmux (foreground)        │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ┌──────────────┐    ┌──────────────────┐   │
│  │ Animation    │    │ User input       │   │
│  │ loop         │    │ reader           │   │
│  │              │    │                  │   │
│  │ phase machine│    │ reads FIFO       │   │
│  │ (idle/       │    │ non-blocking     │   │
│  │  moving/     │    │                  │   │
│  │  typing)     │    │ p → paused flag  │   │
│  │              │    │ n → skip_current │   │
│  │ sends Ex     │    │ b → go_back      │   │
│  │ commands via │    │ q → stopped flag │   │
│  │ tmux send-   │    │                  │   │
│  │ keys         │    │                  │   │
│  └──────┬───────┘    └────────┬─────────┘   │
│         │                     │             │
└─────────┼─────────────────────┼─────────────┘
          │                     │
          │  tmux send-keys     │  writefile()
          │                     │
          ▼                     ▼
┌─────────────────────────────────────────────┐
│  Vim (in tmux pane)                         │
│  ┌────────────────────────────────────────┐ │
│  │  Vimscript engine (sourced via -c)     │ │
│  │                                        │ │
│  │  DvSetPos(l, c)    ← Ex commands       │ │
│  │  DvKeep(code)      ← from bash         │ │
│  │  DvInsert(code)    ←                   │ │
│  │  DvDelete()        ←                   │ │
│  │  DvSaveSnap(path)  ←                   │ │
│  │  DvLoadSnap(path)  ←                   │ │
│  │                                        │ │
│  │  Normal-mode mappings:                 │ │
│  │  Space → writefile(['p'], FIFO)        │ │
│  │  n     → writefile(['n'], FIFO)        │ │
│  │  b     → writefile(['b'], FIFO)        │ │
│  │  q     → writefile(['q'], FIFO)        │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Key characteristics

- **Two processes** — bash (orchestrator) and vim (display).
- **tmux is the communication channel** — bash sends Ex commands to vim
  via `tmux send-keys -l`, and vim sends user input to bash via a named
  pipe (FIFO).
- **Animation loop is in bash** — a `while` loop with `sleep` advances
  the animation state machine (idle → moving → typing → idle → ...).
- **User input is non-blocking** — bash reads the FIFO with `read -t
  0.001` between animation steps.
- **State is in bash variables** — hunk data, cursor position, phase,
  etc. are stored in bash associative arrays and scalar variables.

### Communication flow

```
Bash animation loop                    Vim
─────────────────────                  ──────────────────
                       
phase = typing         
op = char_ops[op_idx] 
                       
send_ex("call          ──tmux──▶       :call DvInsert(97)
  DvInsert(97)")                       (vim executes, cursor moves)
                       
sleep TYPE_DELAY_MS   
                       
read FIFO              ◀──FIFO──       (user presses Space)
  cmd = 'p'            
  paused = 1           
                       
sleep 0.05 (paused)   
read FIFO              ◀──FIFO──       (user presses Space)
  cmd = 'p'            
  paused = 0           
                       
phase = typing (resume)
op_idx++               
```

### Pros

- Bash is easy to read and modify
- Diff logic uses standard tools (`diff`, `sed`, `awk`)
- Animation loop is explicit and debuggable
- Can be integrated with other bash tools and pipelines

### Cons

- **Race conditions** — `tmux send-keys` is asynchronous: bash queues
  keys faster than vim processes them, causing Ex command text to leak
  into normal mode. This is the main known issue.
- Bash's data structures are limited (no nested arrays)
- Char-level diff via `sed` + `diff` is slower than a native LCS
- Timing depends on `sleep` precision (affected by system load)

---

## Implementation 3: `diffvim.pl` (Perl + tmux)

### Architecture

Same as `diffvim-tmux`, but written in Perl with a modular parser
architecture:

```
┌─────────────────────────────────────────────┐
│  Perl orchestrator (diffvim.pl)            │
│  ┌────────────────────────────────────────┐ │
│  │  1. Parse arguments (--parser)         │ │
│  │  2. Compute diff via parser module     │ │
│  │  3. Set up tmux session + FIFO         │ │
│  │  4. Launch vim in tmux pane            │ │
│  │  5. Fork: child runs animation,        │ │
│  │     parent attaches to tmux            │ │
│  └────────────────────────────────────────┘ │
│                                             │
│  ┌──────────────────┐  ┌─────────────────┐  │
│  │ Parser selection │  │ Animation loop  │  │
│  │                  │  │ (same as bash)  │  │
│  │ ┌──────────────┐ │  │                 │  │
│  │ │ Perl.pm      │ │  │ phase machine   │  │
│  │ │ (LCS diff)   │ │  │ send_ex()       │  │
│  │ └──────────────┘ │  │ query_vim()     │  │
│  │                  │  │                 │  │
│  │                  │  │ User input:     │  │
│  │                  │  │ sysread(FIFO)   │  │
│  │                  │  │                 │  │
│  └──────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│  Vim (in tmux pane)                         │
│  (same vimscript engine as diffvim-tmux)    │
└─────────────────────────────────────────────┘
```

### Key characteristics

- **Single parser** — `DiffVim::Parser::Perl` (pure-Perl LCS, no
  external dependencies)
- **Better data structures** — Perl's arrays-of-hashes are more natural
  for hunk data than bash's parallel associative arrays
- **Same tmux+FIFO communication** — and the same race condition issues
  as `diffvim-tmux`
- **Fork-based architecture** — child process runs the animation loop,
  parent attaches to tmux; when tmux detaches, the parent waits for the
  child to finish

### Parser module interface

Both parser modules export a single function:

```perl
parse_diff($old_file, $new_file)
```

Returns:

```perl
{
    hunks => [
        {
            target_line   => $int,
            char_ops      => [ { op => 'keep|delete|insert', code => $int }, ... ],
            deleted_count => $int,
            inserted_count => $int,
            is_end_insert  => $bool,
            is_end_delete  => $bool,
            old_text       => $string,
            new_text       => $string,
        },
    ],
    parser => $string,   # always 'perl'
}
```

### Pros

- Single parser, no external dependencies (pure-Perl LCS)
- Perl's data structures are cleaner than bash's
- `Algorithm::Diff` integration for faster line-level diff
- Better error handling (`eval`, `die`, `warn`)

### Cons

- Same tmux race conditions as `diffvim-tmux`
- Perl is less commonly available than bash

---

## Comparison Table

| Feature                    | `diffvim`        | `diffvim-tmux`   | `diffvim.pl`     |
| -------------------------- | ---------------- | ---------------- | ---------------- |
| **Language**               | Bash + Vimscript | Bash             | Perl             |
| **Vim communication**      | Native (timer)   | tmux send-keys   | tmux send-keys   |
| **User input**             | Native mappings  | FIFO             | FIFO             |
| **Race conditions**        | No               | Yes              | Yes              |
| **External dependencies**  | Vim only         | tmux, diff, sed, awk | tmux, diff    |
| **Diff algorithm**         | LCS (Vimscript)  | LCS (diff+sed)   | LCS (C++)       |
| **Char-level diff**        | LCS (Vimscript)  | LCS (diff+sed)   | LCS (C++)       |
| **Easing**                 | ease-in-out cubic| ease-in-out cubic| ease-in-out cubic|
| **Snapshots**              | In-memory        | Temp files       | Temp files       |
| **Test coverage**          | Manual           | Manual           | 9 parser tests   |
| **Best for**               | Quick use, no deps | Bash scripting | Perl scripting   |

---

## When to Use Which

- **`diffvim`** — use when you want a self-contained tool with no
  external dependencies. Best for everyday use. No race conditions.

- **`diffvim-tmux`** — use when you want to script or extend the
  animation in bash, or when you need the animation to run in a
  detachable tmux session.

- **`diffvim.pl`** — use when you want to experiment with different
  diff parsers, or when you prefer Perl over Bash. The modular parser
  architecture makes it easy to add new diff algorithms.
