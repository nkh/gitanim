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
- All `--options` (`--speed`, `--output`, `--scroll`, `--preset`, etc.)
- `--parser perl|diff2html`
- `--scroll zz|zt|zb|none`
- `--algorithm lcs|myers|patience`
- `--compute-tool c|cpp|rust|go`
- `--preset fast-delete|review|present|ai-code|custom`
- `--log-mode 1|2`
- `--theme dark|light|high-contrast`
- File paths for positional arguments

## How It Works

The completion scripts are loaded by the shell when you type `diffvim`
and press `<Tab>`. They are **static** — they list all known options
at the time the script was generated. If you add new options, you need
to update the completion scripts in `completion/`.

## Verifying Completion Works

```bash
# Bash — after sourcing/installing:
diffvim --<Tab>      # should show all --options
diffvim --speed <Tab>  # should show 0.5 1 2 3 5
diffvim --algorithm <Tab>  # should show lcs myers patience

# Zsh — after installing to fpath:
diffvim --<Tab>

# Fish — after installing:
diffvim --<Tab>
```

## Generating Completions

The completion scripts are static and ship with the repo. To regenerate
or customize, edit the files in `completion/`.
