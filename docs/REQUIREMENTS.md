# ad — Requirements Specification

**Version:** 2.0.0  
**Date:** 2026-08-30  
**Repository:** https://github.com/nkh/gitanim  

---

## 1. Overview

`ad` (animate-diff) is a toolkit that animates code diffs. It takes an old
file and a new file, computes a character-level diff, and renders the
transformation as if a human were typing — character by character, with
smooth cursor movement, pause/skip/speed controls, and syntax highlighting.

`ad_vim` is the primary application: it renders the animation inside vim.
`ad_pipeline` runs the same pipeline in a terminal (no vim required).

### 1.1 Design Principles

| Principle | Implementation |
|-----------|---------------|
| Plugin-based layers | Layers are standalone executables; the orchestrator discovers and chains them via `--ad-layer` flags |
| No environment variables | Configuration via config file + CLI flags only |
| C + Perl twins | Every layer has a C implementation (preferred) and a Perl twin (byte-identical output) |
| TDD | Each layer has a test file written before or alongside the implementation |
| XDG compliance | Config at `$XDG_CONFIG_HOME/ad/config` (defaults to `~/.config/ad/config`) |

---

## 2. Architecture

```
  ┌─────────┐                                                                     
  │ old.py  │──┐                                                                  
  └─────────┘  │                                                                  
               ▼                                                                  
  ┌─────────┐  ┌──────────┐   ┌──────────────┐   ┌────────────┐   ┌──────────┐
  │ new.py  │─▶│ad_compute│──▶│ad_postprocess│──▶│ad_layer_   │──▶│   ad     │
  └─────────┘  └──────────┘   └──────┬───────┘   │   pace     │   │(animator)│
                                    │            └────────────┘   └────┬─────┘
                                    │ chains                          │
                                    │ --ad-layer=... flags            ▼
                                    │                          ┌──────────┐
                    ┌───────────────┼───────────────┐          │ terminal │
                    ▼               ▼               ▼          │ or vim   │
              ┌──────────┐  ┌──────────────┐  ┌──────────────┐└──────────┘
              │ad_layer_ │  │ad_layer_     │  │ad_layer_    │
              │ reorder   │  │ indent_last  │  │ highlight   │
              └──────────┘  └──────────────┘  └──────────────┘
```

The pipeline has 4 stages:

| Stage | Binary | Input | Output |
|-------|--------|-------|--------|
| 1. Compute | `bin/ad_compute` | old + new files | Raw char ops (V2 TSV) |
| 2. Postprocess | `pipeline/ad_postprocess` | Raw ops via stdin | Reordered ops (V2 TSV) |
| 3. Pace | `bin/ad_layer_pace` | Reordered ops via stdin | Timed ops (V2 TSV + delay lines) |
| 4. Animate | `bin/ad` | Timed ops via stdin + old file | Terminal/vim animation |

**Note:** `ad_layer_pace` and `ad_layer_highlight` are layers but run as
separate pipeline stages (not via `--ad-layer`). The orchestrator handles
layers between compute and pace; pace and highlight are invoked directly
by the launcher/pipeline. This allows them to take their own CLI args.

---

## 3. V2 TSV Format

All inter-process communication uses V2 TSV (tab-separated values):

```
# diffvim raw diff v2            ← header (passed through)
# algorithm patience             ← algorithm used
# hunk_count 1                   ← number of hunks
HUNK    1    3    1    0    0    ← hunk header
delete  1    1    100  'd'       ← op: type  line  col  code  char_repr
keep    1    4    10   \n        ← keep op (newline)
insert  1    4    66   'B'       ← insert op
HUNK_END                          ← end of hunk
                                  ← blank line at end
```

### 3.1 Op Types

| Type | Code | Description |
|------|------|-------------|
| `keep` | any | Character stays in buffer; cursor advances |
| `delete` | any | Character removed from buffer; cursor stays |
| `insert` | any | Character added to buffer; cursor advances |
| `overwrite_insert` | any | In-place replace (from overwrite layer) |
| `delay` | N/A | Delay line: `delay\t<ms>\t<type>` |
| `highlight` | N/A | Highlight instruction (from highlight layer) |
| `dim` | N/A | Dim instruction |
| `fold` | N/A | Fold instruction |
| `sign` | N/A | Sign column instruction |
| `marker` | N/A | Generic marker (e.g. git blame) |
| `glide` | N/A | Cursor glide instruction |
| `snapshot` | N/A | Take snapshot instruction |
| `debug` | N/A | Debug comment (passed through by all layers) |

### 3.2 Hunk Header

```
HUNK\t<target_line>\t<del_count>\t<ins_count>\t<end_ins>\t<end_del>
```

---

## 4. Components

### 4.1 Diff Engine (`diff_engine/`)

Computes the character-level diff between old and new files.

| File | Language | Output |
|------|----------|--------|
| `cpp/compute.cpp` | C++ | `bin/ad_compute` (preferred) |
| `perl/compute.pl` | Perl | Fallback (identical output) |
| `tests/l2r/` | Bash/Perl | Left-to-right algorithm tests |

**Algorithm:** Patience diff (anchors on unique common lines, LCS fallback
for ranges without anchors). Character-level diff within each line using
LCS dynamic programming.

**CLI flags:**

| Flag | Default | Description |
|------|---------|-------------|
| `--semantic-cleanup` | off | Merge adjacent del/ins pairs that cancel |
| `--word-diff` | off | Use word-level diff |

### 4.2 Layer Orchestrator (`pipeline/ad_postprocess`)

Bash script that chains layer plugins. Reads V2 TSV from stdin, runs
each layer in sequence, writes V2 TSV to stdout.

| Flag | Description |
|------|-------------|
| `--ad-layer=<name>` | Add a layer to the chain (argv order) |
| `--ad-layer-path=<dir>` | Add search directory (repeatable) |
| `--ad-layer-arg=<L>:<arg>` | Pass arg to layer L only |
| `--ad-layer-passthrough=<a>` | Pass arg to ALL layers |
| `--ad-layer-profile` | Print per-layer timing |
| `--ad-layer-dry-run` | Print chain, don't execute |
| `--ad-layer-keep-temps` | Keep intermediate files for debugging |
| `--list-layers` | List available layers |

**I/O modes:**
- **Pipe mode (default):** `layer1 < input | layer2 | layer3 > output` (fast)
- **Temp mode (`--keep-temps`):** Each layer reads/writes a file (debuggable)

**Layer resolution:** If name contains `/`, treat as path. Otherwise search
each `--ad-layer-path` dir. Extensions: `.pl`→perl, `.py`→python3,
`.rb`→ruby, `.sh`→bash, `.js`→node. No extension = must be executable.

**Error handling:** On layer failure, captures stderr, displays last 20 lines.

### 4.3 Layers (`layers/`)

Each layer is a standalone executable: reads V2 TSV stdin, writes V2 TSV
stdout, exits 0 on success.

| Layer | C source | Perl twin | Purpose |
|-------|----------|-----------|---------|
| `ad_layer_reorder` | `c/ad_layer_reorder.c` | `perl/ad_layer_reorder.pl` | 4-sweep reorder + position adjust |
| `ad_layer_overwrite` | `c/ad_layer_overwrite.c` | `perl/ad_layer_overwrite.pl` | Merge del+ins → overwrite_insert |
| `ad_layer_indent_last` | `c/ad_layer_indent_last.c` | `perl/ad_layer_indent_last.pl` | Move whitespace deletes to end |
| `ad_layer_line_delete_in_place` | `c/ad_layer_line_delete_in_place.c` | `perl/ad_layer_line_delete_in_place.pl` | Delete lines on their own line |
| `ad_layer_skip_indent` | `c/ad_layer_skip_indent.c` | `perl/ad_layer_skip_indent.pl` | Skip animation for indent-only hunks |
| `ad_layer_pace` | `c/ad_layer_pace.c` | `perl/ad_layer_pace.pl` | Insert delay ops (timing) |
| `ad_layer_highlight` | `c/ad_layer_highlight.c` | `perl/ad_layer_highlight.pl` | Insert highlight/dim/fold ops |

**Shared infrastructure:**
- `layers/c/ad_layer_common.h` — Op/Hunk types, TSV parse/write, `ad_layer_run()` driver
- `perl/DiffVim/Layer.pm` — Perl shared module (parse_op, write_op, char_repr, run_layer)

**Layer functions:** Each C layer implements:
```c
static int layer_func(Op *in, int n_ops, Op *out, int out_cap, int *line_offset);
int main(void) { return ad_layer_run(layer_func); }
```

### 4.4 Animator (`animator/`)

Reads timed V2 TSV from stdin, applies ops to a buffer, renders to terminal.

| File | Language | Output |
|------|----------|--------|
| `c/ad.c` | C | `bin/ad` (preferred) |
| `perl/ad.pl` | Perl | Fallback (identical output) |

**Features:** Cursor glide with ease-in-out acceleration, scroll modes
(zz/zt/zb/none), syntax highlighting via colormap files, diff stat overlay,
terminal bell on error, `--seek` to start at op N, `--no-display` for
headless testing.

### 4.5 Vim Application (`apps/vim/`)

| File | Description |
|------|-------------|
| `ad_vim` | Bash launcher (primary entry point) |
| `ad_vim.pl` | Perl launcher (parallel implementation) |
| `diffvim` | Backward-compat wrapper (exec's `ad_vim`) |
| `plugin.vim` | Vim plugin (`:Diffvim` command) |
| `autoload_diffvim/engine.vim` | Vimscript animation engine |

**Config loading:** Sources `$XDG_CONFIG_HOME/ad/config` (bash syntax),
then CLI flags override. Final values written to a vimscript-readable
temp file via `packaging/ad_write_vimconfig.sh`, passed to vim via
`--cmd "let g:ad_config_file=..."`.

### 4.6 Pipeline Driver (`pipeline/ad_pipeline`)

Bash script that runs all 4 stages: compute → postprocess → pace → animate.
Routes options by prefix: `--compute-*`, `--postprocess-*`, `--pace-*`,
`--animator-*`. Unprefixed options go to the animator.

### 4.7 Helper Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| `ad_debug.sh` | Interactive pipeline debugger |
| `ad_debug_bundle.sh` | Collect debug info into tarball |
| `ad_snapshot.sh` | Per-op HTML snapshots |
| `ad_record.sh` / `ad_replay.sh` | Record/replay animations |
| `ad_demo.sh` | Demo runner with preset examples |
| `ad_tune.sh` | Interactive option tuner (tmux) |
| `ad_suggest.sh` | Typo suggestion for CLI options |
| `ad_package.sh` | Create release tarball |
| `ad_compare` | Benchmark diff algorithms |
| `ad_jogger` | Exercise across option combinations |
| `ad_tmux` | Thin wrapper: runs ad_vim in tmux |
| `lib/ad_route.sh` | Shared option routing library |

---

## 5. Configuration

**No environment variables.** Configuration model:

| Priority | Source |
|----------|--------|
| 1 (lowest) | `/etc/ad/config` (system-wide defaults) |
| 2 | `~/.config/ad/config` (user config, bash syntax) |
| 3 (highest) | CLI flags |

Config file is sourced as bash. Variables use UPPER_CASE names (e.g.
`DELETE_PACING=word`). Every CLI flag has a config variable equivalent.

---

## 6. Testing

| Suite | Test file | Count | What it verifies |
|-------|-----------|-------|-------------------|
| Per-layer | `layers/tests/test_<name>.pl` | 7 files | Invocable, structure, C/Perl parity |
| Minimal cases | `tests/run_minimal_tests.sh` | 25 | One transformation per case |
| Examples | `tests/run_all_examples.sh` | 36 | Full pipeline on 26 languages |
| L2R algorithm | `diff_engine/tests/l2r/test_l2r.sh` | 35 | Left-to-right diff mode |
| Plugin contract | `tests/test_layers_discovery.pl` | 9 | --ad-layer, extensions, paths |
| Property-based | `tests/test_property.pl` | 50 | Random diffs through pipeline |
| **Total** | | **167** | All passing |

Run: `make test` (all), `make test-layers` (layers only), `make test-examples`
(examples only).

---

## 7. Documentation

| Document | Location | Description |
|----------|----------|-------------|
| User guide (mdBook) | `docs/src/` | Installation, quick-start, options, config |
| Plugin layers | `docs/src/plugin-layers.md` | Plugin contract, discovery, examples |
| Contributing | `docs/src/contributing.md` | TDD workflow for adding layers |
| Configuration | `docs/src/configuration.md` | Config file + CLI flags reference |
| Manpages | `man/*.1` | 25 manpages for all tools |
| Presentation | `docs/presentation.html` | Visual overview |
| Code analysis | `docs/CODE_ANALYSIS.md` | Code quality findings |
| Layer analysis | `docs/LAYER_ANALYSIS_AND_DOC_REVIEW.md` | Layer mechanism + doc review |
| Design docs | `docs/design/` | 58 historical design documents |

**CI workflows** (in `github/`, move to `.github/workflows/` to activate):

| Workflow | Triggers | What it does |
|----------|----------|-------------|
| `build-and-test.yml` | push, PR | Build + run all tests |
| `docs.yml` | docs/ changes | Build mdBook |
| `lint.yml` | push, PR | shellcheck + perl -c + gcc -fsyntax-only |
| `release.yml` | tag `v*` | Create GitHub Release |

---

## 8. Build System

```bash
make            # Build all binaries into bin/
make test       # Run all 161 tests
make install    # Install to $(PREFIX) (default: /usr/local)
make clean      # Remove bin/
```

**Output:** All binaries go to `bin/` (gitignored). No other bin directories.

---

## 9. Project Statistics

| Metric | Value |
|--------|-------|
| Version | 2.0.0 |
| C files | 10 |
| C++ files | 2 |
| Perl files | 69 |
| Bash files | 27 |
| Vim files | 2 |
| Manpages | 25 |
| Test assertions | 167 |
| Built binaries | 8 |
| Layers (C + Perl) | 7 (14 files) |
| Supported languages | 26+ |
| Environment variables | 0 |
| LOC (C layers) | 524 (was 866, 40% reduction) |
| LOC (pace.c main) | 122 (was 430, 72% reduction) |
| LOC (ad_tmux) | 103 (was 1673, 94% reduction) |

---

## 10. Twenty Improvements for the Next Level

| # | Improvement | Impact | Effort |
|---|-------------|--------|--------|
| 1 | **Web-based demo** — host a live demo where users upload old/new files and see the animation in a browser (WASM port or server-side render to video) | Huge for adoption | High |
| 2 | **VS Code extension** — animate diffs inside VS Code instead of vim, using the same pipeline and layers | Reaches non-vim users | High |
| 3 | **Video export** — render animation to MP4/WebM/GIF for sharing in PRs, blogs, talks | Killer feature for content creators | Medium |
| 4 | **Git integration** — `ad_vim --git HEAD~3` to animate the last 3 commits of a file, auto-detecting old/new from git history | Killer workflow feature | Medium |
| 5 | **Real-time collaboration** — stream the animation to multiple viewers via WebSocket, for live code reviews | Unique use case | High |
| 6 | **Layer marketplace** — a registry where users share layers (e.g. a Python-specific refactor layer, a JSON formatter layer) | Ecosystem growth | Medium |
| 7 | **TypeScript/Node port** — port the C animator to TypeScript for browser/Node.js deployment without WASM | Cross-platform reach | High |
| 8 | **Semantic diff** — use tree-sitter to produce AST-aware diffs that group related changes (e.g. move entire function, rename variable) | Much better diff quality | High |
| 9 | **Distributed compute** — for very large files (>10k lines), parallelize the diff across multiple cores or machines | Performance at scale | Medium |
| 10 | **Undo/redo during animation** — let the viewer step backward and forward through ops with full buffer state at each step | Better UX for review | Medium |
| 11 | **Config profiles** — named config profiles (`--profile=review`, `--profile=presentation`) that set multiple options at once | Convenience | Low |
| 12 | **Diff quality score** — analyze the diff and suggest better pacing/highlight options based on hunk size, change density, language | Smart defaults | Medium |
| 13 | **Animation scripting** — a simple DSL to script custom animations (pause here, zoom here, highlight this word) for demos | Presentation power | Medium |
| 14 | **Integration with git log** — `ad_vim --replay-file` that animates an entire file's git history as a slideshow | Documentation/onboarding | Medium |
| 15 | **Sound effects** — optional typing sounds synced to the animation pace for ASMR-style code review videos | Niche but fun | Low |
| 16 | **Diff stat dashboard** — a TUI dashboard showing diff stats (lines changed, chars changed, hunk count) before animation starts | Better overview | Low |
| 17 | **Multi-file animation** — animate changes across multiple files in sequence, with file transitions (currently `--multi` exists but is rough) | Real-world workflows | Medium |
| 18 | **Layer testing framework** — a framework that auto-generates test cases for layers from property-based test generators (like QuickCheck) | Better test coverage | Medium |
| 19 | **Performance profiling** — built-in flamegraph generation showing where time is spent across compute + layers + animate | Performance tuning | Low |
| 20 | **Internationalization** — support RTL languages, multi-byte char widths (CJK), and emoji in the diff display correctly | Global reach | Medium |
