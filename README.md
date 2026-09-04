# ad — animate a diff

**Watch your code changes come to life.**

`ad` takes two versions of a file and animates the transformation —
character by character, as if a human were typing the changes in real
time. It works with any text file: Python, JavaScript, C, HTML, config
files, prose. If you can diff it, you can animate it.

## Why?

Code reviews show you *what* changed. `ad` shows you *how* it changed —
the order of edits, the rhythm of typing, the places where a small
change ripples through the file. It's a different way to understand a
diff.

Use it for:
- **Demos** — show how a refactor unfolded, not just the final result
- **Code review** — see the edit sequence, spot ordering issues
- **Teaching** — animate how an algorithm was built up step by step
- **Debugging** — watch a bug fix being applied, see if the edit order
  makes sense

## Quick start

```bash
# Build
make

# Animate in vim
./apps/vim/ad_vim old.py new.py

# Or run headless (no vim, just the pipeline)
./pipeline/ad_pipeline old.py new.py

# Debug the ops interactively (vim-only, with diff split + folds)
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder
```

## How it works

```
old.py ──→ ad_compute ──→ ad_postprocess ──→ ad_layer_pace ──→ ad (animator)
new.py     (diff engine)    (layer chain)      (delays)         (vim/terminal)
```

1. **`ad_compute`** — runs a patience diff, produces char-level ops
   (`keep`, `delete`, `insert`) with `(line, col)` positions
2. **`ad_postprocess`** — runs a chain of layer plugins that transform
   the ops (reorder, merge, annotate)
3. **`ad_layer_pace`** — inserts delay ops for animation timing
4. **`ad`** — applies the ops to the old file's buffer, renders each
   step

Each layer is a standalone binary that reads TSV from stdin and writes
TSV to stdout. You can chain any layers in any order:

```bash
./bin/ad_compute old.py new.py /tmp/raw.tsv
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < /tmp/raw.tsv > /tmp/ops.tsv
./bin/ad old.py < /tmp/ops.tsv
```

## Layers

| Layer                           | What it does                                |
| ------------------------------- | ------------------------------------------- |
| `ad_layer_reorder`              | Deletes before inserts within each line     |
| `ad_layer_overwrite`            | Merge adjacent delete+insert into overwrite |
| `ad_layer_indent_last`          | Move whitespace deletes to end of line      |
| `ad_layer_line_delete_in_place` | Delete content before joining lines         |
| `ad_layer_skip_indent`          | Skip animation for indent-only changes      |
| `ad_layer_pace`                 | Add timing delays between ops               |
| `ad_layer_highlight`            | Add highlight/dim/fold decorations          |

No layers run by default. Add them explicitly:
```bash
./apps/vim/ad_vim --ad-layer=ad_layer_reorder old.py new.py
```

Or use a `.ad_layers` file to define layer groups (see [INSTALL.md](INSTALL.md)).

## Debugging tools

The project includes an interactive op debugger:

```bash
# Create a debugging session (vim-only, no tmux needed)
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder --annotate
```

This opens vim with:
- **Left split**: diff between expected new file and the animator's output
- **Right top**: the op list (editable, with syntax highlighting and folds)
- **Right bottom**: the result of applying the ops

Shortcuts: `F5` (animate), `F6` (snapshot + refresh diff), `<leader>g`
(regenerate ops), `<leader>h` (fold hunks), `<leader>a` (toggle
annotations), `<leader>?` (help).

The `--annotate` flag adds `# old:` / `# new:` comments showing the
text content before and after each bundle of ops:

```
# keep: "hello " (line 1, cols 1-6)
keep	1	1	104	'h'
keep	1	2	101	'e'
...
# old: "hello world"
# new: "hello rld"
delete	1	7	119	'w'
delete	1	7	111	'o'
```

## Installation

See [**INSTALL.md**](INSTALL.md) for:
- Prerequisites and build instructions
- All Makefile targets (`make`, `make tools`, `make test`, etc.)
- Installation to a custom prefix
- Full list of binaries, scripts, and manpages
- Debugging tools reference
- The `.ad_layers` layer group file
- Troubleshooting

## Documentation

- [INSTALL.md](INSTALL.md) — Building, installing, testing, debugging
- [docs/src/](docs/src/) — User guide (mdBook)
- [docs/design/LAYERS_REFERENCE.md](docs/design/LAYERS_REFERENCE.md) — All layers with pseudo-code
- [docs/design/LAYERS_REVIEW.md](docs/design/LAYERS_REVIEW.md) — Layer audit and known issues
- [docs/design/AD_SESSION_REQUIREMENTS.md](docs/design/AD_SESSION_REQUIREMENTS.md) — Debugger design

Build the mdBook:
```bash
cd docs && mdbook serve   # http://localhost:3000
```

## Testing

```bash
make test           # all tests
make test-layers    # per-layer C/Perl parity
make test-property  # 50 random property-based tests
make test-examples  # 42 examples through the full pipeline
make test-fuzz      # malformed TSV, binary, empty, large inputs
```

## License

See [LICENSE](LICENSE).
