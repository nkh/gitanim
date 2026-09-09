# layers/

Postprocess layer plugins. Each layer is a standalone executable that
reads V2 TSV from stdin and writes V2 TSV to stdout. Layers are chained
by the orchestrator (`pipeline/ad_postprocess`).

## Contents

### C implementations (`c/`, built to `bin/ad_layer_<name>`)

| Source                            | Binary                          | What it does                                                                           |
| --------------------------------- | ------------------------------- | -------------------------------------------------------------------------------------- |
| `ad_layer_common.h`               | —                               | Shared types, I/O helpers, op parsing                                                  |
| `ad_layer_reorder.c`              | `ad_layer_reorder`              | Reorders ops within each line (deletes before inserts)                                 |
| `ad_layer_overwrite.c`            | `ad_layer_overwrite`            | Merges adjacent delete+insert into overwrite_insert                                    |
| `ad_layer_indent_last.c`          | `ad_layer_indent_last`          | Moves leading whitespace deletes to end of line                                        |
| `ad_layer_line_delete_in_place.c` | `ad_layer_line_delete_in_place` | Deletes content BEFORE joining lines. `--mode batch` (default) or `--mode interleaved` |
| `ad_layer_skip_indent.c`          | `ad_layer_skip_indent`          | Skips animation for indent-only changes                                                |
| `ad_layer_pace.c`                 | `ad_layer_pace`                 | Inserts delay ops between content ops                                                  |
| `ad_layer_highlight.c`            | `ad_layer_highlight`            | Inserts highlight/dim/fold ops                                                         |
| `ad_layer_line_replace.c`         | `ad_layer_line_replace`         | Collapses char ops into delete_line/insert_line                                        |

### AWK implementations (`awk/`)

| Script                              | What it does                                                                                          |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `ad_layer_line_delete_in_place.awk` | Same as C version — deletes content before joining lines. Uses awk state machine with pipeline tools. |

### Perl twins (`perl/`)

Each layer has a Perl twin that produces identical output. The
orchestrator prefers C; if the C binary is missing, it falls back
to Perl.

### Tests (`tests/`)

One test file per layer (TDD-style; C/Perl parity verified).

## Running a layer standalone

    ./bin/ad_layer_reorder < raw_ops.txt > reordered_ops.txt
    bash layers/awk/ad_layer_line_delete_in_place.awk < raw_ops.txt > processed.txt

## Running a chain of layers

Use the orchestrator:

    ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_delete_in_place < raw_ops.txt

## Layer options

Some layers accept options via `--ad-layer-arg`:

    ./pipeline/ad_postprocess \
        --ad-layer=ad_layer_reorder \
        --ad-layer=ad_layer_line_delete_in_place \
        --ad-layer-arg=ad_layer_line_delete_in_place:--mode=interleaved \
        < raw_ops.txt

Or through ad_vim (colon form):

    ./apps/vim/ad_vim --ad-layer=ad_layer_reorder \
        --ad-layer=ad_layer_line_delete_in_place:--mode=interleaved \
        old.py new.py

## Adding a new layer

See `docs/design/DEVELOPING_A_LAYER.md` for the full guide.
