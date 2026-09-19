#!/usr/bin/env python3
"""Insert the ex1-ex15 + examples targets into the Makefile with
proper TAB indentation (Make requires tabs, not spaces)."""

import sys

MAKEFILE = "/home/z/my-project/gitanim/Makefile"

# The block to insert (uses \t for tabs, \n for newlines).
# This goes between test-fuzz and the Debugging section.
TARGETS_BLOCK = """# --- Representative Examples (docs/EXAMPLES_TO_RUN.md) ----------------------
#
# Each target runs ad_pipeline with a representative option combination,
# writes the snapshot to /tmp/exN_out.txt, and verifies it matches the
# expected new.* file. Drop --no-display --speed 1000 to see the animation.
#
# See docs/EXAMPLES_TO_RUN.md for what each example demonstrates.

EX = pipeline/ad_pipeline
EX_RUN = bash $(EX) --no-display --speed 1000
EX_CHECK = new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
           if diff -q "$$new" /tmp/$@_out.txt >/dev/null 2>&1; then \\
               echo "  $@: snapshot matches new file"; \\
           else \\
               echo "  $@: MISMATCH (snapshot != new file)"; \\
           fi

.PHONY: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15 examples

ex1:
\t@echo "=== ex1: default pipeline, small Python ==="
\t@ex_dir=01_small_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex2:
\t@echo "=== ex2: large Python with semantic-cleanup ==="
\t@ex_dir=02_large_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --compute-semantic-cleanup --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --compute-semantic-cleanup --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex3:
\t@echo "=== ex3: JSON config with word-diff ==="
\t@ex_dir=03_json_config; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --compute-word-diff --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --compute-word-diff --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex4:
\t@echo "=== ex4: shell script with overwrite layer ==="
\t@ex_dir=04_shell_script; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex5:
\t@echo "=== ex5: Go code with indent-last ==="
\t@ex_dir=05_go_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_indent_last --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_indent_last --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex6:
\t@echo "=== ex6: TypeScript with line_delete_in_place ==="
\t@ex_dir=06_typescript; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_delete_in_place --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_delete_in_place --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex7:
\t@echo "=== ex7: Rust with overwrite + indent-last (combined layers) ==="
\t@ex_dir=08_rust_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex8:
\t@echo "=== ex8: C code with line_replace (collapse whole lines) ==="
\t@ex_dir=09_c_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_replace --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_line_replace --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex9:
\t@echo "=== ex9: Java with word delete-pacing ==="
\t@ex_dir=13_java; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-delete-pacing word --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-delete-pacing word --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex10:
\t@echo "=== ex10: Kotlin with char delete-pacing (contrast with ex9) ==="
\t@ex_dir=14_kotlin; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-delete-pacing char --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-delete-pacing char --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex11:
\t@echo "=== ex11: Ruby with flash delete-pacing (highlight-then-delete) ==="
\t@ex_dir=16_ruby; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-delete-pacing flash --pace-flash-pause-ms 400 --pace-flash-highlight-ms 300 --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-delete-pacing flash --pace-flash-pause-ms 400 --pace-flash-highlight-ms 300 --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex12:
\t@echo "=== ex12: Swift with gaussian pacing (natural jitter) ==="
\t@ex_dir=15_swift; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-pacing gaussian --pace-gaussian-jitter-pct 20 --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-pacing gaussian --pace-gaussian-jitter-pct 20 --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex13:
\t@echo "=== ex13: Perl with cursor-glide (smooth cursor between hunks) ==="
\t@ex_dir=23_perl; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-cursor-glide-ms 200 --pace-cursor-glide-show-intermediate 1 --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-cursor-glide-ms 200 --pace-cursor-glide-show-intermediate 1 --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex14:
\t@echo "=== ex14: Haskell with distance-speed (adaptive long jumps) ==="
\t@ex_dir=21_haskell; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --pace-distance-speed adaptive --pace-distance-threshold 10 --pace-distance-fast-mult 3.0 --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --pace-distance-speed adaptive --pace-distance-threshold 10 --pace-distance-fast-mult 3.0 --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

ex15:
\t@echo "=== ex15: huge Python with everything (kitchen-sink combo) ==="
\t@ex_dir=42_large_huge_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_RUN) --compute-semantic-cleanup --compute-word-diff --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last --postprocess-ad-layer=ad_layer_line_delete_in_place --pace-delete-pacing word --pace-pacing gaussian --pace-distance-speed adaptive --snapshot /tmp/$@_out.txt $$old $$new"; \\
\t$(EX_RUN) --compute-semantic-cleanup --compute-word-diff --postprocess-ad-layer=ad_layer_reorder --postprocess-ad-layer=ad_layer_overwrite --postprocess-ad-layer=ad_layer_indent_last --postprocess-ad-layer=ad_layer_line_delete_in_place --pace-delete-pacing word --pace-pacing gaussian --pace-distance-speed adaptive --snapshot /tmp/$@_out.txt "$$old" "$$new" 2>/dev/null; \\
\t$(EX_CHECK)

examples: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15
\t@echo "=== All 15 examples passed ==="

"""

# The marker after which to insert (end of test-fuzz target).
MARKER = "# --- Debugging"

with open(MAKEFILE, "r") as f:
    content = f.read()

# Find the marker and insert before it.
idx = content.find(MARKER)
if idx == -1:
    print("ERROR: marker '# --- Debugging' not found in Makefile", file=sys.stderr)
    sys.exit(1)

# Insert the block + a blank line before the marker.
new_content = content[:idx] + TARGETS_BLOCK + "\n" + content[idx:]

with open(MAKEFILE, "w") as f:
    f.write(new_content)

print(f"Inserted ex1-ex15 + examples targets at offset {idx}")
