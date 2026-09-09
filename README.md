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

# Animate in vim (interactive, uses the vimscript engine)
./apps/vim/ad_vim old.py new.py

# Or run headless with the C animator (no vim, just the pipeline)
# This is faster and more reliable for testing/CI
./pipeline/ad_pipeline old.py new.py

# Animate your last commit
./apps/vim/ad_vim <(git show HEAD^:file.py) <(git show HEAD:file.py)

# Replay a file's last 5 commits
./apps/vim/ad_vim --replay src/main.py --from HEAD~5 --to HEAD
```

### Two animators

The project has two animators that apply the same op stream:

- **`ad_vim`** (vimscript) — interactive, runs inside vim. Use this for
  watching the animation and reviewing diffs. Slower for large files.
- **`bin/ad`** (C) — headless, runs in the terminal. Use this for
  testing, CI, and when you just want the output without animation.
  Invoke via `./pipeline/ad_pipeline` or directly with precomputed ops:
  ```bash
  bin/ad_compute old.py new.py /tmp/ops.tsv
  bin/ad --no-display --speed 1000 --snapshot out.txt old.py < /tmp/ops.tsv
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

| Layer                           | What it does                                        |               |
| ------------------------------- | --------------------------------------------------- | ------------- |
| `ad_layer_reorder`              | Deletes before inserts within each line             |               |
| `ad_layer_overwrite`            | Merge adjacent delete+insert into overwrite         |               |
| `ad_layer_indent_last`          | Move whitespace deletes to end of line              |               |
| `ad_layer_line_delete_in_place` | Delete content before joining lines (`--mode batch\ | interleaved`) |
| `ad_layer_skip_indent`          | Skip animation for indent-only changes              |               |
| `ad_layer_pace`                 | Add timing delays between ops                       |               |
| `ad_layer_highlight`            | Add highlight/dim/fold decorations                  |               |

No layers run by default. Add them explicitly:
```bash
./apps/vim/ad_vim --ad-layer=ad_layer_reorder old.py new.py
```

Or use a `.ad_layers` file to define layer groups (see [INSTALL.md](INSTALL.md)).

### Layer options

Some layers accept options. Pass them via `--ad-layer-arg`:

```bash
# Use line_delete_in_place in interleaved mode
./pipeline/ad_postprocess \
    --ad-layer=ad_layer_reorder \
    --ad-layer=ad_layer_line_delete_in_place \
    --ad-layer-arg=ad_layer_line_delete_in_place:--mode=interleaved \
    < raw.tsv > post.tsv

# Then animate:
./apps/vim/ad_vim --precomputed post.tsv old.py new.py
```

Available modes for `ad_layer_line_delete_in_place`:
- `--mode batch` (default) — delete all content first, then join all empty lines
- `--mode interleaved` — delete each line's content, then immediately join

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

## Scripts and Tools

| Tool                      | What it does                                              |
| ------------------------- | --------------------------------------------------------- |
| `apps/vim/ad_vim`         | Main entry point — animates a diff in vim                 |
| `pipeline/ad_pipeline`    | Headless pipeline (C animator, no vim)                    |
| `pipeline/ad_postprocess` | Layer orchestrator — chains layers via `--ad-layer`       |
| `scripts/ad_session`      | Interactive vim debugger with L1/L2, folds, git           |
| `scripts/ad_gen_ops`      | Generate ops from old/new files + layer chain             |
| `scripts/ad_annotate`     | Add `# old:` / `# new:` context comments to ops           |
| `scripts/ad_l1l2`         | Find where ops start failing (L1=last good, L2=first bad) |
| `scripts/ad_anim_test`    | Test animation: per-op snapshots, in-place checks         |
| `scripts/ad_watch`        | Live-preview old/new/diff, auto-refresh on save           |
| `scripts/ad_tmux_watch`   | tmux-based session tool                                   |
| `bin/ad_compute`          | Diff engine — produces char-level ops from old/new files  |
| `bin/ad`                  | C animator — applies ops to a buffer, headless            |
| `bin/ad_layer_*`          | Layer binaries (reorder, overwrite, indent_last, etc.)    |

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
