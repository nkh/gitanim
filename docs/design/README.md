# docs/design/

Design documents, analysis, and historical proposals for the ad project.

## Organization

- **Current design docs** — Architecture, layers, requirements, and
  analysis that reflect the current state of the project.
- **`archive/`** — Superseded documents kept for historical reference.
  These describe old architectures, removed features, or outdated
  designs. See `archive/README.md` for details.

## Key documents

### Getting started with the codebase

- `ARCHITECTURE.md` — (current version in `docs/src/architecture.md`)
- `DEVELOPER_GUIDE.md` — Developer guide for the current pipeline
- `DEVELOPING_A_LAYER.md` — How to write a new postprocess layer
- `PIPELINE.md` — Pipeline architecture overview

### Layer system

- `LAYERS_REFERENCE.md` — All 7 layers with pseudo-code and examples
- `LAYERS_REVIEW.md` — Layer audit with known problems and test results
- `API_REFERENCE.md` — C/C++ API reference for layer infrastructure

### Requirements and analysis

- `REQUIREMENTS.md` — Current requirements specification
- `AD_SESSION_REQUIREMENTS.md` — ad_session tool requirements
- `AD_WATCH_REQUIREMENTS.md` — ad_watch requirements
- `ANIMATOR_REQUIREMENTS.md` — C animator design
- `LINE_DELETE_IN_PLACE_PSEUDOCODE.md` — LDI algorithm analysis

### Improvement proposals

- `IMPROVEMENT_PROPOSALS.md` — 20 improvement proposals per tool
  (supersedes the archived `100_IMPROVEMENTS.md` and
  `FOLLOW_IMPROVEMENTS.md`)
- `IMPLEMENTATION_AUDIT.md` — Frank accounting of what's implemented
  vs promised

### Historical reference

- `USER_REQUESTS.md` — Complete log of all user requests across
  sessions (intentionally historical)
- `archive/` — Outdated design docs (old architectures, removed
  features)

## Inventory

See `../DOCS_AUDIT.md` for a relevance-scored inventory of all design
docs (HIGH/MEDIUM/LOW). Note: that audit may itself be outdated —
always cross-reference with the actual source code.
