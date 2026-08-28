# ad — animate a diff

`ad` is a toolkit for animating code diffs. It opens an old file and progressively transforms it into the new file, character by character, as if a human were typing the changes.

`ad_vim` is the vim application — one consumer of the toolkit — that renders the animation in vim.

## Pipeline

```
<old> <new> → ad_compute → ad_postprocess → ad_layer_pace → ad → animation
```

| Stage | Binary | Language | Purpose |
|-------|--------|----------|---------|
| compute | `bin/ad_compute` | C++ | Patience diff → raw char ops |
| postprocess | `pipeline/ad_postprocess` | Bash | Layer orchestrator (runs `--ad-layer=<name>` chain) |
| layers | `bin/ad_layer_<name>` | C + Perl | Reorder, overwrite, indent_last, pace, highlight, … |
| animator | `bin/ad` | C | Apply ops to buffer, render to terminal |

Each layer has both a C implementation (`layers/c/`) and a Perl twin (`layers/perl/`) that produce byte-identical output.

## Quick start

```bash
# Build all binaries into bin/
make

# Animate a diff in vim:
./apps/vim/ad_vim old.py new.py

# Run the full pipeline without vim (terminal output):
./pipeline/ad_pipeline old.py new.py

# List available layers:
./pipeline/ad_postprocess --list-layers

# Add a custom layer to the chain:
./pipeline/ad_pipeline --ad-layer=my_custom_layer old.py new.py

# Debug the pipeline:
./scripts/ad_debug.sh old.py new.py

# Run all tests:
make test
```

## Directory structure

| Directory | Contents |
|-----------|----------|
| `bin/` | Build output (gitignored; created by `make`) |
| `diff_engine/` | Diff engine (C++ + Perl) — LCS/Hirschberg |
| `layers/` | Postprocess layer plugins (C + Perl twins) + per-layer tests |
| `animator/` | Animator backend (C + Perl) |
| `pipeline/` | Orchestrator (`ad_postprocess`) + pipeline driver (`ad_pipeline`) |
| `apps/vim/` | `ad_vim` — the vim application launcher |
| `scripts/` | Helper scripts (`ad_debug`, `ad_snapshot`, `ad_record`, etc.) |
| `perl/` | Shared Perl library code |
| `tests/` | Cross-cutting tests + `examples/` (canonical test corpus) |
| `docs/` | mdBook documentation source + `design/` (historical design docs) |
| `man/` | Manpages |
| `completion/` | Shell completions (bash, fish, zsh) |
| `packaging/` | Homebrew formula |
| `.github/workflows/` | CI: build-and-test, docs, lint, release |

## Configuration

`ad_vim` reads config from `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config`). See [docs/src/configuration.md](docs/src/configuration.md) for the full reference.

## Documentation

- [docs/src/](docs/src/) — User guide (mdBook source)
- [docs/src/plugin-layers.md](docs/src/plugin-layers.md) — Plugin layer contract
- [docs/src/contributing.md](docs/src/contributing.md) — How to add a layer (TDD)
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

## License

See [LICENSE](LICENSE).
