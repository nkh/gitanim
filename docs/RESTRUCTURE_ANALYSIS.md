# Project Restructure Analysis

> **Status:** Proposal — pick the changes you want implemented.
> Each change is on its own numbered line.
> Source commit at time of writing: `b97649e` (pushed to `origin/main`).

## Goals (from the user's brief)

1. The project is **not** called diffvim. Diffvim is one application
   built on top of the project. The project itself **animates a diff**.
2. The prefix `ad_` (animate-diff) should be used for project-owned
   binaries and concepts — replacing the `dv_` / `diffvim-` prefixes
   that leaked vim-specific names into generic tooling.
3. Subdirectories should be **categorical**, not historical: only the
   animator belongs in `animator/`; layers belong in `layers/`; the
   diff engine belongs in `diff_engine/`; etc.
4. **Compiled binaries are not in git** (already enforced via
   `.gitignore`). `make` must build them into a single `bin/` directory.
5. **Perl code** lives under `perl/` at the project root, or under
   `<category>/perl/` for category-specific tools.
6. **CI was asked for before** (build + test, and mdbook generation) and
   was deleted in commit `b209339` ("Per-layer architecture"). It needs
   to be restored.
7. **Layer tests must exist** — written before the layer (TDD), run on
   every layer change, gated by CI.

---

## A. Project identity & prefix

**1.** Rename the project from "diffvim" (the vim application) to
`ad` (animate-diff). The git repo can stay `gitanim` for history;
the user-facing name in docs, README, manpages, completions becomes
`ad`.

**2.** Rename the top-level launcher `diffvim` → `ad_vim` (the vim
application; first concrete consumer of the `ad_` toolkit).

**3.** Rename the Perl parallel launcher `diffvim.pl` → `ad_vim.pl`
(or delete it if it duplicates the bash launcher — see B-15).

**4.** Rename `diffvim-compute` → `ad_compute` (the diff engine; no
vim dependency).

**5.** Rename `diffvim-postprocess` → `ad_postprocess` (the layer
orchestrator; no vim dependency).

**6.** Rename `diffvim-pipeline` → `ad_pipeline` (the end-to-end
driver; no vim dependency).

**7.** Rename `diffvim-animator` → `ad_animator` (the animator
backend; no vim dependency).

**8.** Rename every `pp_<name>` layer binary → `ad_layer_<name>`
(e.g. `pp_reorder` → `ad_layer_reorder`). The `pp_` prefix was
"postprocess"; the new prefix makes the layer concept explicit and
groups layers alphabetically in `bin/`.

**9.** Rename every `dv_<verb>.sh` script → `ad_<verb>.sh`
(e.g. `dv_debug.sh` → `ad_debug.sh`, `dv_snapshot.sh` →
`ad_snapshot.sh`). Same for the manpages.

**10.** Standardize environment variables on the `AD_` prefix only.
Audit and remove all `DV_*` and `DIFFVIM_*` variants. Examples:
`DV_DEBUG_POSTPROCESS` → `AD_DEBUG_LAYERS`,
`DIFFVIM_LEFT_TO_RIGHT` → `AD_LEFT_TO_RIGHT`.

**11.** Rename `~/.config/diffvim/` → `~/.config/ad/` (XDG Base
Directory spec). Drop the legacy `~/.diffvimrc` fallback. The config
file lives at `$XDG_CONFIG_HOME/ad/config` (defaults to
`~/.config/ad/config`).

---

## B. Top-level directory structure

Today the top level mixes categories (`compute/`, `animator/`) with
artifacts (`A`, `B`, `jq_filter`, `set_config`) and parallel
implementations (`diffvim`, `diffvim.pl`). The proposed structure:

```
ad/                           # project root (rename from gitanim if desired)
├── bin/                      # build output — gitignored, created by `make`
├── diff_engine/              # the diff LCS/Hirschberg engine
│   ├── cpp/                  # C++ implementation
│   ├── perl/                 # Perl implementation (fallback)
│   └── tests/                # diff engine tests
├── layers/                   # postprocess layer plugins (one source file each)
│   ├── c/                    # C implementations
│   ├── perl/                 # Perl implementations (fallback / twins)
│   └── tests/                # per-layer TDD tests (one test file per layer)
├── animator/                 # the animator backend (vimscript + C + Perl)
│   ├── c/
│   ├── perl/
│   └── tests/
├── pipeline/                 # the orchestrator (postprocess driver, pipeline driver)
│   └── bin/                  # bash scripts only
├── apps/                     # application launchers built on the toolkit
│   └── vim/                  # ad_vim (the vim application, formerly `diffvim`)
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

**12.** Create `diff_engine/` and move `compute/cpp/` → `diff_engine/cpp/`,
`compute/perl/` → `diff_engine/perl/`. Delete the empty `compute/`
directory.

**13.** Create `layers/` and move `animator/c/pp_*.c` → `layers/c/`,
`animator/perl/pp_*.pl` → `layers/perl/`. Layers are no longer
under `animator/`.

**14.** Create `layers/tests/` and add one test file per layer
(see section E for the test plan). Move `tests/test_indent_last.pl`
→ `layers/tests/test_indent_last.pl`.

**15.** Keep only the actual animator source in `animator/`:
`animator.c` (renamed `ad_animator.c`), `animator.pl`, the
colorize helper, and the vimscript animator. Move
`animator/diffvim-pipeline` → `pipeline/bin/ad_pipeline`.

**16.** Create `apps/vim/` and move `diffvim` → `apps/vim/ad_vim`,
`diffvim.pl` → `apps/vim/ad_vim.pl` (or delete the Perl duplicate).
Move `plugin/diffvim.vim` → `apps/vim/plugin.vim`.

**17.** Create `tools/bin/` and move `scripts/dv_*.sh` →
`tools/bin/ad_<verb>.sh` (renamed per A-9).

**18.** Delete the root-level junk files: `A`, `B`, `a`, `b`,
`jq_filter`, `difft_json_to_lcs`, `set_config`, `lcs_tools.txt`,
`first_improvements.md`, `IMPROVEMENTS.md`, `the_diff.diff`.
These are either scratch files, aborted experiments, or
superseded docs.

**19.** Delete `DiffVim/` (contains `Parser/Perl.pm` — looks like an
aborted Perl OO refactor; not referenced anywhere).

**20.** Delete `autoload/` and `plugin/` if they contain vim-runtime
files that duplicate `apps/vim/plugin.vim` (after move per B-16).

**21.** Move `packaging/diffvim.rb` → `packaging/ad_vim.rb` (Homebrew
formula) and update the formula's `bin` and `man` install paths to
match the new structure.

**22.** Move `l2r_test/` → `diff_engine/tests/l2r/` (it's a test for
the diff engine's left-to-right mode, not a top-level concept).

---

## C. Build system — single `bin/`, no binaries in git

**23.** Update `.gitignore` to ignore `bin/` (single directory).
Remove the per-directory `animator/bin/`, `compute/bin/` entries —
they're subsumed by the single `bin/`.

**24.** Update `Makefile` to build all binaries into `bin/`:
`bin/ad_compute`, `bin/ad_animator`, `bin/ad_postprocess`,
`bin/ad_layer_<name>`, `bin/ad_pipeline`. The `bin/` directory is
created by `make` if missing.

**25.** Update `Makefile` install target to copy from `bin/` to
`$(DESTDIR)$(BINDIR)`. Single source of binaries.

**26.** Update `Makefile` to add a per-layer target
`bin/ad_layer_<name>` for each layer, depending on the C source AND
the layer's test file (so touching either triggers rebuild + test
re-run).

**27.** Update the `make test` aggregate target to run:
(a) per-layer tests, (b) cross-cutting tests (property, examples),
(c) the l2r diff-engine tests. Make this list data-driven if
possible (e.g. glob `layers/tests/test_*.pl`).

**28.** Add `make install-bin`, `make install-man`,
`make install-comp`, `make install-docs` targets, all writing
to `$(DESTDIR)$(PREFIX)/`. Keep the existing prefix semantics.

---

## D. Layer discovery — the core rewrite

The current discovery (manifest + `--enable` + `--layers=` + implicit
language scan) is wrong on every count you raised. Replace it with a
minimal, user-driven model.

**29.** Delete `animator/layers.conf` (now `layers/layers.conf` after
B-13). The manifest was wrong — it forces the user to learn a custom
file format and to edit it to add a layer. Replace with explicit
user-supplied chain on the command line.

**30.** Drop `--enable=<name>` entirely. The user always supplies
the full chain via repeated `--ad-layer=<name>` flags. There is no
"default minus removed" concept.

**31.** Drop `--layers=<csv>` entirely. Repeated `--ad-layer=<name>`
flags replace it (one flag per layer, in argv order).

**32.** `--ad-layer=<name>` runs layers **in argv order**, not by
any manifest `order` field. `ad_vim --ad-layer=reorder
--ad-layer=indent_last --ad-layer=pace` runs them in that exact
sequence.

**33.** `--ad-layer=<name>` supports **extensions**: `--ad-layer=foo`,
`--ad-layer=foo.pl`, `--ad-layer=foo.py` are all valid. The orchestrator
looks up the file verbatim — no implicit `pp_` prefix when an
extension is present.

**34.** `--ad-layer=foo --ad-layer=foo` runs `foo` **twice**
(idempotency is the layer's problem, not the orchestrator's). Document
this explicitly.

**35.** `--ad-layer-path=<dir>` (repeatable) adds a directory to the
layer search path. Default search path = `<project>/layers/c` and
`<project>/layers/perl` only. The user can override or extend.

**36.** Layer search algorithm:
  (a) If `<name>` contains `/`, treat as a path (relative to CWD or
      absolute). Run it directly.
  (b) Else, search each `--ad-layer-path` dir in declared order. The
      first directory that contains a file named `<name>` (verbatim)
      wins.
  (c) If no match, error: `ad_postprocess: layer '<name>' not found
      in: <list of searched dirs>`.
  (d) If the matched file has extension `.pl`, invoke with `perl`.
      If `.py`, with `python3`. If `.rb`, with `ruby`. If `.sh`, with
      `bash`. If `.js`, with `node`. Otherwise, the file must be
      executable and is run directly (no interpreter). If not
      executable, error: `ad_postprocess: layer '<name>' is not
      executable`. **No magic auto-discovery across language dirs.**

**37.** Keep `--list-layers` but make it list the **contents of the
`--ad-layer-path` dirs** (so the user sees what's available in their
chosen search path). No manifest to list.

**38.** The default layer chain (when no `--ad-layer` is given) is
hardcoded in the `ad_vim` launcher as: `reorder`, `pace`,
`highlight`. This is the *application* default — the orchestrator
itself has no opinion about what runs by default.

**39.** Drop `--pp-<name>` (the generic forwarding prefix introduced
in commit `b97649e`). Replace with `--ad-layer=<name>` everywhere.
Update `ad_vim` and `ad_pipeline` launchers accordingly.

---

## E. Tests — TDD for layers, run on layer changes

**40.** Write one test file per layer, in `layers/tests/`:
`test_reorder.pl`, `test_overwrite.pl`, `test_indent_last.pl`,
`test_line_delete_in_place.pl`, `test_pace.pl`, `test_highlight.pl`.
Each test:
  - Feeds a known V2 TSV input (committed alongside the test as
    `<test_name>_in.tsv`).
  - Asserts specific V2 TSV output (committed as
    `<test_name>_out.tsv`).
  - Asserts the layer is invokable standalone
    (`bin/ad_layer_<name> < in > out; exit 0`).
  - For layers with both C and Perl twins, asserts byte-identical
    output (parity).

**41.** Write the test FIRST (red), then implement the layer (green).
This is enforced by review, not by tooling — but the test file MUST
exist in the same commit that adds the layer.

**42.** Add `Makefile` targets per layer:
`test-layer-reorder`, `test-layer-overwrite`,
`test-layer-indent_last`, `test-layer-line_delete_in_place`,
`test-layer-pace`, `test-layer-highlight`. Aggregate target:
`test-layers` runs them all.

**43.** Add a `Makefile` dependency: `bin/ad_layer_<name>` depends
on both `layers/c/ad_layer_<name>.c` AND
`layers/tests/test_<name>.pl`. Touching either rebuilds the layer
and re-runs its test.

**44.** Delete `tests/test_postprocess_layers.sh` — it references
`pp_layer0/1/2/3` (old layer numbering that no longer exists).
Dead code.

**45.** Consolidate the two parallel test directories (`tests/` and
`animator/tests/`) into one `tests/` directory at the project root.
Move `animator/tests/*.pl` → `tests/`. The `layers/tests/` and
`diff_engine/tests/` subdirectories hold tests that are
category-specific; cross-cutting tests live in `tests/`.

**46.** Add a property-based test runner
(`tests/test_property.pl` — already exists) to the `make test`
aggregate. It runs 50 random diffs through the entire pipeline and
checks invariants (no backward ops, output matches new file).

---

## F. CI integration — restore what was deleted

Commit `b209339` deleted both `.github/workflows/build-and-test.yml`
and `.github/workflows/docs.yml`. They were added in `0888caa` and
should never have been removed.

**47.** Restore `.github/workflows/build-and-test.yml` with the
following updates to match the new structure:
  - Build: `make` (now produces `bin/*`).
  - Test: `make test` (runs unit + layers + property + l2r).
  - Cache `~/.cache/ad/` between runs (for any future state).
  - Run on push to `main` and on all PRs.

**48.** Restore `.github/workflows/docs.yml` with the following
updates:
  - Trigger on push to `main` when `docs/**` changes.
  - Install `mdbook` (pin version, e.g. v0.4.40).
  - Add `docs/book.toml` (currently missing — see F-49).
  - Build: `cd docs && mdbook build`.
  - Publish to GitHub Pages (`actions/deploy-pages@v4`).
  - Upload artifact for download.

**49.** Add `docs/book.toml` (currently missing — that's why
mdbook never built). Minimal config:
```toml
[book]
title = "ad — animate a diff"
authors = ["nkh"]
language = "en"

[output.html]
git-repository-url = "https://github.com/nkh/gitanim"
```

**50.** Add a third workflow `.github/workflows/lint.yml`:
  - Run `shellcheck` on every `*.sh` file (ad_vim, ad_pipeline,
    tools/bin/*.sh).
  - Run `perl -c` on every `*.pl` file (syntax check).
  - Run `gcc -fsyntax-only -Wall -Wextra` on every `*.c` file.
  - Block PR on any failure.

**51.** Add a fourth workflow `.github/workflows/release.yml`:
  - Trigger on git tag `v*`.
  - Build `make`.
  - Create a GitHub Release with tarball of `bin/`, `man/`,
    `completion/`, and the source.

**52.** Document the CI setup in `docs/src/contributing.md`:
  - How to run CI locally (`make test` mirrors build-and-test.yml).
  - How to preview docs locally (`mdbook serve docs/`).
  - How the layer test gating works.

---

## G. Configuration — XDG, not invented places

**53.** Drop the `~/.diffvimrc` fallback path from `ad_pipeline`
(today it sources both `~/.config/diffvim/config` AND
`~/.diffvimrc`). Use `$XDG_CONFIG_HOME/ad/config` only. Default to
`~/.config/ad/config` when `XDG_CONFIG_HOME` is unset.

**54.** Move project-wide defaults out of the bash launcher into a
real config file. Today `ad_vim` has ~50 `DIFFVIM_*` env-var
declarations hardcoded as bash variables. Move them to
`/etc/ad/config` (system) and `~/.config/ad/config` (user), sourced
at startup.

**55.** Audit and remove the `DV_*` environment variables (currently
mixed with `DIFFVIM_*`). Standardize on `AD_*` per A-10. Backward
compat: print a deprecation warning if a `DV_*` var is set, but
still read it for one release cycle.

**56.** Drop the `DIFFVIM_CONFIG_LOADED` env-var hack in
`ad_pipeline`. Source the config file once at the top of the
launcher; if the file doesn't exist, use defaults. No env-var
guard needed.

**57.** Document the config file format in `docs/src/configuration.md`
(replace the existing file, which is out of date).

---

## H. Documentation cleanup

**58.** Move `FLEXIBILITY.md` (root) → `docs/src/plugin-layers.md`
(it's documentation, belongs with the other mdbook source).

**59.** Audit `docs/*.md` (60+ files): delete the design-decision
docs that describe decisions already made
(`POSTPROCESS_REDESIGN.md`, `PER_LAYER_ADJUSTMENT_REQUIREMENTS.md`,
`ARCHITECTURE_ANALYSIS.md`, `OPTION_AUDIT.md`, etc.). Keep only
user-facing reference docs.

**60.** Move surviving design docs to `docs/design/` (separate
mdbook section). Keep `docs/src/` for user-facing reference.

**61.** Update `docs/src/SUMMARY.md` to add the new sections:
Plugin Layers (from F-58), Contributing (from F-52),
Configuration (updated G-57).

**62.** Update `README.md` to reflect the new project name (`ad`)
and the new directory structure. Drop the vim-centric framing.

**63.** Update `man/*.1` files: rename per A-4 through A-9. Update
all internal references from `diffvim-*` to `ad_*`.

**64.** Update `completion/diffvim.bash` → `completion/ad_vim.bash`,
`completion/diffvim.fish` → `completion/ad_vim.fish`,
`completion/_diffvim` → `completion/_ad_vim`. Update internal
command names.

---

## I. Migration plan (suggested order)

If you select all changes, here's the dependency-aware order:

1. **First (no behavior change, pure file moves):** B-12, B-13,
   B-15, B-16, B-17, B-22, C-23, C-24. Just move files and update
   Makefile paths.
2. **Then (rename, update references):** A-1 through A-11, C-25,
   C-26, H-58 through H-64. Rename binaries and update all
   references in scripts, manpages, completions, docs.
3. **Then (rewrite discovery):** D-29 through D-39. Rewrite the
   orchestrator + launchers to use the new `--ad-layer=<name>`
   model.
4. **Then (TDD):** E-40 through E-46. Write per-layer tests.
5. **Then (CI):** F-47 through F-52. Restore and extend workflows.
6. **Finally (config):** G-53 through G-57. Move config to XDG path.

---

## J. Open questions for you

**Q1.** Do you want to keep the Perl twins for every layer, or
only for `indent_last`, `pace`, `highlight` (the three that have
them today)? Keeping twins means more maintenance but C/Perl parity
is a useful invariant.

**Q2.** The `diff_engine/` directory holds the LCS/Hirschberg
engine. Should we keep both C++ and Perl implementations, or
commit to one? The C++ is faster; the Perl is easier to read.

**Q3.** Should `apps/vim/` (the vim application) live in this
repo, or be split into a separate `ad_vim` repo that depends on
`ad` as a library/submodule? The current monorepo is simpler; a
split would let the vim app evolve independently.

**Q4.** Are you OK with the breaking change of dropping `DV_*`
env vars in favor of `AD_*`? Or do you want a longer deprecation
period (e.g. one minor version)?

**Q5.** The `examples/` directory has 44 subdirectories. Should
these become the canonical test corpus (renamed
`tests/examples/`), or stay separate as user-facing examples?
