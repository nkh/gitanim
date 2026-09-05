# scripts/

Helper scripts for the ad project.

## Session and inspection tools

| Script          | What it does                                                   |
| --------------- | -------------------------------------------------------------- |
| `ad_session`    | Vim-only interactive session (splits, F5/F6, folds, git)       |
| `ad_tmux_watch` | tmux-based session tool (ad_watch + vim in panes)              |
| `ad_watch`      | Live-preview: displays old, new, diff — auto-refreshes on save |
| `ad_gen_ops`    | Generates ops from old/new files + layer chain                 |
| `ad_annotate.c` | C source for the annotation tool (builds to `bin/ad_annotate`) |

## Utility scripts

| Script                  | What it does                          |
| ----------------------- | ------------------------------------- |
| `ad_debug.sh`           | Interactive pipeline debugger         |
| `ad_debug_bundle.sh`    | Collect debug info into a tarball     |
| `ad_snapshot.sh`        | Per-op HTML snapshots                 |
| `ad_record.sh`          | Record animation to a file            |
| `ad_replay.sh`          | Replay a recorded animation           |
| `ad_demo.sh`            | Demo runner with preset examples      |
| `ad_tune.sh`            | Interactive option tuner (tmux)       |
| `ad_suggest.sh`         | Suggest options for a given diff      |
| `ad_package.sh`         | Package the project for distribution  |
| `ad_compare`            | Generate diffs with all option combos |
| `ad_jogger`             | Generate test cases with patterns     |
| `ad_tmux`               | tmux-based animation launcher         |
| `ad_doc_provenance`     | Print git provenance for a file       |
| `add_doc_provenance.py` | Add provenance headers to docs        |
| `format_tables.py`      | Format markdown tables                |
| `fix_c_memory.py`       | Fix realloc anti-patterns in C code   |
| `fix_diffvim_refs.py`   | Replace diffvim references with ad    |

## Subdirectories

- `vim/` — Vim scripts (`ad_session.vim`, `ad_ops_syntax.vim`)
- `lib/` — Shared bash libraries (`ad_route.sh`, `ad_layer_groups.sh`)
