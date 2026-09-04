# docs/

Documentation for the ad project.

## Structure

- `src/` — User guide (mdBook source). Build with `make docs` or
  `cd docs && mdbook serve`.
- `design/` — Design documents, analysis, and historical proposals.
  See `design/DOCS_AUDIT.md` for a relevance-scored inventory.

## Key documents

- [INSTALL.md](../INSTALL.md) — Building, installing, testing, debugging
- [src/SUMMARY.md](src/SUMMARY.md) — mdBook table of contents
- [design/LAYERS_REFERENCE.md](design/LAYERS_REFERENCE.md) — All layers with pseudo-code
- [design/LAYERS_REVIEW.md](design/LAYERS_REVIEW.md) — Layer audit and known issues
- [design/AD_SESSION_REQUIREMENTS.md](design/AD_SESSION_REQUIREMENTS.md) — Debugger design

## Building the mdBook

```bash
cd docs && mdbook serve    # http://localhost:3000
```
