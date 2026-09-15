#!/usr/bin/env python3
"""Apply reversed-direction test targets to the Makefile using real tabs.

The Makefile uses tab characters for indentation (as make requires).
The Read tool displays tabs as 8 spaces, which can be misleading when
constructing string matches. This script uses real tabs.
"""
from pathlib import Path

MAKEFILE = Path("/home/z/my-project/gitanim/Makefile")
text = MAKEFILE.read_text()

T = "\t"  # real tab character

# --- Edit 1: extend .PHONY list and `test` deps, add `test-reversed` recipe ---
old1 = (
    ".PHONY: test test-layers test-unit test-minimal test-l2r test-property \\\n"
    f"{T}test-examples test-indent-last test-pipeline-options \\\n"
    f"{T}test-layers-discovery \\\n"
    f"{T}test-layer-reorder test-layer-overwrite test-layer-indent-last \\\n"
    f"{T}test-layer-line_delete_in_place test-layer-pace test-layer-highlight\n"
    "\n"
    "test: test-layers test-unit test-minimal test-l2r test-property test-fuzz "
    "test-indent-last test-pipeline-options test-layers-discovery\n"
    f'{T}@echo ""\n'
    f'{T}@echo "=== All tests passed ==="'
)

new1 = (
    ".PHONY: test test-layers test-unit test-minimal test-l2r test-property \\\n"
    f"{T}test-property-reversed test-reversed \\\n"
    f"{T}test-examples test-indent-last test-pipeline-options \\\n"
    f"{T}test-layers-discovery \\\n"
    f"{T}test-layer-reorder test-layer-overwrite test-layer-indent-last \\\n"
    f"{T}test-layer-line_delete_in_place test-layer-pace test-layer-highlight\n"
    "\n"
    "test: test-layers test-unit test-minimal test-l2r test-property "
    "test-property-reversed test-fuzz test-indent-last test-pipeline-options "
    "test-layers-discovery test-reversed\n"
    f'{T}@echo ""\n'
    f'{T}@echo "=== All tests passed ==="\n'
    "\n"
    "# Reversed-direction tests: run every minimal + example case with file\n"
    "# order swapped (new -> old). Verifies the pipeline is symmetric.\n"
    "test-reversed:\n"
    f'{T}@echo "=== Reversed-direction tests (new -> old) ==="\n'
    f"{T}@bash tests/run_all_tests_reversed.sh 2>&1 | tail -3"
)

assert old1 in text, "old1 not found"
text = text.replace(old1, new1)

# --- Edit 2: add test-property-reversed after test-property recipe ---
old2 = (
    "test-property:\n"
    f'{T}@echo "=== Property-based tests ==="\n'
    f"{T}@perl tests/test_property.pl 2>&1 | tail -5"
)

new2 = old2 + (
    "\n\n"
    "# Property test with file order reversed (new -> old). Verifies the\n"
    "# pipeline produces `old` when started from `new` on random inputs.\n"
    "test-property-reversed:\n"
    f'{T}@echo "=== Property-based tests (reversed: new -> old) ==="\n'
    f"{T}@perl tests/test_property_reversed.pl 2>&1 | tail -5"
)

assert old2 in text, "old2 not found"
text = text.replace(old2, new2)

# --- Edit 3: extend `help` target with new entries ---
old3 = (
    f'{T}@echo "  make test           Run all tests"\n'
    f'{T}@echo "  make test-layers    Run per-layer tests (TDD)"\n'
    f'{T}@echo "  make test-property  Run property-based tests"\n'
    f'{T}@echo "  make test-examples  Run all examples through pipeline"'
)

new3 = (
    f'{T}@echo "  make test           Run all tests"\n'
    f'{T}@echo "  make test-layers    Run per-layer tests (TDD)"\n'
    f'{T}@echo "  make test-property  Run property-based tests"\n'
    f'{T}@echo "  make test-property-reversed  Run property tests (new -> old)"\n'
    f'{T}@echo "  make test-reversed   Run all corpus tests (new -> old)"\n'
    f'{T}@echo "  make test-examples  Run all examples through pipeline"'
)

assert old3 in text, "old3 not found"
text = text.replace(old3, new3)

MAKEFILE.write_text(text)
print("Makefile updated successfully with real tabs.")
