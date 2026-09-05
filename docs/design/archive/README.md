# docs/design/archive/

**OUTDATED DESIGN DOCUMENTS.** Kept for historical reference only.

These documents describe designs, architectures, or features that have
been **superseded, removed, or significantly changed**. They do not
reflect the current state of the project and should NOT be used as
implementation guides.

## Why these were archived

The project underwent major architectural changes:
1. **Rename**: "diffvim" / "dv" → "ad"
2. **Algorithm**: Myers diff removed — Patience is the only algorithm
3. **Architecture**: Monolithic vimscript engine → external pipeline
   (`ad_compute → ad_postprocess → ad_layer_pace → ad`)
4. **Python removed**: `ad_annotate` rewritten in C
5. **`--tool` flag removed**: No more C/C++/Rust/Go compute tool selection
6. **diff2html removed**: Pure Perl parser is the default
7. **Streaming mode removed**: `--stream` no longer exists
8. **Layer system redesigned**: Layers are now standalone executables
   (no `pp_` prefix, no `ad_layer_noop_*` / `ad_layer_layer_*` names)
9. **Parsers removed**: The old `DiffVim::Parser::Perl` architecture is
   gone
10. **Env vars removed**: The 107 `AD_*` env vars no longer exist

## Contents

### Architecture (old monolithic vimscript engine)

- `ARCHITECTURE.md` — Old 3-implementation architecture with vimscript
  engine doing compute+postprocess+pace internally.
- `ARCHITECTURE_ANALYSIS.md` — Analysis of the old monolithic engine,
  `dv_` prefix, `plugin/diffvim.vim`, `:Diffvim` commands.
- `PARALLEL_COMPUTE.md` — Old `--precomputed FILE` option and vimscript
  polling, replaced by the external pipeline.

### Postprocess (old layer system)

- `POSTPROCESS_PIPELINE.md` — Old layer file names
  (`ad_layer_noop_reorder.c`, `ad_layer_layer_indent_last.c`).
- `POSTPROCESS_LAYERS.md` — Old layer names
  (`ad_layer_noop_v2.c`, `ad_layer_noop_reorder.c`, `ad_layer_layer_*`).
- `POSTPROCESS_OPTIONS.md` — Removed options (`--semantic-cleanup`,
  `--indent-aware`, `--op-order`, `AD_LEFT_TO_RIGHT`).
- `POST_PROCESSING.md` — Old vimscript engine functions
  (`s:BuildHunks`, `s:CharDiff`, `s:OptimizeSequence`).
- `PP_LAYER_OVERWRITE.md` — Old layer name
  (`ad_layer_layer_overwrite.c`) and `-DPP_STANDALONE` flag.
- `PP_LAYER_DELETE_LINE_FIRST.md` — Old layer name
  (`ad_layer_delete_line_first`, now `ad_layer_line_delete_in_place`).

### Removed features

- `LEFT_TO_RIGHT_ANALYSIS.md` — Removed `--left-to-right` flag and
  `AD_LEFT_TO_RIGHT` env var; behavior now in `ad_layer_reorder`.
- `LEFT_TO_RIGHT_PROPOSED.md` — Proposal for the removed
  `--left-to-right` flag.
- `ENV_VAR_ANALYSIS.md` — Entire doc about the 107 `AD_*` env vars
  that were all removed.
- `CONFIGURATION.md` — Old `AD_*` env vars (`AD_TICK_MS`,
  `AD_TYPE_DELAY_MS`, etc.) that were all removed.
- `PARSERS.md` — Old parser-based architecture
  (`DiffVim::Parser::Perl`), replaced by the external pipeline.

### Old improvement lists (superseded)

- `100_IMPROVEMENTS.md` — 100 improvement ideas; references `PP_LAYER`
  pattern (old). Superseded by `IMPROVEMENT_PROPOSALS.md`.
- `FOLLOW_IMPROVEMENTS.md` — 50 UX improvement ideas; some vim-specific
  (`matchaddpos`), many still relevant. Superseded by
  `IMPROVEMENT_PROPOSALS.md`.

### Old adoption guide

- `ADOPTION_GUIDE.md` — Heavy old names: `dv` alias, `--tool` flag,
  `plugin/diffvim.vim`, `:DiffvimPick`/`:DiffvimCommit`,
  `make -C compute`.

### Old API reference

- `API_REFERENCE.md` — Old C/C++ API reference (superseded by current
  layer system and `docs/design/API_REFERENCE.md` in the parent
  directory).

### Old requirements

- `REQUIREMENTS.md` — Original requirements document (superseded by
  `docs/design/REQUIREMENTS.md` in the parent directory).
- `POSTPROCESS_OPERATIONS.md` — Old postprocess design (superseded by
  the layer plugin system).

### Old session planning

- `NEXT_SESSION.md` — Planning notes for a session that has concluded.

---

## Where to find current documentation

- **Current architecture**: `docs/src/architecture.md`
- **Current layers**: `docs/src/plugin-layers.md`,
  `docs/design/LAYERS_REFERENCE.md`
- **Current options**: `docs/src/options.md`
- **Current configuration**: `docs/src/configuration.md`
- **Current improvements**: `docs/design/IMPROVEMENT_PROPOSALS.md`
- **Layer development guide**: `docs/design/DEVELOPING_A_LAYER.md`
- **Implementation audit**: `docs/design/IMPLEMENTATION_AUDIT.md`
