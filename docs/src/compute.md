# External Compute Tool

diffvim's in-vim LCS computation is fast enough for files up to a few
hundred lines. For larger files (1000+ lines, or diffs with thousands
of changed characters), the vimscript LCS can take seconds or even
tens of seconds before the animation starts.

The **external compute tool** solves this. It is a standalone binary
written in C++ that implements the exact same algorithm as the
vimscript engine, but compiled to native code. It is 10-100x faster.

> The historical C, Rust, and Go variants were removed in the Phase A
> refactor — they all produced byte-identical output and the maintenance
> cost outweighed the value. Only the C++ tool remains. When the C++
> binary is missing, `diffvim-pipeline` falls back to the pure-Perl
> `compute/perl/compute_builtin.pl`.

## Quick Start

```bash
# Build the C++ tool
make -C compute

# Compute the diff, then run diffvim with --precomputed
compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt
diffvim --precomputed /tmp/diff.txt old.py new.py

# Or in one line:
compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt && \
    diffvim --precomputed /tmp/diff.txt old.py new.py
```

`diffvim` and `diffvim-pipeline` look for the C++ binary automatically
(in `compute/bin/`, `/usr/local/bin/`, and `~/.local/bin/`); when it
is present they pre-compute before launching vim, so the manual
`--precomputed` step is rarely needed.

## The C++ Variant

| Binary                       | Source                       | Build cmd              | Notes                          |
| ---------------------------- | ---------------------------- | ---------------------- | ------------------------------ |
| `compute/bin/diffvim-compute-cpp` | `compute/cpp/diffvim-compute.cpp` | `make cpp`        | C++17, the only compute implementation |

## Direct Usage

```bash
# Compute the diff and write to a file
compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt

# Use a specific algorithm
compute/bin/diffvim-compute-cpp --algorithm patience --semantic-cleanup \
    old.py new.py /tmp/diff.txt

# Convert a unified diff to diffvim's format
compute/bin/diffvim-compute-cpp --diff patch.diff /tmp/diff.txt
compute/bin/diffvim-compute-cpp --diff - /tmp/diff.txt < patch.diff

# Show help
compute/bin/diffvim-compute-cpp --help
```

Then run diffvim with the precomputed file:

```bash
diffvim --precomputed /tmp/diff.txt old.py new.py
```

## Options

| Option                       | Description                                          |
| ---------------------------- | ---------------------------------------------------- |
| `--algorithm lcs\|patience`  | Diff algorithm (default: `lcs`)                     |
| `--semantic-cleanup`         | Merge adjacent delete/insert pairs into keeps        |
| `--word-diff`                | Batch word runs in char ops                          |
| `--indent-aware`             | Treat indent-only changes specially                  |
| `--optimize-sequence`        | Reorder ops within a line (default: on)              |
| `--no-optimize-sequence`     | Disable op reordering                                |
| `--left-to-right`            | Emit keeps, then deletes, then inserts per line      |
| `--diff`                     | Read a unified diff instead of two files             |
| `-h, --help`                 | Show help and exit                                   |

`--algorithm myers` was removed: it OOMs on 15K-line files and
produces the same op count as LCS.

## Environment Variables

| Variable                       | Effect                                          |
| ------------------------------ | ----------------------------------------------- |
| `DIFFVIM_ALGORITHM`            | Default `--algorithm` value                     |
| `DIFFVIM_SEMANTIC_CLEANUP`     | Set to `1` to enable by default                 |
| `DIFFVIM_WORD_DIFF`            | Set to `1` to enable by default                 |
| `DIFFVIM_INDENT_AWARE`         | Set to `1` to enable by default                 |
| `DIFFVIM_OPTIMIZE_SEQUENCE`    | Default `1`; set to `0` to disable              |
| `DIFFVIM_LEFT_TO_RIGHT`        | Set to `1` to enable by default                 |
| `DIFFVIM_COMPUTE_BIN`          | Override path to the compute binary (advanced)  |

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

Use `compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt 2>&1`
to see the compute time, then run diffvim to see the animation startup.

## Fallback

If `compute/bin/diffvim-compute-cpp` is not on disk:

- `diffvim` falls back to the embedded vimscript LCS
  (`s:LineDiff` / `s:CharDiff` in `autoload/diffvim/engine.vim`) —
  slower but always available.
- `diffvim-pipeline` falls back to `compute/perl/compute_builtin.pl`,
  a thin Perl wrapper around `DiffVim::Parser::Perl::parse_diff` that
  emits the same op-stream format as the C++ tool.

Both fallbacks produce byte-identical output to the C++ tool, just
slower.

## Benchmark

On a 1000-line Python file with ~200 changed lines:

| Tool                  | Compute time |
| --------------------- | ------------ |
| vimscript LCS         | ~3500 ms     |
| Perl fallback         | ~150 ms      |
| `diffvim-compute-cpp` | 11 ms        |

The native C++ tool is ~300x faster than the vimscript LCS and ~15x
faster than the Perl fallback.

## See Also

- [`diffvim-compute(1)`](../man/diffvim-compute.1) — the compute tool manpage
- [Parallel Compute](../PARALLEL_COMPUTE.md) — architecture and parallelism opportunities
- [Parsers](./parsers.md) — the diff file format reference
- [Multi-File Animation](../MULTI_FILE.md) — using compute tools with `--multi`
