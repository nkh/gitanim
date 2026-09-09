# scripts/

Helper scripts for the ad project.

## Session and inspection tools

| Script          | What it does                                                       | When to use                                       |
| --------------- | ------------------------------------------------------------------ | ------------------------------------------------- |
| `ad_session`    | Interactive vim session: splits, F5/F6, folds, git, L1/L2 auto-run | Debugging ops, testing layer chains interactively |
| `ad_tmux_watch` | tmux-based session tool (same as ad_session but in tmux panes)     | When you prefer tmux over vim splits              |
| `ad_watch`      | Live-preview: displays old, new, diff — auto-refreshes on save     | Watching files change in real time                |
| `ad_gen_ops`    | Generates ops from old/new files + layer chain                     | Standalone op generation (no vim)                 |
| `ad_annotate.c` | C source for the annotation tool (builds to `bin/ad_annotate`)     | Adds `# old:` / `# new:` context comments to ops  |

## Debugging and testing tools

| Script          | What it does                                                   | When to use                                                  |
| --------------- | -------------------------------------------------------------- | ------------------------------------------------------------ |
| `ad_l1l2`       | L1/L2 bisect: applies ops hunk by hunk, finds first error      | Finding which hunk/layer produces wrong ops                  |
| `ad_anim_test`  | Animation test: per-op snapshots via `--seek`, in-place checks | Testing animation quality (content jumps, join on non-empty) |
| `audit_help.sh` | Checks that every script/binary has `--help` and a manpage     | Auditing documentation completeness                          |

## Utility scripts

| Script               | What it does                                | When to use                                   |
| -------------------- | ------------------------------------------- | --------------------------------------------- |
| `ad_compare`         | Generate diffs with all option combinations | Comparing different layer/pacing combinations |
| `ad_jogger`          | Generate test cases with patterns           | Creating stress-test inputs                   |
| `ad_tmux`            | tmux-based animation launcher               | When you want animation in tmux               |
| `ad_debug.sh`        | Interactive pipeline debugger               | Step-by-step pipeline debugging               |
| `ad_debug_bundle.sh` | Collect debug info into a tarball           | Bug reports                                   |
| `ad_snapshot.sh`     | Per-op HTML snapshots                       | Visual debugging                              |
| `ad_replay.sh`       | Replay a recorded animation                 | Reviewing animations                          |
| `ad_record.sh`       | Record animation to a file                  | Capturing animations for replay               |
| `ad_demo.sh`         | Demo runner with preset examples            | Showcasing features                           |
| `ad_suggest.sh`      | Suggest options for a given diff            | Option discovery                              |
| `ad_tune.sh`         | Interactive option tuner (tmux)             | Fine-tuning pacing/timing                     |
| `ad_package.sh`      | Package the project for distribution        | Releases                                      |
| `ad_doc_provenance`  | Print git provenance for a file             | Document traceability                         |

## Vim scripts (`vim/`)

| Script              | What it does                                                 |
| ------------------- | ------------------------------------------------------------ |
| `ad_session.vim`    | Vimscript for ad_session (splits, F5/F6, folds, L1/L2, trim) |
| `ad_ops_syntax.vim` | Syntax highlighting for ops.tsv files                        |

## Shared libraries (`lib/`)

| Library              | What it does                          |
| -------------------- | ------------------------------------- |
| `ad_route.sh`        | Option routing for ad_pipeline        |
| `ad_layer_groups.sh` | Layer group file parsing (.ad_layers) |
