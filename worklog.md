# Worklog

## Task ID: 8 — Agent: option-auditor
**Task:** Audit all script options vs docs (manpages + design docs).
**Branch:** refactor/no-newline-in-char-ops
**Date:** 2026-09-10

### Scope
Audited 32 tools/binaries against their manpages using the standard
method: grep the source for accepted options, grep the manpage for
documented options, diff the two lists. Also checked design docs and
READMEs for stale `--seek` references (must not appear as a working
option anywhere) and for stale `--tick-ms`/`--max-line-len` references
in the bin/ad manpage.

### Result
Full audit report returned to the orchestrator as the final message.
No files were edited (read-only audit per task instructions).

### Key findings
- 25 phantom options total (documented but not actually accepted)
- 50 undocumented options total (accepted but not in manpage)
- `--seek` confirmed absent from all current manpages and source code
  (only historical mentions in docs/design/CODE_ANALYSIS.md and
  docs/design/archive/LAYER_ANALYSIS_AND_DOC_REVIEW.md — both OK)
- bin/ad manpage still has the known phantom `--tick-ms` and
  `--max-line-len` entries (plus `-V` alias not in ad.c)
- bin/ad_compute manpage documents 4 options that the C++ tool does
  not accept (`--algorithm patience`, `--optimize-sequence`,
  `--no-optimize-sequence`, `--left-to-right`) and omits
  `--semantic-cleanup` which it does accept
- apps/vim/ad_vim manpage is the most out-of-sync: 5 phantom + 26
  undocumented options
- 3 layer manpages (reorder, overwrite, indent_last) document a
  `--debug` option that no layer C source actually accepts
- scripts/ad_suggest.1 documents `--help`/`-h` for a script that has
  no argument parser at all (it's a sourced function library)
- 3 ad_pipeline manpage entries (`--ad-layer-arg`, `--ad-layer-profile`,
  `--ad-layer-dry-run`, `--ad-layer-keep-temps`) are ad_postprocess
  options wrongly listed as ad_pipeline options
- scripts/ad_tmux manpage documents `--tmux-session NAME` but the
  script accepts `--session-name NAME` (wrong name in manpage)
- scripts/README.md and man/README.md are missing index entries for
  `ad_doc_provenance`, `ad_anim_test`, `ad_l1l2` manpages
- docs/design/COMPLETE_OPTIONS_REFERENCE.md still lists `--tick-ms`
  as a working ad_vim option (lines 37–41) — stale
- docs/design/OPTIONS_ANALYSIS.md line 108 lists `--tick-ms` as a
  "current" timing option — stale
- docs/design/OPTION_AUDIT.md correctly marks `--max-line-len` as
  "Not used" (audit is honest about it)

---
Task ID: reverse-1
Agent: main
Task: Run all minimal tests in opposite order (new -> old), verify final snapshot == old, and run ad_l1l2 on each.

Work Log:
- Wrote tests/run_minimal_tests_reversed.sh — mirrors run_minimal_tests.sh but swaps OLD/NEW per case.
- Pipeline stages run with swapped args:
    bin/ad_compute new old raw
    pipeline/ad_postprocess --ad-layer=ad_layer_reorder < raw > post
    bin/ad_layer_pace < post > timed
    bin/ad --no-display --speed 1000 --snapshot snap new < timed
- Compared snap vs old (new target). On FAIL, ran scripts/ad_l1l2 new old timed.
- Then ran scripts/ad_l1l2 on every reversed timed file regardless of pass/fail to catch hidden per-hunk divergence.

Stage Summary:
- All 27 minimal cases PASS in reversed direction (new -> old).
- L1/L2 on every reversed timed file: L2=0 and L2_HUNK=0 across the board — no divergence detected.
- The 27_weird_insert case (previously a bug in this session) now PASSES both directions.
- Reversed-direction stage files retained at /tmp/ad_reverse/ for inspection.
- New script: tests/run_minimal_tests_reversed.sh

---
Task ID: reverse-2
Agent: main
Task: Run ALL tests (minimal + examples) in opposite order (new -> old), verify snapshot == old, run ad_l1l2 on every case.

Work Log:
- Extended runner to tests/run_all_tests_reversed.sh — covers BOTH tests/minimal/* (no-ext old/new pairs) and tests/examples/* (old.<ext>/new.<ext> pairs across 20+ languages).
- Same reversed pipeline: ad_compute new->old, ad_postprocess --ad-layer=ad_layer_reorder, ad_layer_pace, ad --snapshot starting from new.
- For failures: run scripts/ad_l1l2 new old timed to find L1/L2.
- For all-pass: also run ad_l1l2 on every reversed timed file to confirm no per-hunk divergence (L2=0 expected).

Stage Summary:
- ALL 68 cases pass in reversed direction (27 minimal + 41 example). Examples 25 is absent from the corpus (no such directory exists).
- Largest case: 42_large_huge_python with raw ops of 57019 lines and L_TOTAL=1016.
- L1/L2 audit: L2=0, L2_HUNK=0 across the board. The pipeline is symmetric for every case in the corpus.
- Reversed stage files retained at /tmp/ad_reverse/.
- New script: tests/run_all_tests_reversed.sh

---
Task ID: reverse-3
Agent: main
Task: Wire reversed-direction tests into the Makefile and add a property-based reversed fuzz test.

Work Log:
- Discovered the working-tree Makefile had its tab indentation clobbered to 8 spaces by an earlier edit, breaking every recipe. Restored via `git checkout HEAD -- Makefile` (HEAD's version uses real tabs).
- Wrote scripts/edit_makefile.py — a surgical Python editor that uses real `\t` chars (the MultiEdit tool was converting `\t` JSON escapes to 8 spaces, which broke recipes).
- Added 3 sections to the Makefile:
    - `test-reversed` target → calls tests/run_all_tests_reversed.sh
    - `test-property-reversed` target → calls tests/test_property_reversed.pl
    - 2 new entries in `help` (`make test-property-reversed`, `make test-reversed`)
- Wired both new targets into the main `test` target so they run in CI.
- Wrote tests/test_property_reversed.pl — mirrors test_property.pl but runs ad_pipeline with swapped args (new -> old) and verifies snap == old. 100 iterations, runs ad_l1l2 on failure to locate L1/L2.
- Discovered `make test-property-reversed` env var override: AD_PROPERTY_REVERSED_ITERATIONS controls iteration count.

Stage Summary:
- `make test-reversed`: 68/68 corpus cases pass (27 minimal + 41 example), L2=0 everywhere.
- `make test-property-reversed`: 100/100 random iterations pass.
- `make test-minimal`: 27/27 pass (unchanged).
- `make test-property`: 50/50 pass (unchanged).
- Makefile diff vs HEAD: 16 insertions, 1 deletion — clean, no whitespace collateral.
- New files: tests/run_all_tests_reversed.sh, tests/test_property_reversed.pl, scripts/edit_makefile.py.

---
Task ID: strategy-1
Agent: main
Task: Step back from byte-level bug fixing and write a real strategy for fixing animation quality.

Work Log:
- Inspected actual op stream for tests/minimal/04_word_replace (hello → greet) — found the smoking gun: LCS splits the word at the shared 'e' and produces 2 delete-insert pairs for what is semantically one word replacement. The reorder layer can't fix this because it can only reorder within segments; the diff itself is wrong.
- Surveyed existing layers: all 9 are patch-up layers operating on char ops after the fact. None categorizes the change semantically.
- Surveyed existing design docs: DIFF_STUDY.md covers reading-speed/cognitive-load research but doesn't translate it into an architectural fix.
- Wrote docs/design/ANIMATION_QUALITY_STRATEGY.md — 4-phase plan:
  Phase 1: Corpus analysis on existing tests + ~10 OS git histories, produce empirical edit-category histogram.
  Phase 2: Lock a 10-15 category taxonomy with disambiguation rules.
  Phase 3: Build a categorizer + per-category renderers, replacing the patch-up layers. Requires new animator op types (select, block_cut, cursor_jump, indent_shift, paste).
  Phase 4: Validation harness — structural op-stream tests + per-category property tests + side-by-side comparison. (This is what we've been skipping — snap==target is necessary but not sufficient.)
- Listed research to lean on: GumTree, difftastic, SemanticMerge, git --color-moved, JetBrains diff viewer, CodeMirror, Tversky animation research, Sweller cognitive load.
- Listed layers to deprecate: reorder, overwrite, indent_last, split_in_place, join_insert_in_place, batch_whitespace, skip_indent. Keep pace and highlight.

Stage Summary:
- Strategy doc at docs/design/ANIMATION_QUALITY_STRATEGY.md
- Key reframe: stop treating the char-diff as source of truth; the edit category is the source of truth.
- Asked user to confirm the reframe before starting Phase 1.

---
Task ID: strategy-2
Agent: main
Task: After user correction (layers ARE the categorization, don't remove them), do large corpus analysis and write revised strategy.

Work Log:
- Wrote analysis/edit_corpus_analysis.py — categorizes hunks from tests/minimal, tests/examples, and gitanim's own git history (200 commits sampled). No network for OS repos, used local git history instead.
- Analyzed 3,215 hunks total (3,129 from gitanim history + 62 from examples + 24 from minimal).
- Top categories: block_modify 23.6%, block_insert 18.9%, word_replace 18.8%, block_replace 10.8%, literal_replace 6.9%.
- Wrote analysis/layer_audit.py — runs each (category, layer) pair through the pipeline and records op-stream quality metrics: op count, deletes, inserts, overwrite_inserts, interleave flicker, unmerged del-ins pairs.
- Confirmed bug: ad_layer_overwrite does NOTHING on hello→greet. Input has delete 1 5 'h' followed by insert 1 5 'g' (adjacent, same line, same col) — exactly the pattern the layer claims to merge. Output is identical to input. 0 overwrite_insert ops produced.
- Confirmed bug: ad_layer_line_replace produces 0 ops for most categories and snapshot mismatch for the rest.
- Confirmed gap: block_move (2.0%) has no dedicated layer — current pipeline treats it as separate delete + insert.
- Confirmed gap: block_modify (23.6%) has 6 interleave flickers + 15 unmerged del-ins pairs surviving every layer.
- Wrote docs/design/LAYER_CENTRIC_STRATEGY.md — revised strategy that keeps the layer architecture. Plan:
    Phase 1: Fix ad_layer_overwrite (1 day) — hello→greet should produce 0 deletes
    Phase 2: Fix ad_layer_line_replace (1 day)
    Phase 3: Add test_op_stream_quality.pl (1 day) — catches "looks bad" patterns in CI
    Phase 4: Add ad_layer_word_replace (2 days) — needs new `select` op type
    Phase 5: Generalize ad_layer_line_delete_in_place to multi-line (1 day)
    Phase 6: Generalize ad_layer_indent_last (1 day)
    Phase 7: Add ad_layer_block_modify (2 days) — depends on word_replace
    Phase 8: Add ad_layer_block_move (3 days) — needs new move_start/move_end ops
    Phase 9: Generalize skip_indent → skip_noise (0.5 days)
    Phase 10: Word-boundary-aware LCS in compute (3 days, deferred)
- First visible win: Phase 1, 1-day fix, addresses most common visible bug.
- After Phase 7: 61% of corpus (top 3 categories) is fixed.

Stage Summary:
- analysis/edit_corpus.csv — 3,215 hunk rows with category + features
- analysis/edit_corpus_summary.md — histogram + per-category examples
- analysis/layer_audit.csv — per-(category, layer) quality metrics
- analysis/layer_audit.py — re-runnable audit script
- docs/design/LAYER_CENTRIC_STRATEGY.md — revised strategy (keeps layers, fixes them)
- Strategy asks user to confirm priority order, approve new op types (select, move_start/move_end), decide on batch_insert, decide on word-boundary LCS timing.

---
Task ID: layer-contracts-1
Agent: main
Task: Write 1-3 line contract tests for each layer, wire into make test, write detailed analysis document.

Work Log:
- Read all 9 layer source files (reorder, overwrite, indent_last, line_delete_in_place, split_in_place, join_insert_in_place, batch_whitespace, skip_indent, line_replace). Documented each layer's contract from its source code comments and implementation.
- Wrote tests/test_layer_contracts.pl — contract tests that feed hand-crafted 1-3 line input op streams directly into each layer binary and assert properties of the OUTPUT op stream (op count, type, positions, ordering). NOT snapshot tests. Key insight: snapshot==target passes with NO layer at all (raw op stream already produces correct buffer), so it cannot catch layer failures. Contract tests can.
- Discovered the Write tool converts tab characters to spaces in heredocs. Wrote scripts/write_layer_contracts.py to emit the test file with real Perl-interpreted \t escapes inside double-quoted strings.
- Test results: 27 passed, 2 failed. Both failures in ad_layer_overwrite on the hello→greet pattern (multi-delete + multi-insert run). Root cause identified: lines 36-42 of ad_layer_overwrite.c have a next_is_insert_same_line guard that blocks merging when the op after the insert is also an insert on the same line. This guard is wrong — overwrite_insert followed by insert is a valid sequence with no information loss.
- Wired test-layer-contracts into Makefile:
  - New target test-layer-contracts using `set -o pipefail` so failures propagate through `tail`.
  - Added to test-layers aggregate deps.
  - test-layers is already in `test` target, so `make test` now blocks on contract test failures.
  - Makefile diff: 7 insertions, 1 deletion (clean).
- Verified `make test` now stops at test-layer-contracts failure (exit 2) instead of continuing past broken layers.
- Wrote docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md — detailed engineering document with:
  - Per-layer contract, source location, test case, result, root cause analysis, fix design (with specific line numbers and code changes), acceptance criteria, risk assessment.
  - 10 phases with effort estimates (hours/days), dependencies, and new op type requirements.
  - 14 open questions for the user embedded in the relevant phases.
  - Phase summary table.

Stage Summary:
- tests/test_layer_contracts.pl — 29 assertions across 9 layers, 27 pass / 2 fail
- scripts/write_layer_contracts.py — script to regenerate the test file with real tabs
- docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md — the detailed analysis document
- Makefile wired so `make test` catches the 2 overwrite failures
- All 14 decision questions are in the document, not in chat
- Awaiting user review of the document and phase selection before writing any fix code
