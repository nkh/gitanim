# scripts/lib/

Shared bash libraries sourced by other scripts.

## Files

- `ad_route.sh` — Shared option routing. Routes CLI flags to the
  appropriate pipeline stage (compute, postprocess, pace, decorate,
  animator). Used by `ad_vim`, `ad_pipeline`, `ad_snapshot.sh`.
- `ad_layer_groups.sh` — Layer group file parser. Reads `.ad_layers`
  files and extracts the active group's layer list. Used by
  `ad_session` and `ad_tmux_watch`.
