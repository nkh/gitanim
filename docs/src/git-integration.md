# Git Integration

## --replay: Animate Git History

The `--replay` flag animates a file's git history. For each commit in
the range, it extracts the old version and animates the transformation
to the next commit, ending with the working copy.

```bash
# Animate last 5 commits of a file
diffvim --replay src/main.py

# Specific commit range
diffvim --replay src/main.py --from v1.0 --to HEAD

# Multiple files
diffvim --replay src/main.py src/utils.py
```

### How It Works

1. Get the commit list: `git log --reverse --format=%H FROM..TO -- FILE`
2. For each consecutive commit pair, extract file content:
   - `git show COMMIT:FILE > /tmp/old`
   - `git show NEXT_COMMIT:FILE > /tmp/new`
3. Animate the diff between the extracted files
4. Final pair: last commit → working copy

## --git-rev: Commit Range Syntax

The `--git-rev` flag accepts `REV..REV` syntax:

```bash
diffvim --git-rev HEAD~3..HEAD src/main.py
diffvim --git-rev v1.0..v2.0 src/main.py
diffvim --git-rev abc123..def456 src/main.py
```

This is equivalent to `--replay --from REV1 --to REV2`.

## --git-blame: Show Blame Information

The `--git-blame` flag shows git blame for each changed line:

```bash
diffvim --git-blame old.py new.py
```

During animation, the commit hash and author are displayed for each
line being changed.

## Animating a Git Diff

To animate the diff between the current working copy and the last commit:

```bash
git show HEAD:file.py > /tmp/old.py
diffvim /tmp/old.py file.py
```

Or for a specific commit:

```bash
git show abc123:file.py > /tmp/old.py
diffvim /tmp/old.py file.py
```

## Multi-File Git Replay

Animate multiple files' git history in sequence:

```bash
diffvim --replay src/main.py src/utils.py src/config.py
```

Each file's history is animated separately, with a "next file" message
between them.

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
