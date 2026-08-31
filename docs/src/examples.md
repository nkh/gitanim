# Examples

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


The repo includes example file pairs in `tests/tests/examples/`, each in a separate
directory:

## 01 — Small Python (3 lines)

A simple f-string conversion.

```bash
diffvim tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py
```

## 02 — Large Python (76→123 lines)

A data processor module refactored with type hints, dataclasses, and
JSON support.

```bash
diffvim tests/tests/examples/02_large_python/old.py tests/tests/examples/02_large_python/new.py
```

## 03 — JSON Config (14→26 lines)

A package.json updated with new scripts, dependencies, and engine constraints.

```bash
diffvim tests/tests/examples/03_json_config/old.json tests/tests/examples/03_json_config/new.json
```

## 04 — Shell Script (26→54 lines)

An init.d-style script improved with proper error handling, logging, and
a status command.

```bash
diffvim tests/tests/examples/04_shell_script/old.sh tests/tests/examples/04_shell_script/new.sh
```

## 05 — Go Code (16→81 lines)

A simple HTTP handler expanded with graceful shutdown, health checks,
and proper structure.

```bash
diffvim tests/tests/examples/05_go_code/old.go tests/tests/examples/05_go_code/new.go
```

## 06 — TypeScript (23→58 lines)

A UserService class expanded with Map-based storage, update/delete methods,
and role-based types.

```bash
diffvim tests/tests/examples/06_typescript/old.ts tests/tests/examples/06_typescript/new.ts
```

## 07 — Text Prose (24→36 lines)

An architecture document rewritten with more detail and structure.

```bash
diffvim tests/tests/examples/07_text_prose/old.txt tests/tests/examples/07_text_prose/new.txt
```

## Multi-File Animation

Animate multiple file pairs in sequence:

```bash
diffvim --multi \
    tests/tests/examples/01_small_python/old.py:tests/tests/examples/01_small_python/new.py \
    tests/tests/examples/04_shell_script/old.sh:tests/tests/examples/04_shell_script/new.sh
```

## Git Replay

Animate a file's git history:

```bash
# Last 5 commits
diffvim --replay src/main.py

# Specific range
diffvim --replay src/main.py --from v1.0 --to HEAD

# Using --git-rev syntax
diffvim --git-rev HEAD~3..HEAD src/main.py

# Multiple files
diffvim --replay src/main.py src/utils.py
```

## Dry Run

Print the diff ops without launching vim:

```bash
perl diffvim.pl --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py
```

## Plugin Mode

Inside an existing vim session:

```vim
:Diffvim old.py new.py
:Diffvim old.py new.py tabnew
:Diffvim old.py new.py vsplit
```

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
