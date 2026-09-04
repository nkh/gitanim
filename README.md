# ad — animate a diff

`ad` is a toolkit for animating code diffs. It opens an old file and progressively transforms it into the new file, character by character, as if a human were typing the changes.

`ad_vim` is the vim application — one consumer of the toolkit — that renders the animation in vim.

## Quick start

```bash
# Build all binaries
make

# Animate a diff in vim:
./apps/vim/ad_vim old.py new.py

# Run the full pipeline without vim:
./pipeline/ad_pipeline old.py new.py

# Debug ops interactively (vim-only):
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder

# Run all tests:
make test
```

## Installation

See [INSTALL.md](INSTALL.md) for:
- Prerequisites
- Build targets (`make`, `make layers`, `make tools`, etc.)
- Installation (`make install`)
- Testing (`make test`, individual test targets)
- Debugging tools (`ad_session`, `ad_tmux_watch`, `ad_gen_ops`, `ad_watch`)
- The `.ad_layers` layer group file
- Directory structure
- Troubleshooting

## Documentation

- [INSTALL.md](INSTALL.md) — Building, installing, and testing
- [docs/src/](docs/src/) — User guide (mdBook source)
- [docs/LAYERS_REFERENCE.md](docs/LAYERS_REFERENCE.md) — All layers with pseudo-code and examples
- [docs/LAYERS_REVIEW.md](docs/LAYERS_REVIEW.md) — Layer audit with known problems
- [docs/design/AD_SESSION_REQUIREMENTS.md](docs/design/AD_SESSION_REQUIREMENTS.md) — Debugging tool design
- [docs/src/plugin-layers.md](docs/src/plugin-layers.md) — Plugin layer contract

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
