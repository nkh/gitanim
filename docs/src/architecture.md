# Architecture Overview

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


## Conceptual Pipeline

All three implementations share the same conceptual pipeline:

```
Diff Computation → Hunk Grouping → Char-level patience → Animate in Vim
                                                       ↑
                                        User Input (FIFO / timer)
```

1. **Diff computation** — compare old and new files, produce line-level ops
2. **Hunk grouping** — group consecutive non-keep ops into hunks
3. **Char-level patience** — within each hunk, compute minimal char ops
4. **Animate** — open old file in vim, send commands to transform buffer

## Three Implementations

### ad_vim (Bash + Vimscript)

```
┌─────────────────────────────────────────────┐
│  Bash launcher                              │
│  ┌────────────────────────────────────────┐ │
│  │  1. Parse arguments                    │ │
│  │  2. Generate vimscript file            │ │
│  │  3. Launch vim with the script         │ │
│  └────────────────────────────────────────┘ │
└─────────────────────┬───────────────────────┘
                      ▼
┌─────────────────────────────────────────────┐
│  Vim (single process)                       │
│  ┌────────────────────────────────────────┐ │
│  │  Vimscript engine (timer_start)        │ │
│  │  - Diff logic (patience)                    │ │
│  │  - Animation loop (timer callback)     │ │
│  │  - Buffer manipulation (setline/cursor)│ │
│  │  - User input (nnoremap mappings)      │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

**Key characteristics:**
- Single process — everything runs inside vim
- `timer_start()` drives the animation (no race conditions)
- User input is native (vim mappings call functions directly)
- No external dependencies beyond vim

### ad_tmux (Bash + tmux)

```
┌─────────────────────────────────────────────┐
│  Bash orchestrator                          │
│  ┌──────────────┐  ┌──────────────────┐     │
│  │ Animation    │  │ User input       │     │
│  │ loop         │  │ reader           │     │
│  │ (sleep-based)│  │ (FIFO non-block) │     │
│  └──────┬───────┘  └────────┬─────────┘     │
└─────────┼────────────────────┼─────────────┘
          │ tmux send-keys     │ writefile()
          ▼                    ▼
┌─────────────────────────────────────────────┐
│  Vim (in tmux pane)                         │
│  ┌────────────────────────────────────────┐ │
│  │  Vimscript engine (Dv* functions)      │ │
│  │  - DvSetPos, DvInsert, DvDelete        │ │
│  │  - Mappings write to FIFO              │ │
│  └────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### ad_vim.pl (Perl + tmux)

Same architecture as ad_tmux but written in Perl with:
- Single parser module (`DiffVim::Parser::Perl`, pure-Perl patience, no deps)
- `IPC::Open3` for vim communication (when using `--no-tmux`)
- `File::Temp` with `CLEANUP => 1` for automatic temp file cleanup

## Comparison

| Feature | ad_vim | ad_tmux | ad_vim.pl |
|---------|---------|--------------|------------|
| Race conditions | No | Yes | Yes |
| Parser pluggability | No | No | Yes |
| External deps | Vim only | tmux, diff, sed, awk | Perl, tmux, diff |
| Best for | Quick use | Bash scripting | Parser research |

## When to Use Which

- **diffvim** — everyday use, no external dependencies
- **ad_tmux** — when you want to script/extend in bash
- **ad_vim.pl** — when you want parser pluggability or prefer Perl

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/REQUIREMENTS.md` and `docs/src/contributing.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
