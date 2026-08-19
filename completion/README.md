# completion/

Shell completions for the `diffvim` command.

## Files

- `diffvim.bash` — Bash completion. Source it in your `.bashrc`:
  ```bash
  source /path/to/gitanim/completion/diffvim.bash
  ```
- `diffvim.fish` — Fish completion. Copy to
  `~/.config/fish/completions/diffvim.fish`
- `_diffvim` — Zsh completion. Source it or copy to a directory in
  your `fpath`.

## What completes

- All `diffvim` flags (`--speed`, `--no-vimrc`, `--output`, etc.)
- `--algorithm` values: `lcs`, `patience`
- `--pacing` values: `uniform`, `adaptive`, `gaussian`, `review`
- `--delete-pacing` values: `char`, `rapid-eol`, `word`, `instant`
- `--highlight` values: `none`, `inline`, `word`, `hunk`

Note: `--tool` and `myers` were removed in the refactor and are no
longer completed.

## Related

- `../diffvim` — The launcher (defines all options)
- `../docs/src/completion.md` — Completion docs
