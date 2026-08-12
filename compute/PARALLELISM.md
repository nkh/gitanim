# Parallelism in External Compute Tools

## Current State: Single-Threaded

All four compute tools (C, C++, Rust, Go) are currently **single-threaded**.
They process the diff sequentially:

1. Read old file → array of lines
2. Read new file → array of lines
3. Line-level diff (LCS/Myers/Patience) — O(N×M) or O(ND)
4. For each hunk: char-level diff — O(N×M) per hunk
5. Write output

The line-level diff and char-level diffs are the CPU-intensive parts.

---

## Can the C Version Be Made Parallel?

**Yes**, with significant speedup potential for large files. Here's the
analysis:

### Opportunity 1: Parallel Hunk Char-Diffs (Easy, High Impact)

After the line-level diff produces hunks, each hunk's char-level diff is
**independent** — they operate on different text segments with no data
dependencies. This is embarrassingly parallel.

**Current (sequential):**
```c
for (int h = 0; h < hunk_count; h++) {
    hunks[h].char_ops = char_diff(hunks[h].old_text, hunks[h].new_text, ...);
}
```

**Parallel (using OpenMP):**
```c
#pragma omp parallel for
for (int h = 0; h < hunk_count; h++) {
    hunks[h].char_ops = char_diff(hunks[h].old_text, hunks[h].new_text, ...);
}
```

**Expected speedup**: For a file with 20 hunks, 4 cores → ~4x speedup
on the char-diff phase (which is typically 50% of total time).

**Build change**: Add `-fopenmp` to CFLAGS and `#include <omp.h>`.

### Opportunity 2: Parallel Line-Level Diff (Hard, Low Impact)

The line-level LCS is a single dynamic-programming computation with
data dependencies along diagonals. It can be parallelized using the
**anti-diagonal wavefront** approach (process all cells (i,j) with
i+j=const in parallel), but this is complex and the overhead often
exceeds the benefit for typical file sizes.

**Myers diff** is inherently sequential (each edit depth depends on the
previous). Parallel Myers exists in research literature but is complex.

**Recommendation**: Don't parallelize the line-level diff. For files
where it's the bottleneck (>10k lines), use a better algorithm
(Myers O(ND)) rather than parallelizing LCS O(N×M).

### Opportunity 3: Parallel File Reading (Easy, Low Impact)

Reading two files can be done in parallel:
```c
#pragma omp parallel sections
{
    #pragma omp section
    old_lines = read_lines(argv[1]);
    #pragma omp section
    new_lines = read_lines(argv[2]);
}
```

**Impact**: Minimal — file reading is ~0.05ms for typical files. Only
matters for very large files on slow disks.

### Opportunity 4: Multi-File Parallelism (Easy, High Impact for Multi-File)

When animating multiple files (`--multi`), each file's diff is independent.
Pre-computing all diffs in parallel (one thread per file) gives near-linear
speedup. This is already described in `docs/MULTI_FILE.md` using bash
background processes.

---

## Implementation Plan for Parallel C

### Phase 1: OpenMP Parallel Hunks (Recommended)

```bash
# Makefile change
CCFLAGS += -fopenmp
```

```c
// diffvim-compute.c — add parallel hunk processing
#include <omp.h>

// In main(), after building all hunk texts:
#pragma omp parallel for schedule(dynamic)
for (int h = 0; h < hunk_count; h++) {
    Hunk *hk = &hunks[h];
    hk->char_ops = char_diff(hk->old_text, hk->new_text, &hk->char_op_count);
    if (do_semantic) {
        hk->char_ops = semantic_cleanup(hk->char_ops, &hk->char_op_count);
    }
}
```

**Expected results** (on a 4-core machine, 1000-line file with 20 hunks):

| Mode | Time | Speedup |
|------|------|---------|
| Sequential | 5.2 ms | 1.0x |
| Parallel (2 threads) | 2.8 ms | 1.9x |
| Parallel (4 threads) | 1.6 ms | 3.3x |
| Parallel (8 threads) | 1.2 ms | 4.3x |

### Phase 2: Thread Pool for Multi-File (Future)

For `diffvim-precomputed --multi`, a thread pool that processes file pairs
in parallel would give near-linear speedup for multi-file scenarios.

---

## Benchmark: Parallel vs Sequential

To verify the speedup, build both versions and compare:

```bash
cd compute
make clean
# Sequential
make c CFLAGS="-O2 -Wall"
time bin/diffvim-compute-c examples/42_large_huge_python/old.py examples/42_large_huge_python/new.py /tmp/out.txt

# Parallel
make clean
make c CFLAGS="-O2 -Wall -fopenmp"
time bin/diffvim-compute-c examples/42_large_huge_python/old.py examples/42_large_huge_python/new.py /tmp/out.txt
```

For the 1000-line Python example, expect ~3x speedup with 4 threads.

---

## Summary

| Approach | Difficulty | Speedup | Recommended |
|----------|-----------|---------|-------------|
| Parallel hunks (OpenMP) | Easy | 3-4x | ✅ Yes |
| Parallel line-level diff | Hard | 1.5-2x | ❌ No (use Myers instead) |
| Parallel file reading | Easy | 1.1x | ❌ Negligible |
| Multi-file parallelism | Easy | Nx (N files) | ✅ Already via bash |

**Current answer to "are the tools running in parallel internally?"**: No,
all 4 tools are single-threaded. The C version can easily be made parallel
using OpenMP for the hunk char-diff phase (3-4x speedup expected).
