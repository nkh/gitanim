# diffvim FAQ

## Why does my file flash during animation?

The flashing was caused by clearing the entire screen on every op.
This is fixed — both the vimscript and C animators now use incremental
rendering (only redraw changed lines).

## How do I slow down the animation?

Use `--speed 0.5` to slow down (delays are divided by speed, so 0.5
makes everything take twice as long). Use `--speed 2` to speed up.

During animation in vim, press `-` to slow down or `+` to speed up.

## How do I skip a hunk?

In vim, press `n` to skip the current hunk (apply instantly).

## What is the ghost-line problem?

When a diff deletes a `\n` (joining two lines), the content of the next
line visually jumps up onto the current line. The ghost-line fix prevents
this by deleting the next line's content first, then removing the empty
line — no visual jump.

## Why does diffvim use Patience diff instead of LCS?

LCS and Patience produce identical op counts on most files. Patience
produces more human-readable hunk boundaries (anchored on unique common
lines). LCS was removed to simplify the codebase.

## Can I use diffvim with git?

Yes! Use `diffvim --replay` to animate git history:
```bash
diffvim --replay --from HEAD~3 --to HEAD file.py
```

Or use `:DiffvimPick` in vim to interactively select a commit.

## How do I get syntax highlighting?

The standalone pipeline (`diffvim-pipeline`) runs coloring in parallel:
```bash
diffvim-pipeline old.py new.py
```

In vim, syntax highlighting is automatic (vim's built-in filetype detection).

## What are typed delays?

Every delay in the timed op stream has a type: `type`, `keep`, `delete`,
`hunk_pause`, `awd_start`, `awd_word`, `awd_space`, `word_insert`, etc.
This enables future per-type dynamic pacing at animation time.
