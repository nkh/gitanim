# man/

Man pages for the diffvim commands.

## Files

- `diffvim.1` — Main man page for the `diffvim` command
- `diffvim-compute.1` — Man page for `diffvim-compute-cpp`
- `diffvim-compare.1` — Man page for `diffvim-compare`
- `diffvim-tmux.1` — Man page for `diffvim-tmux`
- `diffvim-jogger.1` — Man page for `diffvim-jogger`

## Installation

```bash
sudo cp man/diffvim*.1 /usr/local/share/man/man1/
sudo mandb
```

Then view with:
```bash
man diffvim
man diffvim-compute
```

## Related

- `../diffvim` — The launcher
- `../diffvim.1` — A duplicate of `man/diffvim.1` (kept at root for
  backwards compatibility)
