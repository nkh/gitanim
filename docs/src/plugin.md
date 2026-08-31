# Plugin Mode

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


Run ad_vim inside an existing vim session via the `:Diffvim` command.

## Installation

Copy the `plugin/` and `autoload/` directories to your vim runtimepath:

```bash
cp -r plugin autoload ~/.vim/
```

Or with vim-plug:
```vim
Plug 'nkh/gitanim', {'rtp': '.'}
```

Or with packer.nvim:
```lua
use { 'nkh/gitanim', rtp = '.' }
```

## Usage

```vim
:Diffvim old.py new.py
:Diffvim old.py new.py tabnew      " open in a new tab
:Diffvim old.py new.py split       " open in a horizontal split
:Diffvim old.py new.py vsplit      " open in a vertical split
```

## Configuration

Set the `g:diffvim` dictionary in your vimrc:

```vim
let g:diffvim = {
    \ 'type_delay_ms': 50,
    \ 'scroll': 'zz',
    \ 'max_word_chars': 5,
    \ }
```

## How It Works

1. The `:Diffvim` command calls `s:DiffvimStart()` in `plugin/diffvim.vim`
2. The plugin opens the old file in the current window (or new tab/split)
3. It sources `autoload/diffvim/engine.vim` — the full animation engine
4. The engine uses vim's `timer_start()` to drive the animation
5. All controls work natively (Space, n, b, q, +, -, =, u, Ctrl-r, ?)

## Advantages

- No tmux required
- No external bash/perl process
- Runs in your existing vim session with your settings
- Native vim mappings (no FIFO latency)

## Limitations

- Only supports single-file animation (no `--multi` or `--replay`)
- Configuration is via `g:diffvim` only (no env vars)
- The engine is sourced fresh each time (no persistence between runs)

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
