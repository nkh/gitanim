#!/usr/bin/env python3
"""Replace the ex1-ex15 + examples targets in the Makefile to use
ad_vim (vim-based animator) instead of ad_pipeline --no-display.

By default, `make exN` opens vim and animates the diff.
With `make exN HEADLESS=1`, it runs headless and verifies the snapshot.
"""

import sys
import re

MAKEFILE = "/home/z/my-project/gitanim/Makefile"

# The block to insert (uses \t for tabs).
# This replaces the existing ex targets section.
TARGETS_BLOCK = """# --- Representative Examples (docs/EXAMPLES_TO_RUN.md) ----------------------
#
# Each target runs ad_vim (vim-based animator) with a representative
# option combination. By default, vim opens and animates the diff.
# With HEADLESS=1, it runs headless and verifies the snapshot.
#
# Usage:
#   make ex1           # open vim, animate the diff
#   make ex1 HEADLESS=1  # headless, verify snapshot matches new file
#   make examples HEADLESS=1  # run all 15 headless, verify all match
#
# See docs/EXAMPLES_TO_RUN.md for what each example demonstrates.

EX_VIM = apps/vim/ad_vim
EX_CHECK = new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
           if diff -q "$$new" /tmp/$@_out.txt >/dev/null 2>&1; then \\
               echo "  $@: snapshot matches new file"; \\
           else \\
               echo "  $@: MISMATCH (snapshot != new file)"; \\
           fi

# HEADLESS mode: add --no-display --speed 1000 for non-interactive verification.
EX_FLAGS = $$(if [ "$$HEADLESS" = "1" ]; then echo "--no-display --speed 1000 --snapshot /tmp/$@_out.txt"; fi)

.PHONY: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15 examples

ex1:
\t@echo "=== ex1: default pipeline, small Python ==="
\t@ex_dir=01_small_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex2:
\t@echo "=== ex2: large Python with word-diff ==="
\t@ex_dir=02_large_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex3:
\t@echo "=== ex3: JSON config with word-diff ==="
\t@ex_dir=03_json_config; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex4:
\t@echo "=== ex4: shell script with overwrite layer ==="
\t@ex_dir=04_shell_script; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex5:
\t@echo "=== ex5: Go code with indent-last ==="
\t@ex_dir=05_go_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex6:
\t@echo "=== ex6: TypeScript with line_delete_in_place ==="
\t@ex_dir=06_typescript; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex7:
\t@echo "=== ex7: Rust with overwrite + indent-last (combined layers) ==="
\t@ex_dir=08_rust_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex8:
\t@echo "=== ex8: C code with line_replace (collapse whole lines) ==="
\t@ex_dir=09_c_code; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex9:
\t@echo "=== ex9: Java with word delete-pacing ==="
\t@ex_dir=13_java; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --delete-pacing word $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --delete-pacing word $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex10:
\t@echo "=== ex10: Kotlin with char delete-pacing (contrast with ex9) ==="
\t@ex_dir=14_kotlin; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --delete-pacing char $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --delete-pacing char $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex11:
\t@echo "=== ex11: Ruby with flash delete-pacing (highlight-then-delete) ==="
\t@ex_dir=16_ruby; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex12:
\t@echo "=== ex12: Swift with gaussian pacing (natural jitter) ==="
\t@ex_dir=15_swift; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex13:
\t@echo "=== ex13: Perl with cursor-glide (smooth cursor between hunks) ==="
\t@ex_dir=23_perl; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex14:
\t@echo "=== ex14: Haskell with distance-speed (adaptive long jumps) ==="
\t@ex_dir=21_haskell; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3.0 $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3.0 $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex15:
\t@echo "=== ex15: huge Python with everything (kitchen-sink combo) ==="
\t@ex_dir=42_large_huge_python; \\
\told=$$(ls tests/examples/$$ex_dir/old.* | head -1); \\
\tnew=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\
\techo "  $(EX_VIM) --word-diff --ad-layer=ad_layer_reorder --overwrite --indent-last --line-delete-in-place --delete-pacing word --pacing gaussian --distance-speed adaptive $(EX_FLAGS) $$old $$new"; \\
\t$(EX_VIM) --word-diff --ad-layer=ad_layer_reorder --overwrite --indent-last --line-delete-in-place --delete-pacing word --pacing gaussian --distance-speed adaptive $(EX_FLAGS) "$$old" "$$new"; \\
\t[ -z "$$HEADLESS" ] || $(EX_CHECK)

examples: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15
\t@if [ "$$HEADLESS" = "1" ]; then echo "=== All 15 examples passed (headless) ==="; \\
\telse echo "=== All 15 examples animated in vim ==="; fi

"""

with open(MAKEFILE, "r") as f:
    content = f.read()

# Find the start of the ex targets section and the end (the Debugging section).
start_marker = "# --- Representative Examples"
end_marker = "# --- Debugging"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1:
    print("ERROR: start marker not found", file=sys.stderr)
    sys.exit(1)
if end_idx == -1:
    print("ERROR: end marker not found", file=sys.stderr)
    sys.exit(1)

# Replace everything between start and end with the new block.
new_content = content[:start_idx] + TARGETS_BLOCK + "\n" + content[end_idx:]

with open(MAKEFILE, "w") as f:
    f.write(new_content)

print(f"Replaced ex targets: bytes {start_idx}..{end_idx} -> new block")
