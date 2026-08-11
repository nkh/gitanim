# Shell Completion

The repo includes shell completion scripts for bash, zsh, and fish.

## Bash

```bash
# Install system-wide
sudo cp completion/diffvim.bash /etc/bash_completion.d/diffvim

# Or for current user
mkdir -p ~/.local/share/bash-completion/completions
cp completion/diffvim.bash ~/.local/share/bash-completion/completions/diffvim

# Or source directly
source completion/diffvim.bash
```

## Zsh

```bash
# Install
sudo cp completion/_diffvim /usr/local/share/zsh/site-functions/

# Or for current user
mkdir -p ~/.zsh/completions
cp completion/_diffvim ~/.zsh/completions/

# Add to fpath in ~/.zshrc
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit
```

## Fish

```bash
# Install
cp completion/diffvim.fish ~/.config/fish/completions/
```

## What Completes

The completion scripts provide tab completion for:
- All `--options` (`--speed`, `--output`, `--scroll`, etc.)
- `--parser perl|diff2html`
- `--scroll zz|zt|zb|none`
- File paths for positional arguments

## Generating Completions

The completion scripts are static and ship with the repo. To regenerate
or customize, edit the files in `completion/`.
