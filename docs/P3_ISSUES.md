# P3 Maintainability Issues — 12 items

These are the 12 maintainability issues from the code analysis. They don't cause bugs or security issues, but they make the code harder to maintain. Listed here for prioritization.

#P3-1 C layer boilerplate duplication (~600 LOC)

The 4 small layer .c files (`reorder`, `overwrite`, `indent_last`, `line_delete_in_place`) each triplicate the hunk-processing code (HUNK-start, HUNK_END, EOF). Combined with cross-file boilerplate, ~60-70% of the layer .c code is duplicated.

`ad_layer_common.h` already provides `ad_layer_run_layer()` to eliminate this, but no layer uses it.

Fix: Refactor the 4 layers to use `ad_layer_run_layer()`, or extract `reorder_hunk()`, `overwrite_hunk()`, etc. helpers.

#P3-2 Perl layer boilerplate (~452 LOC)

7 Perl layer files share byte-for-byte duplicated `parse_op`, `char_repr`, `write_op`, `is_debug_op`, `debug_log`, and the main hunk-driver loop.

Fix: Create `perl/DiffVim/Layer.pm` module exporting shared functions + a `run_layer(\&transform)` driver.

#P3-3 `animator/c/ad.c` — 360-line `main()` and 110-line `render()`

Both far exceed the 100-line guideline.

Fix: Split `main()` into `parse_args()`, `load_inputs()`, `main_loop()`, `cleanup()`. Split `render()` into `compute_scroll_offset()` and `emit_frame()`.

#P3-4 `layers/c/ad_layer_pace.c` — 430-line `main()`

Single function handles 6 pacing strategies in one giant if-else chain.

Fix: Split into `pace_char_delete()`, `pace_rapid_eol()`, `pace_rapid_identical()`, `pace_awd()`, `pace_word_insert()`, etc.

#P3-5 `apps/vim/ad_vim` — 2,170-line monolithic script

Single Bash script with embedded 800-line vimscript heredoc.

Fix: Split into `ad_vim` (CLI parsing), `ad_vim_engine.vim` (animation engine), `ad_vim_pipeline.sh` (pipeline runner).

#P3-6 `scripts/ad_tmux` — 1,673-line script duplicating 60% of ad_vim

Duplicates CLI parsing, vimscript engine, and animation loop from `ad_vim`.

Fix: Make `ad_tmux` a thin wrapper around shared code.

#P3-7 Magic number `1048576` (1MB) defined 4 times

In `ad_layer_common.h`, `ad_layer_pace.c`, `ad_layer_highlight.c`, `animator/c/ad.c`.

Fix: Use one canonical `AD_LAYER_MAX_LINE` from `ad_layer_common.h` everywhere.

#P3-8 TSV tokenizer duplicated 9+ times

`parse_tsv` in `ad_layer_pace.c`, `ad_layer_highlight.c`, inlined twice in `ad.c`, variant in `ad_layer_common.h`.

Fix: Use one `parse_op_fields()` function everywhere.

#P3-9 `char_repr` defined 3 times

In `ad_layer_common.h`, `compute.cpp`, embedded in `ad_layer_write_op`.

Fix: Use one canonical definition.

#P3-10 Option routing duplicated in 4 scripts

`ad_pipeline`, `ad_snapshot.sh`, `ad_vim`, `ad_tmux` all have ~50-line option-routing `case` blocks.

Fix: Extract `scripts/lib/ad_route.sh` shared library.

#P3-11 Dead stubs in `ad_layer_highlight.c`

`do_highlight_word` (line 244) and `git_blame` (line 388) are stubs that don't do what they claim.

Fix: Implement or remove the `--highlight word` and `--git-blame` options.

#P3-12 Version string hardcoded in 2 places

`1.5.0` in both `ad_vim.pl:363` and `ad_tmux:236`.

Fix: Use a single `VERSION` file or `git describe --tags`.

---

## Recommended fix priority

1. **P3-1 + P3-2** (layer boilerplate) — eliminates ~1050 LOC of duplication, highest impact
2. **P3-3 + P3-4** (long main() functions) — improves readability of the two most complex C files
3. **P3-5 + P3-6** (monolithic bash scripts) — biggest maintainability win but most effort
4. **P3-7 + P3-8 + P3-9** (duplicated constants/functions) — quick wins, low effort
5. **P3-10** (option routing library) — reduces maintenance across 4 scripts
6. **P3-11 + P3-12** (stubs + version) — cleanup
