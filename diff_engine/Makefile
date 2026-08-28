# Makefile for the diffvim external diff compute tool.
#
# Builds the single native diff computer (C++). The historical C, Rust,
# and Go implementations have been removed; this is the only compute
# tool diffvim uses.
#
# Output is consumed by:
#   diffvim --precomputed FILE oldfile newfile
#   animator/ad_pipeline ...
#
# Usage:
#   make            # build ad_compute
#   make cpp        # same as above (alias for compatibility)
#   make benchmark  # build + run a single timing
#   make clean      # remove the binary

CXX     ?= c++
CXXFLAGS ?= -O2 -Wall -std=c++17
BIN_DIR := bin

BIN_CPP := $(BIN_DIR)/ad_compute

.PHONY: all cpp benchmark clean

all: cpp

cpp: $(BIN_CPP)

$(BIN_CPP): cpp/ad_compute.cpp | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

benchmark: all
	@echo "=== Benchmark: ad_compute ==="
	@echo "Usage: make benchmark OLD=file1 NEW=file2"
	@echo ""
	@if [ -z "$(OLD)" ] || [ -z "$(NEW)" ]; then \
		echo "Please specify OLD and NEW files:"; \
		echo "  make benchmark OLD=tests/tests/examples/01_small_python/old.py NEW=tests/tests/examples/01_small_python/new.py"; \
		exit 1; \
	fi
	@echo ""
	@echo "--- $(BIN_CPP) ---"
	@$(BIN_CPP) $(OLD) $(NEW) /tmp/dv_bench_output.txt

clean:
	rm -rf $(BIN_DIR)
