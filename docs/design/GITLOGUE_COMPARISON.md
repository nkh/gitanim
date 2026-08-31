# ad_vim vs gitlogue — detailed comparison

## Overview

| | ad_vim | gitlogue |
|---|---------|----------|
| Language | C/C++ + Perl + vimscript | Rust |
| UI | vim (or C terminal animator) | ratatui (TUI framework) |
| Diff algorithm | Patience (anchored LCS) | Standard diff (git diff output) |
| Op granularity | Character-level | Line-level (with char-level within changed lines) |
| Animation target | Vim buffer or terminal | Terminal (ratatui) |

## Feature comparison

### Diff computation

| Feature | ad_vim | gitlogue |
|---------|---------|----------|
| Algorithm | Patience diff (anchored on unique lines) | Uses `git diff` output |
| Char-level | Yes — every char is a keep/delete/insert op | No — line-level hunks, char-level within |
| Multi-file | Yes (`--multi old1:new1 old2:new2`) | Yes (plays entire commit history) |
| Git history | Yes (`--replay`, `--git-rev`) | Yes (primary use case) |
| Pre-computed | Yes (`--precomputed FILE`) | No |
| Standalone tool | Yes (ad_compute) | No (embedded in animation engine) |

### Op pipeline

| Feature | ad_vim | gitlogue |
|---------|---------|----------|
| Pipeline stages | compute → postprocess → pace → animate | generate_steps → animate |
| Op format | TSV text (human-readable, debuggable) | Rust structs (in-memory) |
| Stage separation | Yes — each stage is a standalone CLI tool | No — tightly coupled |
| Multiple implementations | C + Perl (byte-identical output) | Rust only |
| Binary format | TSV (planned: binary for performance) | N/A (in-memory) |

### Animation

| Feature | ad_vim | gitlogue |
|---------|---------|----------|
| Cursor movement | Jump to op position (no smooth scroll) | **Smooth ease-in-out** between hunks |
| Distance-based speed | No | **Yes** (short=every line, long=jump) |
| Logarithmic step cap | No | **Yes** (max 60 steps for any distance) |
| Scroll follow | Yes (center cursor in viewport) | Yes (same algorithm) |
| Terminal height detection | Yes (ioctl TIOCGWINSZ) | Yes (ratatui) |
| Keyboard controls | q/Space/n/+/-/=/? | Space/q/+/-/arrow keys/menu |
| Pause/resume | Yes (Space/p) | Yes |
| Skip hunk | Yes (n) | Yes (→ next file) |
| Speed control | Yes (--speed, +/- keys) | Yes (--speed, +/- keys) |
| Step mode | Parsed but not implemented | Yes |

### Visual features

| Feature | ad_vim | gitlogue |
|---------|---------|----------|
| Syntax highlighting | **Yes — user's own vim colorscheme** | Yes (syntect — built-in themes) |
| Color in C animator | Yes (colormap with vim/pygmentize) | Yes (syntect) |
| Line numbers | Yes (--line-numbers) | Yes |
| Highlight changed chars | Parsed but not implemented | **Yes** (diff highlight) |
| Dim unchanged lines | Parsed but not implemented | No |
| Sign column | Parsed but not implemented | No |
| Git blame | Parsed but not implemented | No |
| Theme support | Parsed but not implemented | Yes (dark/light/high-contrast) |
| File tree | No | **Yes** (sidebar file list) |
| Terminal simulation | No | **Yes** (simulates git add/commit/push) |
| Status bar | No (--progress shows line info) | **Yes** (ratatui status bar) |
| Commit metadata | No | **Yes** (shows commit hash, author, date) |

### Where ad_vim is better

1. **Seeing the diff in vim** — the user sees their OWN vim, with their
   OWN colorscheme, syntax highlighting, plugins, etc. gitlogue uses
   a separate terminal UI with built-in syntax highlighting that may
   not match the user's environment.

2. **User's own colorscheme** — vim syntax highlighting uses the user's
   installed colorscheme and syntax plugins. For languages vim supports
   well (Python, Go, Rust, etc.), this is better than syntect's generic
   highlighting.

3. **Clean pipeline architecture** — 4 separate stages, each testable
   independently, each replaceable (C or Perl). gitlogue is a monolithic
   animation engine.

4. **Human-readable op stream** — TSV format that can be inspected with
   `less`, `grep`, `awk`, `diff`. gitlogue's steps are in-memory Rust
   structs.

5. **Standalone tools** — `ad_compute`, `ad_postprocess`,
   `ad_layer_pace`, `ad` are all standalone CLI tools
   that can be piped. gitlogue has no standalone tools.

6. **Per-op positioning** — every op carries (line, col), making the
   animator scroll-safe and position-independent. gitlogue computes
   positions during animation generation.

### Where gitlogue is better

1. **Smooth cursor movement** — ease-in-out interpolation between
   hunks. ad_vim jumps instantly.

2. **Distance-based speed** — short distances show every line, long
   distances jump. ad_vim has no cursor movement at all.

3. **Terminal simulation** — gitlogue shows the entire git workflow:
   file tree, terminal, git add/commit/push. This is visually
   impressive and tells a complete story.

4. **File tree sidebar** — shows which files are being changed.

5. **Commit metadata** — shows commit hash, author, date.

6. **Theme support** — dark/light/high-contrast themes.

7. **Status bar** — always-visible status information.

8. **Better keyboard handling** — arrow keys, menu navigation, etc.
   (ratatui provides better terminal input handling than raw vimscript).

### What we should learn from gitlogue

1. **Add smooth cursor movement** — generate intermediate MoveCursor
   ops with ease-in-out timing. This is the #1 visual improvement.

2. **Add distance-based speed** — short: every line visible, long: jump.

3. **Consider a TUI mode** — a standalone terminal animator (like the
   C animator) that includes file tree, status bar, and commit info.
   This would be a separate tool from the vim launcher.

4. **Add diff highlighting** — highlight changed chars (green/red) in
   the animator. The colormap already provides syntax highlighting;
   we could add a diff overlay.

### What gitlogue could learn from us

1. **Clean pipeline separation** — gitlogue's animation engine is
   monolithic. Separating compute/postprocess/pace/animate would make
   it testable and replaceable.

2. **Human-readable op stream** — gitlogue's AnimationStep enum is
   in-memory only. A serializable format would help debugging.

3. **Per-op positioning** — gitlogue computes positions during generation.
   Per-op positioning makes the animator simpler and scroll-safe.

4. **Multiple implementations** — gitlogue is Rust-only. Having a
   Perl fallback would make it more portable.
