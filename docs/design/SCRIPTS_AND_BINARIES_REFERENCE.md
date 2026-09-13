# Scripts and Binaries Reference

Complete inventory of all executables and scripts in the ad project,
where they live, what they do, and what they depend on.

## C/C++ Binaries (built by `make`, in `bin/`)

| Binary | Source | What it does |
|--------|--------|-------------|
| `bin/ad` | `animator/c/ad.c` | The C animator. Reads timed V2 TSV op stream from stdin, applies each op to a virtual buffer (loaded from the old file), renders the animation to the terminal. Supports `--no-display` (headless), `--snapshot` (write final buffer), `--speed`, `--scroll`, `--diff-stat`, `--diff-highlight`, `--bell`, `--line-numbers`, `--progress`, `--colormap-old/new`, `--output`, `--verbose`, `--dry-run`, `--version`, `--help`. Handles ops: keep, delete, insert, keep_line, join_lines, split_line, delete_line, batch_insert, delay, snapshot, highlight, dim, fold, sign, marker. |
| `bin/ad_compute` | `diff_engine/cpp/compute.cpp` | The C++ diff engine. Takes old and new files, produces raw V2 TSV ops (the diff). Supports `--semantic-cleanup`, `--word-diff`, `--diff` (read unified diff instead of two files). Produces: HUNK headers, keep/delete/insert ops, keep_line/join_lines/split_line/delete_line ops. |
| `bin/ad_annotate` | `scripts/ad_annotate.c` | Adds `# old:` / `# new:` context comments before each hunk in the op stream. Reads ops from stdin, writes annotated ops to stdout. |
| `bin/ad_layer_reorder` | `layers/c/ad_layer_reorder.c` | Reorders char ops within each line: deletes first, then inserts, then keeps. Boundaries (keep_line, join_lines, split_line, delete_line, batch_insert) stay in place. |
| `bin/ad_layer_overwrite` | `layers/c/ad_layer_overwrite.c` | Merges adjacent delete+insert pairs into `overwrite_insert` ops. |
| `bin/ad_layer_indent_last` | `layers/c/ad_layer_indent_last.c` | Moves leading whitespace deletes to the END of the line (so content is deleted before indentation shifts). |
| `bin/ad_layer_line_delete_in_place` | `layers/c/ad_layer_line_delete_in_place.c` | Moves content deletes to BEFORE join_lines (so content is deleted in place, not joined first). Handles both full-line (col 1) and partial (col > 1) deletes. Two patterns: Pattern 1 (join + delete@col1 + join) and Pattern 2 (delete + join + delete — moves post-join deletes before the join with col adjustment). `--mode batch` (default) or `--mode interleaved`. `--debug` for logging. |
| `bin/ad_layer_split_in_place` | `layers/c/ad_layer_split_in_place.c` | Moves split_line to BEFORE inserts (so old content is pushed to the next line before new content is typed into the current line). Only reorders when HUNK has `del > 0` or `!is_end_insert` (line has existing content). `--debug` for logging. |
| `bin/ad_layer_skip_indent` | `layers/c/ad_layer_skip_indent.c` | Skips animation for indent-only changes (when only whitespace was added/removed). |
| `bin/ad_layer_pace` | `layers/c/ad_layer_pace.c` | Inserts `delay\t<ms>\t<type>` ops between content ops. Configurable: `--delete-pacing`, `--insert-pacing`, `--delete-speed`, `--insert-speed`, `--pacing`, `--gaussian-jitter-pct`, `--pause-after-lines`, `--accel-delete`, `--flash-pause-ms`, `--cursor-glide-ms`, `--distance-speed`, `--snapshot`. Handles batch_insert and delete_line with delays. |
| `bin/ad_layer_highlight` | `layers/c/ad_layer_highlight.c` | Inserts highlight/dim/fold/sign/marker ops into the timed stream. Options: `--highlight`, `--dim-unchanged`, `--context`, `--fold-unchanged`, `--sign-column`, `--git-blame`, `--old-file=`, `--max-hunk-chars`, `--theme`. |
| `bin/ad_layer_batch_whitespace` | `layers/c/ad_layer_batch_whitespace.c` | Batches consecutive whitespace inserts (tab=9, space=32) into a single `batch_insert` op. Reduces op count for files with lots of indentation. `--debug` for logging. |
| `bin/ad_layer_line_replace` | `layers/c/ad_layer_line_replace.c` | Collapses char ops into `delete_line` + `insert_line` ops (line-level replacement). |

## Symlinks (created by `make` in `bin/`)

| Symlink | Points to | Why |
|---------|-----------|-----|
| `bin/ad_postprocess` | `pipeline/ad_postprocess` | Layer orchestrator (bash script, not compiled) |
| `bin/ad_pipeline` | `pipeline/ad_pipeline` | Full pipeline driver (bash script, not compiled) |
| `bin/ad_vim` | `apps/vim/ad_vim` | Vim launcher (bash script, not compiled) |

## Bash Scripts (in `pipeline/`)

| Script | What it does |
|--------|-------------|
| `pipeline/ad_postprocess` | Layer orchestrator. Reads V2 TSV from stdin, runs a chain of layer plugins (each reads TSV stdin, writes TSV stdout). Layer chain supplied on command line. Options: `--ad-layer=NAME`, `--ad-layer-path=DIR`, `--ad-layer-arg=LAYER:ARG`, `--ad-layer-passthrough=ARG`, `--ad-layer-profile`, `--ad-layer-dry-run`, `--ad-layer-keep-temps`, `--interactive`, `--list-layers`. Two I/O modes: pipe (fast, default) and temp (debug, per-layer files). |
| `pipeline/ad_pipeline` | End-to-end pipeline driver. Runs: compute → postprocess → pace → animator. Routes options by prefix: `--compute-*`, `--postprocess-*`, `--pace-*`, `--animator-*`. Unprefixed options (`--speed`, `--no-display`, `--snapshot`, etc.) go to the animator. Direct flags: `--indent-last`, `--overwrite`, `--line-delete-in-place`, `--ad-layer=`, `--list-layers`. |

## Bash Scripts (in `scripts/`)

| Script | What it does | Dependencies |
|--------|-------------|---------------|
| `scripts/ad_debug.sh` | Full pipeline debugger. Runs compute → postprocess → pace → animator, writes each stage to `/tmp/ad_debug/` (raw.txt, post.txt, timed.txt, snap.txt). Compares final buffer against new file. `--keep` preserves temp dir. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace, bin/ad |
| `scripts/ad_debug_bundle.sh` | Collects debug info (system info, binary MD5s, config, op streams, snapshots) into a tarball for bug reports. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace, bin/ad, bin/ad_layer_highlight |
| `scripts/ad_session` | Interactive vim session: splits (left=diff, right=ops editor), F5=animate, F6=snapshot, L1/L2 bisect, git integration. `--ad-layer=`, `--resume=`, `--resume-latest`, `--list-sessions`, `--no-generate`, `--annotate`, `--fold-context=`, `--fold-hunks`, `--layer-debug`, `--layer-file=`. | bin/ad_gen_ops (or pipeline), vim |
| `scripts/ad_tmux_watch` | tmux-based session tool (same as ad_session but in tmux panes). `--ad-layer=`, `--show-delays`, `--show-decorations`, `--session-name=`, `--resume=`, `--list-sessions`. | tmux, bin/ad_watch, vim |
| `scripts/ad_watch` | Live-preview: displays old, new, diff — auto-refreshes on save. `--once`, `--show-delays`, `--show-decorations`. | bin/ad, inotifywait (optional) |
| `scripts/ad_gen_ops` | Generates ops from old/new files + layer chain. Writes timed ops to stdout. `--ad-layer=`, `--ad-layer-path=`, `--annotate`, `--delete-pacing=`, `--insert-pacing=`. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace |
| `scripts/ad_l1l2` | L1/L2 bisect: applies ops hunk by hunk, finds the first hunk where the buffer diverges from the expected output. Reports L1 (last matching line), L2 (first mismatch), L2_HUNK (which hunk broke). | bin/ad |
| `scripts/ad_anim_test` | Animation test: injects `snapshot` ops before/after each join_lines, split_line, keep_line. Runs the animator once, checks buffer state at each checkpoint. `--check-in-place` verifies content is deleted in place (no join on non-empty lines). | bin/ad |
| `scripts/ad_snapshot.sh` | Per-op HTML snapshots: runs the full pipeline, takes a snapshot after every op, renders as an HTML page at `/tmp/ad_snapshots/snapshots.html`. Accepts all ad_vim options. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace, bin/ad |
| `scripts/ad_compare` | Generates a matrix of diff files using every combination of diff algorithm and post-processing option. Writes diff files to output dir. | bin/ad_compute |
| `scripts/ad_jogger` | Generates 18 synthetic test file pairs, runs ad_vim with ~25 option combinations on every pair. Writes logs and a Markdown report. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace, bin/ad |
| `scripts/ad_tmux` | tmux-based animation launcher. Same options as ad_vim. `--session-name=`. | apps/vim/ad_vim, tmux |
| `scripts/ad_replay.sh` | Replays a recorded animation from a file. | bin/ad |
| `scripts/ad_record.sh` | Records an animation to a file for later replay. | bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace |
| `scripts/ad_demo.sh` | Demo runner: runs 3 preset animations end-to-end. | bin/ad_pipeline |
| `scripts/ad_suggest.sh` | Sourced library: provides `dv_suggest_option()` for "Did you mean?" suggestions. Not a standalone CLI. `--help` shows info. | None (library) |
| `scripts/ad_tune.sh` | Interactive option tuner in tmux: adjust pacing/timing, see effect in real time. `--workdir=`, `--stream=`, `--tmux`. | tmux, bin/ad_compute, bin/ad_postprocess, bin/ad_layer_pace, bin/ad_layer_highlight, bin/ad |
| `scripts/ad_package.sh` | Packages the project for distribution: builds binaries, archives with scripts/man/tests into a tarball. | make |
| `scripts/ad_doc_provenance` | Prints git provenance for a file: commit that created it, last modified it, current HEAD. `--help`, `-h`. | git |
| `scripts/audit_help.sh` | Audits that every script/binary has `--help` and a manpage. | All binaries and scripts |

## Perl Scripts (in `layers/perl/`)

| Script | What it does |
|--------|-------------|
| `layers/perl/ad_layer_line_delete_in_place.pl` | Perl twin of the C `ad_layer_line_delete_in_place`. Same behavior. |
| `layers/perl/ad_layer_pace.pl` | Perl twin of `ad_layer_pace`. |
| `layers/perl/ad_layer_highlight.pl` | Perl twin of `ad_layer_highlight`. |
| `layers/perl/ad_layer_indent_last.pl` | Perl twin of `ad_layer_indent_last`. |
| `layers/perl/ad_layer_reorder.pl` | Perl twin of `ad_layer_reorder`. |
| `layers/perl/ad_layer_overwrite.pl` | Perl twin of `ad_layer_overwrite`. |
| `layers/perl/ad_layer_batch_whitespace.pl` | Perl twin of `ad_layer_batch_whitespace`. |

## AWK Scripts (in `layers/awk/`)

| Script | What it does |
|--------|-------------|
| `layers/awk/ad_layer_line_delete_in_place.awk` | AWK implementation of `ad_layer_line_delete_in_place`. |

## Vim Scripts (in `apps/vim/`)

| Script | What it does |
|--------|-------------|
| `apps/vim/ad_vim` | Bash launcher + embedded Vimscript animation engine. The main user-facing tool. Accepts all pipeline options + `--speed`, `--output`, `--no-display`, `--scroll`, `--multi`, `--replay`, `--git-rev`, `--dry-run`, `--annotate`, `--step-mode`, `--highlight`, `--pacing`, `--delete-pacing`, `--insert-pacing`, `--indent-last`, `--overwrite`, `--line-delete-in-place`, `--split-in-place`, `--batch-whitespace`, `--ad-layer=`, `--preset=`, `--keep-dirty`, `--no-vimrc`, `--precomputed=`, `--debug`, etc. |
| `apps/vim/ad_vim.pl` | Perl orchestrator + vim in tmux. Same architecture as ad_tmux but with pluggable diff parser modules. |
| `apps/vim/diffvim` | Legacy alias/symlink to ad_vim. |
| `apps/vim/plugin.vim` | Vim plugin providing `:Diffvim` command. |
| `apps/vim/autoload_diffvim/engine.vim` | Standalone vimscript animation engine (sourced by the plugin). |

## Other

| Script | What it does |
|--------|-------------|
| `scripts/lib/ad_route.sh` | Option routing library for ad_pipeline. |
| `scripts/lib/ad_layer_groups.sh` | Layer group file parsing (.ad_layers). |
| `scripts/vim/ad_ops_syntax.vim` | Vim syntax highlighting for ops.tsv files. |
| `scripts/vim/ad_session.vim` | Vimscript for ad_session (splits, F5/F6, folds, L1/L2). |

## Build

```
make              # Build all C binaries + symlinks into bin/
make animator     # Build only bin/ad
make diff_engine  # Build only bin/ad_compute
make layers       # Build only layer binaries
make tools        # Build only bin/ad_annotate
make clean        # Remove bin/
make test         # Run all test suites
make install      # Install binaries, manpages, completions
```

After `make`, all binaries and symlinks are in `bin/`. Scripts in
`scripts/` and `pipeline/` reference `$ROOT/bin/` which includes
the symlinks for non-compiled scripts.
