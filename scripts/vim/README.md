# scripts/vim/

Vim scripts for the ad debugging tools.

## Files

- `ad_session.vim` — Vim setup script for `ad_session`. Sets up the
  split layout (diff | ops | result), F5/F6 mappings, leader shortcuts,
  fold expressions, and the `:AdRun`, `:AdGen`, `:AdCommit`, etc.
  commands.
- `ad_ops_syntax.vim` — Standalone syntax highlighting for op TSV files.
  Colors: delete (red bg), insert (green bg), \n ops (magenta bg),
  HUNK/HUNK_END (bold yellow). Load with: `vim -S ad_ops_syntax.vim ops.tsv`
