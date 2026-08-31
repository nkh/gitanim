# Obsolete Design Documents

These documents in `docs/design/` reference removed features, old binary
names, old paths, or environment variables that no longer exist. They have
been deleted from the repository. The table below records what they were
and when they were last accessible.

**Criteria for obsolescence:** The document references one or more of:
`--semantic-cleanup`, `--indent-aware`, `--op-order`, `pp_` prefix,
`animator/bin/`, `compute/bin/`, `DIFFVIM_*` env vars, `layers.conf`,
or old binary names (`diffvim-compute`, `diffvim-postprocess`, etc.).

All were created in commit `12700a4` (2026-08-28) and were last accessible
at commit `d1efd32` (2026-08-31).

| # | Document | Reason for obsolescence |
|---|----------|------------------------|
| 1 | `100_IMPROVEMENTS.md` | References removed options, pp_ prefix, env vars |
| 2 | `ADOPTION_GUIDE.md` | References removed options, env vars |
| 3 | `ANIMATOR_REQUIREMENTS.md` | References removed options |
| 4 | `API_REFERENCE.md` | References removed options, env vars |
| 5 | `ARCHITECTURE_ANALYSIS.md` | References removed options |
| 6 | `BINARY_FORMAT_ANALYSIS.md` | References env vars |
| 7 | `COMPLETE_OPTIONS_REFERENCE.md` | References removed options |
| 8 | `CONFIGURATION.md` | References env vars |
| 9 | `CONTROLS.md` | References env vars |
| 10 | `DEBUGGING.md` | References removed options |
| 11 | `DEBUGGING_LAYERS.md` | References pp_ prefix |
| 12 | `DESIGN_smooth_cursor_and_distance_speed.md` | References env vars |
| 13 | `DEVELOPER_GUIDE.md` | References env vars |
| 14 | `DIFF_STUDY.md` | References removed options |
| 15 | `NEW_FEATURES.md` | References removed options, env vars |
| 16 | `NON_CHAR_OPTIONS.md` | References removed options |
| 17 | `OPTIONS_ANALYSIS.md` | References removed options, env vars |
| 18 | `OPTIONS_OVERVIEW.md` | References removed options |
| 19 | `OPTION_ANALYSIS.md` | References removed options |
| 20 | `OPTION_AUDIT.md` | References removed options, env vars |
| 21 | `OPTION_COMBINATIONS.md` | References removed options |
| 22 | `PER_LAYER_ADJUSTMENT_REQUIREMENTS.md` | References old paths |
| 23 | `POSTPROCESS_LAYERS.md` | References pp_ prefix |
| 24 | `POSTPROCESS_OPERATIONS.md` | References removed options |
| 25 | `POSTPROCESS_OPTIONS.md` | References removed options |
| 26 | `POSTPROCESS_PIPELINE.md` | References pp_ prefix |
| 27 | `POSTPROCESS_QUICK_REFERENCE.md` | References removed options |
| 28 | `POSTPROCESS_REDESIGN.md` | References removed options, pp_ prefix |
| 29 | `POSTPROCESS_TRANSFORMS.md` | References removed options |
| 30 | `PP_LAYER_DELETE_LINE_FIRST.md` | References pp_ prefix, old paths |
| 31 | `PP_LAYER_OVERWRITE.md` | References env vars |
| 32 | `REQUIREMENTS.md` | References removed options, env vars |
| 33 | `RESTORING_OLD_FEATURES.md` | References removed options, env vars |
| 34 | `TUNE_INTERFACE_ANALYSIS.md` | References removed options |
| 35 | `USER_REQUESTS.md` | References removed options |
| 36 | `VISUAL_GUIDE.md` | References env vars |

**Created:** `12700a4` (2026-08-28 15:46:39 +0000)  
**Last accessible:** `d1efd32` (2026-08-31)  
**Deleted:** this commit  

## Remaining design docs (23 files)

These documents do not reference any removed features and are kept as
historical design reference:

| Document | Description |
|----------|-------------|
| `AI_CODE_DIFFING.md` | AI-generated code diffing research notes |
| `ARCHITECTURE.md` | Architecture overview |
| `ARCHITECTURE_DIAGRAMS.md` | ASCII architecture diagrams |
| `DIFF_TOOL_REPLACEMENT.md` | Analysis of replacing other diff tools |
| `FAQ.md` | Frequently asked questions |
| `FOLLOW_IMPROVEMENTS.md` | Improvement ideas for following patches |
| `FORMATS.md` | File format documentation |
| `GITLOGUE_ANALYSIS.md` | Analysis of the gitlogue tool |
| `GITLOGUE_COMPARISON.md` | Comparison with gitlogue |
| `KEEP_OPS_ANALYSIS.md` | Analysis of keep ops |
| `LEFT_TO_RIGHT_ANALYSIS.md` | Analysis of l2r mode |
| `LEFT_TO_RIGHT_PROPOSED.md` | Original l2r proposal |
| `MULTI_FILE.md` | Multi-file animation docs |
| `NEXT_SESSION.md` | Notes for next session |
| `OP_LIST_PARALLELISM.md` | Parallel op list analysis |
| `PARALLEL_COMPUTE.md` | Parallel compute docs |
| `PARSERS.md` | Parser documentation |
| `PICKER.md` | Picker design |
| `PIPELINE.md` | Pipeline overview |
| `PIPELINE_DECORATE_ANALYSIS.md` | Decorate layer analysis |
| `POST_PROCESSING.md` | Post-processing overview |
| `README.md` | Design docs index |
| `VOCABULARY.md` | Project vocabulary |
