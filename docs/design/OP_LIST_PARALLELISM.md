# Op-list parallelism analysis

## Question

What would making the op list (the TSV stream between pipeline stages)
parallel gain us, computed on multiple sizes of input files?
Assume max lines = 2^16 (65536) and max chars per line = 256.

## Scale analysis

### Input file sizes

| Lines | Chars/line | Total chars | Typical file |
|-------|-----------|-------------|--------------|
| 100 | 80 | 8 KB | Small script |
| 1,000 | 80 | 80 KB | Medium source file |
| 10,000 | 80 | 800 KB | Large source file |
| 65,536 | 256 | 16 MB | Very large file (max spec) |

### Op counts (estimated)

For a typical diff where ~10% of chars change:
- 100 lines × 80 chars × 10% = 800 ops
- 1,000 lines × 80 chars × 10% = 8,000 ops
- 10,000 lines × 80 chars × 10% = 80,000 ops
- 65,536 lines × 256 chars × 10% = 1,677,721 ops (~1.7M ops)

Each op is a TSV line: `keep\t12345\t67\t104\t'h'` = ~30 bytes.
So the op stream is:
- 800 ops → 24 KB
- 8,000 ops → 240 KB
- 80,000 ops → 2.4 MB
- 1.7M ops → 50 MB

## Where parallelism could help

### 1. Compute stage (diff algorithm)

**Current**: Patience diff runs on the whole file sequentially.
- O(N×M) for LCS fallback where N, M are line counts
- For 65K lines, LCS could take seconds

**With parallelism**:
- Split the file at anchor points (unique lines that match)
- Diff each segment in parallel
- Merge results

**Gain**: For large files with many anchors, near-linear speedup.
For files with few anchors (mostly changed), little gain.

**Estimated speedup**: 2-4x for 10K+ line files, minimal for small files.

### 2. Postprocess stage

**Current**: Single-pass over ops, reordering within line groups.
- O(N) where N is op count
- Very fast (~1ms for 80K ops)

**With parallelism**:
- Split at HUNK boundaries (each hunk is independent)
- Process each hunk in parallel
- Merge results

**Gain**: Negligible. Postprocess is already O(N) and fast. The overhead
of splitting/merging would exceed the computation time for all but the
largest files.

**Estimated speedup**: <1.5x even for 1.7M ops. Not worth the complexity.

### 3. Pace stage

**Current**: Single-pass over ops, inserting delays.
- O(N) where N is op count
- Very fast (~1ms for 80K ops)

**With parallelism**: Same as postprocess — negligible gain.

### 4. Animator stage

**Current**: Sequential — applies ops to a virtual buffer one at a time.
- O(N) where N is op count
- Rendering is the bottleneck (terminal I/O), not computation

**With parallelism**: Cannot parallelize — each op depends on the
buffer state after the previous op. The buffer is a shared mutable state.

**Gain**: Zero. The animator is inherently sequential.

### 5. Colorize stage (already parallel)

**Current**: Runs in parallel with the compute→postprocess→pace pipeline.
The colorize tool syntax-highlights both old and new files while the
diff pipeline runs.

**Gain**: Already parallel. No change needed.

## What parallelism would actually gain

### For small files (< 1K lines, < 80K ops)

**Nothing.** All stages run in <10ms. Parallelism overhead exceeds
computation time. The pipeline is already fast enough.

### For medium files (1K-10K lines, 8K-80K ops)

**Marginal.** Compute might take 10-50ms. Postprocess and pace are
<5ms. Animator is I/O-bound (terminal rendering). Total pipeline is
50-100ms, dominated by compute. Parallelizing compute could save 20-30ms.

### For large files (65K lines, 1.7M ops)

**Significant for compute only.**
- Compute: 100-500ms (LCS on 65K lines)
- Postprocess: 50ms (1.7M ops, single pass)
- Pace: 50ms (1.7M ops, single pass)
- Animator: 5-10 seconds (terminal rendering is the bottleneck)

Parallelizing compute could save 200-400ms. But the animator takes
5-10 seconds — the compute time is <5% of total. Parallelizing
postprocess/pace would save 50ms each — negligible.

**The bottleneck is the animator (terminal I/O), not the op processing.**

## Recommendation

**Do not parallelize the op list.** The gains are negligible:

| Stage | Time (65K lines) | Parallel gain | Worth it? |
|-------|-----------------|---------------|-----------|
| Compute | 100-500ms | 200-400ms saved | Maybe (if files are huge) |
| Postprocess | 50ms | 25ms saved | No |
| Pace | 50ms | 25ms saved | No |
| Animator | 5-10s | 0 (sequential) | No |
| Colorize | Already parallel | — | Already done |

The only stage where parallelism helps is **compute** (the diff
algorithm), and only for very large files (65K+ lines). For everything
else, the pipeline is already fast enough.

### What would help more

1. **Incremental rendering** — only re-render changed lines, not the
   whole buffer. This would make the animator 10-100x faster.

2. **Pre-computed color** — cache the colorize output so it doesn't
   re-run on every animation.

3. **Skip unchanged hunks** — if a hunk has only keeps, skip it entirely
   (no delay, no render).

These would have 10-100x more impact than parallelizing the op list.

## Memory analysis

For 1.7M ops × 30 bytes/op = 50 MB op stream. This fits in memory
easily. The current single-pass approach is optimal for memory — no
need to buffer the whole stream.

If we parallelized, we'd need to split the stream, process chunks
in parallel, then merge — which would increase memory usage and
add complexity for negligible gain.
