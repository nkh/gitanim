# layers/

Postprocess layer plugins. Each layer is a standalone executable that
reads V2 TSV from stdin and writes V2 TSV to stdout. Layers are chained
by the orchestrator (`pipeline/ad_postprocess`).

## Contents

- `c/` — C implementations (built to `bin/ad_layer_<name>`)
  - `ad_layer_common.h` — shared types and I/O helpers
  - `ad_layer_reorder.c` — 4-sweep reorder + position adjust
  - `ad_layer_overwrite.c` — merge delete+insert pairs into overwrite_insert
  - `ad_layer_indent_last.c` — move leading whitespace deletes to end of line
  - `ad_layer_line_delete_in_place.c` — delete whole lines on their own line
  - `ad_layer_pace.c` — insert delay ops between ops
  - `ad_layer_highlight.c` — insert highlight/dim/fold ops
- `perl/` — Perl twins (produce byte-identical output to C versions)
- `tests/` — one test file per layer (TDD-style; C/Perl parity verified)

## Running a layer standalone

    ./bin/ad_layer_reorder < raw_ops.txt > reordered_ops.txt

## Running a chain of layers

Use the orchestrator:

    ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_indent_last < raw_ops.txt

## Adding a new layer

See `docs/src/contributing.md` for the TDD workflow.
