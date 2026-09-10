# Improvement Proposals — 20 Per Tool

This document lists 20 concrete improvement proposals for each script
and binary in the `ad` toolkit. Each tool is described first (what it
does, when you use it), then the 20 proposals follow.

Status markers:
- ✅ already implemented
- ⬜ not yet implemented (proposal)
- 🔄 partially implemented / needs work

Last updated: 2026-09-09 (reflects `refactor/no-newline-in-char-ops` branch)

## Recent progress (2026-09)

- ✅ Removed `\n` from char ops — line boundaries are now explicit
  `keep_line`/`join_lines`/`split_line` ops
- ✅ Animators are dumb buffers — no position computation
- ✅ `ad_layer_overwrite`: 28/42 → 42/42 (removed position recomputation)
- ✅ `ad_layer_line_delete_in_place`: now works (42/42), two modes
  (`--mode batch` / `--mode interleaved`)
- ✅ L1/L2 redesigned: applies ops hunk by hunk, reports which hunk
  failed (`L2_HUNK`)
- ✅ `ad_anim_test`: snapshot-based animation testing tool
- 🔄 `ad_layer_line_replace`: 1/42 (needs rewrite)
- 🔄 `ad_layer_skip_indent`: 40/42 (2 failures on large examples)
- ⬜ Perl twins not yet updated for new op types

---

## `ad` (C animator)

**What it is:** The C animator (`bin/ad`). Reads a timed op stream from
stdin, applies each op to a virtual buffer (loaded from the old file),
and renders the animation to the terminal. Supports `--no-display`
(headless mode for testing), `--snapshot` (write final buffer to file),
`--speed`, scrolling, colormaps, and keyboard controls (pause, skip
hunk, speed up/down). The animator is a dumb buffer — it has no seek
primitive. Per-op checkpoint testing is done by injecting `snapshot`
ops into the stream, not by re-running the animator at a seek position.

**When you use it:** Headless testing (`--no-display --snapshot`),
CI pipelines, `ad_pipeline` (which calls it internally), and
`ad_anim_test` (which injects `snapshot` ops for per-op checkpoint
testing).

1. ⬜ **Inline char highlight** — paint each freshly-typed char green for
   200ms, each freshly-deleted char red for 200ms, using ANSI escape
   codes.
2. ⬜ **Ghost text for deletions** — show deleted text as struck-through
   overlay for 400ms before it disappears.
3. ⬜ **Cursor trail** — leave a fading trail behind the cursor for
   ~300ms after each move.
4. ⬜ **"Just changed" line tint** — briefly tint the entire line subtle
   yellow for 500ms after any char op lands on it.
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
13. ⬜ **"Why didn't this hunk animate?" notice** — when
    `--max-hunk-chars` skips, show `hunk 4 skipped (312 > 200)`.
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

**What it is:** A C tool (`bin/ad_annotate`) that reads ops from stdin
and adds `# old:` / `# new:` / `# keep:` context comments before each
hunk or bundle of ops. The comments show the text content before and
after the change, making the op stream readable by humans.

**When you use it:** When you want to understand what an op stream does
without watching the animation. Used by `ad_gen_ops --annotate` and
`ad_session --annotate`. Also useful for debugging — the comments show
exactly what text each hunk modifies.

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
   comment.
10. ⬜ **Truncation control** — `--max-line-len N` (currently hardcoded
    120).
11. ⬜ **Multi-line join separator** — `--join-separator " | "`.
12. ⬜ **Keep comments** — `--show-keeps` for all keep bundles.
13. ⬜ **Op count per hunk** — `# hunk 3: 47 ops (12 del, 35 ins)`.
14. ⬜ **Time estimate** — `# est. 14s at default speed`.
15. ⬜ **Exclude delay ops** — `--no-delays` to skip delay ops.
16. ⬜ **Diff algorithm info** — `# algorithm: patience`.
17. ⬜ **File paths in header** — `# old: old.py` / `# new: new.py`.
18. ⬜ **Timestamp** — `# generated: 2026-09-05T12:34:56`.
19. ⬜ **Version** — `# ad_annotate 1.0`.
20. ⬜ **Exit code on parse error** — `--strict` to fail on malformed
    ops.

---

## `ad_compute`

**What it is:** The diff engine (`bin/ad_compute`). Reads two files,
runs a patience line-level diff, then a char-level diff (anchored LCS
on concatenated lines). Produces a TSV op stream with `HUNK` headers
and `keep`/`delete`/`insert`/`keep_line`/`join_lines`/`split_line` ops,
each with `(line, col)` positions.

**When you use it:** Called internally by `ad_vim` and `ad_pipeline`.
Can also be run standalone to produce raw ops: `ad_compute old.py new.py
ops.tsv`. Use the ops with `ad --precomputed ops.tsv old.py` or inspect
them directly.

1. ⬜ **Myers algorithm option** — `--algorithm myers` as alternative.
2. ⬜ **Histogram diff** — `--algorithm histogram` for better move
   detection.
3. ⬜ **Semantic cleanup toggle** — `--semantic-cleanup` exists; add
   `--no-semantic-cleanup`.
4. ⬜ **Indent-aware diff** — `--indent-aware` to treat indent-only
   changes as keeps.
5. ⬜ **Word-level diff** — `--word-diff` to batch word runs.
6. ⬜ **Move detection** — detect line moves and emit `move` ops.
7. ⬜ **Refactor detection** — detect renamed functions/variables.
8. ⬜ **Line-level diff only** — `--line-only` to skip char-level diff.
9. ⬜ **Char-level only** — `--char-only` to skip line-level anchoring.
10. ⬜ **Progress bar** — for large files, show progress on stderr.
11. ⬜ **Memory limit** — `--max-memory N` to bail on huge files.
12. ⬜ **Multi-file input** — `ad_compute file1 file2 file3`.
13. ⬜ **Binary file detection** — refuse to diff binary files.
14. ⬜ **Encoding detection** — handle UTF-16, Latin-1.
15. ⬜ **Line ending normalization** — `--normalize-eol`.
16. ⬜ **BOM handling** — strip or preserve BOM.
17. ⬜ **Hunk count limit** — `--max-hunks N`.
18. ⬜ **Hunk size limit** — `--max-hunk-size N` to split large hunks.
19. ⬜ **Output to stdout** — `-` for stdout.
20. ⬜ **Timing breakdown** — `--timing` shows per-stage ms (currently
    always on; add flag to disable).

---

## `ad_layer_reorder`

**What it is:** A C layer (`bin/ad_layer_reorder`) that reorders char
ops within each line segment — emits all deletes first, then all
inserts, then keeps. Boundaries (keeps, `keep_line`, `join_lines`,
`split_line`) stay in place. This makes the animation look cleaner:
deletions happen first, then insertions, instead of interleaved.

**When you use it:** Almost always — it's the default layer in
`ad_session` and most examples. Without it, the diff engine's
interleaved delete/insert/keep ops produce a jumpy animation.

1. ⬜ **Configurable sweep order** — `--sweep-order inserts,deletes`.
2. ⬜ **Per-line-type config** — different rules for code vs strings.
3. ⬜ **Debug mode** — `--debug` to print sweep decisions.
4. ⬜ **Stats output** — `--stats` to print op counts before/after.
5. ⬜ **Verify mode** — `--verify` to check positions after reorder.
6. ⬜ **Custom segment delimiters** — treat other op types as
   boundaries.
7. ⬜ **Sort within sweep** — `--sort` to sort deletes/inserts by col.
8. ⬜ **Reverse order** — `--reverse` for testing.
9. ⬜ **Merge adjacent same-type** — `--merge`.
10. ⬜ **Split large segments** — `--max-segment N`.
11. ⬜ **Per-hunk config** — different rules per hunk.
12. ⬜ **Profile output** — `--profile` to print per-hunk timing.
13. ⬜ **Dry run** — `--dry-run`.
14. ⬜ **Keep original positions** — `--keep-positions`.
15. ⬜ **Custom position walk** — `--walk-mode forward|reverse`.
16. ⬜ **Op count limit** — `--max-ops N`.
17. ⬜ **Filter by type** — `--only deletes`.
18. ⬜ **Filter by line** — `--only-line N`.
19. ⬜ **Interactive mode** — `--interactive`.
20. ⬜ **AWK implementation** — port to awk for systems without C
   compiler.

---

## `ad_layer_overwrite`

**What it is:** A C layer (`bin/ad_layer_overwrite`) that detects
adjacent `delete` + `insert` at the same `(line, col)` and merges them
into a single `overwrite_insert` op. This produces in-place replacement
instead of delete-then-insert, which looks cleaner for single-char
changes.

**When you use it:** When you want char replacements to look like
in-place overwrites rather than delete-then-type. Useful for
refactoring animations where many chars are replaced at the same
position.

1. ⬜ **Configurable merge threshold** — `--min-overlap N`.
2. ⬜ **Max distance** — `--max-distance N` cols between delete and
   insert.
3. ⬜ **Debug mode** — `--debug`.
4. ⬜ **Stats** — `--stats`.
5. ⬜ **Custom merge type** — `--merge-type overwrite|combine|replace`.
6. ⬜ **Filter by line** — `--only-line N`.
7. ⬜ **Filter by op count** — `--min-ops N`.
8. ⬜ **Max merge size** — `--max-merge N`.
9. ⬜ **Dry run** — `--dry-run`.
10. ⬜ **Profile** — `--profile`.
11. ⬜ **Verify** — `--verify`.
12. ⬜ **Reverse mode** — `--reverse` to split overwrite_insert back.
13. ⬜ **Custom char mapping** — `--map 'A->B'`.
14. ⬜ **Case insensitive** — `--ignore-case`.
15. ⬜ **Whitespace normalize** — `--normalize-whitespace`.
16. ⬜ **Unicode aware** — handle multi-byte chars.
17. ⬜ **Line context** — `--context N` for debug.
18. ⬜ **Op type filter** — `--only delete+insert`.
19. ⬜ **Interactive** — `--interactive`.
20. ⬜ **AWK implementation**.

---

## `ad_layer_indent_last`

**What it is:** A C layer (`bin/ad_layer_indent_last`) that moves
leading whitespace deletes to AFTER content deletes on the same line.
Without it, deleting indent first makes the line shift left before its
content disappears, which looks visually wrong. With it, content
disappears first, then the indent shrinks — a cleaner shrink-to-empty
effect.

**When you use it:** When animating code where indentation changes
(e.g., a block is un-indented or removed). Especially useful for
Python/YAML where indentation is semantic.

1. ⬜ **Configurable whitespace chars** — `--whitespace " \t"`.
2. ⬜ **Min indent** — `--min-indent N`.
3. ⬜ **Max indent** — `--max-indent N`.
4. ⬜ **Debug mode** — `--debug`.
5. ⬜ **Stats** — `--stats`.
6. ⬜ **Dry run** — `--dry-run`.
7. ⬜ **Profile** — `--profile`.
8. ⬜ **Verify** — `--verify`.
9. ⬜ **Filter by line** — `--only-line N`.
10. ⬜ **Custom order** — `--order first|last|middle`.
11. ⬜ **Preserve trailing** — `--preserve-trailing`.
12. ⬜ **Tab handling** — `--tab-mode keep|expand|collapse`.
13. ⬜ **Mixed indent** — `--mixed-mode keep|normalize`.
14. ⬜ **Line ending** — `--eol-mode keep|normalize`.
15. ⬜ **BOM** — `--bom-mode keep|strip`.
16. ⬜ **Encoding** — `--encoding utf-8|latin-1`.
17. ⬜ **Max ops** — `--max-ops N`.
18. ⬜ **Reverse** — `--reverse`.
19. ⬜ **Interactive** — `--interactive`.
20. ⬜ **Custom rules** — `--rules FILE` for per-filetype config.

---

## `ad_layer_line_delete_in_place`

**What it is:** A C layer (`bin/ad_layer_line_delete_in_place`) that
reorders ops so content is deleted BEFORE lines are joined. When the
diff engine deletes multiple consecutive lines, it produces
`delete(chars) → join_lines → delete(chars) → join_lines`. The
`join_lines` pulls the next line's content up before it's deleted,
causing visual jumping. This layer reorders to
`delete(chars) → delete(chars at original line) → join → join`,
so content disappears in place.

**Two modes** (switchable via `--mode batch|interleaved`):
- **batch** (default): delete all content first, then join all empty
  lines. Fewer visual jumps.
- **interleaved**: pass-through (diff engine's natural output). Delete
  content → join → delete next → join. Each line disappears completely
  before the next is touched.

**Also available in:** AWK (`layers/awk/`), Bash (`layers/bash/`),
Perl (`layers/perl/`).

**When you use it:** When animating the deletion of multiple
consecutive lines (e.g., a function is removed, a block is deleted).

1. ✅ **--mode batch** — delete all content first, then join all.
2. ✅ **--mode interleaved** — pass-through, each line deleted then
   joined immediately.
3. ✅ **Col 1 check** — only matches full-line deletions (col 1),
   leaves partial content unchanged.
4. ✅ **C implementation** — `layers/c/ad_layer_line_delete_in_place.c`.
5. ✅ **AWK implementation** — `layers/awk/ad_layer_line_delete_in_place.awk`.
6. ✅ **Bash implementation** — `layers/bash/ad_layer_line_delete_in_place.sh`
   (pipeline of grep + awk).
7. ✅ **Perl implementation** — `layers/perl/ad_layer_line_delete_in_place.pl`.
8. ⬜ **--mode adaptive** — choose batch or interleaved based on hunk
   size.
9. ⬜ **Debug mode** — `--debug` to print pattern matches.
10. ⬜ **Stats** — `--stats` to print reorder counts.
11. ⬜ **Dry run** — `--dry-run`.
12. ⬜ **Profile** — `--profile` per-hunk timing.
13. ⬜ **Verify** — `--verify` positions after reorder.
14. ⬜ **Filter by line** — `--only-line N`.
15. ⬜ **Custom col threshold** — `--col-threshold N` (currently col 1
    only).
16. ⬜ **Reverse** — `--reverse` to undo (move content back after join).
17. ⬜ **Max reorders** — `--max-reorders N` to cap.
18. ⬜ **Interactive** — `--interactive` to prompt for each reorder.
19. ⬜ **Log reorders** — `--log FILE` to record what was reordered.
20. ⬜ **Report** — `--report` to print what was reordered.

---

## `ad_layer_skip_indent`

**What it is:** A C layer (`bin/ad_layer_skip_indent`) that detects
indent-only hunks (all changes are whitespace) and wraps them with
delay markers so the pace layer applies them instantly (no animation).
The ops are still applied — only the timing/animation is skipped.

**When you use it:** When you have large indentation changes (e.g.,
a block is re-indented) and don't want to watch every space/tab being
deleted and re-inserted.

1. ⬜ **Configurable skip threshold** — `--min-indent-chars N`.
2. ⬜ **Skip mode** — `--skip-mode instant|delay|flash`.
3. ⬜ **Debug mode** — `--debug`.
4. ⬜ **Stats** — `--stats`.
5. ⬜ **Dry run** — `--dry-run`.
6. ⬜ **Profile** — `--profile`.
7. ⬜ **Verify** — `--verify`.
8. ⬜ **Filter by line** — `--only-line N`.
9. ⬜ **Custom skip pattern** — `--pattern FILE`.
10. ⬜ **Skip blanks** — `--skip-blanks`.
11. ⬜ **Skip comments** — `--skip-comments`.
12. ⬜ **Skip strings** — `--skip-strings`.
13. ⬜ **Max skip size** — `--max-skip N`.
14. ⬜ **Interactive** — `--interactive`.
15. ⬜ **Log skipped** — `--log-skipped FILE`.
16. ⬜ **Report** — `--report`.
17. ⬜ **Unicode** — handle multi-byte whitespace.
18. ⬜ **Encoding** — `--encoding`.
19. ⬜ **AWK implementation**.
20. ⬜ **Fix 2 failing large examples** (35_large_perl, 38_large_java).

---

## `ad_layer_pace`

**What it is:** A C layer (`bin/ad_layer_pace`) that inserts `delay`
ops between content ops to control animation timing. Supports multiple
pacing modes (uniform, adaptive, gaussian, review), delete/insert
pacing strategies (char, word, accel, instant, flash), cursor glide,
distance-based speed, pause-after-N-lines, and block deletion.

**When you use it:** Almost always — it's the default timing layer.
Without it, the animator applies ops at full speed with no delays,
producing a blur. The pace layer adds the "human typing" feel.

1. ⬜ **Variable typing speed (Gaussian)** — `--gaussian-mean`,
   `--gaussian-stddev`.
2. ⬜ **Per-hunk-type pacing** — different delays for insert-heavy vs
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
10. ⬜ **Flash mode** — exists; add `--flash-color`.
11. ⬜ **Cursor glide** — exists; add `--glide-curve
    linear|ease|bounce`.
12. ⬜ **Custom delay table** — `--delay-table FILE`.
13. ⬜ **Min/max delay** — `--min-delay-ms` / `--max-delay-ms`.
14. ⬜ **Jitter mode** — `--jitter gaussian|uniform|none`.
15. ⬜ **Hunk pause** — `--hunk-pause-ms N`.
16. ⬜ **Word pause** — `--word-pause-ms N`.
17. ⬜ **Sentence pause** — `--sentence-pause-ms N` (after `.`).
18. ⬜ **Paragraph pause** — `--paragraph-pause-ms N`.
19. ⬜ **Debug** — `--debug`.
20. ⬜ **Profile** — `--profile` per-op-type timing.

---

## `ad_layer_highlight`

**What it is:** A C layer (`bin/ad_layer_highlight`) that inserts
decoration ops (`highlight`, `dim`, `fold`, `sign`) into the op stream.
These ops tell the animator to highlight changed regions, dim unchanged
lines, fold long unchanged runs, and show +/- signs in the sign column.

**When you use it:** When you want visual emphasis during animation —
highlighting what's changing, dimming what's not, folding context.
Activated via `--highlight`, `--dim-unchanged`, `--fold-unchanged`,
`--sign-column`, `--git-blame` flags on `ad_vim`.

1. ⬜ **Inline char highlight** — `--highlight inline` exists; add
   per-char color control.
2. ⬜ **Word highlight** — `--highlight word` exists; add
   `--word-boundary mode`.
3. ⬜ **Hunk highlight** — `--highlight hunk` exists; add `--hunk-color`.
4. ⬜ **Dim unchanged** — exists; add `--dim-mode static|gradient`.
5. ⬜ **Fold unchanged** — exists; add `--fold-mode all|context`.
6. ⬜ **Sign column** — exists; add `--sign-char`.
7. ⬜ **Git blame** — exists; add `--blame-format`.
8. ⬜ **Context lines** — exists; add `--context-mode fixed|adaptive`.
9. ⬜ **Theme** — exists; add `--theme-custom FILE`.
10. ⬜ **Max hunk chars** — exists; add `--max-hunk-mode skip|flash`.
11. ⬜ **Color map** — exists; add `--colormap-mode`.
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

**What it is:** The main entry point (`apps/vim/ad_vim`). A bash
launcher that runs the full pipeline (compute → postprocess → pace →
animate) and opens vim with the animation engine. Supports `--speed`,
`--output`, `--context`, `--multi`, `--replay`, `--git-rev`,
`--git-blame`, `--annotate`, `--preset`, layer chaining via
`--ad-layer`, and keyboard controls during animation (Space=pause,
n=skip hunk, q=quit, +=faster).

**When you use it:** This is the primary tool users run. It's the
"watch your code changes come to life" command.

1. ⬜ **Side-by-side old/new view** — `--vsplit`.
2. ⬜ **Goal line preview** — dimmed preview of inserted line.
3. ⬜ **Jump to hunk** — `:DiffvimHunk 5`.
4. ⬜ **Bookmark hunk** — `m` marks, `` ` `` returns.
5. ⬜ **Replay last hunk slowly** — `r`.
6. ⬜ **Pan/zoom viewport** — `<C-Up>`/`<C-Down>`.
7. ⬜ **Diff lens overlay** — `L`.
8. ⬜ **Semantic hunk grouping** — bracket in sign column.
9. ⬜ **Syntax-aware token boundaries** — Tree-sitter.
10. ⬜ **Indent guides** — faint vertical guides.
11. ⬜ **Color new file by change-type**.
12. ⬜ **Diff heat-map sidebar**.
13. ⬜ **Post-animation summary**.
14. ⬜ **Plain-English hunk description**.
15. ⬜ **Estimated time remaining**.
16. ⬜ **"What's coming next" preview**.
17. ⬜ **Change-type icon**.
18. ⬜ **Net line-count delta**.
19. ⬜ **"Why didn't this hunk animate?" notice**.
20. ⬜ **Thinking pause before complex hunks**.

---

## `ad_pipeline`

**What it is:** The headless pipeline driver (`pipeline/ad_pipeline`).
Runs the full pipeline (compute → postprocess → pace → animate) without
vim. Routes options by prefix (`--compute-*`, `--postprocess-*`,
`--pace-*`, `--animator-*`). Used for testing, CI, and when you just
want the output without animation.

**When you use it:** Testing (`make test-examples`), CI pipelines, and
headless verification. Also used internally by `ad_l1l2` and
`ad_anim_test`.

1. ⬜ **Parallel compute** — run `ad_compute` in parallel with vim
   startup.
2. ⬜ **Progress reporting** — `--progress`.
3. ⬜ **Stage timing** — `--timing`.
4. ⬜ **Cache** — cache compute results.
5. ⬜ **Resume** — `--resume`.
6. ⬜ **Multi-file** — `--multi`.
7. ⬜ **Dry run** — `--dry-run`.
8. ⬜ **Config file** — `--config FILE`.
9. ⬜ **Layer profiles** — `--profile NAME`.
10. ⬜ **Output format** — `--output-format tsv|json|binary`.
11. ⬜ **Input format** — `--input-format`.
12. ⬜ **Compression** — `--compress`.
13. ⬜ **Streaming** — `--stream`.
14. ⬜ **Checkpoint** — `--checkpoint FILE`.
15. ⬜ **Replay** — `--replay FILE`.
16. ⬜ **Debug** — `--debug`.
17. ⬜ **Verify** — `--verify`.
18. ⬜ **Stats** — `--stats`.
19. ⬜ **Filter** — `--filter EXPR`.
20. ⬜ **Transform** — `--transform EXPR`.

---

## `ad_postprocess`

**What it is:** The layer orchestrator (`pipeline/ad_postprocess`).
Reads TSV from stdin, chains layer plugins (one per `--ad-layer` flag,
in argv order), writes TSV to stdout. Supports `--ad-layer-arg` for
per-layer options, `--ad-layer-path` for search paths,
`--ad-layer-keep-temps` for debugging, `--list-layers` for discovery,
and `--ad-layer-dry-run` for previewing the chain.

**When you use it:** Called internally by `ad_vim` and `ad_pipeline`.
Can also be run standalone to process ops: `ad_postprocess
--ad-layer=ad_layer_reorder < raw.tsv > post.tsv`.

1. ⬜ **Layer manifest** — `--manifest FILE`.
2. ⬜ **Layer groups** — `--group NAME`.
3. ⬜ **Layer dependencies** — declare that layer B requires A.
4. ⬜ **Layer ordering** — `--order FILE`.
5. ⬜ **Layer versioning** — `--version-check`.
6. ⬜ **Layer discovery** — `--list-layers` exists; add `--list-json`.
7. ⬜ **Layer dry run** — exists; add `--dry-run-json`.
8. ⬜ **Layer profile** — exists; add per-hunk timing.
9. ⬜ **Layer keep temps** — exists; add `--keep-temps-dir`.
10. ⬜ **Layer args** — `--ad-layer-arg` exists; add `--arg-file`.
11. ⬜ **Layer path** — exists; add `--path-recursive`.
12. ⬜ **Layer cache** — cache output.
13. ⬜ **Layer parallel** — run independent layers in parallel.
14. ⬜ **Layer timeout** — `--timeout N`.
15. ⬜ **Layer retries** — `--retries N`.
16. ⬜ **Layer fallback** — `--fallback NAME`.
17. ⬜ **Layer verify** — `--verify`.
18. ⬜ **Layer stats** — `--stats`.
19. ⬜ **Layer debug** — `--debug`.
20. ⬜ **Layer interactive** — `--interactive`.

---

## `ad_session`

**What it is:** An interactive vim-based debugging tool
(`scripts/ad_session`). Creates a session directory with old/new/ops
files, launches vim with a split layout (diff on left, ops on right
top, result on right bottom). Supports F5 (animate), F6 (snapshot),
git commit, layer group files, L1/L2 auto-run on save, fold identical
lines, trim (create reduced files from L2), and annotations.

**When you use it:** When debugging layer issues, testing op chains,
or inspecting why an animation produces wrong output. The L1/L2
auto-run on save is especially useful — edit ops, save, see where
the error is.

1. ⬜ **Session templates** — `--template NAME`.
2. ⬜ **Session sharing** — `--share`.
3. ⬜ **Session diff** — `--diff SESSION1 SESSION2`.
4. ⬜ **Session merge** — `--merge`.
5. ⬜ **Session history** — `--history`.
6. ⬜ **Session bookmark** — `--bookmark`.
7. ⬜ **Session restore** — `--restore`.
8. ⬜ **Session export** — `--export FORMAT`.
9. ⬜ **Session import** — `--import FILE`.
10. ⬜ **Session annotate** — `--annotate` exists; add per-op notes.
11. ⬜ **Session search** — `--search TEXT`.
12. ⬜ **Session filter** — `--filter EXPR`.
13. ⬜ **Session sort** — `--sort KEY`.
14. ⬜ **Session count** — `--count`.
15. ⬜ **Session verify** — `--verify`.
16. ⬜ **Session clean** — `--clean`.
17. ⬜ **Session list** — `--list-sessions` exists; add `--list-json`.
18. ⬜ **Session resume** — `--resume-latest` exists; add `--resume-by-name`.
19. ⬜ **Session profile** — `--profile`.
20. ⬜ **Session debug** — `--debug`.

---

## `ad_l1l2`

**What it is:** A bisect tool (`scripts/ad_l1l2`) that applies ops hunk
by hunk, checking after each hunk whether the buffer matches the new
file up to the lines that hunk modified. Reports L1 (last matching
line), L2 (first mismatching line), and L2_HUNK (which hunk introduced
the error). Also detects animator crashes (invalid ops).

**When you use it:** When a layer produces wrong output. L1/L2 tells
you which HUNK is wrong, narrowing the debugging surface. Auto-runs in
`ad_session` on start and on ops.tsv save. Can also be run standalone.

1. ✅ **Hunk-level bisect** — applies ops hunk by hunk, finds first
   failing hunk.
2. ✅ **L2_HUNK output** — reports which hunk failed.
3. ✅ **Animator crash detection** — detects when ops are invalid
   (animator produces no snapshot).
4. ✅ **Auto-run in ad_session** — runs on start and on save.
5. ⬜ **Op-level bisect** — within the failing hunk, find the exact op.
6. ⬜ **Faster comparison** — use diff instead of line-by-line sed.
7. ⬜ **Parallel hunk checking** — check multiple hunks in parallel.
8. ⬜ **JSON output** — `--json` for machine-readable.
9. ⬜ **Verbose mode** — `--verbose` to print each hunk check.
10. ⬜ **Skip hunks** — `--skip N` to skip first N hunks.
11. ⬜ **Max hunks** — `--max-hunks N` to check only first N.
12. ⬜ **Filter by hunk** — `--only-hunk N`.
13. ⬜ **Report** — `--report FILE` to write detailed report.
14. ⬜ **Log** — `--log FILE` to record each check.
15. ⬜ **Exit code** — exit 1 on failure, 0 on success (for CI).
16. ⬜ **Multiple files** — `ad_l1l2 old1 new1 ops1 old2 new2 ops2`.
17. ⬜ **Compare to expected** — `--expected FILE` instead of new file.
18. ⬜ **Snapshot at L2** — write buffer state at the failing hunk.
19. ⬜ **Trim** — `--trim` to create reduced files from L2 (like
   `<leader>t` in ad_session).
20. ⬜ **AWK implementation**.

---

## `ad_anim_test`

**What it is:** An animation testing tool (`scripts/ad_anim_test`)
that inserts `snapshot` ops into the op stream at checkpoints
(before/after `join_lines`, `split_line`, `keep_line`), runs the
animator ONCE, then checks each snapshot. With `--check-in-place`,
verifies that `join_lines` only happens on empty lines (content
deleted before join).

**When you use it:** When testing whether a layer produces good
ANIMATION (not just correct final output). L1/L2 tests the final
output; `ad_anim_test` tests intermediate states — does content jump
between lines? Are joins happening on non-empty lines?

1. ✅ **Snapshot ops** — inserts `snapshot\t<file>` ops, runs animator
   once.
2. ✅ **--check-in-place** — checks join_lines only on empty lines.
3. ✅ **Checkpoint at line boundaries** — before/after join_lines,
   split_line, keep_line.
4. ✅ **Final output check** — verifies final buffer matches new file.
5. ⬜ **Op-level checkpoints** — insert snapshots after each op group
   (not just line boundaries).
6. ⬜ **Indent check** — verify indent deletes happen after content
   deletes.
7. ⬜ **Verbose mode** — `--verbose` to print all checkpoints.
8. ⬜ **JSON output** — `--json`.
9. ⬜ **Filter checkpoints** — `--only join_lines` to check specific
   types.
10. ⬜ **Max checkpoints** — `--max N` to limit.
11. ⬜ **Snapshot dir** — `--snapshot-dir DIR`.
12. ⬜ **Keep snapshots** — `--keep` to not clean up.
13. ⬜ **Compare snapshots** — `--compare DIR` to compare against
   previous run.
14. ⬜ **Report** — `--report FILE`.
15. ⬜ **Exit code** — for CI.
16. ⬜ **Multiple files** — test multiple examples in one run.
17. ⬜ **Batch mode** — `--batch` to test all examples.
18. ⬜ **Layer chain** — `--ad-layer` to test with layers.
19. ⬜ **AWK implementation**.
20. ⬜ **Integration with ad_session** — run as `<leader>a` in session.

---

## `ad_watch`

**What it is:** A live-preview tool (`scripts/ad_watch`) that displays
old, new, and diff side by side, auto-refreshing when files change.
Uses inotify-tools if available (falls back to stat polling) and
diff-so-fancy if available (falls back to plain `diff -u`).

**When you use it:** When you're editing old/new files and want to
see the diff update in real time. Useful with `ad_session` — edit
ops.tsv, ad_watch shows the diff changing.

1. ⬜ **Multi-file watch** — `--watch file1 file2`.
2. ⬜ **Diff mode** — `--diff unified|side-by-side|word`.
3. ⬜ **Color** — `--color always|never|auto`.
4. ⬜ **Context** — `--context N`.
5. ⬜ **Ignore** — `--ignore PATTERN`.
6. ⬜ **Filter** — `--filter EXPR`.
7. ⬜ **Notify** — `--notify` desktop notification.
8. ⬜ **Sound** — `--sound`.
9. ⬜ **Log** — `--log FILE`.
10. ⬜ **Stats** — `--stats`.
11. ⬜ **Graph** — `--graph`.
12. ⬜ **Timeline** — `--timeline`.
13. ⬜ **Snapshot** — `--snapshot FILE`.
14. ⬜ **Restore** — `--restore FILE`.
15. ⬜ **Compare** — `--compare FILE1 FILE2`.
16. ⬜ **Merge** — `--merge FILE`.
17. ⬜ **Export** — `--export FORMAT`.
18. ⬜ **Profile** — `--profile`.
19. ⬜ **Debug** — `--debug`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_gen_ops`

**What it is:** A standalone op generator (`scripts/ad_gen_ops`).
Runs `ad_compute` and optionally `ad_postprocess` + `ad_annotate` to
produce a complete op stream from old/new files. Supports `--annotate`
and `--ad-layer` flags. Output goes to stdout.

**When you use it:** When you want to generate ops without launching
vim — for inspection, piping to `ad --precomputed`, or feeding to
`ad_l1l2`.

1. ⬜ **Multi-file** — `--multi`.
2. ⬜ **Layer chain** — `--ad-layer` exists; add `--layer-chain FILE`.
3. ⬜ **Annotate** — `--annotate` exists; add `--annotate-format`.
4. ⬜ **Output format** — `--output-format tsv|json|binary`.
5. ⬜ **Compress** — `--compress`.
6. ⬜ **Cache** — `--cache`.
7. ⬜ **Verify** — `--verify`.
8. ⬜ **Stats** — `--stats`.
9. ⬜ **Profile** — `--profile`.
10. ⬜ **Debug** — `--debug`.
11. ⬜ **Filter** — `--filter EXPR`.
12. ⬜ **Transform** — `--transform EXPR`.
13. ⬜ **Sort** — `--sort KEY`.
14. ⬜ **Search** — `--search TEXT`.
15. ⬜ **Count** — `--count`.
16. ⬜ **Diff** — `--diff FILE`.
17. ⬜ **Merge** — `--merge FILE`.
18. ⬜ **Export** — `--export FORMAT`.
19. ⬜ **Dry run** — `--dry-run`.
20. ⬜ **Help** — `--help` (exists).

---

## `ad_compare`

**What it is:** A comparison tool (`scripts/ad_compare`) that generates
diffs with all option combinations — runs `ad_compute` with various
flags and produces a matrix of results. Useful for finding the best
option combination for a given diff.

**When you use it:** When tuning options for a specific file pair —
compare different algorithms, pacing modes, layer chains side by side.

1. ⬜ **Output format** — `--output-format text|json|csv|html`.
2. ⬜ **Filter** — `--filter EXPR`.
3. ⬜ **Sort** — `--sort KEY`.
4. ⬜ **Limit** — `--limit N`.
5. ⬜ **Parallel** — `--parallel N`.
6. ⬜ **Timeout** — `--timeout N`.
7. ⬜ **Cache** — `--cache`.
8. ⬜ **Verify** — `--verify`.
9. ⬜ **Stats** — `--stats`.
10. ⬜ **Profile** — `--profile`.
11. ⬜ **Debug** — `--debug`.
12. ⬜ **Dry run** — `--dry-run`.
13. ⬜ **Export** — `--export FORMAT`.
14. ⬜ **Import** — `--import FILE`.
15. ⬜ **Diff** — `--diff FILE`.
16. ⬜ **Merge** — `--merge FILE`.
17. ⬜ **Search** — `--search TEXT`.
18. ⬜ **Count** — `--count`.
19. ⬜ **Help** — `--help` (exists).
20. ⬜ **Version** — `--version`.

---

## `ad_jogger`

**What it is:** A test case generator (`scripts/ad_jogger`) that
creates random file pairs with specific patterns (insertions,
deletions, modifications, swaps). Used to stress-test the diff engine
and layers with diverse inputs.

**When you use it:** When creating stress tests or finding edge cases
in the diff engine or layers.

1. ⬜ **Pattern library** — `--pattern NAME`.
2. ⬜ **Custom pattern** — `--pattern-file FILE`.
3. ⬜ **Random seed** — `--seed N`.
4. ⬜ **Size control** — `--min-size` / `--max-size`.
5. ⬜ **Language** — `--language python|go|rust|...`.
6. ⬜ **Complexity** — `--complexity simple|medium|hard`.
7. ⬜ **Mutation rate** — `--mutation-rate N`.
8. ⬜ **Output dir** — `--output DIR`.
9. ⬜ **Count** — `--count N` (exists).
10. ⬜ **Verify** — `--verify`.
11. ⬜ **Stats** — `--stats`.
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

**What it is:** A tmux-based animation launcher (`scripts/ad_tmux`).
Same as `ad_vim` but runs the animation inside a tmux pane instead of
directly in the terminal. Useful for multi-pane setups.

**When you use it:** When you want the animation in a tmux session
alongside other tools (e.g., watching the diff in one pane while
animating in another).

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

## `ad_debug.sh`

**What it is:** An interactive pipeline debugger (`scripts/ad_debug.sh`).
Steps through the pipeline stages (compute → postprocess → pace →
animate) one at a time, showing the output of each stage.

**When you use it:** When a pipeline stage produces unexpected output
and you want to see where it goes wrong.

1. ⬜ **Interactive debugger** — step through ops one at a time.
2. ⬜ **Breakpoints** — `--break LINE`.
3. ⬜ **Watch expressions** — `--watch EXPR`.
4. ⬜ **Call stack** — show layer chain.
5. ⬜ **Variable inspector** — show buffer state.
6. ⬜ **Step** — `--step`.
7. ⬜ **Continue** — `--continue`.
8. ⬜ **Next** — `--next`.
9. ⬜ **Finish** — `--finish`.
10. ⬜ **Print** — `--print EXPR`.
11. ⬜ **Backtrace** — `--backtrace`.
12. ⬜ **Locals** — `--locals`.
13. ⬜ **Args** — `--args`.
14. ⬜ **Set** — `--set VAR=VALUE`.
15. ⬜ **Run** — `--run`.
16. ⬜ **Quit** — `--quit`.
17. ⬜ **Help** — `--help`.
18. ⬜ **Log** — `--log FILE`.
19. ⬜ **Profile** — `--profile`.
20. ⬜ **Stats** — `--stats`.

---

## `ad_debug_bundle.sh`

**What it is:** A script (`scripts/ad_debug_bundle.sh`) that collects
debug information (system info, binary versions, config files, op
streams, snapshots) into a tarball for bug reports.

**When you use it:** When filing a bug report and the maintainer asks
for debug info.

1. ⬜ **Custom bundle contents** — `--include` / `--exclude`.
2. ⬜ **Compression** — `--compress`.
3. ⬜ **Encryption** — `--encrypt`.
4. ⬜ **Upload** — `--upload URL`.
5. ⬜ **Expiry** — `--expire N`.
6-20. (Same common options as other utility scripts.)

---

## `ad_snapshot.sh`

**What it is:** A script (`scripts/ad_snapshot.sh`) that takes per-op
HTML snapshots — injects `snapshot` ops into the op stream and runs the
animator once, then renders the snapshot files as an HTML page showing
the buffer state at each step.

**When you use it:** When you want a visual timeline of the animation
for debugging or documentation.

1. ⬜ **Per-op snapshots** — one file per op.
2. ⬜ **HTML output** — browseable snapshots.
3. ⬜ **Diff between snapshots** — `--diff SNAP1 SNAP2`.
4. ⬜ **Animated GIF** — `--gif`.
5. ⬜ **Video** — `--video`.
6-20. (Same common options.)

---

## `ad_replay.sh`

**What it is:** A script (`scripts/ad_replay.sh`) that replays a
recorded animation from a file.

**When you use it:** When reviewing an animation that was recorded
earlier.

1. ⬜ **Speed control** — `--speed N`.
2. ⬜ **Pause/resume** — keyboard controls.
3. ⬜ **Snapshot injection** — `--snapshot-ops` to control where
   `snapshot` ops are inserted (per op, per hunk, per N ops).
4. ⬜ **Loop** — `--loop`.
5. ⬜ **Reverse** — `--reverse`.
6-20. (Same common options.)

---

## `ad_record.sh`

**What it is:** A script (`scripts/ad_record.sh`) that records an
animation to a file for later replay.

**When you use it:** When capturing an animation for documentation,
bug reports, or replay.

1. ⬜ **Format** — `--format json|binary|tsv`.
2. ⬜ **Compression** — `--compress`.
3. ⬜ **Timestamps** — `--timestamps`.
4. ⬜ **Metadata** — `--meta KEY=VALUE`.
5. ⬜ **Streaming** — `--stream`.
6-20. (Same common options.)

---

## `ad_demo.sh`

**What it is:** A demo runner (`scripts/ad_demo.sh`) with preset
examples — runs `ad_vim` on curated file pairs to showcase features.

**When you use it:** When introducing `ad` to new users or testing
features quickly.

1. ⬜ **Demo library** — `--list`.
2. ⬜ **Custom demo** — `--script FILE`.
3. ⬜ **Narration** — `--narrate FILE`.
4. ⬜ **Auto-advance** — `--auto N`.
5. ⬜ **Record** — `--record FILE`.
6-20. (Same common options.)

---

## `ad_suggest.sh`

**What it is:** A "did you mean?" suggestion function
(`scripts/ad_suggest.sh`). Sourceable library that suggests the
closest matching option name when the user types a wrong flag.

**When you use it:** Sourced by `ad_vim` and other scripts to provide
helpful "Did you mean --speed?" messages.

1. ⬜ **Fuzzy match** — improve Levenshtein.
2. ⬜ **Context-aware** — suggest based on current options.
3. ⬜ **Learn from usage** — track accepted suggestions.
4. ⬜ **Custom dictionary** — `--dict FILE`.
5. ⬜ **Min confidence** — `--min-confidence N`.
6-20. (Same common options.)

---

## `ad_tune.sh`

**What it is:** An interactive option tuner (`scripts/ad_tune.sh`).
Runs in tmux, lets you adjust pacing/timing options interactively and
see the effect on the animation in real time.

**When you use it:** When fine-tuning animation timing for a specific
file pair or presentation.

1. ⬜ **Save/load profiles** — `--save` / `--load`.
2. ⬜ **Compare profiles** — `--diff`.
3. ⬜ **Auto-tune** — `--auto`.
4. ⬜ **A/B test** — `--ab`.
5. ⬜ **Export** — `--export FORMAT`.
6-20. (Same common options.)

---

## `ad_package.sh`

**What it is:** A packaging script (`scripts/ad_package.sh`) that
creates distributable packages (tar, zip, deb, rpm) of the project.

**When you use it:** When preparing a release.

1. ⬜ **Format** — `--format tar|zip|deb|rpm`.
2. ⬜ **Sign** — `--sign KEY`.
3. ⬜ **Upload** — `--upload URL`.
4. ⬜ **Changelog** — `--changelog FILE`.
5. ⬜ **Version bump** — `--bump major|minor|patch`.
6-20. (Same common options.)

---

## `ad_doc_provenance`

**What it is:** A script (`scripts/ad_doc_provenance`) that prints git
provenance for a file — the commit that created it, the commit that
last modified it, and the current HEAD.

**When you use it:** When adding provenance headers to documentation
files.

1. ⬜ **Batch mode** — `--batch`.
2. ⬜ **Format** — `--format text|json|yaml`.
3. ⬜ **Filter** — `--filter EXPR`.
4. ⬜ **Since** — `--since DATE`.
5. ⬜ **Author** — `--author NAME`.
6-20. (Same common options.)

---

## Summary

- **30+ tools** documented with descriptions.
- **600+ proposals** total (20 per tool).
- Most proposals focus on: better `--help`, JSON output, profiling,
  caching, parallelism, filtering, and verification.
- The highest-impact proposals are the "followability" features for
  `ad` and `ad_vim` (inline highlight, hunk descriptions, time
  estimates, etc.) — these directly improve the user experience.
