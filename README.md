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
diff, and it fits naturally into the git workflows you already run.

Use it for:
- **Self-review before a commit** — animate your staged changes and
  watch the edit sequence before you write the commit message
- **Pull request walkthroughs** — show a reviewer how a branch evolved,
  commit by commit, instead of dumping a 600-line diff
- **Code review follow-ups** — replay the changes a teammate left
  comments on, so the discussion has context
- **Mentoring and pairing** — walk a teammate through how you arrived
  at a solution, not just the final shape of the code
- **Branch retrospectives** — replay a feature branch from main to HEAD
  and see whether the commit ordering tells a clean story

## Quick start

```bash
# Build
make

# Animate in vim
./apps/vim/ad_vim old.py new.py

# Or run headless (no vim, just the pipeline)
./pipeline/ad_pipeline old.py new.py

# Animate your last commit
./apps/vim/ad_vim <(git show HEAD^:file.py) <(git show HEAD:file.py)

# Replay a file's last 5 commits
./apps/vim/ad_vim --replay src/main.py --from HEAD~5 --to HEAD
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

## Good git usage

`ad` is most useful when wired into the git workflows you already run.
The launcher ships with flags for the common cases:

### Review your own work before committing

```bash
# Animate your working-tree changes against the last commit
./apps/vim/ad_vim <(git show HEAD:file.py) file.py

# Animate what you've staged (not yet committed)
./apps/vim/ad_vim <(git show :file.py) <(git stash create)
```

This is a 10-second gut-check before `git commit`: you see whether the
edit order reads like a deliberate change or a fumbled sequence of
saves. If the animation feels off, the commit message probably will
too.

### Walk a reviewer through a branch

```bash
# Replay every commit on this file from main to HEAD
./apps/vim/ad_vim --replay src/main.py --from main --to HEAD

# Same thing, using git rev range syntax
./apps/vim/ad_vim --git-rev main..HEAD src/main.py

# Multiple files in sequence
./apps/vim/ad_vim --replay src/main.py src/utils.py
```

Drop this into a PR description: *"Run `ad_vim --git-rev main..HEAD src/main.py` for a walkthrough."* Reviewers
get a narrative instead of a wall of unified diff.

### See who last touched each animated line

```bash
./apps/vim/ad_vim --git-blame <(git show HEAD^:file.py) file.py
```

Each changed line is annotated with the commit hash and author while it
animates — useful when a review touches code you didn't write and you
want context without leaving vim.

### Pick a single commit to understand

```bash
# Animate one specific commit's effect on a file
./apps/vim/ad_vim <(git show abc123^:file.py) <(git show abc123:file.py)
```

Helpful for "what did this hotfix actually do?" moments during incident
review, or when cherry-picking a commit and wanting to verify the
intent before applying it.

See [docs/src/git-integration.md](docs/src/git-integration.md) for the
full set of git flags (`--replay`, `--git-rev`, `--git-blame`,
multi-file replay).

## Installation

See [**INSTALL.md**](INSTALL.md) for:
- Prerequisites and build instructions
- All Makefile targets (`make`, `make tools`, `make install`, etc.)
- Installation to a custom prefix
- Full list of binaries, scripts, and manpages
- The `.ad_layers` layer group file
- Interactive session tooling for op inspection
- Troubleshooting

## Documentation

- [INSTALL.md](INSTALL.md) — Building, installing, running the suite
- [docs/src/](docs/src/) — User guide (mdBook)
- [docs/src/git-integration.md](docs/src/git-integration.md) — All git flags and workflows
- [docs/design/LAYERS_REFERENCE.md](docs/design/LAYERS_REFERENCE.md) — All layers with pseudo-code
- [docs/design/LAYERS_REVIEW.md](docs/design/LAYERS_REVIEW.md) — Layer audit and known issues

Build the mdBook:
```bash
cd docs && mdbook serve   # http://localhost:3000
```

## License

See [LICENSE](LICENSE).
