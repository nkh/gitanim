# Commit / File Picker

ad_vim provides interactive commit and file pickers via **fzf** (or
built-in fallback) for selecting what to animate.

## In Vim (`:DiffvimPick`, `:DiffvimCommit`)

The vim plugin (`plugin/diffvim.vim`) defines these commands:

### `:DiffvimPick`

Opens an interactive commit picker with diff preview:

1. Lists all commits that touched the current buffer's file
2. Shows commit hash, short hash, message, and relative date
3. Preview pane shows `git show --stat --patch --color=always` for the
   selected commit
4. Press `Enter` to animate the diff from that commit to the working
   copy

**Backend auto-detection:**
1. **fzf.vim** (vim plugin) — if `fzf#run` exists
2. **fzf CLI** — if `fzf` binary exists (runs in a terminal buffer)
3. **forgit** — if `forgit` command exists
4. **builtin** — vim's `inputlist()` (no preview, numbered list)

**Configuration:**
```vim
let g:diffvim.commit_picker = 'auto'  " or 'fzf', 'fzf-cli', 'forgit', 'builtin'
```

**Requirements:**
- `git` — must be in a git repository
- `fzf` (recommended) — for the best experience with preview
- `forgit` (optional) — alternative picker

### `:DiffvimCommit [commit]`

Animates the diff between the current buffer and a git commit.

- With no argument: prompts for a commit hash
- With a commit argument: animates directly

```vim
:DiffvimCommit HEAD~3
:DiffvimCommit abc1234
```

### `:Diffvim [old] [new]`

The main command — animate a diff between two files.

```vim
:Diffvim old.py new.py
```

## Command Line (ad_vim --replay)

The `diffvim` launcher supports git history replay:

```bash
# Animate all changes to a file between two commits
ad_vim --replay --from HEAD~3 --to HEAD file.py

# Animate from a commit to working copy
ad_vim --replay HEAD~1 file.py

# Animate a range of commits for a file
ad_vim -r HEAD~5..HEAD -- file.py
```

The `--replay` flag uses `git log --reverse` to find all commits in
the range that touched the file, then animates each transition
(commit N → commit N+1) in sequence.

**Options:**
- `--replay (-r)` — enable replay mode
- `--from REV` — starting commit (default: first commit touching the file)
- `--to REV` — ending commit (default: working copy / HEAD)
- `--git-rev REV..REV` — shorthand for `--from REV1 --to REV2`

## Standalone Animator (ad_pipeline)

The standalone pipeline does not currently have a built-in picker.
To animate a git commit diff:

```bash
# Get the old version from git
git show HEAD~1:file.py > /tmp/old.py

# Animate
ad_pipeline /tmp/old.py file.py
```

Or as a shell function:

```bash
dv-git() {
    local file=$1 commit=${2:-HEAD~1}
    git show "$commit:$file" > /tmp/dv_old.tmp 2>/dev/null
    ad_pipeline /tmp/dv_old.tmp "$file"
}

# Usage: dv-git file.py HEAD~3
```

## fzf Integration for File Picking (not yet built)

A `:DiffvimPickFile` command (pick a file, then animate its diff vs HEAD
or a picked commit) is planned but not yet implemented. The commit
picker (`:DiffvimPick`) already works.
