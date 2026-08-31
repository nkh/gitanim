# ad_vim vim plugin

## Installation

### Using vim-plug

```vim
Plug 'nkh/gitanim'
```

Then in vim: `:PlugInstall`

### Using packer.nvim (Neovim)

```lua
use 'nkh/gitanim'
```

### Manual installation

```bash
# Clone the repo
git clone https://github.com/nkh/gitanim.git ~/.vim/bundle/gitanim

# Build the C tools
cd ~/.vim/bundle/gitanim
make

# Install to system paths (optional, for command-line use)
make install
```

Or for Neovim:
```bash
git clone https://github.com/nkh/gitanim.git ~/.local/share/nvim/site/pack/gitanim/start/gitanim
cd ~/.local/share/nvim/site/pack/gitanim/start/gitanim
make
```

## Requirements

- Vim 8+ with `+timers` and `+float`, or Neovim
- A C compiler (gcc or clang) for building the pipeline tools
- Perl 5 (for the fallback pipeline — optional, only used if C tools missing)

## Commands

| Command                               | Description                       |
| ------------------------------------- | --------------------------------- |
| `:DiffVim old new`                    | Animate the diff from old to new  |
| `:DiffVim --speed 2 old new`          | Animate at 2x speed               |
| `:DiffVim --highlight inline old new` | Highlight changed chars           |
| `:DiffVimTo target`                   | Animate current file → target     |
| `:DiffVimGit REV`                     | Animate git diff for current file |

## Configuration

```vim
" Set the ad_vim launcher path (if not in PATH)
let g:diffvim_binary = '/path/to/diffvim'

" Set default options
let g:diffvim_defaults = {
    \ 'speed': 1.0,
    \ 'highlight': 'inline',
    \ 'pacing': 'gaussian',
    \ }
```

## Keyboard controls (during animation)

| Key           | Action                  |
| ------------- | ----------------------- |
| `q`           | Stop animation and quit |
| `Space` / `p` | Pause / resume          |
| `n`           | Skip to next hunk       |
| `+`           | Speed up (x1.5)         |
| `-`           | Slow down (x0.67)       |
| `=`           | Reset speed to 1.0      |
| `?`           | Show help               |

## After animation

- `:q` quits cleanly (buffer marked as not modified)
- Use `--keep-dirty` to leave the buffer modified (requires `:q!`)

## Building the tools

After cloning, run `make` to build all C tools:

```bash
make        # Build all binaries
make install  # Install to /usr/local (or PREFIX)
```

The plugin will automatically find the binaries if they're in your PATH,
or you can set `g:diffvim_binary` to point to the launcher.
