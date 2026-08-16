# External Diff Compute Tools

Native-compiled diff computation tools for the diffvim project. These tools
compute line-level and char-level diffs 10–100x faster than the embedded
vimscript engine, making them ideal for large files or pre-processing
pipelines.

Available in four languages — all produce **byte-identical output**:

| Tool | Language | Binary | Typical Speed |
|------|----------|--------|---------------|
| `diffvim-compute-c` | C | `compute/bin/diffvim-compute-c` | ~0.8 ms |
| `diffvim-compute-cpp` | C++ | `compute/bin/diffvim-compute-cpp` | ~0.8 ms |
| `diffvim-compute-rust` | Rust | `compute/bin/diffvim-compute-rust` | ~4 ms |
| `diffvim-compute-go` | Go | `compute/bin/diffvim-compute-go` | ~1.4 ms |

All four support the **same CLI options**, **same input formats**, and
**same output format**. They are interchangeable.

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
- [Feature Parity](#feature-parity)
- [Using with diffvim](#using-with-diffvim)
- [Using Standalone](#using-standalone)
- [Performance](#performance)

---

## Build

```bash
cd compute/
make            # build all 4 tools
make c          # build C only
make cpp        # build C++ only
make rust       # build Rust only
make go         # build Go only
make benchmark  # build all + run timing comparison
make clean      # remove all binaries
```

**Prerequisites:**
- C: `cc` (GCC or Clang)
- C++: `c++` (GCC or Clang, needs C++17)
- Rust: `rustc` 1.50+
- Go: `go` 1.18+

Binaries are placed in `compute/bin/`.

---

## Usage

### Two-File Mode

```
diffvim-compute-<lang> <oldfile> <newfile> <outputfile> [options]
```

Reads two files, computes the diff, writes the precomputed diff to
`<outputfile>`.

```bash
diffvim-compute-c old.py new.py diff.txt
diffvim-compute-rust --algorithm myers old.py new.py diff.txt
diffvim-compute-go --word-diff --semantic-cleanup old.py new.py diff.txt
```

### Unified Diff Mode

```
diffvim-compute-<lang> --diff <patchfile> <outputfile> [options]
```

Reads a unified diff (patch file) instead of two separate files. Parses
the diff to reconstruct old/new content, then computes the char-level ops.

```bash
# From a patch file
diff -u old.py new.py > changes.patch
diffvim-compute-c --diff changes.patch diff.txt

# From git diff
git diff HEAD~1 > changes.patch
diffvim-compute-c --diff changes.patch diff.txt
```

### Stdin Mode

```
diffvim-compute-<lang> --diff - <outputfile> [options]
```

Reads the unified diff from stdin. Use `-` as the patch file path.

```bash
git diff HEAD~1 | diffvim-compute-c --diff - diff.txt
diff -u old.py new.py | diffvim-compute-go --diff - diff.txt
```

---

## Options

All options work in both two-file mode and `--diff` mode.

| Option | Description | Default |
|--------|-------------|---------|
| `--algorithm lcs\|myers\|patience` | Line-level diff algorithm | `lcs` |
| `--semantic-cleanup` | Merge adjacent delete+insert pairs that cancel out | off |
| `--word-diff` | Use word-level diff (groups changes by word tokens) | off |
| `--indent-aware` | Normalize indentation before line diff (indent-only changes = keep) | off |
| `--diff <file>` | Read unified diff from `<file>` instead of two files | (none) |
| `--diff -` | Read unified diff from stdin | (none) |

Options can be combined freely and in any order:

```bash
diffvim-compute-c --algorithm patience --word-diff --semantic-cleanup old.py new.py diff.txt
```

---

## Environment Variables

All options can also be set via environment variables (useful for
the compute tools or CI pipelines):

| Variable | Values | Equivalent to |
|----------|--------|---------------|
| `DIFFVIM_ALGORITHM` | `lcs`, `myers`, `patience` | `--algorithm` |
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
| `# algorithm <lcs\|myers\|patience>` | Line-level algorithm used |
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
AlgorithmLine := "# algorithm " (lcs|myers|patience) "\n"
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

$ compute/bin/diffvim-compute-c old.py new.py diff.txt
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

### Example 2: Myers algorithm with semantic cleanup

```bash
$ compute/bin/diffvim-compute-c --algorithm myers --semantic-cleanup old.py new.py diff.txt
```

### Example 3: Word-level diff

```bash
$ compute/bin/diffvim-compute-go --word-diff old.py new.py diff.txt
```

### Example 4: From a git diff

```bash
$ git diff HEAD~1 src/main.py > changes.patch
$ compute/bin/diffvim-compute-c --diff changes.patch diff.txt
```

### Example 5: From stdin (pipe)

```bash
$ git diff HEAD~1 | compute/bin/diffvim-compute-rust --diff - diff.txt
```

### Example 6: All options combined

```bash
$ compute/bin/diffvim-compute-c \
    --algorithm patience \
    --word-diff \
    --semantic-cleanup \
    --indent-aware \
    old.py new.py diff.txt
```

### Example 7: Benchmark all tools

```bash
$ make -C compute benchmark OLD=examples/02_large_python/old.py NEW=examples/02_large_python/new.py

--- compute/bin/diffvim-compute-c ---
compute: 0.97 ms (read 0.05 + diff 0.45 + write 0.47)
hunks: 21, lines: 77 -> 124

--- compute/bin/diffvim-compute-cpp ---
compute: 0.84 ms (read 0.09 + diff 0.38 + write 0.37)
hunks: 21, lines: 77 -> 124

--- compute/bin/diffvim-compute-rust ---
compute: 4.29 ms (read 0.03 + diff 0.72 + write 3.54)
hunks: 21, lines: 77 -> 124

--- compute/bin/diffvim-compute-go ---
compute: 1.58 ms (read 0.11 + diff 1.01 + write 0.45)
hunks: 21, lines: 77 -> 124
```

---

## Feature Parity

All four tools implement the **same functionality**:

| Feature | C | C++ | Rust | Go |
|---------|---|-----|------|----|
| Two-file input | ✅ | ✅ | ✅ | ✅ |
| `--diff <file>` unified diff input | ✅ | ✅ | ✅ | ✅ |
| `--diff -` stdin input | ✅ | ✅ | ✅ | ✅ |
| `--algorithm lcs` | ✅ | ✅ | ✅ | ✅ |
| `--algorithm myers` | ✅ | ✅ | ✅ | ✅ |
| `--algorithm patience` | ✅ | ✅ | ✅ | ✅ |
| `--semantic-cleanup` | ✅ | ✅ | ✅ | ✅ |
| `--word-diff` | ✅ | ✅ | ✅ | ✅ |
| `--indent-aware` | ✅ | ✅ | ✅ | ✅ |
| UTF-8 codepoint-aware char diff | ✅ | ✅ | ✅ | ✅ |
| Timing output to stderr | ✅ | ✅ | ✅ | ✅ |
| Same output format | ✅ | ✅ | ✅ | ✅ |
| Byte-identical output | ✅ | ✅ | ✅ | ✅ |

**Verified**: All 4 tools produce byte-identical output across 32 example
file pairs × 7 flag combinations (224 comparisons per tool pair, zero
mismatches).

---

## Using with diffvim

### Via the wrapper script

```bash
# Computes the diff with the C tool, then runs diffvim --precomputed
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt && diffvim --precomputed /tmp/diff.txt old.py new.py

# With options
compute/bin/diffvim-compute-c --algorithm myers --word-diff old.py new.py /tmp/diff.txt && diffvim --precomputed /tmp/diff.txt old.py new.py

# With timing
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt 2>&1 # shows timing
```

### Manually

```bash
# Step 1: compute
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt

# Step 2: run diffvim with --precomputed
./diffvim --precomputed /tmp/diff.txt old.py new.py
```

### Via environment variables

```bash
export DIFFVIM_ALGORITHM=myers
export DIFFVIM_WORD_DIFF=1
compute/bin/diffvim-compute-c old.py new.py /tmp/diff.txt && diffvim --precomputed /tmp/diff.txt old.py new.py
```

---

## Using Standalone

The tools are useful independently of diffvim for any application that
needs a structured diff representation:

### As a diff inspector

```bash
# See the char-level ops for a change
compute/bin/diffvim-compute-c old.py new.py /dev/stdout 2>/dev/null | head -20
```

### In a build pipeline

```bash
# Pre-compute diffs for CI
for file in $(git diff --name-only HEAD~1); do
    git show HEAD~1:$file > /tmp/old
    git show HEAD:$file > /tmp/new
    compute/bin/diffvim-compute-c /tmp/old /tmp/new "diffs/${file//\//_}.txt"
done
```

### As a library (C only)

The C tool's functions (`line_diff`, `char_diff`, `myers_diff`,
`patience_diff`, `semantic_cleanup`, `word_diff`) can be compiled as a
library and linked into other C programs:

```bash
cc -c -O2 compute/c/diffvim-compute.c -o diffvim-compute.o
# Link diffvim-compute.o into your program
```

---

## Performance

Benchmarked on a 76→123 line Python file (examples/02_large_python):

| Tool | Total | Read | Diff | Write |
|------|-------|------|------|-------|
| C | 0.97 ms | 0.05 ms | 0.45 ms | 0.47 ms |
| C++ | 0.84 ms | 0.09 ms | 0.38 ms | 0.37 ms |
| Rust | 4.29 ms | 0.03 ms | 0.72 ms | 3.54 ms |
| Go | 1.58 ms | 0.11 ms | 1.01 ms | 0.45 ms |
| vimscript (inline) | ~500 ms | — | ~500 ms | — |

The external tools are **500x faster** than the inline vimscript engine
for this file size. The speedup grows with file size — for 1000+ line
files, the external tools finish in <5ms while vimscript takes 5+ seconds.

**C and C++ are the fastest** overall. Rust has higher write overhead
due to the `writeln!` macro's formatting. Go is a good middle ground
with fast compilation and no external dependencies.
