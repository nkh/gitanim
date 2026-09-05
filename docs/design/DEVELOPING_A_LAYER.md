# Developing a Postprocess Layer

This guide walks through creating a new postprocess layer for the `ad`
pipeline — from concept to tested, documented, and integrated.

## Table of Contents

1. [Why Write a Layer?](#why-write-a-layer)
2. [When to Write a Layer vs. When Not To](#when-to-write-a-layer-vs-when-not-to)
3. [Choosing a Language](#choosing-a-language)
4. [The Plugin Contract](#the-plugin-contract)
5. [Your First Layer: `ad_layer_reverse_inserts`](#your-first-layer-ad_layer_reverse_inserts)
6. [Testing Your Layer](#testing-your-layer)
7. [Documenting Your Layer](#documenting-your-layer)
8. [Integrating with the Pipeline](#integrating-with-the-pipeline)
9. [Debugging](#debugging)
10. [Advanced Patterns](#advanced-patterns)
11. [Checklist](#checklist)

---

## Why Write a Layer?

The `ad` pipeline is `ad_compute → ad_postprocess → ad_layer_pace → ad`.
The postprocess stage (`ad_postprocess`) chains layer plugins that
transform the op stream before animation. Layers let you:

- **Reorder ops** — e.g., delete before insert within each line
  (`ad_layer_reorder`)
- **Merge ops** — e.g., combine adjacent delete+insert into overwrite
  (`ad_layer_overwrite`)
- **Insert timing** — e.g., add delays for pacing (`ad_layer_pace`)
- **Decorate ops** — e.g., add highlight markers (`ad_layer_highlight`)
- **Filter ops** — e.g., skip indent-only changes (`ad_layer_skip_indent`)

Layers are **standalone executables** that read TSV from stdin and write
TSV to stdout. This means:
- Any language (C, Perl, Python, Ruby, Bash, Node)
- Independently testable
- Composable in any order
- No recompilation of the core pipeline needed

---

## When to Write a Layer vs. When Not To

### Write a layer when:
- You want to transform the **op stream** (reorder, merge, insert, filter)
- The transformation is **post-diff** (after `ad_compute` produces ops)
- You want it to be **optional** and composable with other layers
- You want users to be able to **enable/disable it** via `--ad-layer=<name>`

### Do NOT write a layer when:
- You want to change the **diff algorithm** itself → modify `ad_compute`
- You want to change **animation rendering** → modify `animator/c/ad.c`
- You want to change **CLI options** → modify `apps/vim/ad_vim`
- The transformation is **trivial** and better done as a pipeline `sed`/`awk`

---

## Choosing a Language

| Language | When to use | Pros | Cons |
|----------|-------------|------|------|
| **C** | Production layers (performance-critical) | Fastest, no runtime dep | More code, manual memory |
| **Perl** | Rapid prototyping, text processing | Powerful regex, concise | Slower, Perl dependency |
| **Python** | Complex logic, data structures | Readable, rich stdlib | Slowest, Python dep |
| **Bash** | Simple glue, `sed`/`awk` wrappers | No compilation | Fragible, slow for big inputs |
| **Ruby** | If you prefer Ruby | Clean syntax | Ruby dep |

**Recommendation**: Start with Perl for prototyping (fast to iterate),
port to C if performance matters. The existing layers all have C
implementations in `layers/c/` and Perl twins in `layers/perl/`.

---

## The Plugin Contract

A layer is any executable that obeys these rules:

1. **Reads V2 TSV from stdin.** Format:
   ```
   # diffvim raw diff v2       ← header (pass through or rewrite)
   # algorithm patience
   HUNK  <target> <del> <ins> <end_ins> <end_del>
   <type>  <line>  <col>  <code>  <char_repr>
   ...
   HUNK_END
   HUNK  ...
   ```

2. **Writes V2 TSV to stdout** in the same format. The layer may:
   - Transform ops (change type, line, col, code)
   - Reorder ops
   - Insert new ops (e.g., `delay`, `highlight`)
   - Delete ops
   - Pass ops through unchanged

3. **Exits 0 on success.** Non-zero exits abort the pipeline.

4. **Accepts `--help` / `-h`.** Prints usage to stderr and exits 0.

### Op Types

| Type | Meaning |
|------|---------|
| `keep` | Character is unchanged (advances cursor) |
| `delete` | Character is deleted from the buffer |
| `insert` | Character is inserted at (line, col) |
| `overwrite_insert` | Delete then insert at same position |
| `delay` | Timing delay (code = ms, not a char) |
| `highlight` | Decoration (no buffer effect) |
| `dim` | Decoration |
| `fold` | Decoration |
| `sign` | Decoration |
| `marker` | Decoration |
| `HUNK` / `HUNK_END` | Hunk boundaries |
| `EOF` / `done` | End of stream |

### Char Codes

- `10` = newline (`\n`)
- `32` = space
- `9` = tab
- `33-126` = printable ASCII
- `>127` = UTF-8 code points

---

## Your First Layer: `ad_layer_reverse_inserts`

Let's create a layer that reverses the order of insert ops within each
line. (This is a toy example — not particularly useful, but
demonstrates the pattern.)

### Step 1: Create the C source

Create `layers/c/ad_layer_reverse_inserts.c`:

```c
/* ad_layer_reverse_inserts.c — Reverse insert ops within each line.
 *
 * Within each segment (between keeps and \n ops), reverse the order
 * of insert ops. Deletes and keeps stay in place.
 *
 * This is a toy example. See ad_layer_reorder.c for a real layer.
 */
#include "ad_layer_common.h"

static int layer_reverse_inserts(Op *ops, int n_ops, Op *out, int out_cap,
                                  int *line_offset) {
    int out_count = 0;
    int segment_start = 0;

    for (int i = 0; i <= n_ops; i++) {
        /* Check for segment boundary (keep, \n, or end) */
        int is_boundary = (i == n_ops);
        if (i < n_ops && !ad_layer_is_debug_op(&ops[i])) {
            if (strcmp(ops[i].type, "keep") == 0 ||
                ops[i].code == AD_LAYER_CHAR_NEWLINE)
                is_boundary = 1;
        }

        if (is_boundary) {
            /* Collect inserts in this segment */
            int ins_start = out_count;
            for (int j = segment_start; j < i; j++) {
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "insert") == 0 &&
                    ops[j].code != AD_LAYER_CHAR_NEWLINE &&
                    out_count < out_cap) {
                    out[out_count++] = ops[j];
                }
            }
            /* Reverse the inserts we just added */
            int n_ins = out_count - ins_start;
            for (int k = 0; k < n_ins / 2; k++) {
                Op tmp = out[ins_start + k];
                out[ins_start + k] = out[ins_start + n_ins - 1 - k];
                out[ins_start + n_ins - 1 - k] = tmp;
            }
            /* Emit non-inserts (deletes, debug) in original order */
            for (int j = segment_start; j < i; j++) {
                if (!ad_layer_is_debug_op(&ops[j]) &&
                    strcmp(ops[j].type, "insert") != 0 &&
                    out_count < out_cap) {
                    out[out_count++] = ops[j];
                }
            }
            /* Emit debug ops */
            for (int j = segment_start; j < i; j++) {
                if (ad_layer_is_debug_op(&ops[j]) && out_count < out_cap)
                    out[out_count++] = ops[j];
            }
            /* Emit the boundary op itself */
            if (i < n_ops && out_count < out_cap)
                out[out_count++] = ops[i];
            segment_start = i + 1;
        }
    }

    /* Recompute positions (col walk) — see ad_layer_reorder.c Pass 2 */
    /* ... (omitted for brevity — copy from ad_layer_reorder.c) ... */

    return out_count;
}

int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    return ad_layer_run(layer_reverse_inserts);
}
```

### Step 2: Add to the Makefile

Edit `Makefile` and add your layer to the `LAYERS` list:

```makefile
LAYERS = ad_layer_reorder ad_layer_overwrite ad_layer_indent_last \
         ad_layer_line_delete_in_place ad_layer_skip_indent \
         ad_layer_pace ad_layer_highlight \
         ad_layer_reverse_inserts
```

### Step 3: Build

```bash
make layers
```

### Step 4: Test standalone

```bash
echo -e "HUNK\t1\t1\t1\t0\t0\ninsert\t1\t1\t97\t'a'\ninsert\t1\t2\t98\t'b'\ninsert\t1\t3\t99\t'c'\nHUNK_END" \
  | ./bin/ad_layer_reverse_inserts
```

Expected output: the inserts are reversed (`c`, `b`, `a`).

---

## Testing Your Layer

### Unit Tests

Create `tests/test_layer_reverse_inserts.pl`:

```perl
#!/usr/bin/env perl
use strict; use warnings;

my $root = "/home/z/my-project/gitanim";
my $pass = 0; my $fail = 0;

# Test 1: reverses inserts within a segment
my $input = "HUNK\t1\t1\t3\t0\t0\ninsert\t1\t1\t97\t'a'\ninsert\t1\t2\t98\t'b'\ninsert\t1\t3\t99\t'c'\nHUNK_END\n";
my $expected_types = "insert\tinsert\tinsert";
my $expected_codes = "99\t98\t97";  # c, b, a (reversed)

my $out = `echo -e "$input" | $root/bin/ad_layer_reverse_inserts 2>/dev/null`;
my @op_lines = grep { /^insert\s/ } split /\n/, $out;
my $got_codes = join "\t", map { (split /\t/)[3] } @op_lines;

if ($got_codes eq $expected_codes) {
    print "PASS: inserts reversed correctly\n";
    $pass++;
} else {
    print "FAIL: expected '$expected_codes', got '$got_codes'\n";
    $fail++;
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
```

### C/Perl Parity

If you write both C and Perl versions, verify they produce identical
output on all 42 examples:

```bash
for d in tests/examples/*/; do
    old=$(ls $d/old.* 2>/dev/null | head -1)
    new=$(ls $d/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    bin/ad_compute "$old" "$new" /tmp/raw.tsv 2>/dev/null
    bin/ad_layer_reverse_inserts < /tmp/raw.tsv > /tmp/c_out.tsv 2>/dev/null
    perl layers/perl/ad_layer_reverse_inserts.pl < /tmp/raw.tsv > /tmp/pl_out.tsv 2>/dev/null
    diff -q /tmp/c_out.tsv /tmp/pl_out.tsv || echo "PARITY FAIL: $d"
done
```

### Pipeline Integration

Test that your layer works in the full pipeline:

```bash
./pipeline/ad_pipeline --no-display --speed 1000 --snapshot /tmp/snap.txt \
    old.py new.py --postprocess-layer=ad_layer_reverse_inserts
diff new.py /tmp/snap.txt  # should match
```

### Property-Based Tests

Run the property tests with your layer enabled to catch edge cases:

```bash
AD_POSTPROCESS_LAYERS=ad_layer_reverse_inserts make test-property
```

---

## Documenting Your Layer

### 1. Add a manpage

Create `man/ad_layer_reverse_inserts.1`:

```troff
.TH AD_LAYER_REVERSE_INSERTS 1 "2026-09-05" "ad 1.0" "User Commands"
.SH NAME
ad_layer_reverse_inserts \- reverse insert ops within each line
.SH SYNOPSIS
.B ad_layer_reverse_inserts
< ops.tsv > processed.tsv
.SH DESCRIPTION
Reverses the order of insert operations within each segment (between
keeps and newline ops). Deletes and keeps stay in their original
positions.
.SH USAGE
Typically invoked via
.BR ad_postprocess (1):
.PP
.RS
ad_postprocess --ad-layer=ad_layer_reverse_inserts < raw.tsv
.RE
.SH SEE ALSO
.BR ad_postprocess (1),
.BR ad_layer_reorder (1)
```

### 2. Add to the layers table

Update `README.md` and `INSTALL.md` layers tables:

```markdown
| `ad_layer_reverse_inserts`     | Reverse insert ops within each line |
```

### 3. Add to the mdBook

Update `docs/src/plugin-layers.md` with a section for your layer.

### 4. Add to LAYERS_REFERENCE.md

Update `docs/design/LAYERS_REFERENCE.md` with pseudo-code and examples.

---

## Integrating with the Pipeline

Users can now use your layer:

```bash
# Direct invocation
./pipeline/ad_postprocess --ad-layer=ad_layer_reverse_inserts < raw.tsv

# Via ad_vim
./apps/vim/ad_vim --ad-layer=ad_layer_reverse_inserts old.py new.py

# Via ad_gen_ops
./scripts/ad_gen_ops --ad-layer=ad_layer_reverse_inserts old.py new.py > ops.tsv

# Via ad_session
./scripts/ad_session --ad-layer=ad_layer_reverse_inserts old.py new.py --annotate
```

### Layer Groups

Users can define layer groups in `.ad_layers`:

```
my_workflow
ad_layer_reorder
ad_layer_reverse_inserts
ad_layer_indent_last
```

Then: `./scripts/ad_session --layer-file=.ad_layers old.py new.py`

---

## Debugging

### Inspect intermediate output

Use `--ad-layer-keep-temps` to see each layer's input/output:

```bash
./pipeline/ad_postprocess \
    --ad-layer=ad_layer_reorder \
    --ad-layer=ad_layer_reverse_inserts \
    --ad-layer-keep-temps < raw.tsv > out.tsv
ls /tmp/ad_postprocess_*/  # intermediate files
```

### Trace op flow

Add debug output to your layer (to stderr):

```c
if (getenv("AD_LAYER_DEBUG")) {
    fprintf(stderr, "reverse_inserts: segment %d-%d, %d inserts\n",
            segment_start, i, n_ins);
}
```

### Compare with/without layer

```bash
# Without layer
bin/ad_compute old.py new.py /tmp/raw.tsv 2>/dev/null
bin/ad --no-display --speed 1000 --snapshot /tmp/snap_without.tsv old.py < /tmp/raw.tsv

# With layer
./pipeline/ad_postprocess --ad-layer=ad_layer_reverse_inserts < /tmp/raw.tsv > /tmp/post.tsv
bin/ad --no-display --speed 1000 --snapshot /tmp/snap_with.tsv old.py < /tmp/post.tsv

# Compare
diff /tmp/snap_without.tsv /tmp/snap_with.tsv
```

### Use ad_session for interactive debugging

```bash
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reverse_inserts --annotate
```

This opens vim with:
- Left: diff between expected and actual output
- Right top: the op list (editable, with annotations)
- Right bottom: the result of applying the ops

Press `F5` to animate, `F6` to snapshot, `<leader>g` to regenerate ops.

See [docs/src/debugging.md](../src/debugging.md) for the full debugging
tool reference.

### Common bugs

| Symptom | Likely cause |
|---------|-------------|
| Output is empty | Layer crashed; check stderr |
| Positions are wrong | Didn't recompute (line, col) after reordering |
| Animator produces garbage | Op positions don't match buffer state |
| HUNK header mismatch | Didn't update target_line with line_offset |
| Double-counted line shifts | Layer shifted ops but animator also applies line_shift |

---

## Advanced Patterns

### Layers that insert ops

`ad_layer_pace` inserts `delay` ops. `ad_layer_highlight` inserts
`highlight`/`dim`/`fold` ops. These don't affect the buffer — the
animator recognizes them as metadata.

### Layers that change line count

If your layer inserts or deletes `\n` ops, it changes the line count.
The layer runner tracks this via `*line_offset` and updates subsequent
HUNK headers automatically. See `layers/c/ad_layer_common.h`
`AD_LAYER_FLUSH_HUNK()`.

### Layers with options

`ad_layer_pace` and `ad_layer_highlight` accept their own CLI options.
Parse them in `main()` before calling `ad_layer_run()`:

```c
int main(int argc, char **argv) {
    __argc = argc; __argv = argv;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--my-option") == 0 && i + 1 < argc)
            my_option = argv[++i];
        else if (strcmp(argv[i], "--help") == 0) {
            fprintf(stderr, "Usage: ...\n");
            return 0;
        }
    }
    return ad_layer_run(my_layer);
}
```

---

## Checklist

Before submitting a new layer:

- [ ] Source file in `layers/c/<name>.c`
- [ ] Added to `LAYERS` in `Makefile`
- [ ] `make layers` builds successfully
- [ ] `--help` / `-h` works
- [ ] Manpage in `man/<name>.1`
- [ ] Added to layers table in `README.md` and `INSTALL.md`
- [ ] Added to `docs/src/plugin-layers.md`
- [ ] Added to `docs/design/LAYERS_REFERENCE.md`
- [ ] Unit test in `tests/test_layer_<name>.pl`
- [ ] C/Perl parity test (if Perl twin exists)
- [ ] Pipeline integration test passes (`make test-examples`)
- [ ] Property tests pass (`make test-property`)
- [ ] No regressions in `make test`

---

## See Also

- [docs/src/plugin-layers.md](../src/plugin-layers.md) — Plugin contract reference
- [docs/design/LAYERS_REFERENCE.md](LAYERS_REFERENCE.md) — All layers with pseudo-code
- [docs/design/LAYERS_REVIEW.md](LAYERS_REVIEW.md) — Layer audit and known issues
- [docs/src/debugging.md](../src/debugging.md) — Debugging tools reference
- [layers/c/ad_layer_reorder.c](../layers/c/ad_layer_reorder.c) — Reference implementation
- [layers/c/ad_layer_common.h](../layers/c/ad_layer_common.h) — Shared infrastructure
