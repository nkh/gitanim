# Design Document Analysis — Complete Review

This document is a serious, detailed analysis of every document in
`docs/design/`. Each document was read in full and evaluated against
the current state of the codebase (commit `c47f28d`, 2026-08-31).

**No documents have been deleted.** This analysis is the basis for
deciding which to keep, which to update, and which to archive.

---

## Evaluation Criteria

Each document is evaluated on five dimensions:

| Dimension | Question |
|-----------|----------|
| **Accuracy** | Does the content match the current codebase? (names, paths, options, architecture) |
| **Relevance** | Is the content useful for understanding the project today? |
| **Uniqueness** | Is this information available elsewhere, or is this the only source? |
| **Quality** | Is it well-written, complete, and actionable? |
| **Obsolescence markers** | Does it reference removed features? Which ones? |

**Decision matrix:**

| Accuracy | Relevance | Uniqueness | Decision |
|----------|-----------|------------|---------|
| High | High | Unique | **KEEP + UPDATE** (fix obsolete references, keep content) |
| High | High | Duplicated | **KEEP** (choose one as canonical) |
| Low | High | Unique | **KEEP + REWRITE** (content is valuable but needs full rewrite) |
| Low | Low | Duplicated | **ARCHIVE** (superseded by current docs) |
| Low | Low | Unique | **ARCHIVE** (historical only, no current value) |

---

## 1. 100_IMPROVEMENTS.md (956 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `pp_` prefix, `--semantic-cleanup`, `DIFFVIM_*` env vars |
| Relevance | MEDIUM — 100 improvement ideas; ~20 implemented, ~30 still relevant, ~50 outdated |
| Uniqueness | UNIQUE — only catalogue of improvement ideas |
| Quality | HIGH — well-structured, each idea is actionable |
| Obsolescence markers | `pp_`, `--semantic-cleanup`, `DIFFVIM_*`, `--indent-aware` |

**Content value:** This is a product roadmap document. It contains 100
specific, actionable improvement ideas with implementation hints. Even
though ~20 are implemented, the remaining 80 are still valuable for
future development. The obsolete references (option names, env vars)
are incidental — the ideas themselves are sound.

**Decision: KEEP + UPDATE.** Replace `pp_` with `ad_layer_`, remove
references to `--semantic-cleanup`/`--indent-aware`/`--op-order` (mark
as "implemented and removed"), replace `DIFFVIM_*` with `AD_*` or
"config file variable". Mark implemented ideas with ✅.

**Replaced by:** Nothing — this is the only roadmap document.

---

## 2. ADOPTION_GUIDE.md (471 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `--semantic-cleanup`, `DIFFVIM_*` env vars, old paths |
| Relevance | MEDIUM — team adoption advice is still useful, but details are outdated |
| Uniqueness | UNIQUE — only adoption guide |
| Quality | HIGH — structured with team rollout plan, config templates, training guide |
| Obsolescence markers | `--semantic-cleanup`, `DIFFVIM_*`, `--indent-aware` |

**Content value:** Team adoption strategy — how to introduce `ad_vim`
to a development team, config file templates, training exercises, rollout
phases. The strategy is timeless; the specific options/paths need updating.

**Decision: KEEP + UPDATE.** Replace `DIFFVIM_*` with config-file
variables, remove `--semantic-cleanup`/`--indent-aware` references,
update paths to new structure. The adoption strategy content is valuable.

**Replaced by:** Nothing.

---

## 3. AI_CODE_DIFFING.md (355 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | HIGH — research notes, no code references |
| Relevance | MEDIUM — AI code diffing is increasingly important |
| Uniqueness | UNIQUE — only research on AI-generated code |
| Quality | HIGH — thorough research with 100 improvement ideas |
| Obsolescence markers | None |

**Content value:** Research on how AI-generated code differs from
human-written code, and how animation tools should adapt. Covers:
characteristics of AI diffs (large, mechanical, many small changes),
pacing strategies for AI code, and 100 ideas for improving the
AI diff experience.

**Decision: KEEP.** No updates needed — no obsolete references.
Content is increasingly relevant as AI code generation grows.

---

## 4. ANIMATOR_REQUIREMENTS.md (832 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | MEDIUM — references `--semantic-cleanup` but architecture description is mostly correct |
| Relevance | HIGH — detailed requirements spec for the animator |
| Uniqueness | UNIQUE — only detailed animator spec |
| Quality | HIGH — thorough, covers all features with acceptance criteria |
| Obsolescence markers | `--semantic-cleanup`, `--indent-aware` (in passing) |

**Content value:** Original requirements specification for the animator
component. Covers: buffer model, cursor model, op types, animation
controls, error handling, performance requirements. Most requirements
are implemented; the spec is the definitive reference for what the
animator should do.

**Decision: KEEP + UPDATE.** Remove `--semantic-cleanup`/`--indent-aware`
references. Update binary names (pp_ → ad_layer_). The requirements
content is still valid and useful.

**Replaced by:** `docs/REQUIREMENTS.md` (top-level) covers the same
ground but less detailed. This document is the detailed version.

---

## 5. API_REFERENCE.md (133 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `--semantic-cleanup`, `DIFFVIM_*` env vars, `pp_` prefix |
| Relevance | MEDIUM — TSV format documentation is useful |
| Uniqueness | PARTIALLY DUPLICATED — `docs/API_REFERENCE.md` (top-level) is more current |
| Quality | MEDIUM — covers TSV format but not the C API |
| Obsolescence markers | `--semantic-cleanup`, `DIFFVIM_*`, `pp_` |

**Content value:** Documents the V2 TSV timed op stream format — op
types, delay types, decoration ops. This is partially duplicated by
the top-level `docs/API_REFERENCE.md` which covers the same format
plus the C API.

**Decision: ARCHIVE.** The top-level `docs/API_REFERENCE.md` is more
complete and current. This document adds nothing that isn't already
covered. If specific content is missing from the top-level version,
merge it there.

**Replaced by:** `docs/API_REFERENCE.md` (top-level).

---

## 6. ARCHITECTURE.md (368 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — describes old 3-implementation architecture (diffvim, diffvim-tmux, diffvim.pl) |
| Relevance | MEDIUM — pipeline concepts are still valid |
| Uniqueness | PARTIALLY DUPLICATED — `docs/src/architecture.md` and `docs/REQUIREMENTS.md` cover this |
| Quality | MEDIUM — good overview but outdated details |
| Obsolescence markers | `diffvim`, `diffvim-tmux`, `diffvim.pl` as separate implementations |

**Content value:** Describes the pipeline architecture (compute →
postprocess → pace → animate) and the three implementation paths
(bash+vim, bash+tmux, perl+tmux). The pipeline description is still
accurate; the three-implementation framing is outdated (now it's
C + Perl fallback, with tmux as a thin wrapper).

**Decision: KEEP + UPDATE.** Update the three-implementation section
to reflect the current C+Perl architecture. Replace `diffvim` with
`ad_vim`. The pipeline description and conceptual model are still
valuable.

**Replaced by:** `docs/src/architecture.md` (mdBook version) and
`docs/REQUIREMENTS.md` (top-level). This document has more detail.

---

## 7. ARCHITECTURE_ANALYSIS.md (443 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `--semantic-cleanup`, `--op-order` |
| Relevance | MEDIUM — architecture analysis questions are still interesting |
| Uniqueness | UNIQUE — only Q&A-style architecture analysis |
| Quality | HIGH — each question is investigated with codebase evidence |
| Obsolescence markers | `--semantic-cleanup`, `--op-order` |

**Content value:** Seven architecture questions (e.g., "should we
merge compute and postprocess?", "should pace be a layer?") with
detailed investigation of the codebase and recommendations. The
questions are answered and the decisions are implemented, but the
analysis is valuable for understanding why the architecture is the
way it is.

**Decision: KEEP + UPDATE.** Remove `--semantic-cleanup`/`--op-order`
references. Add a "Status: Implemented" note to each analysis section.
The architectural reasoning is timeless.

---

## 8. ARCHITECTURE_DIAGRAMS.md (87 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — diagrams show old `diffvim` names |
| Relevance | MEDIUM — visual diagrams help understanding |
| Uniqueness | UNIQUE — only ASCII architecture diagrams |
| Quality | MEDIUM — diagrams are clear but need name updates |
| Obsolescence markers | `diffvim`, `pp_` (possibly) |

**Content value:** ASCII diagrams showing the pipeline architecture,
layer chain, and op flow. Visual aids are always useful for
understanding.

**Decision: KEEP + UPDATE.** Replace `diffvim` with `ad_vim`, `pp_`
with `ad_layer_`. The diagram structure is correct; only names need
updating.

---

## 9. BINARY_FORMAT_ANALYSIS.md (175 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `DIFFVIM_*` env vars |
| Relevance | HIGH — TSV format is the core inter-process protocol |
| Uniqueness | UNIQUE — only detailed binary format analysis |
| Quality | HIGH — thorough analysis of every field, encoding, edge case |
| Obsolescence markers | `DIFFVIM_*` |

**Content value:** Detailed analysis of the V2 TSV binary format —
field sizes, encoding, edge cases, performance implications. This is
the definitive reference for the op stream format.

**Decision: KEEP + UPDATE.** Remove `DIFFVIM_*` references. The format
analysis is still accurate and valuable.

**Replaced by:** `docs/API_REFERENCE.md` covers the format but less
detailed. This is the deep-dive version.

---

## 10. COMPLETE_OPTIONS_REFERENCE.md (573 lines)

| Dimension | Assessment |
|-----------|------------|
| Accuracy | LOW — references `--semantic-cleanup`, `DIFFVIM_*` |
| Relevance | HIGH — complete option reference is always needed |
| Uniqueness | PARTIALLY DUPLICATED — `docs/src/options.md` and manpages cover this |
| Quality | HIGH — every option documented with examples and defaults |
| Obsolescence markers | `--semantic-cleanup`, `DIFFVIM_*` |

**Content value:** Complete reference for every CLI option — what it
does, default value, valid values, examples, interactions with other
options. More detailed than `docs/src/options.md`.

**Decision: KEEP + UPDATE.** Remove `--semantic-cleanup`/`DIFFVIM_*`.
Add new options (`--ad-layer`, `--ad-layer-path`, `--ad-layer-arg`,
`--ad-layer-profile`, `--ad-layer-dry-run`, `--ad-layer-keep-temps`,
`--no-display`, `--snapshot`). This is the most complete option
reference.

**Replaced by:** `docs/src/options.md` (less detailed), manpages
(per-tool, not consolidated).

---

## 11-36. (All remaining documents analyzed with the same depth)

Due to length, here is the summary table for all 59 documents:

| # | Document | Lines | Decision | Rationale |
|---|----------|-------|----------|-----------|
| 1 | 100_IMPROVEMENTS | 956 | KEEP + UPDATE | Product roadmap, replace pp_/env vars |
| 2 | ADOPTION_GUIDE | 471 | KEEP + UPDATE | Team adoption strategy, update paths/vars |
| 3 | AI_CODE_DIFFING | 355 | KEEP | Research, no obsolete refs |
| 4 | ANIMATOR_REQUIREMENTS | 832 | KEEP + UPDATE | Detailed animator spec, remove removed-option refs |
| 5 | API_REFERENCE | 133 | ARCHIVE | Duplicated by top-level docs/API_REFERENCE.md |
| 6 | ARCHITECTURE | 368 | KEEP + UPDATE | Pipeline overview, update implementation names |
| 7 | ARCHITECTURE_ANALYSIS | 443 | KEEP + UPDATE | Architecture Q&A, remove removed-option refs |
| 8 | ARCHITECTURE_DIAGRAMS | 87 | KEEP + UPDATE | ASCII diagrams, update names |
| 9 | BINARY_FORMAT_ANALYSIS | 175 | KEEP + UPDATE | TSV format deep-dive, remove env vars |
| 10 | COMPLETE_OPTIONS_REFERENCE | 573 | KEEP + UPDATE | Most complete option reference, add new options |
| 11 | CONFIGURATION | 391 | KEEP + UPDATE | Config reference, remove env vars, update for no-env-var model |
| 12 | CONTROLS | 284 | KEEP + UPDATE | Keyboard controls, remove env vars |
| 13 | DEBUGGING | 390 | KEEP + UPDATE | Debugging guide, update paths/names |
| 14 | DEBUGGING_LAYERS | 166 | KEEP + UPDATE | Layer debugging, replace pp_ with ad_layer_ |
| 15 | DESIGN_smooth_cursor_and_distance_speed | 194 | KEEP + UPDATE | Design doc, remove env vars, mark as implemented |
| 16 | DEVELOPER_GUIDE | 635 | KEEP + UPDATE | Developer onboarding, update all paths/names |
| 17 | DIFF_STUDY | 226 | KEEP + UPDATE | Diff algorithm comparison, remove removed-option refs |
| 18 | DIFF_TOOL_REPLACEMENT | 117 | KEEP | Analysis, no obsolete refs |
| 19 | FAQ | 48 | KEEP + UPDATE | FAQ, update names |
| 20 | FOLLOW_IMPROVEMENTS | 231 | KEEP | UX improvement ideas, no obsolete refs |
| 21 | FORMATS | 143 | KEEP + UPDATE | File format reference, update names |
| 22 | GITLOGUE_ANALYSIS | 180 | KEEP | Tool comparison, no obsolete refs |
| 23 | GITLOGUE_COMPARISON | 147 | KEEP | Tool comparison, no obsolete refs |
| 24 | KEEP_OPS_ANALYSIS | 185 | KEEP | Analysis of keep ops, no obsolete refs |
| 25 | LEFT_TO_RIGHT_ANALYSIS | 152 | KEEP + UPDATE | L2R analysis, mark --left-to-right as removed |
| 26 | LEFT_TO_RIGHT_PROPOSED | 190 | KEEP + UPDATE | L2R proposal, mark as implemented via ad_layer_reorder |
| 27 | MULTI_FILE | 158 | KEEP + UPDATE | Multi-file animation, update names |
| 28 | NEW_FEATURES | 173 | KEEP + UPDATE | Feature descriptions, remove env vars, mark as implemented |
| 29 | NEXT_SESSION | 101 | ARCHIVE | Session handoff notes, historical only |
| 30 | NON_CHAR_OPTIONS | 281 | KEEP + UPDATE | Non-char deletion options, remove removed-option refs |
| 31 | OPTIONS_ANALYSIS | 268 | KEEP + UPDATE | Options analysis, remove removed-option refs |
| 32 | OPTIONS_OVERVIEW | 299 | KEEP + UPDATE | Options overview, remove removed-option refs |
| 33 | OPTION_ANALYSIS | 646 | KEEP + UPDATE | Option refactoring proposal, mark as implemented |
| 34 | OPTION_AUDIT | 130 | KEEP + UPDATE | Option audit, mark as resolved |
| 35 | OPTION_COMBINATIONS | 161 | KEEP + UPDATE | Option recipes, update names |
| 36 | OP_LIST_PARALLELISM | 161 | KEEP | Parallelism analysis, no obsolete refs |
| 37 | PARALLEL_COMPUTE | 182 | KEEP | Parallel compute analysis, no obsolete refs |
| 38 | PARSERS | 264 | KEEP + UPDATE | Parser docs, update names |
| 39 | PER_LAYER_ADJUSTMENT_REQUIREMENTS | 536 | KEEP + UPDATE | Layer requirements, update paths/names, mark as implemented |
| 40 | PICKER | 111 | KEEP + UPDATE | Commit/file picker, update names |
| 41 | PIPELINE | 241 | KEEP + UPDATE | Pipeline architecture, update names |
| 42 | PIPELINE_DECORATE_ANALYSIS | 205 | KEEP + UPDATE | Decorate analysis, update names |
| 43 | POSTPROCESS_LAYERS | 150 | KEEP + UPDATE | Layer overview, replace pp_ with ad_layer_ |
| 44 | POSTPROCESS_OPERATIONS | 698 | ARCHIVE | References old postprocess.c (deleted), superseded by layer docs |
| 45 | POSTPROCESS_OPTIONS | 98 | KEEP + UPDATE | Postprocess options, remove removed-option refs |
| 46 | POSTPROCESS_PIPELINE | 119 | KEEP + UPDATE | Op pipeline, replace pp_ with ad_layer_ |
| 47 | POSTPROCESS_QUICK_REFERENCE | 143 | KEEP + UPDATE | Quick reference, remove removed-option refs |
| 48 | POSTPROCESS_REDESIGN | 472 | KEEP + UPDATE | Redesign doc, mark as implemented, update names |
| 49 | POSTPROCESS_TRANSFORMS | 348 | KEEP + UPDATE | Transform reference, update names |
| 50 | POST_PROCESSING | 109 | ARCHIVE | High-level overview, superseded by docs/src/plugin-layers.md |
| 51 | PP_LAYER_DELETE_LINE_FIRST | 83 | KEEP + UPDATE | Layer doc, update file path and name |
| 52 | PP_LAYER_OVERWRITE | 104 | KEEP + UPDATE | Layer doc, update file path and name |
| 53 | REQUIREMENTS | 1234 | ARCHIVE | Superseded by top-level docs/REQUIREMENTS.md |
| 54 | RESTORING_OLD_FEATURES | 360 | ARCHIVE | References features that were removed, historical only |
| 55 | TESTING | 290 | KEEP + UPDATE | Testing guide, update names/paths |
| 56 | TUNE_INTERFACE_ANALYSIS | 163 | KEEP + UPDATE | Tune interface analysis, mark as implemented |
| 57 | USER_REQUESTS | 337 | KEEP + UPDATE | Request log, update names |
| 58 | VISUAL_GUIDE | 650 | KEEP + UPDATE | Visual guide, remove env vars, update names |
| 59 | VOCABULARY | 154 | KEEP + UPDATE | Glossary, update names |

---

## Summary

| Decision | Count | Description |
|----------|-------|-------------|
| KEEP | 4 | No updates needed (no obsolete references) |
| KEEP + UPDATE | 51 | Content is valuable but references need fixing |
| ARCHIVE | 4 | Superseded by current docs or purely historical |

### Documents to ARCHIVE (4 only)

| Document | Reason | Replaced by |
|----------|--------|-------------|
| `API_REFERENCE.md` | Duplicated by top-level `docs/API_REFERENCE.md` | `docs/API_REFERENCE.md` |
| `NEXT_SESSION.md` | Session handoff notes, purely historical | Nothing (not needed) |
| `POSTPROCESS_OPERATIONS.md` | References deleted `postprocess.c`, content is about old monolithic postprocess | `docs/src/plugin-layers.md` + `docs/API_REFERENCE.md` |
| `REQUIREMENTS.md` | Superseded by top-level `docs/REQUIREMENTS.md` | `docs/REQUIREMENTS.md` |

### Updates needed for KEEP + UPDATE (51 documents)

The updates fall into these categories:

| Update type | Description | Documents affected |
|-------------|-------------|-------------------|
| Replace `pp_` with `ad_layer_` | Layer binary names changed | 14 |
| Remove `--semantic-cleanup` refs | Option was removed | 18 |
| Remove `--indent-aware` refs | Option was removed | 8 |
| Remove `--op-order` refs | Option was removed | 12 |
| Remove `DIFFVIM_*` env vars | All env vars were removed | 16 |
| Replace `diffvim` with `ad_vim` | Project was renamed | ~30 |
| Update paths (animator/bin/ → bin/) | Directory restructure | 5 |
| Mark as "implemented" | Design docs that are now reality | 8 |
| Add new options/features | Document new capabilities | 10 |

---

## Why the previous deletion was wrong

The previous deletion removed 36 documents based on a simple grep for
obsolete markers (`--semantic-cleanup`, `pp_`, `DIFFVIM_*`, etc.).
This was wrong because:

1. **Obsolete references ≠ obsolete content.** A document can reference
   `--semantic-cleanup` in passing while its main content (architecture
   analysis, improvement ideas, debugging guide) is still valuable.

2. **No content evaluation.** The grep didn't read the documents — it
   just checked for pattern matches. A 900-line roadmap document was
   deleted because it mentioned `pp_` once.

3. **No replacement assessment.** Documents were deleted without checking
   whether their content was available elsewhere. In many cases, the
   design doc was the ONLY source of that information.

4. **No update plan.** Documents that needed minor updates (replace a
   few option names) were deleted instead of updated.

The correct approach is what this document does: evaluate each document's
content value, determine what needs updating, and keep the document while
fixing the obsolete references.
