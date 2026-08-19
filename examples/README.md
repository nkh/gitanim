# examples/

42 old/new file pairs for testing the diffvim pipeline. Each pair is
in a subdirectory named `NN_description/`.

## Usage

```bash
# Animate a specific example:
./diffvim examples/01_small_python/old.py examples/01_small_python/new.py

# Run the C pipeline:
./animator/diffvim-pipeline examples/01_small_python/old.py examples/01_small_python/new.py

# Debug a specific example:
bash scripts/dv_debug.sh examples/01_small_python/old.py examples/01_small_python/new.py

# Run all 42 examples through the pipeline:
bash scripts/verify_md5.sh

# Test the vimscript animator on all examples:
bash scripts/test_vimscript_animator.sh
```

## Categories

### Small examples (1-31)
Single-language, small file size. Good for quick testing.

- `01_small_python` — 3 lines → 0 lines (pure deletion)
- `02_large_python` — Python class refactor
- `03_json_config` — JSON config change
- ...
- `31_javascript` — JavaScript change

### Large examples (32-42)
Larger files (100+ lines). Good for stress testing.

- `32_python_classes` — Python classes
- `33_large_python` — Large Python file
- ...
- `42_large_huge_python` — Very large Python file

## File naming

Each example directory contains:
- `old.<ext>` — the old version of the file
- `new.<ext>` — the new version

The extension matches the language (`.py`, `.js`, `.rs`, etc.).

## Related

- `../tests/minimal/` — Minimal test cases (25 cases, each testing one
  specific transformation)
- `../scripts/verify_md5.sh` — Runs all 42 examples through both C and
  Perl pipelines, compares output MD5
- `../scripts/test_vimscript_animator.sh` — Tests vimscript animator on
  all examples
