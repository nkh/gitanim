# tests/

Test suites for the `ad` toolkit.

## Contents

- `examples/` — 36 old/new file pairs covering 26 languages (Python, Go,
  Rust, C, TypeScript, Java, etc.). The canonical end-to-end test corpus.
  Run with `bash tests/run_all_examples.sh`.
- `minimal/` — 25 minimal old/new file pairs, each testing ONE specific
  transformation (insert, delete, replace, indent change, etc.).
  Run with `bash tests/run_minimal_tests.sh`.
- `test_*.pl` / `test_*.sh` — cross-cutting tests (property, roundtrip,
  parity, pipeline options, layer discovery, etc.).
- `run_all_examples.sh` — runs every example through the full pipeline.
- `run_minimal_tests.sh` — runs every minimal case.

## Running tests

    make test                 # all tests
    make test-layers          # per-layer tests (TDD)
    make test-minimal         # 25 minimal cases
    make test-examples        # 36 examples (canonical corpus)
    make test-l2r             # l2r algorithm tests (35 cases)
    make test-property        # 50 random property-based tests
    make test-layers-discovery  # plugin contract tests

## Per-layer tests

Live in `layers/tests/` (one test file per layer). See
`layers/README.md` and `docs/src/contributing.md` for the TDD workflow.
