# Binary op format analysis

## Question

What would making the op list a binary format gain us, for all pipe
commands and diffvim, computed on multiple sizes of input files?
Assume max lines = 2^16 (65536) and max chars per line = 256.
We'd also add `--op-text-format` to be able to read it.

## Current format (TSV text)

Each op is a line of tab-separated text:
```
keep\t12345\t67\t104\t'h'
```

| Field | Type | Example | Bytes |
|-------|------|---------|-------|
| type | string | `keep` / `delete` / `insert` | 4-6 |
| line | int (1-65536) | `12345` | 1-5 |
| col | int (1-256) | `67` | 1-3 |
| code | int (0-1114111) | `104` | 1-7 |
| char_repr | string | `'h'` / `\\n` / `space` | 2-8 |

Plus tab separators (4) + newline (1) = ~20-35 bytes per op.

**Average**: ~30 bytes/op.

## Proposed binary format

Each op is a fixed-size record:

```
struct OpRecord {
    uint8_t  type;       // 0=keep, 1=delete, 2=insert
    uint16_t line;       // 1-65536
    uint8_t  col;        // 1-256
    uint32_t code;       // 0-1114111 (Unicode codepoint)
    // No char_repr (can be computed from code)
};
```

**Size**: 1 + 2 + 1 + 4 = 8 bytes/op.

## Size comparison

| File size | Ops | TSV (30 B/op) | Binary (8 B/op) | Ratio |
|-----------|-----|--------------|-----------------|-------|
| Small (100 lines) | 800 | 24 KB | 6.4 KB | 3.75x smaller |
| Medium (1K lines) | 8,000 | 240 KB | 64 KB | 3.75x smaller |
| Large (10K lines) | 80,000 | 2.4 MB | 640 KB | 3.75x smaller |
| Max (65K lines) | 1,677,721 | 50 MB | 13.4 MB | 3.75x smaller |

**Binary is ~3.75x smaller** than TSV. For the max file size, that's
50 MB → 13.4 MB — saves 37 MB.

## Speed comparison

### Parsing

**TSV**: Each line must be tokenized (split on tabs), strings converted
to ints. ~1μs per op (10-100ns for tokenize + 100-500ns for atoi ×4).

**Binary**: No parsing — just read 8 bytes and cast. ~10ns per op.

| File size | Ops | TSV parse | Binary read | Speedup |
|-----------|-----|-----------|-------------|---------|
| Small | 800 | 0.8ms | 0.008ms | 100x |
| Medium | 8,000 | 8ms | 0.08ms | 100x |
| Large | 80,000 | 80ms | 0.8ms | 100x |
| Max | 1,677,721 | 1.68s | 16.8ms | 100x |

**Binary is ~100x faster to parse.**

### Writing

**TSV**: sprintf/printf for each op. ~500ns per op.

**Binary**: Direct memory write. ~10ns per op.

| File size | Ops | TSV write | Binary write | Speedup |
|-----------|-----|-----------|-------------|---------|
| Max | 1,677,721 | 840ms | 16.8ms | 50x |

### I/O (pipe transfer)

**TSV**: 50 MB through pipe. At 1 GB/s pipe bandwidth: 50ms.

**Binary**: 13.4 MB through pipe. At 1 GB/s: 13.4ms.

**Speedup**: 3.75x faster I/O.

## Total pipeline time comparison

For a max-size file (1.7M ops):

| Stage | TSV (current) | Binary | Savings |
|-------|--------------|--------|---------|
| Compute write | 840ms | 17ms | 823ms |
| Postprocess read | 1,680ms | 17ms | 1,663ms |
| Postprocess write | 840ms | 17ms | 823ms |
| Pace read | 1,680ms | 17ms | 1,663ms |
| Pace write | 840ms | 17ms | 823ms |
| Animator read | 1,680ms | 17ms | 1,663ms |
| Pipe I/O | 150ms (3×50MB) | 40ms (3×13.4MB) | 110ms |
| **Total I/O** | **7,710ms** | **142ms** | **7,568ms** |

**Binary saves ~7.5 seconds** on a max-size file. But the animator
takes 5-10 seconds to render — so the total is still 5-10 seconds.

For a medium file (8K ops):

| Stage | TSV | Binary | Savings |
|-------|-----|--------|---------|
| Total I/O | 48ms | 1ms | 47ms |

**Binary saves 47ms** — negligible for medium files.

## When binary helps

| File size | TSV total I/O | Binary total I/O | Worth it? |
|-----------|--------------|-----------------|-----------|
| Small (800 ops) | 4.8ms | 0.1ms | No (overhead > gain) |
| Medium (8K ops) | 48ms | 1ms | Marginal |
| Large (80K ops) | 480ms | 10ms | Yes (saves 470ms) |
| Max (1.7M ops) | 7,710ms | 142ms | Yes (saves 7.5s) |

**Binary is worth it for files with 80K+ ops** (10K+ lines with 10%
change rate).

## Drawbacks of binary

1. **Not human-readable** — need `--op-text-format` to inspect/debug
2. **Endianness** — binary format must specify endianness (or use
   network byte order)
3. **Versioning** — binary format must include a version header
4. **No grep/awk/sed** — can't inspect or filter with standard tools
5. **No diff** — can't compare two op streams with `diff`
6. **Perl compatibility** — Perl would need `pack`/`unpack` instead
   of simple string parsing

## Implementation complexity

- **C**: Easy — `fwrite(&record, sizeof(record), 1, stdout)`
- **Perl**: Moderate — `pack("CSCV", $type, $line, $col, $code)`
- **vimscript**: Hard — vim doesn't have native binary I/O

The vimscript animator would need to convert binary back to text
before parsing, negating the speed benefit for the launcher.

## Recommendation

**Yes, implement binary format with `--op-text-format` fallback.**

For large files (10K+ lines), the 7.5-second I/O savings is significant.
For small files, the overhead is negligible.

**Format spec:**
```
Header: "DIFFVIM_BIN_v1\n" (14 bytes)
Ops:    [type:1][line:2][col:1][code:4] (8 bytes each, little-endian)
Markers: HUNK = [255][target:2][del:2][ins:2][end_ins:1][end_del:1]
         HUNK_END = [254]
         DELAY = [253][ms:4][type_len:1][type_str]  (variable)
```

Type byte 0-2 = keep/delete/insert, 253-255 = markers.

**Implementation:**
1. Add `--op-format binary|text` to compute, postprocess, pace
2. Default: binary (for speed)
3. `--op-text-format`: text (for debugging, same as current)
4. Animator auto-detects by reading the first 14 bytes

**Estimated effort:** 4-8 hours to implement across all stages.
