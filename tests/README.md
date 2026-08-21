# tests/

Test suites for the diffvim pipeline.

## Subdirectories

- `minimal/` — 25 minimal old/new file pairs, each testing one specific
  transformation. See `minimal/README.md` for details.

## Files (test suites in this directory)

These test the old vimscript engine (pre-refactor). Most are now
deprecated — the engine was replaced with a thin timed-op-stream
reader. Use the `animator/tests/` directory for current tests.

- `test_comprehensive.pl` — Comprehensive test (may reference removed features)
- `test_correctness.pl` — Basic correctness tests
- `test_delete_pacing.pl` — Delete pacing tests
- `test_e2e_perl.pl` — End-to-end Perl tests
- `test_features.pl` — Feature tests
- `test_highlight.pl` — Syntax highlighting tests
- `test_integration.pl` — Integration tests
- `test_parser_compare.pl` — Parser comparison
- `test_parsers.pl` — Parser tests
- `test_pacing.pl` — Pacing tests
- `test_precomputed.pl` — Precomputed diff tests
- `test_vim_correctness.pl` — Vim correctness (sync mode)
- `test_vim_engine.pl` — Vim engine tests
- `test_vim_roundtrip.pl` — Vim round-trip tests

## Scripts

- `generate_minimal_tests.sh` — Generate the 25 minimal test cases.
  Usage: `bash tests/generate_minimal_tests.sh`

- `run_minimal_tests.sh` — Run all minimal test cases through the C
  pipeline and report PASS/FAIL with stage details.
  Usage: `bash tests/run_minimal_tests.sh [case_name]`

## Quick start

```bash
# Generate minimal test cases (creates tests/minimal/*/old and new):
bash tests/generate_minimal_tests.sh

# Run all minimal tests:
bash tests/run_minimal_tests.sh

# Run one minimal test:
bash tests/run_minimal_tests.sh 11_delete_last_line

# Debug one case with the full pipeline debugger:
bash scripts/dv_debug.sh tests/minimal/11_delete_last_line/old \
                          tests/minimal/11_delete_last_line/new
```

## Related

- `../animator/tests/` — Current animator test suites (117 tests)
- `../tests/verify_md5.sh` — Full pipeline verification (42 examples)
- `../tests/test_vimscript_animator.sh` — Vimscript animator tests
- `../docs/DEBUGGING.md` — Debugging guide
