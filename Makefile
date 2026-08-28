# Makefile for diffvim — top-level build system.
#
# Targets:
#   make                Build all C/C++ binaries (compute + animator)
#   make all            Same as above
#   make compute        Build only the compute tool (diffvim-compute-cpp)
#   make animator       Build only the animator tools (postprocess, pace, animator-c)
#   make install        Install binaries, launcher, manpages, completions
#   make install-bin     Install binaries only
#   make install-man    Install manpages only
#   make install-comp   Install shell completions only
#   make docs            Build documentation (mdBook if available)
#   make man             Build manpages from source (if manpages need generation)
#   make test            Run all test suites
#   make test-unit       Run animator unit tests (117 tests)
#   make test-minimal    Run minimal test cases (25 tests)
#   make test-pipeline   Run full pipeline verification (42 examples)
#   make test-l2r        Run l2r algorithm tests (35 tests)
#   make test-vimscript  Run vimscript animator tests (42 examples)
#   make test-debug-bundle  Run dv_debug_bundle.sh script tests (12 tests)
#   make debug           Run the pipeline debugger on example 01
#   make snapshot        Run dv_snapshot.sh on example 01
#   make clean           Remove all built binaries
#   make clean-compute   Remove compute binaries only
#   make clean-animator  Remove animator binaries only
#   make distclean       Clean + remove generated docs
#   make check           Check that all binaries are up to date
#   make help            Show this help

# --- Configuration ---------------------------------------------------------

PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
MANDIR  := $(PREFIX)/share/man/man1
COMPDIR := $(PREFIX)/share/bash-completion/completions

CC      ?= cc
CXX     ?= c++
CFLAGS  ?= -O2 -Wall -Wextra -Wunused -Werror
CXXFLAGS ?= -O2 -Wall -Wextra -Wunused -Werror -std=c++17

ROOT    := $(CURDIR)

# --- Binaries --------------------------------------------------------------

COMPUTE_BIN   := compute/bin/diffvim-compute-cpp
PACE_BIN      := animator/bin/diffvim-pace
ANIMATOR_BIN  := animator/bin/diffvim-animator-c
DECORATE_BIN  := animator/bin/diffvim-decorate
ANIMATOR_BINS := $(PACE_BIN) $(ANIMATOR_BIN) $(DECORATE_BIN)

$(COMPUTE_BIN): compute/cpp/diffvim-compute.cpp
	@mkdir -p compute/bin
	$(CXX) $(CXXFLAGS) -o $@ $<

$(PACE_BIN): animator/c/pace.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -o $@ $<

$(ANIMATOR_BIN): animator/c/animator.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -o $@ $<

$(DECORATE_BIN): animator/c/decorate.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -o $@ $<

LAYER_BINS := animator/bin/pp_reorder animator/bin/pp_indent_last animator/bin/pp_overwrite

.PHONY: all compute animator

all: compute animator

compute: $(COMPUTE_BIN)

animator: $(ANIMATOR_BINS) $(LAYER_BINS)



# Standalone layer binaries (for bash orchestrator)
$(LAYER_BINS): animator/c/pp_common.h 

animator/bin/pp_reorder: animator/c/pp_reorder.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -I animator/c -o $@ animator/c/pp_reorder.c

animator/bin/pp_indent_last: animator/c/pp_indent_last.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -I animator/c -o $@ animator/c/pp_indent_last.c

animator/bin/pp_overwrite: animator/c/pp_overwrite.c
	@mkdir -p animator/bin
	$(CC) $(CFLAGS) -I animator/c -o $@ animator/c/pp_overwrite.c


# --- Installation ----------------------------------------------------------

.PHONY: install install-bin install-man install-comp

install: install-bin install-man install-comp
	@echo "Installed to $(PREFIX)"

install-bin: all
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 $(COMPUTE_BIN) $(DESTDIR)$(BINDIR)/diffvim-compute-cpp
	install -m 755 $(POSTPROCESS_BIN) $(DESTDIR)$(BINDIR)/diffvim-postprocess
	install -m 755 $(PACE_BIN) $(DESTDIR)$(BINDIR)/diffvim-pace
	install -m 755 $(ANIMATOR_BIN) $(DESTDIR)$(BINDIR)/diffvim-animator-c
	install -m 755 $(DECORATE_BIN) $(DESTDIR)$(BINDIR)/diffvim-decorate
	install -m 755 diffvim $(DESTDIR)$(BINDIR)/diffvim
	install -m 755 animator/diffvim-pipeline $(DESTDIR)$(BINDIR)/diffvim-pipeline
	# Perl tools
	install -m 755 compute/perl/compute_builtin.pl $(DESTDIR)$(BINDIR)/diffvim-compute-perl
	install -m 755 animator/perl/postprocess.pl $(DESTDIR)$(BINDIR)/diffvim-postprocess-perl
	install -m 755 animator/perl/pace.pl $(DESTDIR)$(BINDIR)/diffvim-pace-perl
	install -m 755 animator/perl/animator.pl $(DESTDIR)$(BINDIR)/diffvim-animator-perl
	install -m 755 animator/perl/decorate.pl $(DESTDIR)$(BINDIR)/diffvim-decorate-perl

install-man:
	install -d $(DESTDIR)$(MANDIR)
	for f in man/*.1; do \
	        install -m 644 $$f $(DESTDIR)$(MANDIR)/; \
	done

install-comp:
	install -d $(DESTDIR)$(COMPDIR)
	install -m 644 completion/diffvim.bash $(DESTDIR)$(COMPDIR)/diffvim
	install -m 644 completion/diffvim.fish $(DESTDIR)$(PREFIX)/share/fish/completions/diffvim.fish
	install -m 644 completion/_diffvim $(DESTDIR)$(PREFIX)/share/zsh/site-functions/_diffvim

# --- Documentation ---------------------------------------------------------

.PHONY: docs man

docs:
	@echo "Building documentation..."
	@if command -v mdbook >/dev/null 2>&1; then \
	        mdbook build docs/src/; \
	else \
	        echo "  mdbook not installed — docs are plain Markdown, no build needed"; \
	fi

man:
	@echo "Manpages are pre-built in man/*.1"
	@ls man/*.1

# --- Testing ---------------------------------------------------------------

.PHONY: test test-unit test-minimal test-pipeline test-l2r test-vimscript test-debug-bundle test-new-features test-no-backward test-indent-last test-pipeline-options

test: test-unit test-minimal test-l2r test-debug-bundle test-new-features test-no-backward test-indent-last test-pipeline-options
	@echo ""
	@echo "=== All tests passed ==="

test-unit:
	@echo "=== Animator unit tests ==="
	@for t in test_all_animators test_cross_language test_newline_fix \
	         test_roundtrip test_roundtrip_verify test_snapshot_each_op \
	         ; do \
	        perl animator/tests/$$t.pl 2>&1 | grep "Results:"; \
	done

test-minimal:
	@echo "=== Minimal test cases ==="
	@bash tests/run_minimal_tests.sh 2>&1 | tail -1

test-pipeline:
	@echo "=== Pipeline verification (42 examples) ==="
	@bash tests/verify_md5.sh 2>&1 | tail -4

test-l2r:
	@echo "=== l2r algorithm tests ==="
	@bash l2r_test/test_l2r.sh 2>&1 | tail -1

test-vimscript:
	@echo "=== Vimscript animator tests (42 examples) ==="
	@bash tests/test_vimscript_animator.sh 2>&1 | tail -1

test-debug-bundle:
	@echo "=== dv_debug_bundle.sh tests ==="
	@bash tests/test_debug_bundle.sh 2>&1 | tail -3

test-new-features:
	@echo "=== New features tests ==="
	@bash tests/test_new_features.sh 2>&1 | tail -3

test-no-backward:
	@echo "=== No-backward-ops diagnostic ==="
	@perl tests/test_no_backward_ops.pl 2>&1 | tail -5

test-indent-last:
	@echo "=== Indent-last test ==="
	@perl tests/test_indent_last.pl 2>&1 | tail -3

test-pipeline-options:
	@echo "=== Pipeline options end-to-end ==="
	@bash tests/test_pipeline_options.sh 2>&1 | tail -3

# --- Debugging -------------------------------------------------------------

.PHONY: debug snapshot

debug:
	@echo "=== Pipeline debugger on example 01 ==="
	@bash scripts/dv_debug.sh examples/01_small_python/old.py examples/01_small_python/new.py 2>&1 | tail -20

snapshot:
	@echo "=== Per-op snapshots for example 01 ==="
	@bash scripts/dv_snapshot.sh examples/01_small_python/old.py examples/01_small_python/new.py 2>&1
	@echo "Open: file:///tmp/dv_snapshots/snapshots.html"

# --- Clean -----------------------------------------------------------------

.PHONY: clean distclean

clean: clean-compute clean-animator
	@echo "All binaries removed"

clean-compute:
	rm -rf compute/bin

clean-animator:
	rm -f $(ANIMATOR_BINS) $(LAYER_BINS)

distclean: clean
	rm -rf docs/src/book
	rm -rf /tmp/dv_debug /tmp/dv_snapshots /tmp/dv_md5_verify

# --- Check -----------------------------------------------------------------

check:
	@echo "Checking binary freshness..."
	@needs_build=0; \
	for src_bin in \
	        "compute/cpp/diffvim-compute.cpp:$(COMPUTE_BIN)" \
	        "animator/c/postprocess.c:$(POSTPROCESS_BIN)" \
	        "animator/c/pace.c:$(PACE_BIN)" \
	        "animator/c/animator.c:$(ANIMATOR_BIN)"; do \
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
	@echo "diffvim build system"
	@echo ""
	@echo "Targets:"
	@echo "  make                Build all binaries"
	@echo "  make compute        Build compute tool only"
	@echo "  make animator       Build animator tools only"
	@echo "  make install        Install everything to $(PREFIX)"
	@echo "  make install-bin    Install binaries only"
	@echo "  make install-man    Install manpages only"
	@echo "  make docs           Build documentation"
	@echo "  make test           Run unit + minimal + l2r tests"
	@echo "  make test-pipeline  Run full 42-example verification"
	@echo "  make test-vimscript Run vimscript animator tests"
	@echo "  make test-debug-bundle  Run dv_debug_bundle.sh tests"
	@echo "  make debug          Debug pipeline on example 01"
	@echo "  make snapshot       Generate per-op HTML snapshots"
	@echo "  make clean          Remove all binaries"
	@echo "  make check          Check if binaries are up to date"
	@echo "  make help           Show this help"
