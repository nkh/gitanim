# C/C++ API Reference

Internal API documentation for the `ad` toolkit's C and C++ components.

---

## `ad_layer_common.h` — Shared Layer Infrastructure

### Types

#### `Op`
```c
typedef struct {
    char type[AD_LAYER_TYPE_LEN];  /* "keep", "delete", "insert", "overwrite_insert" */
    int  code;               /* char code (10=\n, 32=space, 9=tab, etc.) */
    int  line;               /* 1-indexed line number */
    int  col;                /* 1-indexed column number */
} Op;
```

Represents a single operation in the V2 TSV stream. All layers read and
write arrays of `Op`.

#### `Hunk`
```c
typedef struct {
    int target;    /* target line (1-indexed) */
    int del;       /* deleted line count */
    int ins;       /* inserted line count */
    int end_ins;   /* end insert flag */
    int end_del;   /* end delete flag */
} Hunk;
```

Hunk metadata from the HUNK header.

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `AD_LAYER_MAX_LINE` | 1048576 | Max line size (1MB) |
| `AD_LAYER_TYPE_LEN` | 20 | Max op type string length |
| `AD_LAYER_INIT_CAPACITY` | 4096 | Initial op array capacity |
| `AD_LAYER_OUTPUT_SLACK` | 1024 | Extra slots in output buffer |
| `AD_LAYER_MAX_TOKENS` | 8 | Max TSV tokens per line |
| `AD_LAYER_CHAR_SPACE` | 32 | ASCII space |
| `AD_LAYER_CHAR_TAB` | 9 | ASCII tab |
| `AD_LAYER_CHAR_NEWLINE` | 10 | ASCII newline |
| `AD_LAYER_DEFAULT_SKIP_PAUSE_MS` | 300 | Default indent-skip pause |

### Functions

#### `ad_layer_parse_op`
```c
int ad_layer_parse_op(const char *line, Op *op);
```
Parse a TSV line into an `Op`. Returns 1 on success, 0 on failure.

#### `ad_layer_parse_tsv`
```c
int ad_layer_parse_tsv(char *line, char *toks[], int max_toks);
```
Split a TSV line in-place into tokens. Returns token count. Modifies `line`
(replaces tabs with null terminators).

#### `ad_layer_write_op`
```c
void ad_layer_write_op(Op *op);
```
Write an `Op` to stdout in V2 TSV format (5 fields: type, line, col, code, char_repr).

#### `ad_layer_write_hunk`
```c
void ad_layer_write_hunk(Hunk *h);
```
Write a HUNK header to stdout.

#### `ad_layer_is_debug_op`
```c
int ad_layer_is_debug_op(Op *op);
```
Returns 1 if the op type is "debug" (a passthrough comment).

#### `ad_layer_run`
```c
int ad_layer_run(int (*layer_func)(Op *in, int in_count, Op *out,
                                    int out_cap, int *line_offset));
```
Standalone layer driver. Reads V2 TSV from stdin, calls `layer_func` for
each hunk, writes output to stdout. Handles HUNK/HUNK_END parsing, header
pass-through, and cross-hunk `line_offset` tracking.

**Layer function signature:**
```c
int my_layer(Op *in, int in_count, Op *out, int out_cap, int *line_offset);
```
- `in` — input ops (already position-adjusted with line_offset)
- `in_count` — number of input ops
- `out` — output buffer (capacity `out_cap`)
- `out_cap` — output buffer capacity (typically `in_count + AD_LAYER_OUTPUT_SLACK`)
- `line_offset` — pointer to cumulative line offset; update if the layer
  changes the \n insert/delete balance
- **Returns** — number of output ops

---

## `diff_engine/cpp/compute.cpp` — Diff Engine

### Types

#### `OpType`
```cpp
enum OpType { OP_KEEP, OP_DELETE, OP_INSERT };
```

#### `CharOp`
```cpp
struct CharOp { OpType type; int code; };
```

#### `LineOp`
```cpp
struct LineOp { OpType type; int a_idx; int b_idx; };
```

#### `Hunk`
```cpp
struct Hunk {
    int target_line, deleted_count, inserted_count;
    int is_end_insert, is_end_delete;
    std::vector<CharOp> char_ops;
};
```

### Key Functions

#### `patience_diff`
```cpp
vector<LineOp> patience_diff(const vector<string>& a, const vector<string>& b);
```
Patience diff: anchors on unique common lines, recurses on gaps with LCS.
Returns line-level ops.

**Complexity:** O(n log n) for anchor finding, O(n*m) for LCS fallback.

#### `char_diff`
```cpp
vector<CharOp> char_diff(const string& a, const string& b);
```
Character-level diff using LCS dynamic programming. UTF-8 aware (works on
codepoint arrays).

**Complexity:** O(n*m) where n, m are codepoint counts.

#### `semantic_cleanup`
```cpp
vector<CharOp> semantic_cleanup(vector<CharOp> ops);
```
Merge adjacent delete+insert pairs that cancel out (same char code).

#### `word_diff`
```cpp
vector<CharOp> word_diff(const string& a, const string& b);
```
Word-level diff: splits into tokens (whitespace-delimited), runs LCS at
token level, expands to char ops.

---

## `animator/c/ad.c` — Animator

### Key Functions

#### `keep_char`
```c
void keep_char(int code);
```
Advance cursor past a kept character. Updates internal cursor position.

#### `delete_char`
```c
void delete_char(int code);
```
Delete a character from the buffer at current cursor position. If code is
10 (\n), joins the current line with the next.

#### `insert_char`
```c
void insert_char(int code);
```
Insert a character at current cursor position. UTF-8 aware (multi-byte
chars are encoded as multiple bytes). If code is 10 (\n), splits the line.

#### `set_cursor`
```c
void set_cursor(int line, int col);
```
Move the internal cursor to (line, col). 1-indexed. Clamps to buffer bounds.

#### `render`
```c
void render(void);
```
Render the current buffer state to the terminal. Respects scroll mode
(zz/zt/zb/none), viewport height, and diff-stat overlay. No-op if
`no_display` or `suppress_render` is set.

#### `cleanup_handler`
```c
void cleanup_handler(int sig);
```
Async-signal-safe signal handler. Writes a newline and calls `_exit(1)`.
Registered for SIGINT and SIGTERM.

#### `atexit_handler`
```c
void atexit_handler(void);
```
Terminal cleanup: restores original terminal mode, shows cursor. Registered
via `atexit()`.

---

## V2 TSV Op Stream Format

### Op Line Format
```
<type>\t<line>\t<col>\t<code>\t<char_repr>
```

| Field | Type | Description |
|-------|------|-------------|
| type | string | `keep`, `delete`, `insert`, `overwrite_insert` |
| line | int | 1-indexed line number |
| col | int | 1-indexed column number |
| code | int | ASCII/Unicode codepoint |
| char_repr | string | Human-readable: `'a'`, `\\n`, `space`, `32` |

### Hunk Header
```
HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
```

### Delay Op (from pace layer)
```
delay\t<ms>\t<type>
```
Where type is: `char`, `word`, `hunk`, `awd_slow`, `awd_fast`, `awd_skip`,
`accel_delete`, `block_start`, `block_end`, `pause_after`, `flash_pause`,
`flash_delete`, `flash_end`, `rapid_eol`, `rapid_identical`, `indent_skip_end`.

### Indent Skip Markers (from skip_indent layer)
```
delay\t-1\t0\t0       ← start skip mode
delay\t-1\t1\t<ms>    ← end skip mode, pause for <ms>
```
Uses `line=-1` (never occurs in normal ops) as a sentinel.

### Decoration Ops (from highlight layer)
```
highlight\t<start_line>\t<start_col>\t<end_line>\t<end_col>\t<type>\t<duration_ms>
dim\t<start_line>\t<end_line>\t<pct>
fold\t<start_line>\t<end_line>
sign\t<line>\t<type>
marker\t<line>\t<col>\t<text>
glide\t<from_line>\t<from_col>\t<to_line>\t<to_col>\t<duration_ms>
snapshot\t<file_path>
```
