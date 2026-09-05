# Implementation Audit — What Was Promised vs What's Done

This is a frank accounting of what the user has asked for across sessions
and what is actually implemented, tested, and working as of
2026-09-05. Items are grouped by status.

---

## Recently Fixed (This Session)

### ✅ 35 property-test failures → 0
- **Was**: `make test-property` had 15-35/50 failures (nondeterministic).
  The animator had no line-shift tracking — \n deletes (joins) and
  \n inserts (splits) corrupted subsequent ops' positions.
- **Now**: 500/50 pass across 10 random seeds. The diff engine, animator,
  and layer runner were all fixed to track line shifts consistently.
  See commit `ecd4628`.

### ✅ 36/36 examples pass (was 5/36)
- **Was**: Only 5/36 examples passed because the reorder layer shifted
  op positions but the HUNK headers weren't updated, causing the
  animator's line-shift logic to double-count.
- **Now**: The layer runner updates HUNK target_line with the cumulative
  line_offset, and the animator detects "post-processed" headers to
  skip its own remapping. See commit `ecd4628`.

### ✅ `ad_vim` startup crash (no layers specified)
- **Was**: `ad_vim old.py new.py` exited 1 without starting vim because
  `ad_postprocess` died on empty layer chain.
- **Now**: `ad_postprocess` passes stdin through to stdout when no
  layers are specified (matching the documented "no layers by default"
  behavior). See commit `259447d`.

### ✅ `--annotate` flag on `ad_vim`
- **Was**: `--annotate` only existed on `ad_session` and `ad_gen_ops`.
  `ad_vim` users had no way to get the `# old:` / `# new:` comments.
- **Now**: `ad_vim --annotate old.py new.py` writes annotated ops to
  `/tmp/ad_vim_ops_annotated_<pid>.tsv`. See commit `1d7ec95`.

### ✅ `ad_annotate` SIGABRT on exit
- **Was**: `ad_annotate` crashed with SIGABRT on exit due to two
  memory bugs: double-free in `buffer_free` (stale pointer after join)
  and free of garbage pointers (uninitialized slots after realloc).
- **Now**: Both fixed, ASAN-clean. See commit `1d7ec95`.

---

## Implemented and Working

### Core Animation
- ✅ Patience diff (line-level + char-level)
- ✅ Cursor glide with ease-in-out
- ✅ Timer-based animation engine (vimscript)
- ✅ External pipeline: `ad_compute` → `ad_postprocess` → `ad_layer_pace` → `ad`
- ✅ `--speed`, `--output`, `--context`, `--max-hunk-chars`, `--scroll`
- ✅ `--multi`, `--replay`, `--git-rev`, `--git-blame`
- ✅ `--word-diff`, `--step-mode`, `--sign-column`
- ✅ Controls: Space=pause, n=skip, b=back, q=quit, +/-/= speed, ?=help

### Layers (7 total)
- ✅ `ad_layer_reorder` — deletes before inserts within each line
- ✅ `ad_layer_overwrite` — merge adjacent delete+insert
- ✅ `ad_layer_indent_last` — whitespace deletes to end of line
- ✅ `ad_layer_line_delete_in_place` — delete content before joining
- ✅ `ad_layer_skip_indent` — skip indent-only changes
- ✅ `ad_layer_pace` — timing delays
- ✅ `ad_layer_highlight` — highlight/dim/fold decorations

### Tooling
- ✅ `ad_session` — vim-only interactive debugger (F5/F6, folds, git)
- ✅ `ad_tmux_watch` — tmux-based debugger
- ✅ `ad_watch` — live-preview display
- ✅ `ad_gen_ops` — standalone op generator
- ✅ `ad_annotate` — `# old:` / `# new:` context comments
- ✅ Shell completions (bash/zsh/fish)
- ✅ Manpages for all tools
- ✅ mdBook documentation

### Testing
- ✅ `make test-layers` — C/Perl parity per layer
- ✅ `make test-minimal` — 25 minimal cases through pipeline
- ✅ `make test-property` — 50 random property-based tests
- ✅ `make test-examples` — 36 examples through full pipeline
- ✅ `make test-fuzz` — 60 fuzz tests (malformed inputs)

---

## Known Issues (Pre-Existing, Not Yet Fixed)

### Highlight layer C/Perl parity
- `make test-layers` reports 1 failure: C and Perl `ad_layer_highlight
  --highlight none` produce different output. This is a pre-existing
  issue in the highlight layer, unrelated to the line-shift fix.

### Perl animator has the same line-shift bug
- `animator/perl/ad.pl` has no line-shift tracking — it will produce
  the same corruption as the C animator did before the fix.
- The C animator is the default; Perl is a fallback. Fixing Perl is
  a separate task.

---

## Promised But Not Yet Implemented

From `docs/design/FOLLOW_IMPROVEMENTS.md` — top 10 priorities:

### ⬜ #2: Inline char-level highlight while typing
- Paint each freshly-typed char green for 200ms, each freshly-deleted
  char red for 200ms, using `matchaddpos()`.
- Status: Not started. The `--highlight` flag exists but highlights
  hunk regions, not individual chars.

### ⬜ #12: Plain-English hunk description
- Before each hunk, announce: `Hunk 3/7: replaced 1 line in function
  hello()`. Generated from diff structure + nearest enclosing scope.
- Status: Not started.

### ⬜ #24: Thinking pause before complex hunks
- Auto-pause ~600ms before hunks with >30 changed chars.
- Status: Not started.

### ⬜ #8: "Just changed" line background tint
- Briefly tint the entire line subtle yellow for 500ms after any char
  op lands on it.
- Status: Not started.

### ⬜ #50: Post-animation summary screen
- After animation: `Done. 7 hunks applied. +42 / −28 lines. Press u to
  undo, :w to save, :q to quit.`
- Status: Not started.

### ⬜ #36: Jump to specific hunk
- `:DiffvimHunk 5` jumps directly to hunk #5.
- Status: Not started.

### ⬜ #15: Estimated time remaining
- `~14s remaining` based on pending ops × average delay.
- Status: Not started.

### ⬜ #42: Side-by-side old/new view
- Open the new file in a vsplit; old file animates, new file is the goal.
- Status: Not started.

### ⬜ #46: Syntax-aware token boundaries
- Use Tree-sitter to never split a string literal or identifier across
  delete+insert; replace the whole token instead.
- Status: Not started.

### ⬜ #9: Deletion/insertion counter on status line
- Show `−14 +8` next to hunk progress.
- Status: Not started.

---

## Documentation Cleanup (In Progress)

### ⬜ mdBook SUMMARY.md
- Still has "Debugging" and "Testing" as top-level sections, which
  contradicts the README's "good git usage" framing.
- Need to reorganize under "Git Integration" or "Workflow".

### ⬜ Subdirectory READMEs
- `scripts/README.md` still says "Debugging tools" as the first section.
- `apps/vim/README.md` mentions `ad_vim.pl` as "duplicate functionality;
  can be deleted" — it should either be deleted or the note removed.
- `man/README.md` lists manpages for scripts that may not exist (e.g.,
  `verify_md5.1`, `test_vimscript_animator.1`).
- `animator/README.md` mentions "Perl fallback (produces identical
  output)" — but Perl has the line-shift bug and does NOT produce
  identical output for join/split cases.

---

## Summary

- **3 critical bugs fixed this session** (animator line-shift, ad_postprocess
  pass-through, ad_annotate memory).
- **All test suites pass** (50/50 property, 36/36 examples, 25/25 minimal,
  60/60 fuzz, all layer tests except 1 pre-existing highlight parity issue).
- **`--annotate` now works on `ad_vim`**, `ad_session`, and `ad_gen_ops`.
- **10 FOLLOW_IMPROVEMENTS items** remain unimplemented (the "top 10"
  list from the followability doc).
- **Documentation cleanup** is partially done (top-level README done,
  mdBook and subdirectory READMEs still pending).
