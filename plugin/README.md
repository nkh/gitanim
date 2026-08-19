# plugin/

Vim plugin entry point.

## Files

- `diffvim.vim` — Vim plugin that registers the `:DiffVim` command.
  When invoked, it calls the `diffvim` bash launcher with the
  appropriate arguments.

## Usage

In vim, after installing the plugin:
```vim
:DiffVim old.py new.py
```

Or use the bash launcher directly:
```bash
./diffvim old.py new.py
```

## Related

- `../diffvim` — The bash launcher
- `../autoload/diffvim/engine.vim` — The old vimscript engine (unused)
