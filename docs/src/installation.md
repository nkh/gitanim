# Installation

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


## Prerequisites

### ad_vim (Bash + Vimscript)

- **Vim 8+** with `+timers` and `+float` features
- **Bash 4+**

Check your vim:
```bash
vim --version | grep -E 'timers|float'
```

### ad_tmux (Bash + tmux)

- **Bash 4+**
- **tmux 3+**
- **Vim 8+**
- **diff**, **sed**, **awk** (standard Unix tools)

### ad_vim.pl (Perl + tmux)

- **Perl 5.10+**
- **tmux 3+**
- **Vim 8+**
- **diff**
- Optional: **git** (for `--replay` and `--git-rev`)

## Installation Methods

### Manual

```bash
# Clone the repo
git clone https://github.com/nkh/gitanim.git
cd gitanim

# Make scripts executable
chmod +x ad_vim ad_tmux ad_vim.pl

# Copy to your PATH
cp ad_vim ad_tmux /usr/local/bin/      # or ~/.local/bin
cp ad_vim.pl /usr/local/bin/
cp -r DiffVim /usr/local/lib/perl5/          # for ad_vim.pl

# Install the man page
cp ad_vim.1 /usr/local/share/man/man1/
mandb
man ad_vim
```

### Vim Plugin (for `:Diffvim` command)

Copy the `plugin/` and `autoload/` directories to your vim runtimepath:

```bash
cp -r plugin autoload ~/.vim/
```

Or with vim-plug:
```vim
Plug 'nkh/gitanim', {'rtp': '.'}
```

### Shell Completion

```bash
# Bash
cp completion/ad_vim.bash /etc/bash_completion.d/ad_vim
# or
source completion/ad_vim.bash

# Zsh
cp completion/__ad_vim /usr/local/share/zsh/site-functions/

# Fish
cp completion/ad_vim.fish ~/.config/fish/completions/
```

## Verification

```bash
ad_vim --help
ad_tmux --help
perl ad_vim.pl --version
```

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
