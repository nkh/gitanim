# Makefile for diffvim external diff compute tools.
#
# Builds native-compiled diff computers in C, C++, Rust, and Go.
# Each produces the same output format, consumable by:
#   diffvim --precomputed FILE oldfile newfile
#
# Usage:
#   make            # build all
#   make c          # build C version
#   make cpp        # build C++ version
#   make rust       # build Rust version
#   make go         # build Go version
#   make benchmark  # build all + run timing comparison
#   make clean      # remove all binaries

CC      ?= cc
CXX     ?= c++
RUSTC   ?= rustc
GO      ?= go
CFLAGS  ?= -O2 -Wall
CXXFLAGS ?= -O2 -Wall -std=c++17
RUSTFLAGS ?= -O
BIN_DIR := bin

BIN_C   := $(BIN_DIR)/diffvim-compute-c
BIN_CPP := $(BIN_DIR)/diffvim-compute-cpp
BIN_RUST := $(BIN_DIR)/diffvim-compute-rust
BIN_GO  := $(BIN_DIR)/diffvim-compute-go

.PHONY: all c cpp rust go benchmark clean

all: c cpp rust go

c: $(BIN_C)
cpp: $(BIN_CPP)
rust: $(BIN_RUST)
go: $(BIN_GO)

$(BIN_C): c/diffvim-compute.c | $(BIN_DIR)
	$(CC) $(CFLAGS) -o $@ $<

$(BIN_CPP): cpp/diffvim-compute.cpp | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<

$(BIN_RUST): rust/diffvim-compute.rs | $(BIN_DIR)
	$(RUSTC) $(RUSTFLAGS) -o $@ $<

$(BIN_GO): go/diffvim-compute.go | $(BIN_DIR)
	$(GO) build -o $@ $<

$(BIN_DIR):
	mkdir -p $(BIN_DIR)

benchmark: all
	@echo "=== Benchmark: all compute tools ==="
	@echo "Usage: make benchmark OLD=file1 NEW=file2"
	@echo ""
	@if [ -z "$(OLD)" ] || [ -z "$(NEW)" ]; then \
		echo "Please specify OLD and NEW files:"; \
		echo "  make benchmark OLD=examples/01_small_python/old.py NEW=examples/01_small_python/new.py"; \
		exit 1; \
	fi
	@for tool in $(BIN_C) $(BIN_CPP) $(BIN_RUST) $(BIN_GO); do \
		echo ""; \
		echo "--- $$tool ---"; \
		$$tool $(OLD) $(NEW) /tmp/dv_bench_output.txt; \
	done
	@echo ""
	@echo "=== Output verification ==="
	@echo "All tools produce the same output format. Verify with:"
	@echo "  diff <($(BIN_C) $(OLD) $(NEW) /dev/stdout) <($(BIN_CPP) $(OLD) $(NEW) /dev/stdout)"

clean:
	rm -rf $(BIN_DIR)
