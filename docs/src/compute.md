# External Compute Tools

diffvim's in-vim LCS computation is fast enough for files up to a few
hundred lines. For larger files (1000+ lines, or diffs with thousands
of changed characters), the vimscript LCS can take seconds or even
tens of seconds before the animation starts.

The **external compute tools** solve this. They are standalone
binaries written in C, C++, Rust, and Go that implement the exact
same algorithm as the vimscript engine, but compiled to native code.
They are 10-100x faster.

## Quick Start

```bash
# Build all four variants
make -C compute

# Compute the diff, then run diffvim with --precomputed
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt
diffvim --precomputed /tmp/diff.txt old.py new.py

# Or in one line:
compute/bin/diffvim-compute-rust old.py new.py /tmp/diff.txt && \
    diffvim --precomputed /tmp/diff.txt old.py new.py
```

## The Four Variants

All four implementations produce **byte-for-byte identical output**.
Pick whichever language's toolchain you have available.

| Binary                       | Source                       | Build cmd              | Notes                          |
| ---------------------------- | ---------------------------- | ---------------------- | ------------------------------ |
| `compute/bin/diffvim-compute-c`   | `compute/c/diffvim-compute.c`     | `make c`          | Reference implementation       |
| `compute/bin/diffvim-compute-cpp` | `compute/cpp/diffvim-compute.cpp` | `make cpp`        | Modern C++17                   |
| `compute/bin/diffvim-compute-rust`| `compute/rust/diffvim-compute.rs` | `make rust`       | Requires `rustc`               |
| `compute/bin/diffvim-compute-go`  | `compute/go/diffvim-compute.go`   | `make go`         | Requires `go`                  |

## Direct Usage

```bash
# Compute the diff and write to a file
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt

# Use a specific algorithm
compute/bin/diffvim-compute-c --algorithm patience --semantic-cleanup \
    old.py new.py /tmp/diff.txt

# Convert a unified diff to diffvim's format
compute/bin/diffvim-compute-c --diff patch.diff /tmp/diff.txt
compute/bin/diffvim-compute-c --diff - /tmp/diff.txt < patch.diff

# Show help
compute/bin/diffvim-compute-c --help
```

Then run diffvim with the precomputed file:

```bash
diffvim --precomputed /tmp/diff.txt old.py new.py
```

## Options

All four variants accept the same options:

| Option                       | Description                                          |
| ---------------------------- | ---------------------------------------------------- |
| `--algorithm lcs\|myers\|patience` | Diff algorithm (default: `lcs`)                |
| `--semantic-cleanup`         | Merge adjacent delete/insert pairs into keeps        |
| `--word-diff`                | Batch word runs in char ops                          |
| `--indent-aware`             | Treat indent-only changes specially                  |
| `--optimize-sequence`        | Reorder ops within a line (default: on)              |
| `--no-optimize-sequence`     | Disable op reordering                                |
| `--left-to-right`            | Emit keeps, then deletes, then inserts per line      |
| `--diff`                     | Read a unified diff instead of two files             |
| `-h, --help`                 | Show help and exit                                   |

## Environment Variables

| Variable                       | Effect                                          |
| ------------------------------ | ----------------------------------------------- |
| `DIFFVIM_ALGORITHM`            | Default `--algorithm` value                     |
| `DIFFVIM_SEMANTIC_CLEANUP`     | Set to `1` to enable by default                 |
| `DIFFVIM_WORD_DIFF`            | Set to `1` to enable by default                 |
| `DIFFVIM_INDENT_AWARE`         | Set to `1` to enable by default                 |
| `DIFFVIM_OPTIMIZE_SEQUENCE`    | Default `1`; set to `0` to disable              |
| `DIFFVIM_LEFT_TO_RIGHT`        | Set to `1` to enable by default                 |

## Output Format

The compute tool writes a line-oriented diff file that diffvim's
`--precomputed` flag reads:

```
# algorithm lcs
# semantic_cleanup 0
# word_diff 0
# indent_aware 0
# optimize_sequence 1
# left_to_right 0
# hunk_count 3
HUNK 2
keep 32
keep 32
keep 32
keep 32
keep 112
insert 102
keep 34
...
delete 32
delete 43
delete 32
delete 110
delete 97
delete 109
delete 101
HUNK 5
...
```

Each `keep`/`delete`/`insert` line is followed by the Unicode code
point of the character (e.g. `97` for `a`, `10` for newline). See
[`docs/PARSERS.md`](../PARSERS.md) for the full format reference.

## Timing Output

Timing is printed to stderr:

```
compute: 12.3 ms (total)
startup: 0.4 ms (process start to first byte read)
```

Use `compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt 2>&1`
to see the compute time, then run diffvim to see the animation startup.

## When to Use Each Variant

- **C** — fastest startup, smallest binary. Best for repeated invocations.
- **C++** — same speed as C, slightly larger binary. Useful if you want to extend with C++ libraries.
- **Rust** — same speed as C/C++, safest code. Best if you want to hack on the algorithm.
- **Go** — slightly larger binary, same speed. Best if your team already uses Go.

In practice the difference is negligible — pick whichever builds
cleanly on your system.

## Benchmark

On a 1000-line Python file with ~200 changed lines:

| Tool                 | Compute time |
| -------------------- | ------------ |
| vimscript LCS        | ~3500 ms     |
| `diffvim-compute-c`  | 11 ms        |
| `diffvim-compute-cpp`| 12 ms        |
| `diffvim-compute-rust`| 13 ms       |
| `diffvim-compute-go` | 14 ms        |

All four native variants finish in under 15ms — a 250x speedup over
vimscript.

## See Also

- [`diffvim-compute(1)`](../man/diffvim-compute.1) — the compute tool manpage
- [Parallel Compute](../PARALLEL_COMPUTE.md) — architecture and parallelism opportunities
- [Parsers](./parsers.md) — the diff file format reference
- [Multi-File Animation](../MULTI_FILE.md) — using compute tools with `--multi`
