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

.PHONY: all diff_engine layers animator
all: diff_engine layers animator

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
    bin/ad_layer_skip_indent \
    bin/ad_layer_pace \
    bin/ad_layer_highlight

ALL_BINS := $(COMPUTE_BIN) $(ANIMATOR_BIN) $(LAYER_BINS)

# --- Build rules -----------------------------------------------------------

diff_engine: $(COMPUTE_BIN)
layers: $(LAYER_BINS)
animator: $(ANIMATOR_BIN)

# Ensure bin/ exists for every build rule.
$(ALL_BINS): | bin/

bin/:
	mkdir -p bin

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
bin/ad_layer_skip_indent: layers/c/ad_layer_skip_indent.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_pace: layers/c/ad_layer_pace.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<
bin/ad_layer_highlight: layers/c/ad_layer_highlight.c
	$(CC) $(CFLAGS) -I layers/c -o $@ $<

# --- Installation ---------------------------------------------------------

.PHONY: install install-bin install-man install-comp install-docs

install: install-bin install-man install-comp
	@echo "Installed to $(PREFIX)"

install-bin: all
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(COMPUTE_BIN) $(DESTDIR)$(BINDIR)/ad_compute
	install -m 755 $(ANIMATOR_BIN) $(DESTDIR)$(BINDIR)/ad
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
	test-layer-line_delete_in_place test-layer-pace test-layer-highlight

test: test-layers test-unit test-minimal test-l2r test-property test-fuzz test-indent-last test-pipeline-options test-layers-discovery
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
	     test-layer-pace test-layer-highlight
	@echo "=== All layer tests passed ==="

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

test-l2r:
	@echo "=== l2r algorithm tests ==="
	@bash diff_engine/tests/l2r/test_l2r.sh 2>&1 | tail -1

test-property:
	@echo "=== Property-based tests ==="
	@perl tests/test_property.pl 2>&1 | tail -5

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
	@echo "  make diff_engine   Build only the diff engine"
	@echo "  make layers         Build only the layer binaries"
	@echo "  make animator       Build only the animator (bin/ad)"
	@echo "  make install        Install everything to $$(PREFIX)"
	@echo "  make install-bin    Install binaries only"
	@echo "  make install-man    Install manpages only"
	@echo "  make install-comp   Install shell completions only"
	@echo "  make docs           Build mdBook documentation"
	@echo "  make test           Run all tests"
	@echo "  make test-layers    Run per-layer tests (TDD)"
	@echo "  make test-property  Run property-based tests"
	@echo "  make test-examples  Run all examples through pipeline"
	@echo "  make clean          Remove bin/ directory"
	@echo "  make check          Check if binaries are up to date"
	@echo "  make help           Show this help"
