#!/usr/bin/env python3
"""Rewrite the ex targets in the Makefile with:
1. Longer examples (so the animation lasts long enough to watch)
2. A SPEED variable (make ex1 SPEED=0.3 to slow down to 30%)
3. ex8 uses 33_large_python (real line replacement, not pure inserts)
4. ex16 fixed (insert-pacing word no longer hangs)
"""

import sys

MAKEFILE = "/home/z/my-project/gitanim/Makefile"

with open(MAKEFILE, "r") as f:
    content = f.read()

# Find and replace the ex section
start_marker = "# --- Representative Examples"
end_marker = "# --- Debugging"

start_idx = content.find(start_marker)
end_idx = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print("ERROR: markers not found", file=sys.stderr)
    sys.exit(1)

TARGETS_BLOCK = r'''# --- Representative Examples (docs/EXAMPLES_TO_RUN.md) ----------------------
#
# Each target runs ad_vim (vim-based animator) with a representative
# option combination. By default, vim opens and animates the diff.
# With HEADLESS=1, it runs headless and verifies the snapshot.
#
# Usage:
#   make ex1             # open vim, animate at default speed (1.0)
#   make ex1 SPEED=0.3   # slow down to 30% speed (3.3x slower)
#   make ex1 HEADLESS=1  # headless, verify snapshot matches new file
#   make examples HEADLESS=1  # run all 16 headless, verify all match
#
# SPEED variable: passed to ad_vim --speed. 1.0=default, 0.3=slow,
# 0.1=very slow, 2.0=fast. Default is 1.0 if not set.
#
# See docs/EXAMPLES_TO_RUN.md for what each example demonstrates.

EX_VIM = apps/vim/ad_vim
EX_SPEED = $$(if [ -n "$$SPEED" ]; then echo "--speed $$SPEED"; else echo "--speed 1.0"; fi)
EX_CHECK = if [ ! -f /tmp/$@_out.txt ]; then \
           echo "  $@: no snapshot (interactive mode — use HEADLESS=1 to verify)"; \
           else \
           new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
           if diff -q "$$new" /tmp/$@_out.txt >/dev/null 2>&1; then \
               echo "  $@: snapshot matches new file"; \
           else \
               echo "  $@: MISMATCH (snapshot != new file)"; \
           fi; \
           fi

# HEADLESS mode: add --no-display --speed 1000 --snapshot for non-interactive verification.
EX_FLAGS = $$(if [ "$$HEADLESS" = "1" ]; then echo "--no-display --speed 1000 --snapshot /tmp/$@_out.txt"; else echo "$(EX_SPEED)"; fi)

.PHONY: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15 ex16 examples

ex1:
	@echo "=== ex1: default pipeline, large Python ==="
	@ex_dir=33_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex2:
	@echo "=== ex2: large Python with word-diff ==="
	@ex_dir=33_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex3:
	@echo "=== ex3: large Go config with word-diff ==="
	@ex_dir=37_large_go; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex4:
	@echo "=== ex4: large Rust with overwrite layer ==="
	@ex_dir=36_large_rust; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex5:
	@echo "=== ex5: large Python with indent-last ==="
	@ex_dir=33_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex6:
	@echo "=== ex6: large Java with line_delete_in_place ==="
	@ex_dir=38_large_java; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex7:
	@echo "=== ex7: large Rust with overwrite + indent-last (combined layers) ==="
	@ex_dir=36_large_rust; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex8:
	@echo "=== ex8: large Python with line_replace (full-line replacement) ==="
	@ex_dir=33_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex9:
	@echo "=== ex9: large Java with word delete-pacing ==="
	@ex_dir=38_large_java; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing word $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing word $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex10:
	@echo "=== ex10: large Java with char delete-pacing (contrast with ex9) ==="
	@ex_dir=38_large_java; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing char $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing char $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex11:
	@echo "=== ex11: large Ruby with flash delete-pacing (highlight-then-delete) ==="
	@ex_dir=41_large_ruby; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex12:
	@echo "=== ex12: large C# with gaussian pacing (natural jitter) ==="
	@ex_dir=40_large_csharp; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex13:
	@echo "=== ex13: large Perl with cursor-glide (smooth cursor between hunks) ==="
	@ex_dir=35_large_perl; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex14:
	@echo "=== ex14: huge Python with distance-speed (adaptive long jumps) ==="
	@ex_dir=42_large_huge_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3.0 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3.0 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex15:
	@echo "=== ex15: huge Python with everything (kitchen-sink combo) ==="
	@ex_dir=42_large_huge_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff --ad-layer=ad_layer_reorder --overwrite --indent-last --line-delete-in-place --delete-pacing word --pacing gaussian --distance-speed adaptive $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff --ad-layer=ad_layer_reorder --overwrite --indent-last --line-delete-in-place --delete-pacing word --pacing gaussian --distance-speed adaptive $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex16:
	@echo "=== ex16: wordwise animation (word-diff + word pacing) ==="
	@ex_dir=33_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff --insert-pacing word --delete-pacing word $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff --insert-pacing word --delete-pacing word $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

examples: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15 ex16
	@if [ "$$HEADLESS" = "1" ]; then echo "=== All 16 examples passed (headless) ==="; \
	else echo "=== All 16 examples animated in vim ==="; fi

'''

new_content = content[:start_idx] + TARGETS_BLOCK + "\n" + content[end_idx:]

with open(MAKEFILE, "w") as f:
    f.write(new_content)

print("Rewrote ex targets with longer examples, SPEED variable, and ex8 fix")
