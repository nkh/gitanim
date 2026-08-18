# External Diff Compute Tools

The native diff computer for the diffvim project. Computes line-level
and char-level diffs 10–100x faster than the embedded vimscript engine,
making it ideal for large files or pre-processing pipelines.

There is **one implementation** in C++:

| Tool | Language | Binary | Typical Speed |
|------|----------|--------|---------------|
| `diffvim-compute-cpp` | C++17 | `compute/bin/diffvim-compute-cpp` | ~0.8 ms |

The historical C, Rust, and Go variants were removed during the Phase A
refactor — they produced byte-identical output and the maintenance cost
outweighed the value of having single implementation. The C++ tool is the
only compute tool that diffvim uses.

When the C++ binary is not on disk:

- `diffvim` falls back to the embedded vimscript LCS
  (`s:LineDiff` / `s:CharDiff` in `autoload/diffvim/engine.vim`)
- `diffvim-pipeline` falls back to `compute/perl/compute_builtin.pl`,
  a thin wrapper around `DiffVim::Parser::Perl::parse_diff` that emits
  the same op-stream format

Both fallbacks emit the same output as the C++ tool, just slower.

---

## Table of Contents

- [Build](#build)
- [Usage](#usage)
  - [Two-File Mode](#two-file-mode)
  - [Unified Diff Mode](#unified-diff-mode)
  - [Stdin Mode](#stdin-mode)
- [Options](#options)
- [Environment Variables](#environment-variables)
- [Output Format](#output-format)
- [Input Schema](#input-schema)
- [Output Schema](#output-schema)
- [Examples](#examples)
- [Using with diffvim](#using-with-diffvim)
- [Using Standalone](#using-standalone)
- [Performance](#performance)

---

## Build

```bash
cd compute/
make            # build diffvim-compute-cpp
make cpp        # alias (kept for backwards compatibility)
make benchmark  # build + run a single timing
make clean      # remove the binary
```

**Prerequisites:**
- C++: `c++` (GCC or Clang, needs C++17)

The binary is placed in `compute/bin/diffvim-compute-cpp`.

The old `make c|rust|go` targets were removed in the refactor.

---

## Usage

### Two-File Mode

```
diffvim-compute-cpp <oldfile> <newfile> <outputfile> [options]
```

Reads two files, computes the diff, writes the precomputed diff to
`<outputfile>`.

```bash
diffvim-compute-cpp old.py new.py diff.txt
diffvim-compute-cpp --algorithm patience old.py new.py diff.txt
diffvim-compute-cpp --word-diff --semantic-cleanup old.py new.py diff.txt
```

### Unified Diff Mode

```
diffvim-compute-cpp --diff <patchfile> <outputfile> [options]
```

Reads a unified diff (patch file) instead of two separate files. Parses
the diff to reconstruct old/new content, then computes the char-level ops.

```bash
# From a patch file
diff -u old.py new.py > changes.patch
diffvim-compute-cpp --diff changes.patch diff.txt

# From git diff
git diff HEAD~1 > changes.patch
diffvim-compute-cpp --diff changes.patch diff.txt
```

### Stdin Mode

```
diffvim-compute-cpp --diff - <outputfile> [options]
```

Reads the unified diff from stdin. Use `-` as the patch file path.

```bash
git diff HEAD~1 | diffvim-compute-cpp --diff - diff.txt
diff -u old.py new.py | diffvim-compute-cpp --diff - diff.txt
```

---

## Options

All options work in both two-file mode and `--diff` mode.

| Option | Description | Default |
|--------|-------------|---------|
| `--algorithm lcs\|patience` | Line-level diff algorithm | `lcs` |
| `--semantic-cleanup` | Merge adjacent delete+insert pairs that cancel out | off |
| `--word-diff` | Use word-level diff (groups changes by word tokens) | off |
| `--indent-aware` | Normalize indentation before line diff (indent-only changes = keep) | off |
| `--diff <file>` | Read unified diff from `<file>` instead of two files | (none) |
| `--diff -` | Read unified diff from stdin | (none) |

> `--algorithm myers` was removed in the Phase A refactor: it OOMs on
> 15K-line files and produces the same op count as LCS.

Options can be combined freely and in any order:

```bash
diffvim-compute-cpp --algorithm patience --word-diff --semantic-cleanup old.py new.py diff.txt
```

---

## Environment Variables

All options can also be set via environment variables (useful for
CI pipelines):

| Variable | Values | Equivalent to |
|----------|--------|---------------|
| `DIFFVIM_ALGORITHM` | `lcs`, `patience` | `--algorithm` |
| `DIFFVIM_SEMANTIC_CLEANUP` | `1` | `--semantic-cleanup` |
| `DIFFVIM_WORD_DIFF` | `1` | `--word-diff` |
| `DIFFVIM_INDENT_AWARE` | `1` | `--indent-aware` |

CLI flags override environment variables.

---

## Output Format

The output is a plain-text file with a simple, line-oriented format:

```
# diffvim precomputed diff v1
# algorithm lcs
# semantic_cleanup 0
# word_diff 0
# indent_aware 0
# hunk_count 3
HUNK 2 1 1 0 0
keep 32
keep 32
keep 112
insert 102
keep 34
delete 34
...
HUNK 8 0 2 1 0
insert 10
insert 105
...
```

### Header Lines

All header lines start with `#`:

| Line | Description |
|------|-------------|
| `# diffvim precomputed diff v1` | Format identifier and version |
| `# algorithm <lcs\|patience>` | Line-level algorithm used |
| `# semantic_cleanup <0\|1>` | Whether semantic cleanup was applied |
| `# word_diff <0\|1>` | Whether word-level diff was used |
| `# indent_aware <0\|1>` | Whether indent-aware normalization was used |
| `# hunk_count <N>` | Number of hunks in the file |

### Hunk Lines

Each hunk starts with a `HUNK` line:

```
HUNK <target_line> <deleted_count> <inserted_count> <is_end_insert> <is_end_delete>
```

| Field | Type | Description |
|-------|------|-------------|
| `target_line` | int | 1-indexed line in the old file where the hunk starts |
| `deleted_count` | int | Number of old lines deleted |
| `inserted_count` | int | Number of new lines inserted |
| `is_end_insert` | 0/1 | 1 if this is a pure insertion at end of file |
| `is_end_delete` | 0/1 | 1 if this is a pure deletion at end of file |

### Char Op Lines

After each `HUNK` line, the char-level operations are listed one per line:

```
<op_type> <code>
```

| `op_type` | Description |
|-----------|-------------|
| `keep` | Keep this char (advance cursor, no buffer change) |
| `delete` | Delete this char at the cursor |
| `insert` | Insert this char at the cursor |

`<code>` is a Unicode code point (integer). Code 10 = newline (`\n`).

---

## Input Schema

### Two-File Mode Input

```
<oldfile>    — path to the original file (UTF-8 text)
<newfile>    — path to the modified file (UTF-8 text)
<outputfile> — path to write the precomputed diff
```

Both files are read as UTF-8 text. Binary files (containing null bytes)
are not specially handled — they will be processed as-is.

### Unified Diff Mode Input

```
<patchfile>  — path to a unified diff file, or - for stdin
<outputfile> — path to write the precomputed diff
```

The unified diff must follow the standard `diff -u` / `git diff` format:

```diff
--- oldfile.py
+++ newfile.py
@@ -1,3 +1,3 @@
 context line
-old line
+new line
 context line
```

**Parsing rules:**
- `--- <path>` — old file header (path is ignored)
- `+++ <path>` — new file header (path is ignored)
- `@@ -a,b +c,d @@` — hunk header (ignored; we recompute our own hunks)
- ` <line>` — context line (present in both old and new; leading space stripped)
- `-<line>` — old-only line (leading `-` stripped)
- `+<line>` — new-only line (leading `+` stripped)
- `\<message>` — diff metadata (e.g., `\ No newline at end of file`), ignored
- Lines not matching any of the above are ignored

Multiple hunks are concatenated to reconstruct the full old/new file content.

---

## Output Schema

```
File        := Header Hunk*
Header      := FormatLine AlgorithmLine SemanticLine WordDiffLine IndentLine HunkCountLine
FormatLine  := "# diffvim precomputed diff v1\n"
AlgorithmLine := "# algorithm " (lcs|patience) "\n"
SemanticLine := "# semantic_cleanup " (0|1) "\n"
WordDiffLine := "# word_diff " (0|1) "\n"
IndentLine   := "# indent_aware " (0|1) "\n"
HunkCountLine := "# hunk_count " Int "\n"
Hunk        := HunkLine CharOp*
HunkLine    := "HUNK " Int " " Int " " Int " " Int " " Int "\n"
CharOp      := ("keep"|"delete"|"insert") " " Int "\n"
Int         := [0-9]+
```

---

## Examples

### Example 1: Basic two-file diff

```bash
$ cat old.py
def greet(name):
    print("Hello, " + name)
    return None

$ cat new.py
def greet(name):
    print(f"Hello, {name}!")
    return None

$ compute/bin/diffvim-compute-cpp old.py new.py diff.txt
compute: 0.27 ms (read 0.03 + diff 0.01 + write 0.23)
startup: 0.00 ms (process start to first read)
hunks: 1, lines: 3 -> 3

$ cat diff.txt
# diffvim precomputed diff v1
# algorithm lcs
# semantic_cleanup 0
# word_diff 0
# indent_aware 0
# hunk_count 1
HUNK 2 1 1 0 0
keep 32
keep 32
keep 32
keep 32
keep 112
keep 114
keep 105
keep 110
keep 116
keep 40
insert 102
keep 34
...
```

### Example 2: Patience algorithm with semantic cleanup

```bash
$ compute/bin/diffvim-compute-cpp --algorithm patience --semantic-cleanup old.py new.py diff.txt
```

### Example 3: Word-level diff

```bash
$ compute/bin/diffvim-compute-cpp --word-diff old.py new.py diff.txt
```

### Example 4: From a git diff

```bash
$ git diff HEAD~1 src/main.py > changes.patch
$ compute/bin/diffvim-compute-cpp --diff changes.patch diff.txt
```

### Example 5: From stdin (pipe)

```bash
$ git diff HEAD~1 | compute/bin/diffvim-compute-cpp --diff - diff.txt
```

### Example 6: All options combined

```bash
$ compute/bin/diffvim-compute-cpp \
    --algorithm patience \
    --word-diff \
    --semantic-cleanup \
    --indent-aware \
    old.py new.py diff.txt
```

### Example 7: Benchmark

```bash
$ make -C compute benchmark OLD=examples/02_large_python/old.py NEW=examples/02_large_python/new.py

--- compute/bin/diffvim-compute-cpp ---
compute: 0.84 ms (read 0.09 + diff 0.38 + write 0.37)
hunks: 21, lines: 77 -> 124
```

---

## Using with diffvim

### Default behaviour (automatic precompute)

`diffvim` and `diffvim-pipeline` now look for `compute/bin/diffvim-compute-cpp`
automatically. If found, they precompute the diff before launching vim. If
not found, they fall back to a builtin LCS implementation (vimscript LCS
in `diffvim`, Perl LCS via `compute/perl/compute_builtin.pl` in
`diffvim-pipeline`).

There is no `--tool` flag any more — it was removed in Phase B. The C++
tool is always the default; the fallback is automatic.

### Manually

```bash
# Step 1: compute
compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt

# Step 2: run diffvim with --precomputed
./diffvim --precomputed /tmp/diff.txt old.py new.py
```

### Via environment variables

```bash
export DIFFVIM_ALGORITHM=patience
export DIFFVIM_WORD_DIFF=1
compute/bin/diffvim-compute-cpp old.py new.py /tmp/diff.txt && diffvim --precomputed /tmp/diff.txt old.py new.py
```

---

## Using Standalone

The tool is useful independently of diffvim for any application that
needs a structured diff representation:

### As a diff inspector

```bash
# See the char-level ops for a change
compute/bin/diffvim-compute-cpp old.py new.py /dev/stdout 2>/dev/null | head -20
```

### In a build pipeline

```bash
# Pre-compute diffs for CI
for file in $(git diff --name-only HEAD~1); do
    git show HEAD~1:$file > /tmp/old
    git show HEAD:$file > /tmp/new
    compute/bin/diffvim-compute-cpp /tmp/old /tmp/new "diffs/${file//\//_}.txt"
done
```

---

## Performance

Benchmarked on a 76→123 line Python file (examples/02_large_python):

| Tool | Total | Read | Diff | Write |
|------|-------|------|------|-------|
| C++ | 0.84 ms | 0.09 ms | 0.38 ms | 0.37 ms |
| Perl fallback (`compute_builtin.pl`) | ~3 ms | — | — | — |
| vimscript (inline) | ~500 ms | — | ~500 ms | — |

The external C++ tool is **500x faster** than the inline vimscript engine
for this file size. The speedup grows with file size — for 1000+ line
files, the external tool finishes in <5ms while vimscript takes 5+
seconds. The Perl fallback sits in between and is used only when the
C++ binary is unavailable.
