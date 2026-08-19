# animator/tests/

Test suites for the animator pipeline. All tests are in Perl.

## Test suites

| Test | Description | # tests |
|------|-------------|---------|
| `test_all_animators.pl` | Tests C and Perl animators on 15 cases | 30 |
| `test_cross_language.pl` | Verifies C == Perl for postprocess + pace | 14 |
| `test_newline_fix.pl` | Tests \n delete/insert handling | 6 |
| `test_roundtrip.pl` | Round-trip: old → pipeline → should equal new | 15 |
| `test_roundtrip_verify.pl` | Extended round-trip with more cases | 30 |
| `test_snapshot_each_op.pl` | Per-op snapshot verification | 14 |
| `test_ghost_line.pl` | Ghost-line fix tests | 8 |
| `test_delete_pacing_modes.pl` | Delete pacing mode tests | — |
| `test_streaming.pl` | Streaming mode tests | — |
| `test_property.pl` | Property-based tests | — |
| `test_perl_animator.pl` | Perl animator specific tests | — |
| `test_colormap.pl` | Colormap tests | — |
| `test_perf.pl` | Performance tests | — |

Total: **117 tests** (excluding the open-ended ones).

## Running tests

```bash
# All unit tests:
for t in test_all_animators test_cross_language test_newline_fix \
         test_roundtrip test_roundtrip_verify test_snapshot_each_op \
         test_ghost_line; do
    perl animator/tests/$t.pl
done

# One test:
perl animator/tests/test_ghost_line.pl
```

## test_snapshot_each_op.pl

This test is special — it injects a `snapshot` op after every
keep/delete/insert op, then walks the snapshots and verifies each
intermediate buffer state against a reference animator (a pure-Perl
re-implementation of the animator's logic).

This catches bugs that produce a correct final buffer but wrong
intermediate states (which is what visual flashing looks like).

## Related

- `../../tests/minimal/` — Minimal test cases (25 cases)
- `../../scripts/verify_md5.sh` — Full pipeline verification
- `../../docs/DEBUGGING.md` — Debugging guide
