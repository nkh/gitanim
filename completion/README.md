# Shell Completion

## Bash

```bash
# System-wide (requires sudo):
sudo cp completion/ad_vim.bash /etc/bash_completion.d/ad_vim

# Or user-only:
mkdir -p ~/.local/share/bash-completion/completions
cp completion/ad_vim.bash ~/.local/share/bash-completion/completions/ad_vim

# Or via make:
make install-comp    # installs to $(PREFIX)/share/bash-completion/completions/ad_vim

# Reload:
source ~/.bashrc
# or:
source /etc/bash_completion.d/ad_vim
```

## Zsh

```bash
# System-wide:
sudo cp completion/_ad_vim /usr/local/share/zsh/site-functions/_ad_vim

# Or user-only:
mkdir -p ~/.local/share/zsh/site-functions
cp completion/_ad_vim ~/.local/share/zsh/site-functions/_ad_vim

# Add to ~/.zshrc (if not already there):
fpath+=~/.local/share/zsh/site-functions
autoload -Uz compinit && compinit

# Reload:
source ~/.zshrc
```

## Fish

```bash
# System-wide:
sudo cp completion/ad_vim.fish /usr/local/share/fish/completions/ad_vim.fish

# Or user-only:
mkdir -p ~/.config/fish/completions
cp completion/ad_vim.fish ~/.config/fish/completions/ad_vim.fish

# Fish auto-loads completions, no reload needed.
```

## Via make

```bash
make reinstall    # clean + build + install binaries + manpages + completions
# or:
make install-comp  # just completions
```
