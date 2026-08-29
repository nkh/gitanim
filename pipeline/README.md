# pipeline/

The pipeline drivers. Two scripts:

- `ad_postprocess` — the layer orchestrator. Reads V2 TSV from stdin,
  runs a chain of layer plugins (one per `--ad-layer=<name>` flag, in
  argv order), writes V2 TSV to stdout. See `docs/src/plugin-layers.md`
  for the plugin contract.

- `ad_pipeline` — the end-to-end driver. Runs the full pipeline:
  `ad_compute → ad_postprocess → ad_layer_pace → ad`. Routes options
  by prefix (`--compute-*`, `--postprocess-*`, `--pace-*`, `--animator-*`).

## Usage

    ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < raw_ops.txt > post_ops.txt
    ./pipeline/ad_pipeline --no-display --speed 1000 --snapshot out.txt old.py new.py
    ./pipeline/ad_postprocess --list-layers
