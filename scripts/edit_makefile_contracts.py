#!/usr/bin/env python3
"""Add test-layer-contracts target to the Makefile using real tabs."""
from pathlib import Path

MAKEFILE = Path("/home/z/my-project/gitanim/Makefile")
text = MAKEFILE.read_text()

T = "\t"

# Add test-layer-contracts to the .PHONY list and as a new target.
# Also wire it into the main `test` target and the test-layers aggregate.

# 1. Add to .PHONY
old_phony = ("test-layer-reorder test-layer-overwrite test-layer-indent-last "
             "test-layer-line_delete_in_place test-layer-pace test-layer-highlight")
new_phony = ("test-layer-reorder test-layer-overwrite test-layer-indent-last "
             "test-layer-line_delete_in_place test-layer-pace test-layer-highlight "
             "test-layer-contracts")
assert old_phony in text, "old_phony not found"
text = text.replace(old_phony, new_phony)

# 2. Add test-layer-contracts to the test-layers aggregate target.
old_aggregate = ("test-layers: test-layer-reorder test-layer-overwrite test-layer-indent_last \\\n"
                 f"{T}             test-layer-line_delete_in_place test-layer-skip_indent \\\n"
                 f"{T}             test-layer-pace test-layer-highlight\n"
                 f"{T}@echo \"=== All layer tests passed ===\"")
new_aggregate = ("test-layers: test-layer-reorder test-layer-overwrite test-layer-indent_last \\\n"
                 f"{T}             test-layer-line_delete_in_place test-layer-skip_indent \\\n"
                 f"{T}             test-layer-pace test-layer-highlight test-layer-contracts\n"
                 f"{T}@echo \"=== All layer tests passed ===\"")
assert old_aggregate in text, "old_aggregate not found"
text = text.replace(old_aggregate, new_aggregate)

# 3. Add the test-layer-contracts target after test-layer-highlight.
old_highlight = ("test-layer-highlight: bin/ad_layer_highlight\n"
                 f"{T}@echo \"=== Layer: highlight ===\"\n"
                 f"{T}@perl layers/tests/test_highlight.pl 2>&1 | tail -3")
new_highlight = old_highlight + (

    "\n\n# Contract tests for ALL layers — hand-crafted input op streams,\n"
    "# not snapshot tests. Verifies each layer fires on its documented pattern.\n"
    "test-layer-contracts:\n"
    f"{T}@echo \"=== Layer contract tests (all 9 layers) ===\"\n"
    f"{T}@perl tests/test_layer_contracts.pl 2>&1 | tail -5"
)
assert old_highlight in text, "old_highlight not found"
text = text.replace(old_highlight, new_highlight)

MAKEFILE.write_text(text)
print("Makefile updated with test-layer-contracts target.")
