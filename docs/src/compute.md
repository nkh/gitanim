# External Compute Tool

*Created:* `c07e1e1` (2026-08-16 08:00:10 +0000)
*Last updated:* `db72a00` (2026-08-30 08:35:56 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


ad_vim's in-vim patience computation is fast enough for files up to a few
hundred lines. For larger files (1000+ lines, or diffs with thousands
of changed characters), the vimscript patience can take seconds or even
tens of seconds before the animation starts.

The **external compute tool** solves this. It is a standalone binary
written in C++ that implements the exact same algorithm as the
vimscript engine, but compiled to native code. It is 10-100x faster.

> The historical C, Rust, and Go variants were removed in the Phase A
> refactor — they all produced byte-identical output and the maintenance
> cost outweighed the value. Only the C++ tool remains. When the C++
> binary is missing, `ad_pipeline` falls back to the pure-Perl
> `diff_engine/perl/compute_builtin.pl`.

## Quick Start

```bash
# Build the C++ tool
make diff_engine

# Compute the diff, then run ad_vim with --precomputed
bin/ad_compute old.py new.py /tmp/diff.txt
ad_vim --precomputed /tmp/diff.txt old.py new.py

# Or in one line:
bin/ad_compute old.py new.py /tmp/diff.txt && \
    ad_vim --precomputed /tmp/diff.txt old.py new.py
```

`ad_vim` and `ad_pipeline` look for the C++ binary automatically
(in `bin/ad_compute `, `/usr/local/bin/`, and `~/.local/bin/`); when it
is present they pre-compute before launching vim, so the manual
`--precomputed` step is rarely needed.

## The C++ Variant

| Binary                       | Source                           | Build cmd              | Notes                                  |
| ---------------------------- | -------------------------------- | ---------------------- | -------------------------------------- |
| `bin/ad_compute`             | `diff_engine/cpp/ad_compute.cpp` | `make cpp`             | C++17, the only compute implementation |

## Direct Usage

```bash
# Compute the diff and write to a file
bin/ad_compute old.py new.py /tmp/diff.txt

# Convert a unified diff to ad_vim's format
bin/ad_compute --diff patch.diff /tmp/diff.txt
bin/ad_compute --diff - /tmp/diff.txt < patch.diff

# Show help
bin/ad_compute --help
```

Then run ad_vim with the precomputed file:

```bash
ad_vim --precomputed /tmp/diff.txt old.py new.py
```

## Options

| Option                       | Description                                          |                                      |
| ---------------------------- | ---------------------------------------------------- | ------------------------------------ |
| `--algorithm patience\       | patience`                                            | Diff algorithm (default: `patience`) |
| `--word-diff`                | Batch word runs in char ops                          |                                      |
| `--optimize-sequence`        | Reorder ops within a line (default: on)              |                                      |
| `--no-optimize-sequence`     | Disable op reordering                                |                                      |
| `--diff`                     | Read a unified diff instead of two files             |                                      |
| `-h, --help`                 | Show help and exit                                   |                                      |

`--algorithm myers` was removed: it OOMs on 15K-line files and
produces the same op count as patience.

## Environment Variables

| Variable                       | Effect                                          |
| ------------------------------ | ----------------------------------------------- |

## Output Format

The compute tool writes a line-oriented diff file that ad_vim's
`--precomputed` flag reads:

```
# algorithm patience
# word_diff 0
# optimize_sequence 1
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

Use `bin/ad_compute old.py new.py /tmp/diff.txt 2>&1`
to see the compute time, then run ad_vim to see the animation startup.

## Fallback

If `bin/ad_compute` is not on disk:

- `ad_vim` falls back to the embedded vimscript patience
  (`s:LineDiff` / `s:CharDiff` in `autoload/ad_vim/engine.vim`) —
  slower but always available.
- `ad_pipeline` falls back to `diff_engine/perl/compute_builtin.pl`,
  a thin Perl wrapper around `ad::Parser::Perl::parse_diff` that
  emits the same op-stream format as the C++ tool.

Both fallbacks produce byte-identical output to the C++ tool, just
slower.

## Benchmark

On a 1000-line Python file with ~200 changed lines:

| Tool                  | Compute time |
| --------------------- | ------------ |
| vimscript patience    | ~3500 ms     |
| Perl fallback         | ~150 ms      |
| `ad_compute`          | 11 ms        |

The native C++ tool is ~300x faster than the vimscript patience and ~15x
faster than the Perl fallback.

## See Also

- [`ad_compute(1)`](../man/ad_compute.1) — the compute tool manpage
- [Parallel Compute](../PARALLEL_COMPUTE.md) — architecture and parallelism opportunities
- [Parsers](./parsers.md) — the diff file format reference
- [Multi-File Animation](../MULTI_FILE.md) — using compute tools with `--multi`
