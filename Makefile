# Makefile for `ad` — animate a diff toolkit.
#
# Builds all binaries into bin/ at the project root.
#
# Targets:
#   make                  Build all binaries
#   make all              Same as above
#   make diff_engine      Build only the diff engine (bin/ad_compute)
#   make layers           Build only the layer binaries (bin/ad_layer_*)
#   make animator         Build only the animator (bin/ad)
#   make install          Install binaries, launcher, manpages, completions
#   make install-bin      Install binaries only
#   make install-man      Install manpages only
#   make install-comp     Install shell completions only
#   make install-docs     Install documentation
#   make docs             Build mdBook documentation (if mdbook installed)
#   make test             Run all test suites
#   make test-layers      Run per-layer tests
#   make test-unit        Run cross-cutting unit tests
#   make test-minimal     Run minimal end-to-end test cases
#   make test-l2r         Run l2r algorithm tests
#   make test-property    Run property-based tests
#   make test-examples    Run all examples through the pipeline
#   make clean            Remove all built binaries
#   make check            Check that all binaries are up to date
#   make help             Show this help

.PHONY: all diff_engine layers animator tools
all: diff_engine layers animator tools

# --- Configuration ---------------------------------------------------------

PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
MANDIR  := $(PREFIX)/share/man/man1
COMPDIR := $(PREFIX)/share/bash-completion/completions
DOCDIR  := $(PREFIX)/share/doc/ad

CC      ?= cc
CXX     ?= c++
CFLAGS  ?= -O2 -Wall -Wextra -Wunused -Werror
CXXFLAGS ?= -O2 -Wall -Wextra -Wunused -Werror -std=c++17

ROOT    := $(CURDIR)

# --- Binaries --------------------------------------------------------------

# Diff engine
COMPUTE_BIN := bin/ad_compute

# Animator (the core engine; binary is called `ad`)
ANIMATOR_BIN := bin/ad

# Layer binaries (one per layer source file)
LAYER_BINS := \
    bin/ad_layer_reorder \
    bin/ad_layer_overwrite \
    bin/ad_layer_indent_last \
    bin/ad_layer_line_delete_in_place \
    bin/ad_layer_split_in_place \
    bin/ad_layer_join_insert_in_place \
    bin/ad_layer_batch_whitespace \
    bin/ad_layer_skip_indent \
    bin/ad_layer_pace \
    bin/ad_layer_highlight \
    bin/ad_layer_line_replace

ALL_BINS := $(COMPUTE_BIN) $(ANIMATOR_BIN) $(LAYER_BINS)

# --- Build rules -----------------------------------------------------------

diff_engine: $(COMPUTE_BIN)
layers: $(LAYER_BINS)
animator: $(ANIMATOR_BIN)

# Ensure bin/ exists for every build rule.
$(ALL_BINS): | bin/

bin/:
	mkdir -p bin
	@# Create symlinks for non-C binaries (pipeline/ and apps/ scripts)
	@ln -sf ../pipeline/ad_postprocess bin/ad_postprocess 2>/dev/null || true
	@ln -sf ../pipeline/ad_pipeline bin/ad_pipeline 2>/dev/null || true
	@ln -sf ../apps/vim/ad_vim bin/ad_vim 2>/dev/null || true

# Diff engine (C++)
$(COMPUTE_BIN): diff_engine/cpp/compute.cpp
	$(CXX) $(CXXFLAGS) -o $@ $<

# Animator (C)
$(ANIMATOR_BIN): animator/c/ad.c layers/c/ad_layer_common.h
	$(CC) $(CFLAGS) -I layers/c -o $@ animator/c/ad.c

# Layer binaries (C). Each depends on its source AND its test file,
# so touching either triggers a rebuild + test re-run via the test target.
LAYER_COMMON := layers/c/ad_layer_common.h

$(LAYER_BINS): $(LAYER_COMMON)

bin/ad_layer_reorder: layers/c/ad_layer_reorder.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_overwrite: layers/c/ad_layer_overwrite.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_indent_last: layers/c/ad_layer_indent_last.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_line_delete_in_place: layers/c/ad_layer_line_delete_in_place.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_split_in_place: layers/c/ad_layer_split_in_place.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_join_insert_in_place: layers/c/ad_layer_join_insert_in_place.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_batch_whitespace: layers/c/ad_layer_batch_whitespace.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_skip_indent: layers/c/ad_layer_skip_indent.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_pace: layers/c/ad_layer_pace.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_highlight: layers/c/ad_layer_highlight.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_line_replace: layers/c/ad_layer_line_replace.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<

# --- Tools (C binaries) -----------------------------------------------

.PHONY: tools
TOOLS_BIN := bin/ad_annotate

tools: $(TOOLS_BIN)

bin/ad_annotate: scripts/ad_annotate.c
	$(CC) $(CFLAGS) -o $@ $<

# --- Installation ---------------------------------------------------------

.PHONY: install install-bin install-man install-comp install-docs reinstall

install: install-bin install-man install-comp
	@echo "Installed to $(PREFIX)"

install-bin: all
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(COMPUTE_BIN) $(DESTDIR)$(BINDIR)/ad_compute
	install -m 755 $(ANIMATOR_BIN) $(DESTDIR)$(BINDIR)/ad
	install -m 755 $(TOOLS_BIN) $(DESTDIR)$(BINDIR)/ad_annotate
	for layer in $(LAYER_BINS); do \
	        install -m 755 $$layer $(DESTDIR)$(BINDIR)/$$(basename $$layer); \
	done
	install -m 755 pipeline/ad_pipeline $(DESTDIR)$(BINDIR)/ad_pipeline
	install -m 755 pipeline/ad_postprocess $(DESTDIR)$(BINDIR)/ad_postprocess
	install -m 755 apps/vim/ad_vim $(DESTDIR)$(BINDIR)/ad_vim
	# Perl fallbacks
	install -m 755 diff_engine/perl/compute.pl $(DESTDIR)$(BINDIR)/ad_compute-perl
	install -m 755 animator/perl/ad.pl $(DESTDIR)$(BINDIR)/ad-perl
	install -m 755 layers/perl/ad_layer_pace.pl $(DESTDIR)$(BINDIR)/ad_layer_pace-perl
	install -m 755 layers/perl/ad_layer_highlight.pl $(DESTDIR)$(BINDIR)/ad_layer_highlight-perl
	install -m 755 layers/perl/ad_layer_indent_last.pl $(DESTDIR)$(BINDIR)/ad_layer_indent_last-perl
	install -m 755 layers/perl/ad_layer_reorder.pl $(DESTDIR)$(BINDIR)/ad_layer_reorder-perl
	install -m 755 layers/perl/ad_layer_overwrite.pl $(DESTDIR)$(BINDIR)/ad_layer_overwrite-perl
	install -m 755 layers/perl/ad_layer_line_delete_in_place.pl $(DESTDIR)$(BINDIR)/ad_layer_line_delete_in_place-perl
	# Helper scripts
	for tool in scripts/*.sh; do \
	        install -m 755 $$tool $(DESTDIR)$(BINDIR)/$$(basename $$tool .sh); \
	done

install-man:
	install -d $(DESTDIR)$(MANDIR)
	for f in man/*.1; do \
	        install -m 644 $$f $(DESTDIR)$(MANDIR)/; \
	done

install-comp:
	install -d $(DESTDIR)$(COMPDIR)
	install -m 644 completion/ad_vim.bash $(DESTDIR)$(COMPDIR)/ad_vim
	install -m 644 completion/ad_vim.fish $(DESTDIR)$(PREFIX)/share/fish/completions/ad_vim.fish
	install -m 644 completion/_ad_vim $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_ad_vim

install-docs:
	install -d $(DESTDIR)$(DOCDIR)
	if [ -d docs/book ]; then \
		cp -r docs/book/* $(DESTDIR)$(DOCDIR)/; \
	else \
		cp -r docs/src/*.md $(DESTDIR)$(DOCDIR)/; \
	fi

# Reinstall: clean, build, install binaries + manpages + completions
reinstall: clean all install-bin install-man install-comp
	@echo "Reinstalled to $(PREFIX)"
	@echo "  binaries:   $(BINDIR)"
	@echo "  manpages:   $(MANDIR)"
	@echo "  completion:  $(COMPDIR)"
	if [ -d docs/book ]; then \
	        cp -r docs/book/* $(DESTDIR)$(DOCDIR)/; \
	else \
	        cp -r docs/src/*.md $(DESTDIR)$(DOCDIR)/; \
	fi

# --- Documentation ---------------------------------------------------------

.PHONY: docs

docs:
	@echo "Building documentation..."
	@if command -v mdbook >/dev/null 2>&1; then \
	        cd docs && mdbook build; \
	else \
	        echo "  mdbook not installed — docs are plain Markdown"; \
	fi

# --- Testing ---------------------------------------------------------------

# Per-layer test files. Each layer bin depends on its test, and each
# test target rebuilds the layer bin if needed.
.PHONY: test test-layers test-unit test-minimal test-l2r test-property \
	test-examples test-indent-last test-pipeline-options \
	test-layers-discovery \
	test-layer-reorder test-layer-overwrite test-layer-indent-last \
	test-layer-line_delete_in_place test-layer-pace test-layer-highlight test-layer-contracts

test: test-layers test-unit test-minimal test-l2r test-property test-property-reversed test-fuzz test-indent-last test-pipeline-options test-layers-discovery test-reversed
	@echo ""
	@echo "=== All tests passed ==="

# Per-layer tests. Each rebuilds the layer bin first, then runs the test.
test-layer-reorder: bin/ad_layer_reorder
	@echo "=== Layer: reorder ==="
	@perl layers/tests/test_reorder.pl 2>&1 | tail -3

test-layer-overwrite: bin/ad_layer_overwrite
	@echo "=== Layer: overwrite ==="
	@perl layers/tests/test_overwrite.pl 2>&1 | tail -3

test-layer-indent_last: bin/ad_layer_indent_last
	@echo "=== Layer: indent_last ==="
	@perl layers/tests/test_indent_last.pl 2>&1 | tail -3

test-layer-line_delete_in_place: bin/ad_layer_line_delete_in_place
	@echo "=== Layer: line_delete_in_place ==="
	@perl layers/tests/test_line_delete_in_place.pl 2>&1 | tail -5

test-layer-line_delete_in_place_per_op: bin/ad_layer_line_delete_in_place bin/ad
	@echo "=== Layer: line_delete_in_place (per-op snapshot test) ==="
	@perl layers/tests/test_line_delete_in_place_per_op.pl 2>&1 | tail -30
	@echo "(Per-op snapshots show EXACTLY where the layer breaks the buffer.)"

test-layer-pace: bin/ad_layer_pace
	@echo "=== Layer: pace ==="
	@perl layers/tests/test_pace.pl 2>&1 | tail -3

test-layer-highlight: bin/ad_layer_highlight
	@echo "=== Layer: highlight ==="
	@perl layers/tests/test_highlight.pl 2>&1 | tail -3

test-layer-skip_indent: bin/ad_layer_skip_indent
	@echo "=== Layer: skip_indent ==="
	@perl layers/tests/test_skip_indent.pl 2>&1 | tail -3

test-layers: test-layer-reorder test-layer-overwrite test-layer-indent_last \
	     test-layer-line_delete_in_place test-layer-skip_indent \
	     test-layer-pace test-layer-highlight test-layer-contracts
	@echo "=== All layer tests passed ==="

# Contract tests for ALL layers — hand-crafted input op streams,
# not snapshot tests. Verifies each layer fires on its documented pattern.
test-layer-contracts:
	@echo "=== Layer contract tests (all 9 layers) ==="
	@set -o pipefail; perl tests/test_layer_contracts.pl 2>&1 | tail -20

# Cross-cutting tests
test-unit:
	@echo "=== Animator unit tests ==="
	@for t in test_all_animators test_cross_language test_newline_fix \
	         test_roundtrip test_roundtrip_verify test_snapshot_each_op \
	         test_perl_animator test_colormap test_streaming \
	         test_delete_pacing_modes test_newline_fix; do \
	        if [ -f tests/$$t.pl ]; then \
	                perl tests/$$t.pl 2>&1 | grep "Results:" || true; \
	        fi; \
	done

test-minimal:
	@echo "=== Minimal test cases ==="
	@bash tests/run_minimal_tests.sh 2>&1 | tail -1

# Reversed-direction tests: run every minimal + example case with file
# order swapped (new -> old). Verifies the pipeline is symmetric.
test-reversed:
	@echo "=== Reversed-direction tests (new -> old) ==="
	@set -o pipefail; bash tests/run_all_tests_reversed.sh 2>&1 | tail -5

test-l2r:
	@echo "=== l2r algorithm tests ==="
	@bash diff_engine/tests/l2r/test_l2r.sh 2>&1 | tail -1

test-property:
	@echo "=== Property-based tests ==="
	@perl tests/test_property.pl 2>&1 | tail -5

# Property test with file order reversed (new -> old).
test-property-reversed:
	@echo "=== Property-based tests (reversed: new -> old) ==="
	@set -o pipefail; perl tests/test_property_reversed.pl 2>&1 | tail -5

test-examples:
	@echo "=== All examples through the pipeline (canonical test corpus) ==="
	@bash tests/run_all_examples.sh 2>&1 | tail -3

test-indent-last:
	@echo "=== Indent-last test (legacy) ==="
	@perl tests/test_indent_last.pl 2>&1 | tail -3

test-pipeline-options:
	@echo "=== Pipeline options end-to-end ==="
	@bash tests/test_pipeline_options.sh 2>&1 | tail -3

test-layers-discovery:
	@echo "=== Layer discovery + plugin contract ==="
	@perl tests/test_layers_discovery.pl 2>&1 | tail -3

test-fuzz:
	@echo "=== Fuzz testing (malformed inputs) ==="
	@perl tests/test_fuzz.pl 2>&1 | tail -3

# --- Representative Examples (docs/EXAMPLES_TO_RUN.md) ----------------------
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

# HEADLESS mode: add --no-display --speed 1000 for non-interactive verification.
EX_FLAGS = $$(if [ "$$HEADLESS" = "1" ]; then echo "--no-display --speed 1000 --snapshot /tmp/$@_out.txt"; fi)

.PHONY: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15 examples

ex1:
	@echo "=== ex1: default pipeline, small Python ==="
	@ex_dir=01_small_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex2:
	@echo "=== ex2: large Python with word-diff ==="
	@ex_dir=02_large_python; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex3:
	@echo "=== ex3: JSON config with word-diff ==="
	@ex_dir=03_json_config; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --word-diff $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --word-diff $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex4:
	@echo "=== ex4: shell script with overwrite layer ==="
	@ex_dir=04_shell_script; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex5:
	@echo "=== ex5: Go code with indent-last ==="
	@ex_dir=05_go_code; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --indent-last $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex6:
	@echo "=== ex6: TypeScript with line_delete_in_place ==="
	@ex_dir=06_typescript; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --line-delete-in-place $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex7:
	@echo "=== ex7: Rust with overwrite + indent-last (combined layers) ==="
	@ex_dir=08_rust_code; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --overwrite --indent-last $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex8:
	@echo "=== ex8: C code with line_replace (collapse whole lines) ==="
	@ex_dir=09_c_code; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_replace $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex9:
	@echo "=== ex9: Java with word delete-pacing ==="
	@ex_dir=13_java; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing word $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing word $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex10:
	@echo "=== ex10: Kotlin with char delete-pacing (contrast with ex9) ==="
	@ex_dir=14_kotlin; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing char $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing char $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex11:
	@echo "=== ex11: Ruby with flash delete-pacing (highlight-then-delete) ==="
	@ex_dir=16_ruby; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --delete-pacing flash --flash-pause-ms 400 --flash-highlight-ms 300 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex12:
	@echo "=== ex12: Swift with gaussian pacing (natural jitter) ==="
	@ex_dir=15_swift; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --pacing gaussian --gaussian-jitter-pct 20 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex13:
	@echo "=== ex13: Perl with cursor-glide (smooth cursor between hunks) ==="
	@ex_dir=23_perl; \
	old=$$(ls tests/examples/$$ex_dir/old.* | head -1); \
	new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \
	echo "  $(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) $$old $$new"; \
	$(EX_VIM) --cursor-glide-ms 200 --cursor-glide-show-intermediate 1 $(EX_FLAGS) "$$old" "$$new"; \
	[ -z "$$HEADLESS" ] || $(EX_CHECK)

ex14:
	@echo "=== ex14: Haskell with distance-speed (adaptive long jumps) ==="
	@ex_dir=21_haskell; \
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

examples: ex1 ex2 ex3 ex4 ex5 ex6 ex7 ex8 ex9 ex10 ex11 ex12 ex13 ex14 ex15
	@if [ "$$HEADLESS" = "1" ]; then echo "=== All 15 examples passed (headless) ==="; \
	else echo "=== All 15 examples animated in vim ==="; fi


# --- Debugging -------------------------------------------------------------

.PHONY: debug snapshot

debug:
	@echo "=== Pipeline debugger on example 01 ==="
	@bash scripts/ad_debug.sh tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1 | tail -20

snapshot:
	@echo "=== Per-op snapshots for example 01 ==="
	@bash scripts/ad_snapshot.sh tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1
	@echo "Open: file:///tmp/ad_snapshots/snapshots.html"

# --- Clean -----------------------------------------------------------------

.PHONY: clean distclean

clean:
	rm -rf bin
	@echo "All binaries removed"

distclean: clean
	rm -rf docs/book
	rm -rf /tmp/ad_debug /tmp/ad_snapshots /tmp/ad_md5_verify

# --- Check -----------------------------------------------------------------

check:
	@echo "Checking binary freshness..."
	@needs_build=0; \
	for src_bin in \
	        "diff_engine/cpp/compute.cpp:$(COMPUTE_BIN)" \
	        "animator/c/ad.c:$(ANIMATOR_BIN)" \
	        "layers/c/ad_layer_reorder.c:bin/ad_layer_reorder" \
	        "layers/c/ad_layer_overwrite.c:bin/ad_layer_overwrite" \
	        "layers/c/ad_layer_indent_last.c:bin/ad_layer_indent_last" \
	        "layers/c/ad_layer_line_delete_in_place.c:bin/ad_layer_line_delete_in_place" \
                "layers/c/ad_layer_split_in_place.c:bin/ad_layer_split_in_place" \
	        "layers/c/ad_layer_pace.c:bin/ad_layer_pace" \
	        "layers/c/ad_layer_highlight.c:bin/ad_layer_highlight"; do \
	        src=$${src_bin%%:*}; \
	        bin=$${src_bin##*:}; \
	        if [ ! -f "$$bin" ] || [ "$$src" -nt "$$bin" ]; then \
	                echo "  STALE: $$bin (newer source: $$src)"; \
	                needs_build=1; \
	        fi; \
	done; \
	if [ $$needs_build -eq 1 ]; then \
	        echo ""; \
	        echo "Run 'make' to rebuild."; \
	        exit 1; \
	else \
	        echo "  All binaries up to date."; \
	fi

# --- Help ------------------------------------------------------------------

help:
	@echo "ad build system"
	@echo ""
	@echo "Targets:"
	@echo "  make                Build all binaries into bin/"
	@echo "  make diff_engine    Build only the diff engine (bin/ad_compute)"
	@echo "  make layers         Build only the layer binaries (bin/ad_layer_*)"
	@echo "  make animator       Build only the animator (bin/ad)"
	@echo "  make tools          Build only the tools (bin/ad_annotate)"
	@echo "  make install        Install everything to $$(PREFIX)"
	@echo "  make install-bin    Install binaries only"
	@echo "  make install-man    Install manpages only"
	@echo "  make install-comp   Install shell completions only"
	@echo "  make reinstall     Clean, rebuild, install everything"
	@echo "  make docs           Build mdBook documentation"
	@echo "  make test           Run all tests"
	@echo "  make test-layers    Run per-layer tests (TDD)"
	@echo "  make test-property  Run property-based tests"
	@echo "  make test-examples  Run all examples through pipeline"
	@echo "  make test-fuzz      Run fuzz tests"
	@echo "  make ex1..ex15      Animate example N in vim (see docs/EXAMPLES_TO_RUN.md)"
	@echo "  make examples       Animate all 15 examples in vim"
	@echo "  make examples HEADLESS=1  Verify all 15 examples headless"
	@echo "  make clean          Remove bin/ directory"
	@echo "  make check          Check if binaries are up to date"
	@echo "  make help           Show this help"
	@echo ""
	@echo "See INSTALL.md for full documentation."
