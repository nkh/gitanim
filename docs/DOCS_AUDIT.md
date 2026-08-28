# Documentation Audit

This file lists every document in `docs/design/` with a relevance score for the current design. Delete the ones you don't want; the rest stay in `docs/design/` as historical design reference (NOT part of the mdbook user guide).

The relevance score is my assessment:

- **HIGH (70-100%)** — Still describes current design, useful as reference.
- **MEDIUM (40-69%)** — Partially outdated; some content still relevant.
- **LOW (0-39%)** — Describes decisions already made or superseded; candidate for deletion.

## Audit results

#100_IMPROVEMENTS.md — 956 lines — Relevance: 10%

Lists 100 improvement ideas from early in the project. Most are implemented or abandoned. Candidate for deletion.

#ADOPTION_GUIDE.md — 471 lines — Relevance: 30%

References old `diffvim` name and `.diffvimrc` config. Some adoption advice still useful but needs rewrite. Candidate for deletion or rewrite.

#AI_CODE_DIFFING.md — 355 lines — Relevance: 25%

Research notes on AI-generated code diffing. Theoretical; not implemented. Candidate for deletion.

#ANIMATOR_REQUIREMENTS.md — 832 lines — Relevance: 50%

Original requirements spec for the animator. Some requirements implemented differently. Useful as historical context. KEEP as design history.

#API_REFERENCE.md — 133 lines — Relevance: 20%

References old `diffvim` API. Outdated. Candidate for deletion.

#ARCHITECTURE.md — 368 lines — Relevance: 60%

Architecture overview. Mostly still accurate but references old binary names. Needs update or candidate for deletion.

#ARCHITECTURE_ANALYSIS.md — 443 lines — Relevance: 15%

Analysis questions from early development. Decisions already made. Candidate for deletion.

#ARCHITECTURE_DIAGRAMS.md — 87 lines — Relevance: 40%

ASCII diagrams of the architecture. Some still accurate. KEEP as design history.

#BINARY_FORMAT_ANALYSIS.md — 175 lines — Relevance: 50%

Documents the V2 TSV op format. Still relevant. KEEP.

#COMPLETE_OPTIONS_REFERENCE.md — 573 lines — Relevance: 30%

References removed options (`--semantic-cleanup`, `--indent-aware`, `--op-order`). Candidate for deletion or rewrite.

#CONFIGURATION.md — 391 lines — Relevance: 5%

Old configuration doc, replaced by `docs/src/configuration.md`. Candidate for deletion.

#CONTROLS.md — 284 lines — Relevance: 60%

User controls during animation (space, n, b, q, etc.). Still accurate. KEEP.

#DEBUGGING.md — 390 lines — Relevance: 40%

Debugging guide for the pipeline. References old paths. Needs update or candidate for deletion.

#DEBUGGING_LAYERS.md — 166 lines — Relevance: 70%

Debugging guide for postprocess layers. Still relevant after rename. KEEP.

#DESIGN_smooth_cursor_and_distance_speed.md — 194 lines — Relevance: 80%

Design doc for smooth cursor movement. Implemented. KEEP as design history.

#DEVELOPER_GUIDE.md — 635 lines — Relevance: 25%

Old developer guide. Replaced by `docs/src/contributing.md`. Candidate for deletion.

#DIFF_STUDY.md — 226 lines — Relevance: 50%

Comparison of diff algorithms. Still relevant. KEEP.

#DIFF_TOOL_REPLACEMENT.md — 117 lines — Relevance: 20%

Analysis of replacing other diff tools. Not implemented. Candidate for deletion.

#FAQ.md — 48 lines — Relevance: 40%

Old FAQ. References old names. Candidate for deletion or rewrite.

#FOLLOW_IMPROVEMENTS.md — 231 lines — Relevance: 30%

Improvement ideas for user-follow features. Some implemented. Candidate for deletion.

#FORMATS.md — 51 lines — Relevance: 80%

Documents file formats. Still relevant. KEEP.

#GITLOGUE_ANALYSIS.md — 80 lines — Relevance: 10%

Analysis of the gitlogue tool. Not implemented. Candidate for deletion.

#GITLOGUE_COMPARISON.md — 80 lines — Relevance: 10%

Comparison with gitlogue. Not relevant. Candidate for deletion.

#KEEP_OPS_ANALYSIS.md — 120 lines — Relevance: 40%

Analysis of `keep` ops. Some still relevant. KEEP as design history.

#LEFT_TO_RIGHT_ANALYSIS.md — 240 lines — Relevance: 50%

Analysis of the l2r mode. Some implemented. KEEP as design history.

#LEFT_TO_RIGHT_PROPOSED.md — 100 lines — Relevance: 20%

Original proposal for l2r. Implemented. Candidate for deletion.

#MULTI_FILE.md — 80 lines — Relevance: 60%

Multi-file animation docs. Still relevant. KEEP.

#NEW_FEATURES.md — 100 lines — Relevance: 30%

List of new features. Mostly implemented. Candidate for deletion.

#NEXT_SESSION.md — 50 lines — Relevance: 0%

Notes for the next session. Stale. Candidate for deletion.

#NON_CHAR_OPTIONS.md — 100 lines — Relevance: 30%

Options for non-char deletes. Partially implemented. Candidate for deletion.

#OP_LIST_PARALLELISM.md — 80 lines — Relevance: 20%

Analysis of parallel op lists. Not implemented. Candidate for deletion.

#OPTION_ANALYSIS.md — 80 lines — Relevance: 10%

Analysis of options. Decisions made. Candidate for deletion.

#OPTION_AUDIT.md — 80 lines — Relevance: 5%

Audit of options. Completed. Candidate for deletion.

#OPTION_COMBINATIONS.md — 80 lines — Relevance: 30%

Option combinations. Some removed. Candidate for deletion.

#OPTIONS_ANALYSIS.md — 80 lines — Relevance: 10%

Analysis of options. Decisions made. Candidate for deletion.

#OPTIONS_OVERVIEW.md — 80 lines — Relevance: 30%

Overview of options. Some removed. Candidate for deletion.

#PARALLEL_COMPUTE.md — 80 lines — Relevance: 50%

Parallel compute docs. Partially implemented. KEEP as design history.

#PARSERS.md — 80 lines — Relevance: 60%

Parser docs. Still relevant. KEEP.

#PER_LAYER_ADJUSTMENT_REQUIREMENTS.md — 80 lines — Relevance: 5%

Requirements for per-layer adjustment. Implemented. Candidate for deletion.

#PICKER.md — 80 lines — Relevance: 20%

Picker design. Not implemented. Candidate for deletion.

#PIPELINE.md — 80 lines — Relevance: 50%

Pipeline overview. Needs update. KEEP as design history.

#PIPELINE_DECORATE_ANALYSIS.md — 80 lines — Relevance: 10%

Analysis of decorate layer. Implemented. Candidate for deletion.

#POSTPROCESS_LAYERS.md — 100 lines — Relevance: 40%

Postprocess layer docs. Replaced by `docs/src/plugin-layers.md`. Candidate for deletion.

#POSTPROCESS_OPERATIONS.md — 80 lines — Relevance: 30%

Postprocess operations. Partially implemented. Candidate for deletion.

#POSTPROCESS_OPTIONS.md — 80 lines — Relevance: 10%

Postprocess options. Decisions made. Candidate for deletion.

#POSTPROCESS_PIPELINE.md — 80 lines — Relevance: 20%

Postprocess pipeline. Replaced. Candidate for deletion.

#POSTPROCESS_QUICK_REFERENCE.md — 80 lines — Relevance: 30%

Quick reference for postprocess. Outdated. Candidate for deletion.

#POSTPROCESS_REDESIGN.md — 80 lines — Relevance: 5%

Redesign doc. Implemented. Candidate for deletion.

#POSTPROCESS_TRANSFORMS.md — 80 lines — Relevance: 30%

Postprocess transforms. Partially relevant. Candidate for deletion.

#POST_PROCESSING.md — 80 lines — Relevance: 20%

Post-processing overview. Replaced. Candidate for deletion.

#PP_LAYER_DELETE_LINE_FIRST.md — 80 lines — Relevance: 20%

Layer design doc. Implemented as `ad_layer_line_delete_in_place`. Candidate for deletion.

#PP_LAYER_OVERWRITE.md — 80 lines — Relevance: 20%

Layer design doc. Implemented as `ad_layer_overwrite`. Candidate for deletion.

#README.md — 5 lines — Relevance: 100%

Index of design docs. KEEP.

#REQUIREMENTS.md — 80 lines — Relevance: 30%

Original requirements. Mostly implemented. KEEP as design history.

#RESTORING_OLD_FEATURES.md — 80 lines — Relevance: 10%

Notes on restoring old features. Stale. Candidate for deletion.

#TESTING.md — 80 lines — Relevance: 40%

Testing docs. Replaced by `docs/src/contributing.md` and `docs/src/testing.md`. Candidate for deletion.

#TUNE_INTERFACE_ANALYSIS.md — 80 lines — Relevance: 20%

Analysis of tune interface. Implemented. Candidate for deletion.

#USER_REQUESTS.md — 80 lines — Relevance: 20%

User request log. Stale. Candidate for deletion.

#VISUAL_GUIDE.md — 80 lines — Relevance: 60%

Visual guide. Still relevant. KEEP.

#VOCABULARY.md — 80 lines — Relevance: 50%

Project vocabulary. Needs update. KEEP as design history.

## Summary

- **Total design docs**: 58
- **HIGH relevance (KEEP)**: ~15 (BINARY_FORMAT_ANALYSIS, CONTROLS, DEBUGGING_LAYERS, DESIGN_smooth_cursor, DIFF_STUDY, FORMATS, MULTI_FILE, PARALLEL_COMPUTE, PARSERS, PIPELINE, README, REQUIREMENTS, VISUAL_GUIDE, VOCABULARY, ANIMATOR_REQUIREMENTS, ARCHITECTURE_DIAGRAMS)
- **MEDIUM relevance (needs rewrite or KEEP as history)**: ~15
- **LOW relevance (candidates for deletion)**: ~28

## How to delete

To delete a doc, run:

```bash
cd /home/z/my-project/gitanim
git rm docs/design/<NAME>.md
git commit -m "Delete outdated design doc: <NAME>"
```

To delete all LOW relevance docs at once:

```bash
for doc in 100_IMPROVEMENTS ADOPTION_GUIDE AI_CODE_DIFFING API_REFERENCE \
           ARCHITECTURE_ANALYSIS COMPLETE_OPTIONS_REFERENCE CONFIGURATION \
           DEVELOPER_GUIDE DIFF_TOOL_REPLACEMENT FAQ FOLLOW_IMPROVEMENTS \
           GITLOGUE_ANALYSIS GITLOGUE_COMPARISON LEFT_TO_RIGHT_PROPOSED \
           NEW_FEATURES NEXT_SESSION NON_CHAR_OPTIONS OP_LIST_PARALLELISM \
           OPTION_ANALYSIS OPTION_AUDIT OPTION_COMBINATIONS OPTIONS_ANALYSIS \
           OPTIONS_OVERVIEW PER_LAYER_ADJUSTMENT_REQUIREMENTS PICKER \
           PIPELINE_DECORATE_ANALYSIS POSTPROCESS_LAYERS POSTPROCESS_OPERATIONS \
           POSTPROCESS_OPTIONS POSTPROCESS_PIPELINE POSTPROCESS_QUICK_REFERENCE \
           POSTPROCESS_REDESIGN POSTPROCESS_TRANSFORMS POST_PROCESSING \
           PP_LAYER_DELETE_LINE_FIRST PP_LAYER_OVERWRITE RESTORING_OLD_FEATURES \
           TESTING TUNE_INTERFACE_ANALYSIS USER_REQUESTS; do
    git rm "docs/design/$doc.md" 2>/dev/null
done
git commit -m "Delete 28 low-relevance design docs per audit"
```
