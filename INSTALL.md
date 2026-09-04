# Installation

## Prerequisites

### Required

- **C compiler** (cc/gcc/clang) — for the animator, layers, and tools
- **C++ compiler** (c++/g++/clang++) — for the diff engine
- **Bash 4+** — for the pipeline and launchers

### Optional (depending on usage)

- **Vim 8+** with `+timers` and `+float` — for `ad_vim` (interactive animation)
- **tmux 3+** — for `ad_tmux_watch` (tmux-based debugging)
- **inotify-tools** — for instant file-change detection in `ad_watch` (falls back to stat polling)
- **diff-so-fancy** — for nicer diff output in `ad_watch` (falls back to plain `diff -u`)
- **mdBook** — for building the HTML documentation (`make docs`)

Check your vim:
```bash
vim --version | grep -E 'timers|float'
```

## Quick start

```bash
git clone https://github.com/nkh/gitanim.git
cd gitanim
make
```

This builds everything into `bin/`. You can run the tools directly from `bin/` or install them system-wide.

## Build targets

### Main targets

| Command            | What it builds                                   |
| ------------------ | ------------------------------------------------ |
| `make`             | Everything: diff engine, layers, animator, tools |
| `make diff_engine` | `bin/ad_compute` — the diff engine (C++)         |
| `make layers`      | All 7 layer binaries (`bin/ad_layer_*`)          |
| `make animator`    | `bin/ad` — the C animator                        |
| `make tools`       | `bin/ad_annotate` — the annotation tool          |

### Installation

| Command             | What it does                                 |
| ------------------- | -------------------------------------------- |
| `make install`      | Installs binaries, manpages, and completions |
| `make install-bin`  | Installs binaries only                       |
| `make install-man`  | Installs manpages only                       |
| `make install-comp` | Installs shell completions (bash, zsh, fish) |
| `make install-docs` | Installs documentation                       |

Default prefix is `/usr/local`. Override with:
```bash
make install PREFIX=$HOME/.local
```

### Testing

| Command              | What it tests                                           |
| -------------------- | ------------------------------------------------------- |
| `make test`          | All tests (layers + unit + minimal + property + fuzz)   |
| `make test-layers`   | Per-layer tests (C/Perl parity, structure)              |
| `make test-unit`     | Animator unit tests                                     |
| `make test-minimal`  | 25 minimal test cases through the pipeline              |
| `make test-property` | Property-based tests (50 random cases)                  |
| `make test-fuzz`     | Fuzz tests (malformed TSV, binary, empty, large inputs) |
| `make test-examples` | All 42 examples through the full pipeline               |

### Other

| Command          | What it does                     |
| ---------------- | -------------------------------- |
| `make clean`     | Removes `bin/` directory         |
| `make distclean` | Clean + remove generated files   |
| `make check`     | Check if binaries are up to date |
| `make help`      | Show available targets           |
| `make docs`      | Build mdBook HTML documentation  |

## What gets built

### Binaries (in `bin/`)

| Binary                          | Source                                     | What it does                                             |
| ------------------------------- | ------------------------------------------ | -------------------------------------------------------- |
| `ad`                            | `animator/c/ad.c`                          | C animator — applies ops to a buffer, renders animation  |
| `ad_compute`                    | `diff_engine/cpp/compute.cpp`              | Diff engine — computes char-level ops from old/new files |
| `ad_layer_reorder`              | `layers/c/ad_layer_reorder.c`              | Reorders ops within each line (deletes before inserts)   |
| `ad_layer_overwrite`            | `layers/c/ad_layer_overwrite.c`            | Merges adjacent delete+insert into overwrite_insert      |
| `ad_layer_indent_last`          | `layers/c/ad_layer_indent_last.c`          | Moves whitespace deletes to end of line                  |
| `ad_layer_line_delete_in_place` | `layers/c/ad_layer_line_delete_in_place.c` | Reorders whole-line deletes (content before joiner \n)   |
| `ad_layer_skip_indent`          | `layers/c/ad_layer_skip_indent.c`          | Skips animation for indent-only hunks                    |
| `ad_layer_pace`                 | `layers/c/ad_layer_pace.c`                 | Inserts delay ops between content ops                    |
| `ad_layer_highlight`            | `layers/c/ad_layer_highlight.c`            | Inserts highlight/dim/fold/sign decoration ops           |
| `ad_annotate`                   | `scripts/ad_annotate.c`                    | Adds `# old:` / `# new:` context comments to ops         |

### Scripts (in `scripts/`, `pipeline/`, `apps/vim/`)

| Script                    | What it does                                          |
| ------------------------- | ----------------------------------------------------- |
| `apps/vim/ad_vim`         | Launches vim with the animation                       |
| `pipeline/ad_pipeline`    | Full pipeline: compute → postprocess → pace → animate |
| `pipeline/ad_postprocess` | Layer orchestrator (runs layer chain)                 |
| `scripts/ad_session`      | Vim-only debugging tool (splits, F5/F6, folds, git)   |
| `scripts/ad_tmux_watch`   | tmux-based debugging tool (ad_watch + vim)            |
| `scripts/ad_watch`        | Live-preview tool (displays old, new, diff)           |
| `scripts/ad_gen_ops`      | Generates ops from old/new files + layer chain        |
| `scripts/ad_annotate`     | Built binary (same as `bin/ad_annotate`)              |

### Perl fallbacks (in `layers/perl/`, `animator/perl/`)

Each layer and the animator have Perl twins that produce byte-identical output. The orchestrator prefers C; if the C binary is missing, it falls back to Perl.

## The `.ad_layers` file

Optional configuration file in the project root that defines layer groups for debugging:

```
# First non-comment line = active group name (edit to switch)
default

default
ad_layer_reorder

debug_ldi
ad_layer_reorder
ad_layer_line_delete_in_place

debug_full
ad_layer_reorder
ad_layer_line_delete_in_place
ad_layer_indent_last
```

Used by `ad_session` and `ad_tmux_watch`. When the file exists, the first non-comment line selects the active group. Editing this line and saving regenerates ops with the new layer chain — no restart needed.

See `docs/design/AD_SESSION_REQUIREMENTS.md` for full details.

## Debugging tools

### `ad_session` (recommended)

Vim-only interactive debugger. Creates a session directory, copies files, generates ops, initializes git, and launches vim with a split layout:

```bash
# New session with generated ops
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder

# With annotations
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder --annotate

# With layer file
./scripts/ad_session old.py new.py

# Resume latest session
./scripts/ad_session --resume-latest

# List sessions
./scripts/ad_session --list-sessions
```

Vim shortcuts: F5 (animate), F6 (snapshot), `<leader>c` (commit), `<leader>g` (regenerate ops), `<leader>h` (fold hunks), `<leader>a` (toggle annotations), `<leader>?` (help).

### `ad_tmux_watch` (tmux alternative)

Same session system but uses tmux panes:

```bash
./scripts/ad_tmux_watch old.py new.py --ad-layer=ad_layer_reorder
```

### `ad_gen_ops` (standalone)

Generates ops from old/new files:

```bash
./scripts/ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder > ops.tsv
./scripts/ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder --annotate > ops.tsv
```

### `ad_watch` (standalone display)

Shows old, new, and diff — auto-refreshes on file change:

```bash
./scripts/ad_watch old.py new.py ops.tsv
```

## Directory structure

```
ad/
├── Makefile
├── INSTALL.md                  ← this file
├── README.md
├── .ad_layers                  ← optional layer group config
├── ad_sessions/                ← debugging sessions (gitignored)
│
├── bin/                        ← BUILD OUTPUT (gitignored)
├── diff_engine/                ← diff engine (C++)
├── layers/                     ← postprocess layers (C + Perl)
├── animator/                   ← animator (C + Perl)
├── pipeline/                   ← pipeline scripts
├── apps/vim/                   ← vim launcher
├── scripts/                    ← tools and helpers
│   ├── ad_session              ← vim-only debugger
│   ├── ad_tmux_watch           ← tmux debugger
│   ├── ad_watch                ← display tool
│   ├── ad_gen_ops              ← op generator
│   ├── ad_annotate.c           ← annotation tool source
│   └── vim/                    ← vim syntax/session scripts
├── man/                        ← manpages
├── docs/                       ← documentation
└── tests/                      ← test suite
```

## Troubleshooting

### "bin/ad: No such file or directory"

Run `make` first. All binaries are built into `bin/`.

### "ad_session: animator (ad) not found"

The session scripts look for `bin/ad` relative to the project root. Run `make` from the project root.

### "ad_annotate not found"

Run `make tools` to build `bin/ad_annotate`.

### Perl fallback not working

Perl layers need `DiffVim::Layer` module. It's in `perl/DiffVim/`. If running layers from a different directory, set `PERL5LIB`:
```bash
PERL5LIB=./perl ./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < raw.tsv
```
