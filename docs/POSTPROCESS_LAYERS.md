# Postprocess Layers

The postprocess stage is being rewritten as a series of **layers**.
Each layer is a pure function: `Op[] → Op[]`. No side effects.

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
Layer 2: Transforms (pp_layer2_transforms.c)
    │   indent-last, semantic-cleanup, overwrite.
    ▼
Layer 3: Cursor Recomputation (pp_layer3_cursor.c)
    │   Assigns correct (line, col) to every op.
    ▼
postprocess output (V2 TSV)
```

## File Structure

| File | Layer | Status |
|------|-------|--------|
| `pp_common.h` | Shared | Types, logging, TSV parsing, standalone runner |
| `pp_layer0_v2.c` | Layer 0 | **Implemented** — V1/V2 detection, conversion |
| `pp_layer1_reorder.c` | Layer 1 | No-op (passthrough) — 4-sweep reorder to be added |
| `pp_layer2_transforms.c` | Layer 2 | No-op (passthrough) — transforms to be added |
| `pp_layer3_cursor.c` | Layer 3 | No-op (passthrough) — cursor recomp to be added |
| `pp_layer_noop.pl` | Perl | No-op (passthrough) — Perl template |

## Build

### Standalone binaries (each reads stdin, writes stdout):
```bash
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer0 animator/c/pp_layer0_v2.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer1 animator/c/pp_layer1_reorder.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer2 animator/c/pp_layer2_transforms.c
cc -DPP_STANDALONE -O2 -Wall -Wextra -Werror -I animator/c \
   -o animator/bin/pp_layer3 animator/c/pp_layer3_cursor.c
```

### Piped (each layer as separate process):
```bash
compute | pp_layer0 | pp_layer1 | pp_layer2 | pp_layer3 > output
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
in the struct.

## Layer Function Signature

Each layer implements:
```c
int layer_N(Op *in, int in_count, Op *out, int out_cap);
```
- `in` — input ops
- `in_count` — number of input ops
- `out` — output ops (pre-allocated)
- `out_cap` — capacity of `out`
- Returns: number of output ops (can be <, =, or > input)

## Tests

```bash
bash tests/test_postprocess_layers.sh
```

Tests (11 total):
1. Layer 0: V2 passthrough matches input ✓
2. Layer 1: no-op passthrough ✓
3. Layer 2: no-op passthrough ✓
4. Layer 3: no-op passthrough ✓
5. Full pipeline (all 4 layers piped) ✓
6. Perl no-op layer ✓
7. C pipeline == Perl pipeline (parity) ✓
8. Debug logging creates files ✓
9. Debug log contains layer name + message ✓
10. Animation output (Layer 3 not yet implemented) ⚠
11. Example 02 (Layer 3 not yet implemented) ⚠
