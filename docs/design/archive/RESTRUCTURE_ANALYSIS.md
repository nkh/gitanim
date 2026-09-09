# Project Restructure Analysis

*Created:* `010cbdc` (2026-08-28 14:41:15 +0000)
*Last updated:* `7b9e449` (2026-08-28 18:57:44 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


Source commit: `b97649e` (pushed to `origin/main`). This analysis: `010cbdc`.

Pick changes by keeping their `#N short name` line (delete the explanation paragraphs). Delete the whole proposal by `dd` on each of its lines, then `.` to repeat. Lines are unwrapped — vim handles the wrap.

## A. Project identity & prefix

#1 Rename project to `ad`

The project animates a diff. Diffvim is one application (the vim one) built on top of the toolkit. Rename the project from "diffvim" to `ad` (animate-diff). The git repo can stay `gitanim` for history; the user-facing name in docs, README, manpages, completions becomes `ad`.

#2 Rename `diffvim` launcher → `ad_vim`

The top-level bash launcher becomes `ad_vim` — the vim application, first concrete consumer of the `ad_` toolkit. (Was the only file with a real vim dependency.)

#3 Rename `ad_vim.pl` → `ad_vim.pl` (or delete)

The Perl parallel launcher is renamed to match #2. Consider deleting it outright if it duplicates the bash launcher — see #15.

#4 Rename `ad_compute` → `ad_compute`

The diff engine has no vim dependency. `ad_compute` is the binary name. Affects source files, manpages, completions, install paths.

#5 Rename `ad_postprocess` → `ad_postprocess`

The layer orchestrator has no vim dependency. `ad_postprocess` is the binary name. Affects source, manpages, install paths.

#6 Rename `ad_pipeline` → `ad_pipeline`

The end-to-end driver has no vim dependency. `ad_pipeline` is the binary name.

#7 Rename `ad` → `ad_animator`

The animator backend (C + Perl twins) has no vim dependency. `ad_animator` is the binary name.

#8 Rename every `pp_<name>` layer → `ad_layer_<name>`

`pp_reorder` → `ad_layer_reorder`, `pp_indent_last` → `ad_layer_indent_last`, etc. The `pp_` prefix meant "postprocess" but the new prefix makes the layer concept explicit and groups layers alphabetically in `bin/`.

#9 Rename every `dv_<verb>.sh` → `ad_<verb>.sh`

`dv_debug.sh` → `ad_debug.sh`, `dv_snapshot.sh` → `ad_snapshot.sh`, `dv_record.sh` → `ad_record.sh`, `dv_replay.sh` → `ad_replay.sh`, `dv_demo.sh` → `ad_demo.sh`, `dv_tune.sh` → `ad_tune.sh`, `dv_suggest.sh` → `ad_suggest.sh`, `dv_debug_bundle.sh` → `ad_debug_bundle.sh`, `dv_package.sh` → `ad_package.sh`. Same renames for the corresponding `man/dv_*.1` files.

#10 Standardize env vars on `AD_` prefix only

Audit and remove all `DV_*` and `DIFFVIM_*` variants. Examples: `DV_DEBUG_POSTPROCESS` → `AD_DEBUG_LAYERS`, `DIFFVIM_LEFT_TO_RIGHT` → `AD_LEFT_TO_RIGHT`, `DIFFVIM_INDENT_LAST` → `AD_INDENT_LAST`. See #55 for the deprecation period.

#11 Move config to `$XDG_CONFIG_HOME/ad/`

Drop the legacy `~/.diffvimrc` fallback. Config file lives at `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config` when `XDG_CONFIG_HOME` is unset). See section G for the full config overhaul.

## B. Top-level directory structure

Today the top level mixes categories (`compute/`, `animator/`) with artifacts (`A`, `B`, `jq_filter`, `set_config`) and parallel implementations. Proposed structure:

```
ad/                           # project root
├── bin/                      # build output — gitignored, created by `make`
├── diff_engine/              # the diff LCS/Hirschberg engine
│   ├── cpp/
│   ├── perl/
│   └── tests/
├── layers/                   # postprocess layer plugins (one source file each)
│   ├── c/
│   ├── perl/
│   └── tests/                # per-layer TDD tests (one test file per layer)
├── animator/                 # the animator backend only
│   ├── c/
│   ├── perl/
│   └── tests/
├── pipeline/                 # the orchestrator (postprocess driver, pipeline driver)
│   └── bin/                  # bash scripts only
├── apps/                     # application launchers built on the toolkit
│   └── vim/                  # ad_vim (the vim application)
├── tools/                    # helper scripts (debug, snapshot, record, ...)
│   └── bin/
├── perl/                     # shared Perl library code (DiffVim:: namespace, if kept)
├── tests/                    # cross-cutting tests (examples, e2e, property)
├── docs/                     # documentation (mdbook source + generated book)
├── man/                      # manpages
├── completion/               # shell completions
├── examples/                 # sample old/new file pairs for tests + demos
├── .github/workflows/        # CI (restored — see section F)
├── Makefile
├── README.md
├── CHANGELOG.md
├── LICENSE
└── .gitignore
```

#12 Create `diff_engine/` and move `compute/` contents

`compute/cpp/` → `diff_engine/cpp/`, `compute/perl/` → `diff_engine/perl/`, `compute/Makefile` → `diff_engine/Makefile`. Delete the empty `compute/` directory. The directory name should describe what's in it (the diff engine), not what calls it (compute was a verb used by ad_vim).

#13 Create `layers/` and move all layer sources

`animator/c/pp_*.c` → `layers/c/ad_layer_*.c` (renamed per #8). `animator/perl/pp_*.pl` → `layers/perl/ad_layer_*.pl`. Layers are no longer under `animator/` — they are a peer concept, not a subcomponent.

#14 Create `layers/tests/` and add per-layer tests

Move `tests/test_indent_last.pl` → `layers/tests/test_indent_last.pl`. Add `test_reorder.pl`, `test_overwrite.pl`, `test_line_delete_in_place.pl`, `test_pace.pl`, `test_highlight.pl` (one per layer — see section E for the test plan).

#15 Keep only animator source in `animator/`

Move `animator/ad_pipeline` → `pipeline/bin/ad_pipeline` (per #6). Move `animator/bin/` content into `bin/` at the project root (per #24). What remains in `animator/`: `c/animator.c`, `perl/animator.pl`, `perl/colorize.pl`, the vimscript animator. This is what the directory name says it contains.

#16 Create `apps/vim/` and move vim-specific files

`diffvim` → `apps/vim/ad_vim` (per #2). `ad_vim.pl` → `apps/vim/ad_vim.pl` (per #3). `plugin/diffvim.vim` → `apps/vim/plugin.vim`. The vim application is one consumer of the `ad_` toolkit; it lives in `apps/vim/`, not at the project root.

#17 Create `tools/bin/` and move helper scripts

`scripts/dv_*.sh` → `tools/bin/ad_<verb>.sh` (renamed per #9). The `scripts/` directory is renamed `tools/` to make its role explicit.

#18 Delete root-level junk files

Delete: `A`, `B`, `a`, `b` (4 single-letter test fixtures, 14-28 bytes each, no purpose), `jq_filter`, `difft_json_to_lcs`, `set_config`, `lcs_tools.txt` (orphan scripts in the root — should be under `tools/` if kept at all), `first_improvements.md`, `IMPROVEMENTS.md`, `the_diff.diff` (superseded docs).

#19 Delete `DiffVim/` directory

Contains `Parser/Perl.pm` — an aborted Perl OO refactor. Not referenced anywhere in the active codebase.

#20 Delete `autoload/` and `plugin/` if they duplicate `apps/vim/`

After #16 moves `plugin/diffvim.vim` → `apps/vim/plugin.vim`, check whether `autoload/` and `plugin/` directories contain anything still in use. If they're vim-runtime files that duplicate the new location, delete them.

#21 Move and rename Homebrew formula

`packaging/diffvim.rb` → `packaging/ad_vim.rb`. Update the formula's `bin` and `man` install paths to match the new structure (single `bin/` directory per #24).

#22 Move `l2r_test/` → `diff_engine/tests/l2r/`

The l2r test is a test for the diff engine's left-to-right mode. It is not a top-level concept. Moving it under `diff_engine/tests/` makes the structure self-documenting.

## C. Build system — single `bin/`, no binaries in git

#23 Update `.gitignore` to ignore `bin/` only

Remove the per-directory `animator/bin/`, `compute/bin/` entries. Single `bin/` line subsumes them. Compiled binaries are never in git.

#24 Update `Makefile` to build into `bin/` at project root

All binaries land in `bin/`: `bin/ad_compute`, `bin/ad_animator`, `bin/ad_postprocess`, `bin/ad_pipeline`, `bin/ad_layer_<name>`. The `bin/` directory is created by `make` if missing. Single source of binaries, no scattered `bin/` subdirectories.

#25 Update install target to copy from `bin/`

`make install-bin` copies from `bin/` to `$(DESTDIR)$(BINDIR)`. Update `install-man` and `install-comp` to use the new manpage names (per #9, #63) and completion names (per #64).

#26 Add per-layer Makefile targets with test dependencies

For each layer: `bin/ad_layer_<name>` depends on BOTH `layers/c/ad_layer_<name>.c` AND `layers/tests/test_<name>.pl`. Touching either triggers a rebuild AND a test re-run. Aggregate target `layers:` builds all layer binaries.

#27 Update `make test` aggregate target

Run (a) per-layer tests, (b) cross-cutting tests (property, examples), (c) the l2r diff-engine tests. Make this data-driven where possible (e.g. glob `layers/tests/test_*.pl`). Output: clear PASS/FAIL summary.

#28 Add granular install targets

`make install-bin`, `make install-man`, `make install-comp`, `make install-docs` — all writing to `$(DESTDIR)$(PREFIX)/`. Keep the existing prefix semantics (`PREFIX ?= /usr/local`).

## D. Layer discovery — the core rewrite

The current discovery (manifest + `--enable` + `--layers=` + implicit language scan) is wrong on every count. Replace with a minimal, user-driven model.

#29 Delete `layers.conf` (was `animator/layers.conf`)

The manifest forces the user to learn a custom file format and edit it to add a layer. Replace with explicit user-supplied chain on the command line. No manifest file.

#30 Drop `--enable=<name>`

The user always supplies the full chain via repeated `--ad-layer=<name>` flags. There is no "default minus removed" concept. The user adds layers; the orchestrator doesn't subtract.

#31 Drop `--layers=<csv>`

Repeated `--ad-layer=<name>` flags replace it (one flag per layer, in argv order). No CSV parsing.

#32 `--ad-layer=<name>` runs layers in argv order

Not by any manifest `order` field. `ad_vim --ad-layer=reorder --ad-layer=indent_last --ad-layer=pace` runs them in that exact sequence. What the user types is the only source of truth.

#33 `--ad-layer=<name>` supports extensions

`--ad-layer=foo`, `--ad-layer=foo.pl`, `--ad-layer=foo.py` are all valid. The orchestrator looks up the file verbatim — no implicit `pp_` prefix when an extension is present. `--ad-layer=foo.pl` and `--ad-layer=foo` are distinct names.

#34 `--ad-layer=foo --ad-layer=foo` runs `foo` twice

Idempotency is the layer's problem, not the orchestrator's. Document this explicitly. If a user wants to chain the same layer twice (e.g. once before pace, once after), they can.

#35 Add `--ad-layer-path=<dir>` (repeatable)

Adds a directory to the layer search path. Default search path = `<project>/layers/c` and `<project>/layers/perl` only. The user can override (clear default) or extend (append). Multiple `--ad-layer-path` flags accumulate.

#36 Layer search algorithm

(a) If `<name>` contains `/`, treat as a path (relative to CWD or absolute). Run it directly. (b) Else, search each `--ad-layer-path` dir in declared order. The first directory containing a file named `<name>` (verbatim) wins. (c) If no match, error: `ad_postprocess: layer '<name>' not found in: <list of searched dirs>`. (d) If the matched file has extension `.pl`, invoke with `perl`. If `.py`, with `python3`. If `.rb`, with `ruby`. If `.sh`, with `bash`. If `.js`, with `node`. Otherwise, the file must be executable and is run directly (no interpreter). If not executable, error: `ad_postprocess: layer '<name>' is not executable`. **No magic auto-discovery across language dirs.**

#37 Make `--list-layers` list the search path

Lists the contents of the `--ad-layer-path` dirs (so the user sees what's available in their chosen search path). No manifest to list. If no `--ad-layer-path` given, lists the defaults.

#38 Default layer chain lives in `ad_vim`, not the orchestrator

When no `--ad-layer` is given, the `ad_vim` launcher supplies its own default: `reorder`, `pace`, `highlight`. This is the application default — the orchestrator itself has no opinion about what runs by default.

#39 Drop `--pp-<name>` forwarding prefix

The generic forwarding prefix introduced in commit `b97649e` is replaced with `--ad-layer=<name>` everywhere. Update `ad_vim` and `ad_pipeline` launchers accordingly. One mechanism, one flag.

## E. Tests — TDD for layers, run on layer changes

#40 Add one test file per layer in `layers/tests/`

`test_reorder.pl`, `test_overwrite.pl`, `test_indent_last.pl`, `test_line_delete_in_place.pl`, `test_pace.pl`, `test_highlight.pl`. Each test: feeds a known V2 TSV input (committed alongside the test as `<test_name>_in.tsv`); asserts specific V2 TSV output (committed as `<test_name>_out.tsv`); asserts the layer is invokable standalone (`bin/ad_layer_<name> < in > out; exit 0`); for layers with both C and Perl twins, asserts byte-identical output (parity).

#41 Write the test FIRST (TDD)

Red, then green. The test file MUST exist in the same commit that adds the layer. This is enforced by review, not by tooling. CI (see F-47) makes it impossible to merge a layer PR without the test.

#42 Add `Makefile` targets per layer

`test-layer-reorder`, `test-layer-overwrite`, `test-layer-indent_last`, `test-layer-line_delete_in_place`, `test-layer-pace`, `test-layer-highlight`. Aggregate target `test-layers:` runs them all.

#43 Add `Makefile` dependency: layer bin depends on layer source AND test

`bin/ad_layer_<name>` depends on both `layers/c/ad_layer_<name>.c` AND `layers/tests/test_<name>.pl`. Touching either rebuilds the layer and re-runs its test.

#44 Delete `tests/test_postprocess_layers.sh`

References `pp_layer0/1/2/3` — old layer numbering that no longer exists. Dead code.

#45 Consolidate test directories

Move `animator/tests/*.pl` → `tests/`. The `layers/tests/` and `diff_engine/tests/` subdirectories hold tests that are category-specific; cross-cutting tests live in `tests/`. Single root for tests makes them easier to find and run.

#46 Run property-based tests in `make test`

`tests/test_property.pl` (already exists) runs 50 random diffs through the entire pipeline and checks invariants (no backward ops, output matches new file). Add to the `make test` aggregate target.

## F. CI integration — restore what was deleted

Commit `b209339` deleted both `.github/workflows/build-and-test.yml` and `.github/workflows/docs.yml`. They were added in `0888caa` and should never have been removed.

#47 Restore `.github/workflows/build-and-test.yml`

Updates to match new structure: Build with `make` (now produces `bin/*`). Test with `make test` (runs unit + layers + property + l2r). Run on push to `main` and on all PRs. Cache `~/.cache/ad/` between runs.

#48 Restore `.github/workflows/docs.yml`

Trigger on push to `main` when `docs/**` changes. Install `mdbook` (pin version, e.g. v0.4.40). Add `docs/book.toml` (currently missing — see #49). Build with `cd docs && mdbook build`. Publish to GitHub Pages (`actions/deploy-pages@v4`). Upload artifact for download.

#49 Add `docs/book.toml`

Currently missing — that's why mdbook never built. Minimal config: `[book] title = "ad — animate a diff"`, `authors = ["nkh"]`, `language = "en"`, `[output.html] git-repository-url = "https://github.com/nkh/gitanim"`.

#50 Add `.github/workflows/lint.yml`

Run `shellcheck` on every `*.sh` file (ad_vim, ad_pipeline, tools/bin/*.sh). Run `perl -c` on every `*.pl` file (syntax check). Run `gcc -fsyntax-only -Wall -Wextra` on every `*.c` file. Block PR on any failure.

#51 Add `.github/workflows/release.yml`

Trigger on git tag `v*`. Build `make`. Create a GitHub Release with tarball of `bin/`, `man/`, `completion/`, and the source.

#52 Document the CI setup in `docs/src/contributing.md`

How to run CI locally (`make test` mirrors build-and-test.yml). How to preview docs locally (`mdbook serve docs/`). How the layer test gating works.

## G. Configuration — XDG, not invented places

#53 Drop the `~/.diffvimrc` fallback

Use `$XDG_CONFIG_HOME/ad/config` only. Default to `~/.config/ad/config` when `XDG_CONFIG_HOME` is unset. Today `ad_pipeline` sources both `~/.config/diffvim/config` AND `~/.diffvimrc` — kill the legacy path.

#54 Move project-wide defaults into a real config file

Today `ad_vim` has ~50 `DIFFVIM_*` env-var declarations hardcoded as bash variables. Move them to `/etc/ad/config` (system) and `~/.config/ad/config` (user), sourced at startup. Single source of truth.

#55 Deprecate `DV_*` env vars in favor of `AD_*`

Standardize on `AD_*` per #10. Print a deprecation warning if a `DV_*` var is set, but still read it for one release cycle (e.g. one minor version). After the deprecation period, drop the `DV_*` reading entirely.

#56 Drop the `DIFFVIM_CONFIG_LOADED` env-var hack

Source the config file once at the top of the launcher; if the file doesn't exist, use defaults. No env-var guard needed. The current hack re-sources the config in subprocesses; a single top-level source is sufficient.

#57 Rewrite `docs/src/configuration.md`

Document the config file format. Currently out of date — references removed options (`--semantic-cleanup`, `--indent-aware`, `--op-order`).

## H. Documentation cleanup

#58 Move `FLEXIBILITY.md` → `docs/src/plugin-layers.md`

It's documentation, belongs with the other mdbook source. Root-level `.md` files clutter the project tree.

#59 Audit `docs/*.md` and delete obsolete design docs

60+ files today. Delete the design-decision docs that describe decisions already made: `POSTPROCESS_REDESIGN.md`, `PER_LAYER_ADJUSTMENT_REQUIREMENTS.md`, `ARCHITECTURE_ANALYSIS.md`, `OPTION_AUDIT.md`, `PIPELINE_DECORATE_ANALYSIS.md`, `BINARY_FORMAT_ANALYSIS.md`, `KEEP_OPS_ANALYSIS.md`, etc. Keep only user-facing reference docs.

#60 Move surviving design docs to `docs/design/`

Separate mdbook section. Keep `docs/src/` for user-facing reference. Design docs become a sub-book with its own summary.

#61 Update `docs/src/SUMMARY.md`

Add the new sections: Plugin Layers (from #58), Contributing (from #52), Configuration (updated #57).

#62 Update `README.md`

Reflect the new project name (`ad`) and the new directory structure. Drop the vim-centric framing. Add a quick-start that shows the `ad_vim` command and a layer example.

#63 Rename `man/*.1` files

Rename per #4 through #9. Update all internal references from `diffvim-*` to `ad_*`. Examples: `man/ad_compute.1` → `man/ad_compute.1`, `man/dv_debug.1` → `man/ad_debug.1`, `man/dv_snapshot.1` → `man/ad_snapshot.1`.

#64 Rename completion files

`completion/ad_vim.bash` → `completion/ad_vim.bash`, `completion/ad_vim.fish` → `completion/ad_vim.fish`, `completion/__ad_vim` → `completion/_ad_vim`. Update internal command names to match the new `ad_vim` binary name.

## I. Migration plan (suggested order)

If you select all changes, here's the dependency-aware order:

1. **First (no behavior change, pure file moves):** #12, #13, #15, #16, #17, #22, #23, #24. Just move files and update Makefile paths.
2. **Then (rename, update references):** #1 through #11, #25, #26, #58 through #64. Rename binaries and update all references in scripts, manpages, completions, docs.
3. **Then (rewrite discovery):** #29 through #39. Rewrite the orchestrator + launchers to use the new `--ad-layer=<name>` model.
4. **Then (TDD):** #40 through #46. Write per-layer tests.
5. **Then (CI):** #47 through #52. Restore and extend workflows.
6. **Finally (config):** #53 through #57. Move config to XDG path.

## J. Open questions

#Q1 Keep Perl twins for every layer?

Only `indent_last`, `pace`, `highlight` have Perl twins today. Keeping twins means more maintenance but C/Perl parity is a useful invariant. Decide: keep all, keep only the three that exist, or drop Perl entirely.

#Q2 Keep both C++ and Perl diff engine implementations?

`diff_engine/` holds the LCS/Hirschberg engine. C++ is faster; Perl is easier to read. Commit to one or keep both?

#Q3 Split vim app into a separate repo?

Should `apps/vim/` (the vim application) live in this repo, or be split into a separate `ad_vim` repo that depends on `ad` as a library/submodule? Monorepo is simpler; split lets the vim app evolve independently.

#Q4 OK with dropping `DV_*` env vars in favor of `AD_*`?

Breaking change. Longer deprecation period (e.g. one minor version) or hard cut?

#Q5 Make `examples/` the canonical test corpus?

The `examples/` directory has 44 subdirectories. Should these become the canonical test corpus (renamed `tests/examples/`), or stay separate as user-facing examples?
