# Testing

## Test Suites

### Parser Tests (`tests/test_parsers.pl`)

Tests the Perl parser with 9 test cases.

```bash
perl tests/test_parsers.pl
```

Test cases:
- Simple modification
- Multi-hunk Python diff
- Pure insertion at start
- Pure deletion at end
- Identical files
- Empty old file
- Insertion at end
- Mid-line insertion
- Delete middle lines

### Feature Tests (`tests/test_features.pl`)

Tests all CLI options and features (52 assertions).

```bash
perl tests/test_features.pl
```

### Integration Tests (`tests/test_integration.pl`)

Runs the full animation pipeline on example files and verifies the
buffer matches the expected output.

```bash
perl tests/test_integration.pl
```

## Running All Tests

```bash
# Run all tests
perl tests/test_parsers.pl && \
perl tests/test_features.pl && \
perl tests/test_integration.pl
```

## Test Coverage

- **Parser tests**: 9 assertions (diff correctness)
- **Feature tests**: 52 assertions (CLI options, help, man page)
- **Integration tests**: 7 assertions (full pipeline on example files)

## Manual Testing

```bash
# Quick test with example files
./diffvim tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py

# Test with --dry-run
perl diffvim.pl --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py

# Test --version
perl diffvim.pl --version
```

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
