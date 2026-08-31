# Installation

*Created:* 4692a55 (2026-08-10)  
*Last updated:* 4625efa (2026-08-28)  
*Repo HEAD:* d1efd32 (2026-08-31)

## Prerequisites

- **vim** 8+ with `+timers` and `+float` features
- **perl** 5.10+ (for Perl fallback implementations)
- **gcc** or **clang** (to build C/C++ binaries)
- **make**

## Build from source

```bash
git clone https://github.com/nkh/gitanim.git
cd gitanim
make
```

All binaries are built into `bin/` (gitignored). Run `make test` to verify.

## Install system-wide

```bash
make install    # installs to /usr/local by default
# or:
make PREFIX=$HOME/.local install
```

## Configuration

Config file at `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config`).
See [Configuration](configuration.md) for details.

## Shell completion

```bash
# Bash
cp completion/ad_vim.bash /etc/bash_completion.d/ad_vim
# or
source completion/ad_vim.bash

# Zsh
cp completion/_ad_vim /usr/local/share/zsh/site-functions/

# Fish
cp completion/ad_vim.fish ~/.config/fish/completions/
```

## Verify installation

```bash
ad_vim --version
man ad_vim
```
