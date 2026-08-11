# Installation

## Prerequisites

### diffvim (Bash + Vimscript)

- **Vim 8+** with `+timers` and `+float` features
- **Bash 4+**

Check your vim:
```bash
vim --version | grep -E 'timers|float'
```

### diffvim-tmux (Bash + tmux)

- **Bash 4+**
- **tmux 3+**
- **Vim 8+**
- **diff**, **sed**, **awk** (standard Unix tools)

### diffvim.pl (Perl + tmux)

- **Perl 5.10+**
- **tmux 3+**
- **Vim 8+**
- **diff**
- Optional: **diff2html-cli** (for the `--parser diff2html` mode)
- Optional: **git** (for `--replay` and `--git-rev`)

## Installation Methods

### Manual

```bash
# Clone the repo
git clone https://github.com/nkh/gitanim.git
cd gitanim

# Make scripts executable
chmod +x diffvim diffvim-tmux diffvim.pl

# Copy to your PATH
cp diffvim diffvim-tmux /usr/local/bin/      # or ~/.local/bin
cp diffvim.pl /usr/local/bin/
cp -r DiffVim /usr/local/lib/perl5/          # for diffvim.pl

# Install the man page
cp diffvim.1 /usr/local/share/man/man1/
mandb
man diffvim
```

### diff2html CLI (optional, for `--parser diff2html`)

```bash
npm install -g diff2html-cli
diff2html --version
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
cp completion/diffvim.bash /etc/bash_completion.d/diffvim
# or
source completion/diffvim.bash

# Zsh
cp completion/_diffvim /usr/local/share/zsh/site-functions/

# Fish
cp completion/diffvim.fish ~/.config/fish/completions/
```

## Verification

```bash
diffvim --help
diffvim-tmux --help
perl diffvim.pl --version
```
