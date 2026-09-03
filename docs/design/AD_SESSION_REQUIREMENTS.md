# `ad_tmux_watch` → `ad_session` — Vim-only interactive op debugger

## Overview

A vim-based interactive tool for debugging op lists. No tmux required.
The tool creates a session directory in the project, copies old/new
files into it, generates initial ops, initializes a git repo, and
launches vim with a split layout showing the diff and the ops.

## Usage

```bash
# Create a new session (generates ops)
ad_session old.py new.py [--ad-layer=ad_layer_reorder]

# Create a new session with existing ops
ad_session old.py new.py existing_ops.tsv [--ad-layer=ad_layer_reorder]

# Resume an existing session
ad_session --resume ad_sessions/my_session

# Resume the most recent session
ad_session --resume-latest

# Custom session name
ad_session old.py new.py --session-name bug42
```

## Session directory

**Location:** `ad_sessions/` in the project root (NOT `/tmp` — sessions
persist across restarts).

**`.gitignore`:** `ad_sessions/` is added to the project's `.gitignore`
(if not already present) so sessions aren't committed to the main repo.

**Directory name:** `ad_sessions/<basename>_<YYYYMMDD_HHMMSS>/` or
`ad_sessions/<custom_name>/` if `--session-name` is given.

The script prints the session directory path on launch.

**Contents:**
```
ad_sessions/oldpy_20260903_143022/
├── old.py          ← copy of original old file
├── new.py          ← copy of original new file
├── ops.tsv         ← op file (generated or copied)
├── result.txt      ← animator output (created on first F5)
├── resume.sh       ← script to resume this session
└── .git/           ← git repo for version tracking
```

### Resume script

`resume.sh` in the session directory:
```bash
#!/usr/bin/env bash
cd "$(dirname "$0")"
exec ad_session --resume .
```

Run with `bash ad_sessions/<name>/resume.sh`.

## Git integration

- `git init` in the session directory on creation.
- Initial commit: "Initial session: old.py, new.py, ops.tsv".
- User commits manually from vim via `:AdCommit` or `<leader>c`.
- `:AdQuit` (`<leader>q`) commits then quits.
- `:AdQuit!` (`<leader>Q`) quits without committing.

## Vim layout

Single vim instance, no tmux:

```
┌─────────────────────┬──────────────────────────┐
│                     │                          │
│  diff split         │  ops.tsv                 │
│  (new vs result)    │  (editing, F5 to run)    │
│                     │                          │
│                     ├──────────────────────────┤
│                     │  result.txt              │
│                     │  (horizontal split)      │
│                     │                          │
└─────────────────────┴──────────────────────────┘
```

- **Left split:** `:vert diffsplit new.<ext>` — shows diff between
  `result.txt` and `new.<ext>`. Updated automatically when F5 runs.
- **Right top:** `ops.tsv` — the op file being edited. Has syntax
  highlighting, fold support, and F5 to run.
- **Right bottom:** `result.txt` — the animator's output. Opens as a
  horizontal split below ops.tsv. Updated on F5.

### Tabs

vim opens with 3 tabs:
1. **Main** (default) — the split layout above
2. **old.<ext>** — the old file (for editing)
3. **new.<ext>** — the new file (for editing)

Switch tabs with `gt` / `gT`.

## F5 — Run animator

Pressing F5 (or running `:AdRun`):
1. Saves `ops.tsv` (if modified).
2. Runs: `bin/ad --no-display --speed 1000 --snapshot result.txt old.<ext> < ops.tsv`
3. Refreshes `result.txt` buffer.
4. Diff split auto-updates (vim detects file change).

**No auto-refresh on save** — only on F5. This is intentional: you
might want to save intermediate states without running the animator
each time.

## Folding

### Fold keep ops

`foldmethod=expr` with a custom fold expression. Consecutive `keep`
ops are folded, showing N context lines (default 5) around non-keep ops.

```
keep    1  1  'h'       ← context (shown)
keep    1  2  'e'       ← context (shown)
keep    1  3  'l'       ← context (shown)
keep    1  4  'l'       ← context (shown)
keep    1  5  'o'       ← context (shown)
+-- 47 lines: keep ops ---  ← folded
keep    1  53 'p'       ← context (shown)
delete  1  54  'X'      ← non-keep (always shown)
keep    1  55  'r'      ← context (shown)
```

- `--fold-context N` (default: 5) — number of context lines.
- `--fold-context 0` — disable keep folding.

### Fold hunks

`:AdFoldHunks` — folds all hunks except the one the cursor is in.
Hunks are delimited by `HUNK` / `HUNK_END` lines.

`--fold-hunks` flag — start with all hunks folded.

### Fold current hunk only

`:AdFoldCurrentHunk` — folds all hunks except the current one (the
one containing the cursor). This is the same as `:AdFoldHunks` but
can be mapped to a shortcut for quick toggling.

Suggested mapping: `<leader>h` — toggle "fold all hunks except current".

## Vim commands and mappings

| Key / Command | Action |
|---|---|
| `F5` or `:AdRun` | Run animator, update result.txt, refresh diff |
| `:AdCommit` or `<leader>c` | `git add -A && git commit` in session dir |
| `:AdQuit` or `<leader>q` | Commit, then quit vim |
| `:AdQuit!` or `<leader>Q` | Quit without committing |
| `:AdFoldHunks` | Fold all hunks except current |
| `<leader>h` | Toggle fold-all-hunks-except-current |
| `:AdGen` | Regenerate ops from old/new (backs up current ops to ops.tsv.bak) |
| `:AdDiff` | Open vertical diffsplit: result.txt vs new.<ext> |
| `:AdLog` | Show git log in a split |

## Session management

### `--resume <path>`

Resume an existing session. Opens the session directory and launches
vim with the same layout. Skips directory creation, file copying, and
git init.

### `--resume-latest`

Find the most recently modified session under `ad_sessions/` and
resume it.

### `--session-name <name>`

Use a custom name instead of the timestamp-based default. Creates
`ad_sessions/<name>/`.

### `--list-sessions`

Print all sessions under `ad_sessions/` with last-modified time and
git status (clean/dirty). Does not launch vim.

## Command-line options

```
ad_session <oldfile> <newfile> [opfile] [options]

Options:
  --ad-layer=<name>       Layer(s) for ad_gen_ops (if generating ops)
  --session-name=<name>   Custom session directory name
  --fold-context=<N>      Context lines around non-keep ops (default: 5)
  --fold-hunks            Start with all hunks folded
  --resume=<path>         Resume existing session
  --resume-latest         Resume most recent session
  --list-sessions         List sessions and exit
  --help, -h              Show help and exit
```

## Implementation

### Script: `scripts/ad_session`

Bash script that:
1. Parses arguments.
2. Creates session directory (unless `--resume`).
3. Copies old/new files.
4. Generates or copies ops file.
5. `git init` and initial commit.
6. Creates `resume.sh`.
7. Generates a vim session script (`session.vim`).
8. Launches vim with the script.

### Vim script: `scripts/vim/ad_session.vim`

Loaded via `vim -S`. Sets up:
- Split layout (diff left, ops+result right).
- Tabs (main, old, new).
- Syntax highlighting for ops.
- Fold expressions for keep ops and hunks.
- F5 mapping and `:AdRun` command.
- `:AdCommit`, `:AdQuit`, `:AdGen`, `:AdDiff`, `:AdLog` commands.
- `<leader>c`, `<leader>q`, `<leader>Q`, `<leader>h` mappings.

### Files created

- `scripts/ad_session` — main script
- `scripts/vim/ad_session.vim` — vim setup script
- `man/ad_session.1` — manpage
- `docs/design/AD_SESSION_REQUIREMENTS.md` — this document

## Accepted improvements from the 20 proposed

| # | Improvement | Accepted? |
|---|---|---|
| 2 | `:AdGen` regenerate ops (with backup) | Yes |
| 4 | `--session-name` custom name | Yes |
| 5 | `--resume-latest` | Yes |
| 6 | Fold by hunk + `--fold-hunks` | Yes |
| 20 | Session notes | No (write comments in ops file) |

## Not implemented (deferred)

- `:AdStep` (per-op stepping) — complex, needs snapshot infrastructure
- `:AdReplay` (real-time animation in vim) — needs terminal integration
- `:AdLayers` (per-layer cascade view) — needs multi-buffer orchestration
- `:AdStats` (op statistics) — nice to have, not core
- Session cleanup (`--clean-sessions`) — can use `find` manually
- Git log in split (`:AdLog`) — can use `:!git log` directly
