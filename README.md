# ad — animate a diff

*Created:* `e99e6fd` (2026-08-10 06:57:04 +0200)
*Last updated:* `4a013a6` (2026-08-28 20:15:31 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


`ad` is a toolkit for animating code diffs. It opens an old file and progressively transforms it into the new file, character by character, as if a human were typing the changes.

`ad_vim` is the vim application — one consumer of the toolkit — that renders the animation in vim.

## Quick start

```bash
# Build all binaries into bin/
make

# Animate a diff in vim:
./apps/vim/ad_vim old.py new.py

# Run the full pipeline without vim (terminal output):
./pipeline/ad_pipeline old.py new.py

# List available postprocess layers:
./pipeline/ad_postprocess --list-layers

# Add a custom layer to the chain:
./pipeline/ad_pipeline --ad-layer=my_custom_layer old.py new.py

# Debug the pipeline:
bash scripts/ad_debug.sh old.py new.py

# Run all tests:
make test
```

## Directory structure

```
ad/
│
├── Makefile                    # builds everything into bin/
├── README.md                   # this file
├── CHANGELOG.md
├── LICENSE
├── .gitignore                  # ignores bin/, stale dirs, editor files
│
├── bin/                        # BUILD OUTPUT (gitignored, created by `make`)
│   ├── ad                      #   ← animator (from animator/c/ad.c)
│   ├── ad_compute              #   ← diff engine (from diff_engine/cpp/compute.cpp)
│   ├── ad_layer_reorder        #   ← postprocess layers (from layers/c/*.c)
│   ├── ad_layer_overwrite
│   ├── ad_layer_indent_last
│   ├── ad_layer_line_delete_in_place
│   ├── ad_layer_pace
│   └── ad_layer_highlight
│
├── diff_engine/                # THE DIFF ENGINE — computes LCS-based char ops
│   ├── cpp/
│   │   └── compute.cpp         #   C++ implementation → bin/ad_compute
│   ├── perl/
│   │   └── compute.pl          #   Perl fallback (identical output)
│   ├── tests/
│   │   └── l2r/                #   left-to-right algorithm tests (35 cases)
│   ├── Makefile
│   ├── README.md
│   └── PARALLELISM.md
│
├── layers/                     # POSTPROCESS LAYERS — plugins that transform op streams
│   ├── c/                      #   C implementations (compiled to bin/ad_layer_*)
│   │   ├── ad_layer_common.h  #     shared types + I/O helpers
│   │   ├── ad_layer_reorder.c #     4-sweep reorder + position adjust
│   │   ├── ad_layer_overwrite.c      merge delete+insert → overwrite_insert
│   │   ├── ad_layer_indent_last.c    move whitespace deletes to end of line
│   │   ├── ad_layer_line_delete_in_place.c  delete lines on their own line
│   │   ├── ad_layer_pace.c          insert delay ops between ops
│   │   └── ad_layer_highlight.c     insert highlight/dim/fold ops
│   ├── perl/                   #   Perl twins (byte-identical output to C)
│   │   ├── ad_layer_reorder.pl
│   │   ├── ad_layer_overwrite.pl
│   │   ├── ad_layer_indent_last.pl
│   │   ├── ad_layer_line_delete_in_place.pl
│   │   ├── ad_layer_pace.pl
│   │   ├── ad_layer_highlight.pl
│   │   └── ad_layer_noop.pl    #     template for writing new layers
│   └── tests/                  #   per-layer TDD tests (one file per layer)
│       ├── test_reorder.pl
│       ├── test_overwrite.pl
│       ├── test_indent_last.pl
│       ├── test_line_delete_in_place.pl
│       ├── test_pace.pl
│       └── test_highlight.pl
│
├── animator/                   # THE ANIMATOR — applies ops to a buffer, renders
│   ├── c/
│   │   └── ad.c                #   C implementation → bin/ad
│   ├── perl/
│   │   ├── ad.pl               #   Perl fallback (identical output)
│   │   └── colorize.pl         #   syntax highlighting helper
│   └── README.md
│
├── pipeline/                   # PIPELINE DRIVERS (bash scripts, not compiled)
│   ├── ad_postprocess          #   layer orchestrator: chains --ad-layer=<name> plugins
│   ├── ad_pipeline             #   end-to-end driver: compute → postprocess → pace → animate
│   └── README.md
│
├── apps/                       # APPLICATIONS built on the ad toolkit
│   └── vim/
│       ├── ad_vim              #   the vim application launcher (bash)
│       ├── ad_vim.pl           #   Perl parallel launcher (duplicate)
│       ├── diffvim             #   backward-compat wrapper (exec's ad_vim)
│       ├── plugin.vim          #   vim plugin entry point (:DiffVim command)
│       ├── autoload_diffvim/   #   vimscript animation engine
│       └── README.md
│
├── scripts/                    # HELPER SCRIPTS (bash, not compiled)
│   ├── ad_debug.sh             #   interactive pipeline debugger
│   ├── ad_debug_bundle.sh     #   collect debug info into a tarball
│   ├── ad_snapshot.sh          #   per-op HTML snapshots
│   ├── ad_record.sh            #   record animation to a file
│   ├── ad_replay.sh            #   replay a recorded animation
│   ├── ad_demo.sh              #   demo runner with preset examples
│   ├── ad_tune.sh              #   interactive option tuner (tmux)
│   ├── ad_suggest.sh           #   suggest options for a given diff
│   ├── ad_package.sh           #   package the project for distribution
│   ├── ad_compare              #   generate diffs with all option combos
│   ├── ad_jogger               #   generate test cases with patterns
│   ├── ad_tmux                 #   tmux-based animation launcher
│   └── README.md
│
├── perl/                       # SHARED PERL LIBRARY CODE (currently empty; reserved)
│   └── README.md
│
├── tests/                      # TEST SUITES + CANONICAL TEST CORPUS
│   ├── examples/               #   36 old/new file pairs (26 languages) — canonical corpus
│   │   ├── 01_small_python/    #     each subdir has old.<ext> and new.<ext>
│   │   ├── 02_large_python/
│   │   ├── ...                 #     run with: bash tests/run_all_examples.sh
│   │   └── README.md
│   ├── minimal/                #   25 minimal cases (one transformation each)
│   │   └── ...
│   ├── test_property.pl        #   50 random property-based tests
│   ├── test_layers_discovery.pl  # plugin contract tests
│   ├── test_all_animators.pl   #   round-trip tests (C + Perl parity)
│   ├── test_roundtrip.pl       #   end-to-end round-trip
│   ├── run_all_examples.sh     #   runs the 36-example corpus
│   ├── run_minimal_tests.sh    #   runs the 25 minimal cases
│   ├── verify_md5.sh           #   md5 verification of pipeline output
│   └── ...                     #   more test scripts
│
├── docs/                       # DOCUMENTATION (mdBook source + design history)
│   ├── book.toml               #   mdBook config
│   ├── src/                    #   mdBook source (user guide)
│   │   ├── SUMMARY.md          #     table of contents
│   │   ├── introduction.md
│   │   ├── installation.md
│   │   ├── quick-start.md
│   │   ├── configuration.md    #     env vars + config file reference
│   │   ├── plugin-layers.md    #     plugin layer contract (--ad-layer)
│   │   ├── contributing.md     #     TDD workflow for adding layers
│   │   ├── options.md           #     full CLI option reference
│   │   └── ...
│   ├── design/                 #   historical design docs (NOT in the user guide)
│   │   └── ...                 #     58 files; see DOCS_AUDIT.md for relevance scores
│   ├── DOCS_AUDIT.md           #   relevance-scored inventory of design docs
│   ├── ENV_VAR_ANALYSIS.md     #   analysis of 107 AD_* env vars + reduction plan
│   ├── RESTRUCTURE_ANALYSIS.md  # the restructure proposal
│   └── README.md
│
├── man/                        # MANPAGES
│   ├── ad_vim.1
│   ├── ad_compute.1
│   ├── ad_debug.1
│   ├── ad_snapshot.1
│   ├── ad_layer_highlight.1
│   └── ...                     #   17 manpages total
│
├── completion/                 # SHELL COMPLETIONS
│   ├── ad_vim.bash             #   bash
│   ├── ad_vim.fish            #   fish
│   ├── _ad_vim                 #   zsh
│   └── README.md
│
├── packaging/                 # PACKAGING RECIPES
│   ├── ad_vim.rb               #   Homebrew formula
│   └── README.md
│
└── github/                     # CI WORKFLOW FILES (move to .github/workflows/ to activate)
    ├── build-and-test.yml
    ├── docs.yml
    ├── lint.yml
    └── release.yml
```

## Configuration

`ad_vim` reads config from `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config`). See [docs/src/configuration.md](docs/src/configuration.md) for the full reference.

## Documentation

- [docs/src/](docs/src/) — User guide (mdBook source)
- [docs/src/plugin-layers.md](docs/src/plugin-layers.md) — Plugin layer contract
- [docs/src/contributing.md](docs/src/contributing.md) — How to add a layer (TDD)
- [docs/ENV_VAR_ANALYSIS.md](docs/ENV_VAR_ANALYSIS.md) — Analysis of 107 env vars + reduction plan
- [docs/DOCS_AUDIT.md](docs/DOCS_AUDIT.md) — Inventory of design docs with relevance scores
- [docs/RESTRUCTURE_ANALYSIS.md](docs/RESTRUCTURE_ANALYSIS.md) — Restructure analysis

Build the mdBook:

```bash
cd docs && mdbook serve   # http://localhost:3000
```

## Rebuilding after git pull

Binaries are gitignored. After `git pull`:

```bash
make clean && make
```

If you have stale directories from before the restructure (e.g. `compute/`, `animator/bin/`, `tools/`), clean them up:

```bash
git clean -fd    # removes untracked files and directories
# or manually:
rm -rf compute/ animator/bin/ tools/
```

## License

See [LICENSE](LICENSE).
