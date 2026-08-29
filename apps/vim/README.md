# apps/vim/

The vim application: `ad_vim`. This is the consumer of the `ad` toolkit
that animates a diff inside vim.

## Contents

- `ad_vim` — bash launcher (the main entry point)
- `ad_vim.pl` — Perl parallel launcher (duplicate functionality; can be deleted)
- `diffvim` — backward-compat wrapper that exec's `ad_vim` (preserves the old name)
- `plugin.vim` — vim plugin entry point (defines the `:DiffVim` command)
- `autoload_diffvim/` — vimscript animation engine (sourced by the launcher)

## Usage

    ./apps/vim/ad_vim old.py new.py
    ./apps/vim/diffvim old.py new.py   # backward-compat wrapper

## Configuration

Reads from `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config`).
See `docs/src/configuration.md` for the full reference.
