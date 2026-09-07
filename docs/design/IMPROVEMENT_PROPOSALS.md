# Improvement Proposals — 20 Per Tool

This document lists 20 concrete improvement proposals for each script
and binary in the `ad` toolkit. Each proposal is specific, actionable,
and framed from the user's perspective.

Status markers:
- ✅ already implemented
- ⬜ not yet implemented (proposal)

Items are grouped by tool, then ordered roughly by impact.

---

## `ad` (C animator)

1. ⬜ **Inline char highlight** — paint each freshly-typed char green for
   200ms, each freshly-deleted char red for 200ms, using ANSI escape
   codes.
2. ⬜ **Ghost text for deletions** — show deleted text as struck-through
   overlay for 400ms before it disappears.
3. ⬜ **Cursor trail** — leave a fading trail behind the cursor for
   ~300ms after each move.
4. ⬜ **"Just changed" line tint** — briefly tint the entire line subtle
   yellow for 500ms after any char op.
5. ⬜ **Deletion/insertion counter** — show `−14 +8` on the status line.
6. ⬜ **Per-hunk minimap** — color the scrollbar region for the current
   hunk.
7. ⬜ **Hunk description** — announce `Hunk 3/7: replaced 1 line in
   function hello()` before each hunk.
8. ⬜ **File-path header** — pin file name + hunk counter in a statusline
   that doesn't scroll.
9. ⬜ **Estimated time remaining** — `~14s remaining` based on pending
   ops × average delay.
10. ⬜ **"What's coming next" preview** — `next: +3 lines at line 47`
    before each hunk.
11. ⬜ **Change-type icon** — `+`, `-`, `~`, `↪`, `↻` next to changed
    lines.
12. ⬜ **Net line-count delta** — `Δ +12 lines` in the corner, live.
13. ⬜ **"Why didn't this hunk animate?" notice** — when `--max-hunk-chars`
    skips, show `hunk 4 skipped (312 > 200)`.
14. ⬜ **Thinking pause** — auto-pause ~600ms before hunks with >30
    changed chars.
15. ⬜ **Variable typing speed (Gaussian)** — vary per-char delay using a
    normal distribution.
16. ⬜ **Indentation block-shift** — when only indent changes, shift the
    whole block as one unit with a slide animation.
17. ⬜ **Slow-motion first hunk** — run the first hunk at 0.5× speed.
18. ⬜ **Pause-after-N-lines** — auto-pause every N lines in >50-line
    hunks.
19. ⬜ **Reading time after inserts** — wait 300ms after typing a long
    inserted line (>40 chars).
20. ⬜ **Post-animation summary** — `Done. 7 hunks. +42/−28 lines. Press
    u to undo, :w to save, :q to quit.`

---

## `ad_annotate`

1. ⬜ **UTF-8 support** — currently assumes ASCII; decode multi-byte
   chars for the `# old:` / `# new:` comments.
2. ⬜ **Configurable comment prefix** — allow `//` or `--` instead of
   `#` for non-TSV formats.
3. ⬜ **Line range filter** — `--from LINE --to LINE` to annotate only
   a subset of hunks.
4. ⬜ **Diff stat header** — add `# stats: +42 -28 lines, 7 hunks` at
   the top.
5. ⬜ **Hunk numbering** — `# hunk 3/7:` before each hunk's comments.
6. ⬜ **Function context** — `# in function calculate_total()` by
   parsing nearest enclosing scope.
7. ⬜ **Color output** — optional ANSI colors for `# old:` (red) and
   `# new:` (green) when outputting to a terminal.
8. ⬜ **JSON output** — `--json` for machine-readable annotation.
9. ⬜ **Bundle size control** — `--bundle-size N` to group N ops per
   comment instead of per bundle.
10. ⬜ **Truncation control** — `--max-line-len N` (currently hardcoded
    120).
11. ⬜ **Multi-line join separator** — `--join-separator " | "` (currently
    hardcoded).
12. ⬜ **Keep comments** — currently only shows keep bundles ≥2 ops;
    add `--show-keeps` for all.
13. ⬜ **Op count per hunk** — `# hunk 3: 47 ops (12 del, 35 ins)`.
14. ⬜ **Time estimate** — `# est. 14s at default speed`.
15. ⬜ **Exclude delay ops** — `--no-delays` to skip delay ops in
   annotation.
16. ⬜ **Diff algorithm info** — `# algorithm: patience` is in header;
    add `# semantic_cleanup: on` if enabled.
17. ⬜ **File paths in header** — `# old: old.py` / `# new: new.py` at
    the top.
18. ⬜ **Timestamp** — `# generated: 2026-09-05T12:34:56`.
19. ⬜ **Version** — `# ad_annotate 1.0`.
20. ⬜ **Exit code on parse error** — currently silently ignores
    malformed ops; add `--strict` to fail.

---

## `ad_compute`

1. ⬜ **Myers algorithm option** — `--algorithm myers` as alternative
   to patience.
2. ⬜ **Histogram diff** — `--algorithm histogram` for better move
   detection.
3. ⬜ **Semantic cleanup toggle** — `--semantic-cleanup` currently
   exists; add `--no-semantic-cleanup` for explicit off.
4. ⬜ **Indent-aware diff** — `--indent-aware` to treat indent-only
   changes as keeps.
5. ⬜ **Word-level diff** — `--word-diff` to batch word runs.
6. ⬜ **Move detection** — detect line moves (cut+paste) and emit
   `move` ops instead of delete+insert.
7. ⬜ **Refactor detection** — detect renamed functions/variables and
   emit `rename` ops.
8. ⬜ **Line-level diff only** — `--line-only` to skip char-level diff.
9. ⬜ **Char-level only** — `--char-only` to skip line-level anchoring.
10. ⬜ **Progress bar** — for large files, show progress on stderr.
11. ⬜ **Memory limit** — `--max-memory N` to bail on huge files.
12. ⬜ **Multi-file input** — `ad_compute file1 file2 file3` to compute
    multiple diffs in one process.
13. ⬜ **Binary file detection** — refuse to diff binary files with a
    helpful error.
14. ⬜ **Encoding detection** — handle UTF-16, Latin-1, etc.
15. ⬜ **Line ending normalization** — `--normalize-eol` to treat
    `\r\n` and `\n` as equal.
16. ⬜ **BOM handling** — strip or preserve BOM based on flag.
17. ⬜ **Hunk count limit** — `--max-hunks N` to cap hunk count.
18. ⬜ **Hunk size limit** — `--max-hunk-size N` to split large hunks.
19. ⬜ **Output to stdout** — currently requires output file; add `-`
    for stdout.
20. ⬜ **Timing breakdown** — `--timing` shows per-stage ms (currently
    always on; add flag to disable).

---

## `ad_layer_reorder`

1. ⬜ **Configurable sweep order** — `--sweep-order inserts,deletes`
   to customize.
2. ⬜ **Per-line-type config** — different reorder rules for code vs.
   strings vs. comments.
3. ⬜ **Preserve original order flag** — `--no-reorder-newlines` to
   keep \n ops in place (currently always does).
4. ⬜ **Debug mode** — `--debug` to print sweep decisions to stderr.
5. ⬜ **Stats output** — `--stats` to print op counts before/after.
6. ⬜ **Verify mode** — `--verify` to check positions are consistent
   after reorder.
7. ⬜ **Custom segment delimiters** — treat other op types as
   boundaries.
8. ⬜ **Sort within sweep** — `--sort` to sort deletes/inserts by col.
9. ⬜ **Reverse order** — `--reverse` for testing.
10. ⬜ **Merge adjacent same-type** — `--merge` to combine consecutive
    same-type ops.
11. ⬜ **Split large segments** — `--max-segment N` to split segments
    > N ops.
12. ⬜ **Per-hunk config** — different rules per hunk.
13. ⬜ **Profile output** — `--profile` to print per-hunk timing.
14. ⬜ **Dry run** — `--dry-run` to print what would change without
    executing.
15. ⬜ **Keep original positions** — `--keep-positions` to not
    recompute (line, col).
16. ⬜ **Custom position walk** — `--walk-mode forward|reverse`.
17. ⬜ **Op count limit** — `--max-ops N` to cap output.
18. ⬜ **Filter by type** — `--only deletes` to reorder only deletes.
19. ⬜ **Filter by line** — `--only-line N` to reorder only specific
    lines.
20. ⬜ **Interactive mode** — `--interactive` to prompt for each
    reorder decision.

---

## `ad_layer_overwrite`

1. ⬜ **Configurable merge threshold** — `--min-overlap N` chars.
2. ⬜ **Max distance** — `--max-distance N` cols between delete and
   insert to merge.
3. ⬜ **Preserve order** — `--preserve-order` to not reorder before
   merging.
4. ⬜ **Debug mode** — `--debug` to print merge decisions.
5. ⬜ **Stats output** — `--stats` to print merge counts.
6. ⬜ **Custom merge type** — `--merge-type overwrite|combine|replace`.
7. ⬜ **Filter by line** — `--only-line N`.
8. ⬜ **Filter by op count** — `--min-ops N` to skip small merges.
9. ⬜ **Max merge size** — `--max-merge N` to cap merge size.
10. ⬜ **Dry run** — `--dry-run`.
11. ⬜ **Profile** — `--profile` per-hunk timing.
12. ⬜ **Verify** — `--verify` positions after merge.
13. ⬜ **Reverse mode** — `--reverse` to split overwrite_insert back
    to delete+insert.
14. ⬜ **Custom char mapping** — `--map 'A->B'` to replace during
    merge.
15. ⬜ **Case insensitive** — `--ignore-case` to merge case variants.
16. ⬜ **Whitespace normalize** — `--normalize-whitespace` before
    merge.
17. ⬜ **Unicode aware** — handle multi-byte chars correctly.
18. ⬜ **Line context** — `--context N` to show surrounding lines in
    debug.
19. ⬜ **Op type filter** — `--only delete+insert` or `--only
    overwrite_insert`.
20. ⬜ **Interactive** — `--interactive` to prompt for each merge.

---

## `ad_layer_indent_last`

1. ⬜ **Configurable whitespace chars** — `--whitespace " \t"`.
2. ⬜ **Min indent** — `--min-indent N` to skip small indents.
3. ⬜ **Max indent** — `--max-indent N` to cap indent size.
4. ⬜ **Debug mode** — `--debug`.
5. ⬜ **Stats** — `--stats` indent move counts.
6. ⬜ **Dry run** — `--dry-run`.
7. ⬜ **Profile** — `--profile`.
8. ⬜ **Verify** — `--verify`.
9. ⬜ **Filter by line** — `--only-line N`.
10. ⬜ **Custom order** — `--order first|last|middle`.
11. ⬜ **Preserve trailing** — `--preserve-trailing` to not move
    trailing whitespace.
12. ⬜ **Tab handling** — `--tab-mode keep|expand|collapse`.
13. ⬜ **Mixed indent** — `--mixed-mode keep|normalize`.
14. ⬜ **Line ending** — `--eol-mode keep|normalize`.
15. ⬜ **BOM** — `--bom-mode keep|strip`.
16. ⬜ **Encoding** — `--encoding utf-8|latin-1`.
17. ⬜ **Max ops** — `--max-ops N`.
18. ⬜ **Reverse** — `--reverse` to undo (move indent to front).
19. ⬜ **Interactive** — `--interactive`.
20. ⬜ **Custom rules** — `--rules FILE` for per-filetype config.

---

## `ad_layer_line_delete_in_place`

1. ⬜ **Configurable delete pattern** — `--pattern delete-then-join`.
2. ⬜ **Min line length** — `--min-len N` to skip short lines.
3. ⬜ **Max line count** — `--max-lines N` to cap joined lines.
4. ⬜ **Debug mode** — `--debug`.
5. ⬜ **Stats** — `--stats`.
6. ⬜ **Dry run** — `--dry-run`.
7. ⬜ **Profile** — `--profile`.
8. ⬜ **Verify** — `--verify`.
9. ⬜ **Filter by line** — `--only-line N`.
10. ⬜ **Reverse** — `--reverse`.
11. ⬜ **Custom join order** — `--join-order top|bottom`.
12. ⬜ **Preserve blank lines** — `--preserve-blanks`.
13. ⬜ **Trim whitespace** — `--trim` before join.
14. ⬜ **Max join size** — `--max-join N`.
15. ⬜ **Interactive** — `--interactive`.
16. ⬜ **Op type filter** — `--only delete|insert`.
17. ⬜ **Line type filter** — `--only code|comment|string`.
18. ⬜ **Context** — `--context N` for debug.
19. ⬜ **Unicode** — handle multi-byte.
20. ⬜ **Encoding** — `--encoding`.

---

## `ad_layer_skip_indent`

1. ⬜ **Configurable skip threshold** — `--min-indent-chars N`.
2. ⬜ **Skip mode** — `--skip-mode instant|delay|flash`.
3. ⬜ **Pause duration** — `--pause-ms N` (exists as
   `--pause-after-ms`).
4. ⬜ **Debug mode** — `--debug`.
5. ⬜ **Stats** — `--stats` skip counts.
6. ⬜ **Dry run** — `--dry-run`.
7. ⬜ **Profile** — `--profile`.
8. ⬜ **Verify** — `--verify`.
9. ⬜ **Filter by line** — `--only-line N`.
10. ⬜ **Reverse** — `--reverse` (don't skip).
11. ⬜ **Custom skip pattern** — `--pattern FILE`.
12. ⬜ **Skip blanks** — `--skip-blanks` to skip blank-only changes.
13. ⬜ **Skip comments** — `--skip-comments`.
14. ⬜ **Skip strings** — `--skip-strings`.
15. ⬜ **Max skip size** — `--max-skip N`.
16. ⬜ **Interactive** — `--interactive`.
17. ⬜ **Log skipped** — `--log-skipped FILE`.
18. ⬜ **Report** — `--report` to print what was skipped.
19. ⬜ **Unicode** — handle multi-byte whitespace.
20. ⬜ **Encoding** — `--encoding`.

---

## `ad_layer_pace`

1. ⬜ **Variable typing speed (Gaussian)** — already has
   `--gaussian-jitter-pct`; add `--gaussian-mean` and
   `--gaussian-stddev`.
2. ⬜ **Per-hunk-type pacing** — different delays for insert-heavy vs.
   delete-heavy hunks.
3. ⬜ **Distance-based speed** — exists; add `--distance-mode
   linear|exponential|step`.
4. ⬜ **Reading time** — `--reading-time-ms N` after long inserts.
5. ⬜ **Thinking pause** — `--thinking-pause-ms N` before complex
   hunks.
6. ⬜ **Slow-motion first hunk** — `--first-hunk-mult 0.5`.
7. ⬜ **Pause-after-N-lines** — exists; add `--pause-after-mode
   hard|soft`.
8. ⬜ **Accelerated deletion** — exists; add `--accel-curve
   linear|exponential|ease-in-out`.
9. ⬜ **Block delete** — exists; add `--block-mode fixed|adaptive`.
10. ⬜ **Flash mode** — exists; add `--flash-color` option.
11. ⬜ **Cursor glide** — exists; add `--glide-curve
   linear|ease|bounce`.
12. ⬜ **Custom delay table** — `--delay-table FILE` for per-op-type
    delays.
13. ⬜ **Min/max delay** — `--min-delay-ms` / `--max-delay-ms`.
14. ⬜ **Jitter mode** — `--jitter gaussian|uniform|none`.
15. ⬜ **Hunk pause** — `--hunk-pause-ms N`.
16. ⬜ **Word pause** — `--word-pause-ms N`.
17. ⬜ **Sentence pause** — `--sentence-pause-ms N` (pause after `.`).
18. ⬜ **Paragraph pause** — `--paragraph-pause-ms N` (pause after
    blank line).
19. ⬜ **Debug** — `--debug` to print delay decisions.
20. ⬜ **Profile** — `--profile` per-op-type timing.

---

## `ad_layer_highlight`

1. ⬜ **Inline char highlight** — `--highlight inline` exists; add
   per-char color control.
2. ⬜ **Word highlight** — `--highlight word` exists; add
   `--word-boundary mode`.
3. ⬜ **Hunk highlight** — `--highlight hunk` exists; add
   `--hunk-color`.
4. ⬜ **Dim unchanged** — exists; add `--dim-mode static|gradient`.
5. ⬜ **Fold unchanged** — exists; add `--fold-mode all|context`.
6. ⬜ **Sign column** — exists; add `--sign-char` custom char.
7. ⬜ **Git blame** — exists; add `--blame-format`.
8. ⬜ **Context lines** — exists; add `--context-mode
   fixed|adaptive`.
9. ⬜ **Theme** — exists; add `--theme-custom FILE`.
10. ⬜ **Max hunk chars** — exists; add `--max-hunk-mode skip|flash`.
11. ⬜ **Color map** — `--colormap-old` / `--colormap-new` exist; add
    `--colormap-mode`.
12. ⬜ **Highlight duration** — exists; add per-type duration.
13. ⬜ **Debug** — `--debug`.
14. ⬜ **Profile** — `--profile`.
15. ⬜ **Verify** — `--verify`.
16. ⬜ **Dry run** — `--dry-run`.
17. ⬜ **Stats** — `--stats`.
18. ⬜ **Filter by line** — `--only-line N`.
19. ⬜ **Filter by type** — `--only insert|delete`.
20. ⬜ **Interactive** — `--interactive`.

---

## `ad_vim`

1. ⬜ **Side-by-side old/new view** — `--vsplit` to show both files.
2. ⬜ **Goal line preview** — dimmed preview of inserted line before
   typing.
3. ⬜ **Jump to hunk** — `:DiffvimHunk 5`.
4. ⬜ **Bookmark hunk** — `m` marks, `` ` `` returns.
5. ⬜ **Replay last hunk slowly** — `r` rewinds and replays at 0.5×.
6. ⬜ **Pan/zoom viewport** — `<C-Up>`/`<C-Down>` scroll without
   moving cursor.
7. ⬜ **Diff lens overlay** — `L` pops up magnified char-diff of
   current line.
8. ⬜ **Semantic hunk grouping** — bracket in sign column for hunks
   in same function.
9. ⬜ **Syntax-aware token boundaries** — Tree-sitter to never split
   tokens.
10. ⬜ **Indent guides** — faint vertical guides during animation.
11. ⬜ **Color new file by change-type** — green=inserted,
    yellow=modified.
12. ⬜ **Diff heat-map sidebar** — 1-column sidebar colored by change
    density.
13. ⬜ **Post-animation summary** — `Done. 7 hunks. +42/−28.`.
14. ⬜ **Plain-English hunk description** — `Hunk 3/7: replaced 1
    line in hello()`.
15. ⬜ **Estimated time remaining** — `~14s remaining`.
16. ⬜ **"What's coming next" preview** — `next: +3 lines at line 47`.
17. ⬜ **Change-type icon** — `+`, `-`, `~` next to lines.
18. ⬜ **Net line-count delta** — `Δ +12 lines` live.
19. ⬜ **"Why didn't this hunk animate?" notice** — when
    `--max-hunk-chars` skips.
20. ⬜ **Thinking pause before complex hunks** — auto-pause ~600ms
    for >30 char hunks.

---

## `ad_pipeline`

1. ⬜ **Parallel compute** — run `ad_compute` in parallel with vim
   startup.
2. ⬜ **Progress reporting** — `--progress` to show stage completion.
3. ⬜ **Stage timing** — `--timing` to print per-stage ms.
4. ⬜ **Cache** — cache compute results for repeated runs.
5. ⬜ **Resume** — `--resume` to continue from a interrupted run.
6. ⬜ **Multi-file** — `--multi` to process multiple file pairs.
7. ⬜ **Dry run** — `--dry-run` to print stages without executing.
8. ⬜ **Config file** — `--config FILE` for pipeline options.
9. ⬜ **Layer profiles** — `--profile NAME` to select layer chain.
10. ⬜ **Output format** — `--output-format tsv|json|binary`.
11. ⬜ **Input format** — `--input-format tsv|json|binary`.
12. ⬜ **Compression** — `--compress` for large op streams.
13. ⬜ **Streaming** — `--stream` for real-time animation.
14. ⬜ **Checkpoint** — `--checkpoint FILE` to save state.
15. ⬜ **Replay** — `--replay FILE` to replay from checkpoint.
16. ⬜ **Debug** — `--debug` to print all stage I/O.
17. ⬜ **Verify** — `--verify` to check final output matches new file.
18. ⬜ **Stats** — `--stats` to print op counts per stage.
19. ⬜ **Filter** — `--filter EXPR` to select ops.
20. ⬜ **Transform** — `--transform EXPR` to modify ops.

---

## `ad_postprocess`

1. ⬜ **Layer manifest** — `--manifest FILE` for layer chain config.
2. ⬜ **Layer groups** — `--group NAME` to select predefined chain.
3. ⬜ **Layer dependencies** — declare that layer B requires layer A.
4. ⬜ **Layer ordering** — `--order FILE` to specify chain order.
5. ⬜ **Layer versioning** — `--version-check` to verify layer
   compatibility.
6. ⬜ **Layer discovery** — `--list-layers` exists; add
   `--list-layers-json`.
7. ⬜ **Layer dry run** — `--dry-run` exists; add `--dry-run-json`.
8. ⬜ **Layer profile** — `--profile` exists; add per-hunk timing.
9. ⬜ **Layer keep temps** — exists; add `--keep-temps-dir`.
10. ⬜ **Layer args** — `--ad-layer-arg` exists; add `--ad-layer-arg-file`.
11. ⬜ **Layer path** — `--ad-layer-path` exists; add
    `--ad-layer-path-recursive`.
12. ⬜ **Layer cache** — cache layer output for repeated runs.
13. ⬜ **Layer parallel** — run independent layers in parallel.
14. ⬜ **Layer timeout** — `--timeout N` per layer.
15. ⬜ **Layer retries** — `--retries N` on failure.
16. ⬜ **Layer fallback** — `--fallback NAME` if primary layer fails.
17. ⬜ **Layer verify** — `--verify` to check output consistency.
18. ⬜ **Layer stats** — `--stats` op counts per layer.
19. ⬜ **Layer debug** — `--debug` to print layer I/O.
20. ⬜ **Layer interactive** — `--interactive` to prompt per layer.

---

## `ad_session`

1. ⬜ **Session templates** — `--template NAME` for predefined
   layouts.
2. ⬜ **Session sharing** — `--share` to export session for others.
3. ⬜ **Session diff** — `--diff SESSION1 SESSION2` to compare.
4. ⬜ **Session merge** — `--merge SESSION1 SESSION2` to combine.
5. ⬜ **Session history** — `--history` to show session timeline.
6. ⬜ **Session bookmark** — `--bookmark` to save state.
7. ⬜ **Session restore** — `--restore` to recover crashed session.
8. ⬜ **Session export** — `--export FORMAT` (json, html, pdf).
9. ⬜ **Session import** — `--import FILE` to load external.
10. ⬜ **Session annotate** — `--annotate` exists; add per-op notes.
11. ⬜ **Session search** — `--search TEXT` to find ops.
12. ⬜ **Session filter** — `--filter EXPR` to show subset.
13. ⬜ **Session sort** — `--sort KEY` to reorder ops.
14. ⬜ **Session count** — `--count` to print op stats.
15. ⬜ **Session verify** — `--verify` to check consistency.
16. ⬜ **Session clean** — `--clean` to remove old sessions.
17. ⬜ **Session list** — `--list-sessions` exists; add
    `--list-sessions-json`.
18. ⬜ **Session resume** — `--resume-latest` exists; add
    `--resume-by-name`.
19. ⬜ **Session profile** — `--profile` to print timing.
20. ⬜ **Session debug** — `--debug` to print internal state.

---

## `ad_tmux_watch`

1. ⬜ **Custom layout** — `--layout NAME` for pane arrangement.
2. ⬜ **Pane titles** — `--titles` to label panes.
3. ⬜ **Pane focus** — `--focus PANE` to highlight active pane.
4. ⬜ **Pane sync** — `--sync` to mirror input across panes.
5. ⬜ **Session attach** — `--attach` to join existing session.
6. ⬜ **Session detach** — `--detach` to leave session running.
7. ⬜ **Session kill** — `--kill` to stop session.
8. ⬜ **Session list** — `--list` to show running sessions.
9. ⬜ **Session save** — `--save` to snapshot state.
10. ⬜ **Session restore** — `--restore` to recover.
11. ⬜ **Auto-refresh** — `--refresh N` seconds (exists).
12. ⬜ **File watch** — `--watch FILE` to monitor changes.
13. ⬜ **Git integration** — `--git` to show blame/diff.
14. ⬜ **Syntax highlight** — `--syntax` for colored output.
15. ⬜ **Line numbers** — `--line-numbers`.
16. ⬜ **Search** — `--search TEXT`.
17. ⬜ **Filter** — `--filter EXPR`.
18. ⬜ **Export** — `--export FORMAT`.
19. ⬜ **Profile** — `--profile` timing.
20. ⬜ **Debug** — `--debug`.

---

## `ad_watch`

1. ⬜ **Multi-file watch** — `--watch file1 file2`.
2. ⬜ **Diff mode** — `--diff unified|side-by-side|word`.
3. ⬜ **Color** — `--color always|never|auto`.
4. ⬜ **Context** — `--context N` lines.
5. ⬜ **Ignore** — `--ignore PATTERN`.
6. ⬜ **Filter** — `--filter EXPR`.
7. ⬜ **Notify** — `--notify` desktop notification on change.
8. ⬜ **Sound** — `--sound` beep on change.
9. ⬜ **Log** — `--log FILE` to append changes.
10. ⬜ **Stats** — `--stats` change frequency.
11. ⬜ **Graph** — `--graph` ASCII chart of changes.
12. ⬜ **Timeline** — `--timeline` chronological view.
13. ⬜ **Snapshot** — `--snapshot FILE` to save state.
14. ⬜ **Restore** — `--restore FILE`.
15. ⬜ **Compare** — `--compare FILE1 FILE2`.
16. ⬜ **Merge** — `--merge FILE` to merge changes.
17. ⬜ **Export** — `--export FORMAT`.
18. ⬜ **Profile** — `--profile`.
19. ⬜ **Debug** — `--debug`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_gen_ops`

1. ⬜ **Multi-file** — `--multi` to generate ops for multiple pairs.
2. ⬜ **Layer chain** — `--ad-layer` exists; add `--layer-chain FILE`.
3. ⬜ **Annotate** — `--annotate` exists; add `--annotate-format`.
4. ⬜ **Output format** — `--output-format tsv|json|binary`.
5. ⬜ **Compress** — `--compress` for large ops.
6. ⬜ **Cache** — `--cache` to reuse compute.
7. ⬜ **Verify** — `--verify` to check ops produce new file.
8. ⬜ **Stats** — `--stats` op counts.
9. ⬜ **Profile** — `--profile` per-stage timing.
10. ⬜ **Debug** — `--debug` to print stage I/O.
11. ⬜ **Filter** — `--filter EXPR` to select ops.
12. ⬜ **Transform** — `--transform EXPR` to modify ops.
13. ⬜ **Sort** — `--sort KEY` to reorder.
14. ⬜ **Search** — `--search TEXT` to find ops.
15. ⬜ **Count** — `--count` to print stats.
16. ⬜ **Diff** — `--diff FILE` to compare op streams.
17. ⬜ **Merge** — `--merge FILE` to combine.
18. ⬜ **Export** — `--export FORMAT`.
19. ⬜ **Dry run** — `--dry-run`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_compare`

1. ⬜ **Output format** — `--output-format text|json|csv|html`.
2. ⬜ **Filter** — `--filter EXPR` to select option combos.
3. ⬜ **Sort** — `--sort KEY` to order results.
4. ⬜ **Limit** — `--limit N` to cap combos.
5. ⬜ **Parallel** — `--parallel N` to run combos concurrently.
6. ⬜ **Timeout** — `--timeout N` per combo.
7. ⬜ **Cache** — `--cache` to reuse results.
8. ⬜ **Verify** — `--verify` to check outputs.
9. ⬜ **Stats** — `--stats` summary.
10. ⬜ **Profile** — `--profile` per-combo timing.
11. ⬜ **Debug** — `--debug`.
12. ⬜ **Dry run** — `--dry-run` to print combos.
13. ⬜ **Export** — `--export FORMAT`.
14. ⬜ **Import** — `--import FILE` for custom combos.
15. ⬜ **Diff** — `--diff FILE` to compare runs.
16. ⬜ **Merge** — `--merge FILE`.
17. ⬜ **Search** — `--search TEXT`.
18. ⬜ **Count** — `--count`.
19. ⬜ **Help** — `--help` (exists).
20. ⬜ **Version** — `--version`.

---

## `ad_jogger`

1. ⬜ **Pattern library** — `--pattern NAME` for predefined test
   patterns.
2. ⬜ **Custom pattern** — `--pattern-file FILE`.
3. ⬜ **Random seed** — `--seed N` for reproducibility.
4. ⬜ **Size control** — `--min-size N` / `--max-size N`.
5. ⬜ **Language** — `--language python|go|rust|...` to generate
   language-specific code.
6. ⬜ **Complexity** — `--complexity simple|medium|hard`.
7. ⬜ **Mutation rate** — `--mutation-rate N`.
8. ⬜ **Output dir** — `--output DIR`.
9. ⬜ **Count** — `--count N` (exists).
10. ⬜ **Verify** — `--verify` to check generated files diff cleanly.
11. ⬜ **Stats** — `--stats` generation stats.
12. ⬜ **Profile** — `--profile`.
13. ⬜ **Debug** — `--debug`.
14. ⬜ **Dry run** — `--dry-run`.
15. ⬜ **Export** — `--export FORMAT`.
16. ⬜ **Import** — `--import FILE`.
17. ⬜ **Diff** — `--diff FILE`.
18. ⬜ **Merge** — `--merge FILE`.
19. ⬜ **Search** — `--search TEXT`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_tmux`

1. ⬜ **Session name** — `--session NAME`.
2. ⬜ **Window layout** — `--layout NAME`.
3. ⬜ **Pane sync** — `--sync`.
4. ⬜ **Detach** — `--detach`.
5. ⬜ **Attach** — `--attach`.
6. ⬜ **Kill** — `--kill`.
7. ⬜ **List** — `--list`.
8. ⬜ **Save** — `--save`.
9. ⬜ **Restore** — `--restore`.
10. ⬜ **Profile** — `--profile`.
11. ⬜ **Debug** — `--debug`.
12. ⬜ **Dry run** — `--dry-run`.
13. ⬜ **Export** — `--export`.
14. ⬜ **Import** — `--import`.
15. ⬜ **Diff** — `--diff`.
16. ⬜ **Merge** — `--merge`.
17. ⬜ **Search** — `--search`.
18. ⬜ **Filter** — `--filter`.
19. ⬜ **Stats** — `--stats`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_debug.sh`, `ad_debug_bundle.sh`, `ad_snapshot.sh`, `ad_replay.sh`, `ad_record.sh`, `ad_demo.sh`, `ad_suggest.sh`, `ad_tune.sh`, `ad_package.sh`, `ad_doc_provenance`

(20 proposals each — these are utility scripts; many proposals overlap
with the main tools. The key improvements for each are:)

### Common proposals for all utility scripts:

1. ⬜ **`--help` / `-h`** — ensure every script responds to this.
2. ⬜ **`--version` / `-V`** — print version.
3. ⬜ **`--man`** — print the manpage.
4. ⬜ **`--dry-run`** — show what would be done without executing.
5. ⬜ **`--debug`** — verbose stderr output.
6. ⬜ **`--quiet` / `-q`** — suppress non-error output.
7. ⬜ **`--verbose` / `-v`** — more detailed output.
8. ⬜ **`--json`** — machine-readable output.
9. ⬜ **`--config FILE`** — read options from file.
10. ⬜ **`--profile`** — timing breakdown.
11. ⬜ **`--stats`** — operation counts.
12. ⬜ **`--verify`** — check output correctness.
13. ⬜ **`--cache`** — cache results.
14. ⬜ **`--parallel N`** — concurrent execution.
15. ⬜ **`--timeout N`** — per-operation timeout.
16. ⬜ **`--retries N`** — retry on failure.
17. ⬜ **`--filter EXPR`** — select subset.
18. ⬜ **`--sort KEY`** — order output.
19. ⬜ **`--limit N`** — cap output size.
20. ⬜ **`--output FILE`** — write to file instead of stdout.

### Script-specific proposals:

#### `ad_debug.sh`
1. ⬜ **Interactive debugger** — step through ops one at a time.
2. ⬜ **Breakpoints** — `--break LINE` to stop at line.
3. ⬜ **Watch expressions** — `--watch EXPR` to monitor.
4. ⬜ **Call stack** — show layer chain.
5. ⬜ **Variable inspector** — show buffer state.

#### `ad_debug_bundle.sh`
1. ⬜ **Custom bundle contents** — `--include` / `--exclude`.
2. ⬜ **Compression** — `--compress`.
3. ⬜ **Encryption** — `--encrypt`.
4. ⬜ **Upload** — `--upload URL`.
5. ⬜ **Expiry** — `--expire N` days.

#### `ad_snapshot.sh`
1. ⬜ **Per-op snapshots** — one file per op.
2. ⬜ **HTML output** — browseable snapshots.
3. ⬜ **Diff between snapshots** — `--diff SNAP1 SNAP2`.
4. ⬜ **Animated GIF** — `--gif`.
5. ⬜ **Video** — `--video`.

#### `ad_replay.sh`
1. ⬜ **Speed control** — `--speed N`.
2. ⬜ **Pause/resume** — keyboard controls.
3. ⬜ **Seek** — `--seek OP_N`.
4. ⬜ **Loop** — `--loop`.
5. ⬜ **Reverse** — `--reverse`.

#### `ad_record.sh`
1. ⬜ **Format** — `--format json|binary|tsv`.
2. ⬜ **Compression** — `--compress`.
3. ⬜ **Timestamps** — `--timestamps`.
4. ⬜ **Metadata** — `--meta KEY=VALUE`.
5. ⬜ **Streaming** — `--stream`.

#### `ad_demo.sh`
1. ⬜ **Demo library** — `--list` to show available demos.
2. ⬜ **Custom demo** — `--script FILE`.
3. ⬜ **Narration** — `--narrate FILE`.
4. ⬜ **Auto-advance** — `--auto N` seconds.
5. ⬜ **Record** — `--record FILE`.

#### `ad_suggest.sh`
1. ⬜ **Fuzzy match** — improve Levenshtein.
2. ⬜ **Context-aware** — suggest based on current options.
3. ⬜ **Learn from usage** — track accepted suggestions.
4. ⬜ **Custom dictionary** — `--dict FILE`.
5. ⬜ **Min confidence** — `--min-confidence N`.

#### `ad_tune.sh`
1. ⬜ **Save/load profiles** — `--save` / `--load`.
2. ⬜ **Compare profiles** — `--diff`.
3. ⬜ **Auto-tune** — `--auto` to find optimal settings.
4. ⬜ **A/B test** — `--ab`.
5. ⬜ **Export** — `--export FORMAT`.

#### `ad_package.sh`
1. ⬜ **Format** — `--format tar|zip|deb|rpm`.
2. ⬜ **Sign** — `--sign KEY`.
3. ⬜ **Upload** — `--upload URL`.
4. ⬜ **Changelog** — `--changelog FILE`.
5. ⬜ **Version bump** — `--bump major|minor|patch`.

#### `ad_doc_provenance`
1. ⬜ **Batch mode** — `--batch` for multiple files.
2. ⬜ **Format** — `--format text|json|yaml`.
3. ⬜ **Filter** — `--filter EXPR`.
4. ⬜ **Since** — `--since DATE`.
5. ⬜ **Author** — `--author NAME`.

---

## Summary

- **30 tools** audited (10 binaries, 20 scripts).
- **600 proposals** total (20 per tool).
- Most proposals focus on: better `--help`, JSON output, profiling,
  caching, parallelism, filtering, and verification.
- The highest-impact proposals are the "followability" features for
  `ad` and `ad_vim` (inline highlight, hunk descriptions, time
  estimates, etc.) — these directly improve the user experience.
