# Option Audit — 2026-09-10

Branch: `refactor/no-newline-in-char-ops`

This is the result of a full audit of every script's options against its
manpage and documentation, after removing `--seek` from the C animator.

## Method

For each tool:
1. Extract the options actually accepted by the source (C: `strcmp(argv[i], "--...")`,
   shell: `case` patterns, Perl: `GetOptions`).
2. Extract the options documented in the manpage (`.B \-\-` and `.BI \-\-` patterns).
3. Compare: phantom = in manpage but not in source; undocumented = in source
   but not in manpage.

## Headline numbers

- Total phantom options found: 25
- Total undocumented options found: 50
- Tools with phantom options: 10
- Tools with undocumented options: 13
- Tools fully clean: 14

## Fixes applied in this commit

### `--seek` removed entirely (was broken-by-design)

The C animator (`bin/ad`) no longer accepts `--seek`. Per-op checkpoint
testing is done by injecting `snapshot` ops into the op stream
(`scripts/ad_anim_test`), not by re-running the animator at a seek
position. Files touched:

- `animator/c/ad.c` — removed `--seek` option, `seek_op`, `suppress_render`,
  help text, and the dead `op_count` counter that existed only for seek.
- `man/ad.1` — removed the `--seek N` TP entry.
- `man/ad_anim_test.1` — rewrote the DESCRIPTION to say "injects `snapshot`
  ops" instead of "uses the C animator's `--seek` flag".
- `scripts/ad_anim_test` — updated the header comment.
- `scripts/README.md` — updated the `ad_anim_test` row.
- `docs/design/IMPROVEMENT_PROPOSALS.md` — `ad` (C animator) description,
  `ad_snapshot.sh` description, `ad_replay.sh` proposal #3.
- `docs/src/debugging.md` — "How it works" section for `ad_anim_test`.
- `docs/design/REQUIREMENTS.md` — animator features list.
- `docs/design/CODE_ANALYSIS.md` — issue #17 updated to "removed (was broken)".
- `docs/design/API_REFERENCE.md` — `render()` description (removed
  `suppress_render` mention).
- `docs/design/archive/LAYER_ANALYSIS_AND_DOC_REVIEW.md` — issue #17 row.

### Other phantom options removed

- `man/ad.1` — removed `--tick-ms`, `--max-line-len`, and `-V` (alias).
  Added `--line-numbers` and `--progress` (were undocumented).
- `man/ad_compute.1` — removed `--algorithm patience`, `--optimize-sequence`,
  `--no-optimize-sequence`, `--left-to-right` (none are parsed by
  `diff_engine/cpp/compute.cpp`). Added `--semantic-cleanup` (was undocumented).
- `man/ad_layer_reorder.1`, `ad_layer_overwrite.1`, `ad_layer_indent_last.1` —
  removed the phantom `--debug` TP entry.
- `man/ad_layer_line_delete_in_place.1` — removed `--debug`, added `--mode`.
- `man/ad_tmux.1` — renamed `--tmux-session` → `--session-name` (the actual
  case-statement option). Removed `--from`/`--to` from the synopsis and the
  `--replay --from --to` example (ad_tmux/ad_vim don't accept these).
- `docs/design/COMPLETE_OPTIONS_REFERENCE.md` — removed the `--tick-ms N`
  section.
- `docs/design/OPTIONS_ANALYSIS.md` — removed `--tick-ms` from the timing
  options enumeration.
- `scripts/README.md` — clarified that `ad_suggest.sh` is a sourced library,
  not a standalone CLI.
- `man/README.md` — added missing index entries for `ad_doc_provenance.1`,
  `ad_anim_test.1`, `ad_l1l2.1`.

## Remaining issues (NOT fixed in this commit — recommendations)

These are the gaps the audit found but the user did not ask me to address
in this pass. Listed here so they are not lost.

### `man/ad_vim.1` — largest gap (5 phantom, 26 undocumented)

Phantom (remove from manpage or qualify as ad_vim.pl-only):
- `--parser perl`, `--from`, `--to`, `--diff`, `--remote`

Undocumented (add to manpage):
- `--snapshot`, `--no-display`, `--sync`, `--no-startup-pause`, `--language`,
  `--no-vimrc`/`-N`, `--startup-feedback`/`-F`, `--preset`/`-p`,
  `--highlight-color`, `--indent-last`, `--overwrite`, `--line-delete-in-place`,
  `--ad-layer`/`--ad-layer=*`, `--ad-layer-path`/`--ad-layer-path=*`,
  `--list-layers`, `--diff-stat`, `--diff-highlight`, `--bell`,
  `--flash-pause-ms`, `--flash-highlight-ms`, `--cursor-glide-ms`,
  `--cursor-glide-show-intermediate`, `--distance-speed`, `--distance-threshold`,
  `--distance-fast-mult`, `--distance-slow-mult`

### `man/ad_pipeline.1` — 4 phantom, 1 undocumented

Phantom (these are ad_postprocess options; ad_pipeline routes them via
`--postprocess-` prefix):
- `--ad-layer-arg`, `--ad-layer-profile`, `--ad-layer-dry-run`, `--ad-layer-keep-temps`

Undocumented:
- `--syntax`

### `man/ad_layer_pace.1` — 1 undocumented

- `--snapshot`

### `man/ad_layer_highlight.1` — 1 undocumented

- `--old-file=PATH`

### `man/ad_session.1` — 3 undocumented

- `--annotate`, `--ad-layer-path=DIR`, `--layer-file=FILE`

### `man/ad_tmux_watch.1` — 6 undocumented

- `--session-name`, `--resume`, `--resume-latest`, `--list-sessions`,
  `--fold-context`, `--fold-hunks`

### `man/ad_gen_ops.1` — 1 undocumented

- `--annotate`

### `man/ad_snapshot.1` — 3 undocumented

- `--no-buffer-frame`, `--font-size`, `--trace`
  (Also: the OPTIONS section is broken embedded text, not proper `.TP`
  entries — needs a full rewrite.)

### `man/ad_suggest.1` — 2 phantom

- `--help`, `-h` — the script is a sourced library with no arg parser.
  Either add a tiny arg parser to `scripts/ad_suggest.sh` so `--help`
  actually prints help, or remove the OPTIONS section from the manpage.

### `man/ad_doc_provenance.1` — 1 undocumented

- `-h` (the short alias is missing from the OPTIONS section; only
  `--help` is in the synopsis).

### `man/ad_debug.1` — 1 loosely documented

- `--keep` is mentioned in an embedded text block, not as a proper `.TP`
  entry.

## Verification

- `make animator` builds clean (no warnings, no unused variables).
- `./bin/ad --help` no longer lists `--seek`.
- `./bin/ad --no-display --snapshot` works (the `snapshot` op replaces
  `--seek` for checkpoint testing).
- `bash tests/run_minimal_tests.sh` — 25/25 pass.
- `bash tests/run_all_examples.sh` — 36/36 pass.
- `layers/bash/ad_layer_line_delete_in_place.sh` produces byte-identical
  output to `bin/ad_layer_line_delete_in_place` on all 25 minimal cases
  and all 42 standard examples.

## `--seek` is gone — final check

Grep for `--seek` across the repo (after the fixes) returns only
historical/audit mentions in:
- `docs/design/CODE_ANALYSIS.md` — "removed (was broken)"
- `docs/design/archive/LAYER_ANALYSIS_AND_DOC_REVIEW.md` — audit table row
- `scripts/ad_anim_test` header comment — "the animator has no seek primitive"
- `docs/design/IMPROVEMENT_PROPOSALS.md`, `docs/design/REQUIREMENTS.md` —
  "the animator has no seek primitive"

No manpage, no source file, no user-facing doc treats `--seek` as a
working option.
