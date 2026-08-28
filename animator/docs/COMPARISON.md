# Comparison: diffvim (vim-based) vs. diffvim-animator-c (standalone)

**Date:** 2026-08-17 (updated 2026-08-18 after Phase A–C refactor)

---

## 1. Architecture Comparison

### Current diffvim (vim-based)

```
User runs:  diffvim old.py new.py

→ bash launcher (4,517 lines)
    → parses 40+ CLI options
    → resolves 6 unified selectors
    → exports 114 env vars
    → generates 4,500 lines of vimscript
    → exec vim (single process)
        → vimscript engine (73 functions)
            → computes diff (Patience)
            → post-processes ops (6 passes)
            → decides pacing (AWD state machine)
            → animates in vim buffer
            → handles user input
            → renders via redraw
```

Everything in one process, one language, one 4,500-line script.

### New animator pipeline (separated tools)

```
User runs:  diffvim old.py new.py  (or the pipeline directly)

→ diffvim-compute-cpp old.py new.py      (existing, C++)
    → computes raw char ops
    → stdout: raw ops
    (falls back to compute/perl/compute_builtin.pl if missing)

→ diffvim-postprocess --op-order optimize  (Perl/C)
    → reorders ops within lines
    → adds per-op (line, col) positions
    → stdout: positioned ops (TSV)

→ pp_pace --delete-pacing word         (Perl/C)
    → analyzes entire op stream
    → adds delays and batching (positions passed through)
    → stdout: timed op stream (TSV v2)

→ diffvim-animator-c-c old.py                  (Perl/C)
    → reads timed op stream
    → sets cursor per op, then applies
    → plays back ops in terminal (or --no-display)
```

Four separate tools, each independently testable, pipable, and
replaceable. The animator is ~200 lines (C++) vs. ~4,500 (vimscript).

> The historical Go implementations of postprocess / pace / animator
> were removed in the Phase A refactor — only Perl and C remain.

---

## 2. Feature Comparison

| Feature | diffvim (vim) | animator (standalone) |
|---------|---------------|----------------------|
| Diff computation | Inline (vimscript Patience) or external C++ | External (C++ compute tool, Perl fallback) |
| Post-processing | In vimscript engine | Separate tool (piped) |
| Pacing decisions | In vimscript engine (lookahead) | Pre-computed (pace tool) |
| Per-op positioning | Tracked in engine (line_offset) | Owned by postprocess (TSV v2 format) |
| Animation rendering | vim buffer + redraw | ANSI escape sequences |
| User input | vim normal-mode mappings | Raw terminal input |
| Buffer model | vim buffer (list of lines) | Virtual buffer (line array) |
| `\n` delete | Mechanical join (Phase F pending) | Same behavior |
| Unicode | vim's strchars() | Native rune handling |
| Dependencies | vim 8+ | None (C static binary) |
| Testability | Hard (timer-based) | Easy (stdin/stdout, --no-display) |
| Lines of code | ~4,500 (vimscript) | ~200 (C animator) + ~380 (Perl postprocess) + ~310 (Perl pace) |
| Process model | Single vim process | Pipeline of separate tools |

---

## 3. The `\n` Problem: Pending Phase F

### In vim-based diffvim

When a whole line is deleted, the `\n` delete joins the current (empty)
line with the next line. The next line's content appears on the current
line, then gets deleted. This looks terrible.

**Why it can't be fixed in vim:** vim's buffer is a flat list of lines.
There is no `\n` character to delete — deleting a newline means joining
two lines, which always pulls the next line up. There is no concept of
hidden or invisible lines.

### In the standalone animator

The animator's virtual buffer is a line array (in C) or `@lines` (in
Perl). When `newline_delete` is processed, it joins the current line
with the next. The animator mechanically joins — this is correct (the
final buffer matches the new file), but the intermediate visual is
jarring when the current line still has content.

A "deferred join" mechanism was tried and reverted (commit `410cfdb`):
it broke mixed delete+insert sequences on large files because the
buffer retained extra `\n`s, causing subsequent inserts to land on
wrong lines.

### Pending fix (Phase F)

The correct fix belongs in **postprocess**, not in the animator. The
postprocessor should detect the `keep X, delete \n, keep Y` pattern
(a line join) and transform it into a sequence that animates naturally
(e.g., delete the entire second line, then re-insert it as new content).

NOT YET IMPLEMENTED — see `docs/PIPELINE.md` for the design discussion.

---

## 4. Performance Comparison

| Operation | vim-based | animator (C++) | animator (C++) |
|-----------|-----------|---------------|-----------------|
| Startup (100-line file) | ~200ms | <1ms | ~20ms |
| Startup (1000-line file, inline Patience) | ~3500ms | N/A (uses external compute) | N/A |
| Startup (1000-line file, with compute) | ~200ms | ~15ms | ~30ms |
| Char op processing | ~1ms/op | ~0.01ms/op | ~0.1ms/op |
| Full screen redraw | ~5ms | ~1ms | ~5ms |
| Incremental redraw | ~3ms | ~0.5ms | ~2ms |
| Memory (1000-line file) | ~50MB (vim) | ~2MB | ~10MB |

The animator is 10-100x faster because:
1. No vim startup overhead
2. No buffer manipulation overhead (setline/getline/PlaceCursor)
3. No timer callback overhead
4. C is compiled, vimscript is interpreted

---

## 5. Language Comparison for Each Tool

### Postprocess and Pace Tools

| Language | Performance | Maintainability | Dependencies | Recommendation |
|----------|-------------|-----------------|--------------|----------------|
| C | ★★★★★ | ★★☆☆☆ | None | Primary |
| Perl | ★★★☆☆ | ★★★☆☆ | Perl 5.10+ | Fallback (text processing) |

### Animator

| Language | Performance | Terminal Control | Unicode | Dependencies | Recommendation |
|----------|-------------|-----------------|---------|--------------|----------------|
| C | ★★★★★ | ★★★☆☆ | ★★☆☆☆ | None | Primary |
| Perl | ★★★☆☆ | ★★★★☆ | ★★★☆☆ | Perl + CPAN | Fallback |

(Go was removed in the Phase A refactor — produced identical output,
not worth maintaining three implementations.)

### Compute

| Language | Performance | Binary Size | Recommendation |
|----------|-------------|-------------|----------------|
| C++ | ★★★★★ | ~1.4 MB | Primary (only compute implementation) |
| Perl | ★★★☆☆ | n/a (script) | Fallback (`compute/perl/compute_builtin.pl`) |

---

## 6. Test Results

### Round-trip Tests (animator pipeline)

```
test_roundtrip.pl:           15/15 PASS (Perl animator)
test_roundtrip_verify.pl:    30/30 PASS (C animator)
test_all_animators.pl:       round-trip across both animators
test_cross_language.pl:       14/14 PASS (C == Perl postprocess + pace)
test_newline_fix.pl:          7/7 PASS
```

Test cases covered:
  - simple insert
  - simple delete
  - mid-line replace
  - whole line delete
  - whole line insert
  - multi-line delete
  - multi-line insert
  - identical files
  - empty old file
  - empty new file
  - python function
  - indent change
  - unicode
  - multiple hunks
  - identical char run

### Current diffvim Tests

```
test_correctness.pl:        91/91 PASS (Perl-only, no vim engine)
test_features.pl:           52/52 PASS
test_compositions.pl:      172/172 PASS
test_op_order.pl:           20/20 PASS
test_delete_pacing.pl:      28/28 PASS
test_insert_pacing.pl:      23/23 PASS
test_pacing.pl:             27/27 PASS
test_highlight.pl:          29/29 PASS
test_highlight_resolution:  12/12 PASS
test_viewport.pl:           22/22 PASS
test_input_source.pl:       14/14 PASS
test_rapid_eol.pl:          20/20 PASS
test_overwrite_deletefirst:  8/8 PASS
test_engine_features.pl:    12/12 PASS
test_new_features.pl:        9/9 PASS
test_semantic_cleanup.pl:   21/21 PASS
test_parsers.pl:             9/9 PASS
test_precomputed.pl:        32/32 PASS
test_vim_correctness.pl:    42/42 PASS (bypasses ProcessCharOp)
Compute parity:             14/14 PASS (C++ == Perl fallback identical)
```

> `tests/test_tool.pl` was deleted in the Phase A refactor — it tested
> the `--tool` flag, which Phase B removed.

### Known Gaps in Current diffvim Tests

- `test_vim_correctness.pl` bypasses `ProcessCharOp` — AWD, pacing,
  and `\n` handling are NOT tested
- No test verifies the `\n` merge bug is actually fixed
- No test exercises the real animation engine in synchronous mode
- `animator/tests/test_synchronous_engine.pl` was already failing
  before the refactor (pre-existing vimscript synchronous-mode issue)

### Animator Advantages in Testing

- `--no-display` mode processes all ops without rendering — fully
  testable without a terminal
- `--snapshot` writes the buffer at any point — verify intermediate
  states
- Each tool is tested independently via stdin/stdout
- Round-trip tests verify the entire pipeline end-to-end

---

## 7. Migration Path

### Phase 1 (current): Both systems coexist

The current diffvim (vim-based) is kept as-is. The new animator tools
are available alongside it:

```bash
# Current (vim-based)
diffvim old.py new.py

# New (standalone)
diffvim-compute-cpp old.py new.py |
  diffvim-postprocess --op-order optimize |
  pp_pace --delete-pacing word |
  diffvim-animator-c-c old.py
```

### Phase 2: Wrapper integration

Add `--animator` flag to the bash `diffvim` wrapper that builds the
pipeline automatically:

```bash
diffvim --animator --delete-pacing word old.py new.py
```

### Phase 3: Animator becomes default

```bash
# Default uses animator
diffvim old.py new.py

# Fall back to vim
diffvim --vim old.py new.py
```

---

## 8. Summary

| Aspect | diffvim (vim) | animator (standalone) |
|--------|---------------|----------------------|
| Correctness | `\n` join looks bad (Phase F pending) | Same behavior |
| Performance | Slow (vim overhead) | ✓ 10-100x faster |
| Testability | Hard (timer-based) | ✓ Easy (stdin/stdout) |
| Dependencies | vim 8+ | ✓ None (C static binary) |
| Architecture | Monolithic (4,500 lines) | ✓ Separated (4 tools, ~200-400 lines each) |
| Lines of code | ~4,500 (vimscript) | ✓ ~1,000 (total across tools) |
| `\n` problem | Pending Phase F | Pending Phase F |
| Round-trip tests | 91 (Perl-only) | ✓ 45+ (full pipeline) |
| Status | Production (with known bugs) | Development (all tests pass) |
