# docs/

*Created:* `28fa1f5` (2026-08-19 20:47:45 +0000)
*Last updated:* `7b9e449` (2026-08-28 18:57:44 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


Documentation for the `ad` toolkit.

## Contents

- `book.toml` — mdBook configuration
- `src/` — mdBook source (user guide). Build with `cd docs && mdbook serve`.
- `design/` — historical design documents (NOT part of the user guide).
  See `DOCS_AUDIT.md` for a relevance-scored inventory.
- `DOCS_AUDIT.md` — audit of every design doc with a relevance score
- `RESTRUCTURE_ANALYSIS.md` — the restructure proposal that drove the
  recent refactor

## Building the docs

    cd docs && mdbook serve    # http://localhost:3000

Or build static HTML:

    cd docs && mdbook build     # output: docs/book/

## mdBook source layout

- `src/SUMMARY.md` — table of contents
- `src/introduction.md`, `src/installation.md`, `src/quick-start.md`, ...
- `src/plugin-layers.md` — plugin layer contract
- `src/contributing.md` — how to add a layer (TDD)
- `src/configuration.md` — environment variables and config file
