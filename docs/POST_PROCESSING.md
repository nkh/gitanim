# Op-Sequence Post-Processing

## Problem

The standard LCS (Longest Common Subsequence) diff algorithm can produce
**erratic, inefficient** char-op sequences that cause the cursor to jump
back and forth across a line. For example, replacing "hello world" with
"hi there" might produce:

```
del 'h', ins 'h', del 'e', ins 'i', del 'l', del 'l', ins ' ', ins 't', ...
```

This interleaved `del, ins, del, ins, ...` pattern forces the viewer's
eye to track the cursor jumping between delete and insert positions —
visually confusing and cognitively demanding.

## Solution

diffvim's `--optimize-sequence` option (default: **on**) post-processes
the char-op sequence to eliminate erratic movement. Use
`--no-optimize-sequence` to disable.

### What It Does

#### Pass 1: Consolidate Interleaved Delete/Insert Pairs

Scans for patterns where deletes and inserts are interleaved within a
single line (no newlines) and regroups them so all deletes come before
all inserts:

**Before:**
```
del 'a', ins 'x', del 'b', ins 'y', del 'c', ins 'z'
```

**After:**
```
del 'a', del 'b', del 'c', ins 'x', ins 'y', ins 'z'
```

This means the viewer sees: "these chars are being deleted" (one
coherent action), then "these chars are being inserted" (another
coherent action), instead of alternating between the two.

#### Why This Works

Research in eye tracking and reading behavior (Rayner, 1998) shows that
saccadic eye movements take ~250ms to acquire a new target. When the
cursor jumps between delete and insert positions every 50ms, the eye
can't track it — the viewer perceives a blur. By consolidating, the
cursor stays in one area for the deletes, then moves to the insert
area, giving the eye time to track each phase.

### When It's Applied

The optimization runs in `s:BuildHunks()` after the char-level diff is
computed, but before `--overwrite` and `--delete-end-first` transforms.
The order is:

1. `s:CharDiff()` or `s:WordDiff()` — compute the raw char ops
2. `s:SemanticCleanup()` — merge canceling pairs (del 'a' + ins 'a' → keep 'a')
3. **`s:OptimizeSequence()`** — consolidate interleaved del/ins runs
4. `s:OverwriteTransform()` — convert del+ins to overwrite pairs (if `--overwrite`)
5. `s:DeleteEndFirst()` — move EOL deletes before inserts (if `--delete-end-first`)

### Effect

| Scenario | Without optimization | With optimization |
|----------|---------------------|-------------------|
| Replace "abc" with "xyz" | del a, ins x, del b, ins y, del c, ins z | del a, del b, del c, ins x, ins y, ins z |
| Modify word mid-line | cursor jumps back and forth | cursor deletes, then inserts |
| Multi-char change | 6 cursor jumps | 2 coherent phases |

### Research Basis

- **Hunt & McIlroy (1976)**: "An Algorithm for Differential File
  Comparison" — the original LCS paper notes that the backtrack can
  produce non-unique solutions; some are more visually coherent than
  others.
- **Bram Cohen (2002)**: Patience diff anchors on unique common lines
  to produce more human-readable diffs. This post-processor applies
  similar principles at the char level.
- **Rayner (1998)**: "Eye movements in reading and information
  processing" — saccade latency is ~250ms; changes faster than this
  blur together.
- **Sweller (1988)**: Cognitive Load Theory — reducing visual
  complexity (fewer cursor jumps) reduces extraneous cognitive load.

### Limitations

- Only consolidates within a single line (stops at newlines). Cross-
  line interleaving is preserved because the line structure provides
  natural visual boundaries.
- Does not change the total number of ops — only reorders them. The
  final buffer content is identical.
- May conflict with `--overwrite` mode (which pairs del+ins as
  overwrite). If both are enabled, optimization runs first, then
  overwrite may re-pair them.

### Disabling

```bash
# Use --no-optimize-sequence to get the raw LCS output
diffvim --no-optimize-sequence old.py new.py
```

This is useful for debugging or when you want to see the "raw" diff
behavior without any post-processing.
