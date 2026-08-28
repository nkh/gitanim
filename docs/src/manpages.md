# Manpages

Every diffvim executable has a manpage in the
[`man/`](https://github.com/diffvim/diffvim/tree/main/man) directory.
Install them to your system manpath to get offline documentation
from `man diffvim`, `man ad_compute`, etc.

## Available Manpages

| Manpage                     | Describes                                            |
| --------------------------- | ---------------------------------------------------- |
| [`diffvim.1`](../../man/diffvim.1)                  | The main `diffvim` command (bash + vimscript)   |
| [`diffvim-tmux.1`](../../man/diffvim-tmux.1)        | The `diffvim-tmux` variant (bash + tmux)        |
| [`diffvim-compare.1`](../../man/diffvim-compare.1)  | The `diffvim-compare` benchmark tool            |
| [`diffvim-jogger.1`](../../man/diffvim-jogger.1)    | The `diffvim-jogger` test-case exerciser        |
| [`ad_compute.1`](../../man/ad_compute.1)  | The `ad_compute` tool (the only compute implementation)     |

## Installing

```bash
# System-wide (requires sudo)
sudo cp man/*.1 /usr/local/share/man/man1/
sudo mandb

# User-local (no sudo needed)
mkdir -p ~/.local/share/man/man1
cp man/*.1 ~/.local/share/man/man1/
mandb --user-path

# Verify
man diffvim
man ad_compute
```

If you installed via Homebrew (`brew install diffvim`), the manpages
are installed automatically.

## Reading Without Installing

You can read the manpages directly from the source tree:

```bash
man -l man/diffvim.1
man -l man/ad_compute.1
```

Or use `groff` to render to text:

```bash
groff -man -Tutf8 man/diffvim.1 | less
```

## Quick Reference

```bash
diffvim --help              # CLI help (always available)
diffvim -h                  # same as --help
man diffvim                 # full manpage (if installed)
man -l man/diffvim.1        # full manpage (from source tree)
```

Every executable in the diffvim project supports both `--help` (for
quick CLI reference) and a manpage (for the full reference with
cross-links to related commands).

## Help Text vs Manpage — What's the Difference?

- **`--help`** — short, focuses on usage and options. Always
  available, even on minimal systems without `man` installed.
- **manpage** — full reference, includes description, options,
  environment variables, files, examples, exit status, bugs, and
  cross-references to related commands. Better for offline reading
  and discovery.

Both are kept in sync. If you find a discrepancy, please open an
issue.

## See Also

- [Installation](./installation.md)
- [Visual Guide](../VISUAL_GUIDE.md) — graphical overview with ASCII art
