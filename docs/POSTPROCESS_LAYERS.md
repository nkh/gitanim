# Postprocess Layers

The postprocess stage is a series of **layers** orchestrated by
`postprocess.c`. Each layer is a pure function: `Op[] → Op[]`. No side
effects. The final stage is an inline `adjust_positions()` pass that
fixes `(line, col)` based on `\n` deletes.

## Architecture

```
compute output (raw ops)
    │
    ▼
Layer 0: V2 Conversion (pp_layer0_v2.c)
    │   Converts V1→V2, writes headers. No modification.
    ▼
Layer 1: Reorder (pp_layer1_reorder.c)
    │   4-sweep: content del → content ins → \n del → \n ins.
    ▼
delete-indent-last (pp_layer_indent_last.c)  [optional, --indent-last]
    │   Reorders leading-whitespace DELETE ops to end of line group.
    │   Does NOT touch line/col positions.
    ▼
overwrite (pp_layer_overwrite.c)  [optional, --overwrite]
    │   Marks adjacent delete+insert pairs as overwrite_insert.
    ▼
adjust_positions (inline in postprocess.c)
    │   Recursive walk; adjusts (line, col) based on \n deletes.
    ▼
postprocess output (V2 TSV)
```

## File Structure

| File | Role | Status |
|------|------|--------|
| `pp_common.h` | Shared | Types, logging, TSV parsing, standalone runner |
| `pp_layer0_v2.c` | Layer 0 | **Implemented** — V1/V2 detection, conversion |
| `pp_layer1_reorder.c` | Layer 1 | 4-sweep reorder |
| `pp_layer_indent_last.c` | delete-indent-last | Reorders leading-whitespace deletes (no line/col changes) |
| `pp_layer_overwrite.c` | overwrite | Marks delete+insert pairs as `overwrite_insert` |
| `postprocess.c` | Orchestrator | Runs the pipeline; contains inline `adjust_positions()` |
| `pp_layer_noop.pl` | Perl | No-op (passthrough) — Perl template |

> There is no `pp_layer2_transforms.c` or `pp_layer3_cursor.c`.
> Cursor recomputation is not a separate layer — it is the inline
> `adjust_positions()` function in `postprocess.c`.

## Build

### Main executable (orchestrator):
```bash
cc -O2 -Wall -Wextra -Wunused -Werror -I animator/c \
   -o diffvim-postprocess postprocess.c \
   pp_layer0_v2.c pp_layer1_reorder.c \
   pp_layer_indent_last.c pp_layer_overwrite.c
```

### Standalone binaries (each reads stdin, writes stdout):
```bash
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer0 animator/c/pp_layer0_v2.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer1 animator/c/pp_layer1_reorder.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror -I animator/c \
   -o animator/bin/pp_indent_last animator/c/pp_layer_indent_last.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Wunused -Werror -I animator/c \
   -o animator/bin/pp_overwrite animator/c/pp_layer_overwrite.c
```

> Standalone binaries do NOT run `adjust_positions`. That step lives
> only inside `postprocess.c` and runs as the final stage of the
> combined pipeline. When piped manually, the consumer must apply its
> own equivalent (or run `diffvim-postprocess` instead of the chain).

### Piped (layers as separate processes, before adjust_positions):
```bash
compute | pp_layer0 | pp_layer1 | pp_indent_last | pp_overwrite > output
```

### Perl (no-op layer):
```bash
compute | perl pp_layer_noop.pl > output
```

## Debug Logging

Set `DV_DEBUG_POSTPROCESS=1` to enable:
- `/tmp/dv_debug/postprocess.log` — log from each layer
- `/tmp/dv_debug/layer_input.txt` — ops before the layer
- `/tmp/dv_debug/layer_output.txt` — ops after the layer
- `/tmp/dv_debug/layer0_output.txt` — Layer 0 V2 output dump

```bash
DV_DEBUG_POSTPROCESS=1 pp_layer1 < input > output
cat /tmp/dv_debug/postprocess.log
```

## Op Struct

```c
typedef struct {
    char type[20];   // "keep", "delete", "insert", "overwrite_insert"
    int  code;        // char code (10=\n, 32=space, 9=tab, etc.)
    int  line;        // 1-indexed line number
    int  col;         // 1-indexed column number
} Op;
```

The `char_repr` field (5th TSV column, e.g. `'A'`, `space`, `\n`) is
derived from `code` by `pp_char_repr()` — it's cosmetic, not stored
in the struct. The `pos_set` flag that previously existed on the
struct has been removed.

## Layer Function Signature

Each layer implements:
```c
int layer_N(Op *in, int in_count, Op *out, int out_cap,
            const char *old_file);
```
- `in` — input ops
- `in_count` — number of input ops
- `out` — output ops (pre-allocated)
- `out_cap` — capacity of `out`
- `old_file` — path to the old (pre-change) file, for layers that need it
- Returns: number of output ops (can be <, =, or > input)

## adjust_positions (inline in postprocess.c)

Not a layer — it runs in-place on the Op array, after every layer.
Algorithm (recursive):

- Track `deleted_lines` and a `characters` carry counter.
- For each op:
  - Rule 1: if the op's (line − deleted_lines) differs from
    `current_line`, reset `characters` to 0.
  - Rule 2: for non-`\n` ops, update `characters` (+1 for insert,
    −1 for delete, net 0 for `overwrite_insert`).
  - Rule 3: `op.line −= deleted_lines; op.col += characters`.
  - Rule 4 (delete `\n`): `deleted_lines += 1`. If `characters > 0`,
    recurse on the rest of the buffer with the carried `characters`
    (this is the "line join" case).
  - Rule 5 (keep/insert/overwrite_insert `\n`): reset `characters = 0`.

## Tests

```bash
bash tests/test_postprocess_layers.sh
```
