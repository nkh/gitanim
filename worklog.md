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
