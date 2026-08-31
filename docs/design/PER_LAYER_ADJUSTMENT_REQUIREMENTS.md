# Requirements: Per-Layer Position Adjustment & Debug Infrastructure

## Background

The postprocess pipeline transforms raw ops from compute into a timed op stream for the animator. Currently, a single `adjust_positions` pass runs at the end of the pipeline, trying to fix line/col positions for all ops after all layers have run. This is fragile — the end-of-pipeline adjust has no knowledge of what each layer did, so it has to reconstruct the entire history from the final op order, which leads to complex recursive logic and subtle bugs.

We want to change to a model where each layer adjusts the positions of the ops it produces, so that after every layer, the op list is valid and can be consumed by any other layer.

We also want to build debugging infrastructure into the layers and the orchestrator, so that when a layer breaks something, we can quickly find out which layer, which op, and why.

---

## Part 1: Per-Layer Position Adjustment

### The Invariant

After every layer runs, applying its output ops to the original old file produces the correct new file. In other words, the ops are a valid "program" that transforms old.txt into new.txt, regardless of order.

This means:

- If you pipe layer A's output directly to the animator, the animator produces the correct final buffer.
- If you pipe layer A's output to layer B, layer B receives a valid op stream.
- Any composition of layers (in any order) produces a valid result, as long as each layer preserves the invariant.

### How Each Layer Adjusts

**Layers that don't reorder or change positions** (overwrite, reorder):

These layers don't change line/col — they just merge ops (overwrite) or reorder within a line group (reorder, which doesn't change line numbers or cols because deletes don't advance col and the reorder stays within the same line). Their adjust is a no-op. They just verify the output is valid (which the debug infrastructure handles).

**Layers that reorder across lines** (indent-last, line-delete-in-place):

These layers need their own adjustment. The principle: the layer knows what it moved, so it can compute the new positions directly.

- **indent-last:** When it moves indent deletes from the start of a line to the end, the content ops on that line need their col shifted by `n_indent` (the number of leading indent chars). The indent deletes stay at col 1 (where the indent is in the buffer). The layer knows `n_indent` because it counted the leading deletes.

- **line-delete-in-place:** When it moves a deleted line's ops before the join, it knows it moved ops from line N+1 to before the join on line N. The moved ops keep their original line (N+1), and the join stays on line N. Everything after the deleted line's `\n` delete shifts up by 1 (because that line is gone). The layer computes this shift itself — it doesn't need a generic adjuster.

### The Animator as Validator

Instead of writing a separate buffer simulator, we use the existing animator executable (`ad`) to validate. The animator takes an old file and a timed op stream, applies the ops, and writes a snapshot. If the snapshot matches the expected new file, the ops are valid.

The orchestrator calls the animator:

```
ad --no-display --speed 1000 --snapshot /tmp/snap.txt old.txt < timed_ops.txt
diff /tmp/snap.txt new.txt
```

This gives us the ultimate correctness check without duplicating buffer logic. The animator is the single source of truth for "are these ops valid?"

### Layer Interface

Each layer function gets a `LayerContext` struct (not global state — passed by value or pointer as a parameter):

```c
typedef struct {
    const char *old_file;        /* path to old file (for buffer validation) */
    const char *new_file;       /* path to new file (for invariant check) */
    int debug_flags;            /* bitmask of debug options (see Part 2) */
    const char *dump_dir;       /* directory for dump files */
    const char *layer_name;     /* name of this layer (for logging) */
    /* ... more fields as needed ... */
} LayerContext;
```

No global state. The context is created by the orchestrator and passed to each layer. Layers read from it, they don't write to it.

---

## Part 2: Debug Infrastructure

### Priority-Ordered Debug Options

Listed from highest impact (most useful for finding bugs fast) to lowest:

#### 1. `--dump-changes FILE` (highest priority)

Write only the ops that changed, showing before → after, and why. This is the single most useful debug tool — when a layer breaks something, you want to see exactly what it changed without wading through 60 unchanged ops.

Format:
```
[18] delete (1,18) \n  → delete (2,1) \n   [reordered: moved before join on line 1]
[19] delete (2,1) 'B'  → delete (2,1) 'B'   [unchanged but moved in stream]
[22] keep (3,1) 'C'    → keep (2,1) 'C'     [line_shifted: 3→2 (line 2 deleted)]
```

**Why it wins:** Immediately shows what the layer did. No noise from passthrough ops. The "why" column is the key — it explains the layer's reasoning.

#### 2. `--trace-decisions`

Print why the layer made each change — what pattern matched, what rule fired, what adjustment was applied. This is the narrative of the layer's logic.

```
[18] delete (1,18) \n
     PATTERN: join on line 1, line 2 is fully deleted
     ACTION: move line 2 ops before join
     ADJUST: line 2 ops keep line=2, join stays at line=1
             ops after line 2's \n delete shift: line -= 1
[22] keep (3,1) 'C'
     ADJUST: line_shifted 3→2 (line 2 was fully deleted before this op)
```

**Why it wins:** When a layer makes a wrong decision, this shows exactly which decision was wrong and why. No need to add print statements and recompile.

#### 3. `--check-invariant`

Apply the output ops to the old file (via the animator) and compare with the new file. If they match, the layer is correct. This is the ultimate correctness check — it catches any bug, not just position bugs.

```
Layer: line_delete_in_place
Invariant check: PASS (snapshot matches new file)
```

or:

```
Layer: line_delete_in_place
Invariant check: FAIL
  Expected: "AC"
  Got:      "A\nC"
  Diff:
  1c1
  < AC
  ---
  > A
  > C
```

**Why it wins:** You don't need to know *why* it's broken — you just know it is. Combined with `--dump-changes`, you can bisect: "the invariant was valid before this layer, and invalid after — what did this layer change?"

#### 4. `--dump-virtual-after FILE`

Apply the output ops to the old file → write the resulting buffer to FILE. This shows the "virtual file" the layer produced. If it doesn't match the expected new file, the layer has a bug.

**Why it wins:** The virtual file is the buffer state after the layer. If it's wrong, the layer broke something. If it's right, the layer is correct (even if the ops look weird). This separates "ops look right" from "ops are right".

Implementation: call the animator:
```
ad --no-display --speed 1000 --snapshot FILE old.txt < output_ops.txt
```

#### 5. `--dump-input FILE` and `--dump-output FILE`

Write the input and output ops to files. Simple but essential — you need to see what the layer started with and what it produced.

**Why it wins:** Enables diffing input vs output, and piping output to the next layer for manual testing.

#### 6. `--trace-buffer`

Print the buffer state after each op is applied (using the animator's snapshot feature). Shows a text "animation" of the buffer evolving:

```
[ 0] keep (1,1) 'A'      → ["A", "B", "C"]
[ 1] delete (2,1) 'B'     → ["A", "", "C"]
[ 2] delete (2,1) \n     → ["A", "C"]
[ 3] delete (1,2) \n     → ["AC"]
```

**Why it wins:** Shows the visual effect of each op. When the buffer goes wrong, you can see exactly which op caused it. This is what `dv_snapshot` does, but per-layer.

Implementation: call the animator with a snapshot after each op. The orchestrator generates a timed op stream with a `snapshot /tmp/trace_N.txt` op after each op, runs the animator, then reads the snapshots.

#### 7. `--stats`

Print a summary of what the layer did:

```
=== Layer: line_delete_in_place ===
Input:  61 ops (45 delete, 10 keep, 6 insert)
Output: 61 ops (45 delete, 10 keep, 6 insert)
Changes: 3 ops reordered, 8 ops line-shifted
Joins detected: 2
Fully deleted lines: 2
Invariant: PASS
```

**Why it wins:** Quick overview. If a layer normally makes 0 changes but suddenly makes 50, something's wrong. Good for regression detection.

#### 8. `--filter-line N`

Only process ops on line N (and N+1 for join detection). Useful for debugging a specific line's issue without noise.

**Why it wins:** Large files have many ops. When a test fails on "line 38", you want to see only line 38's ops, not all 200.

#### 9. `--diff-input-output`

Show a unified diff of input vs output op lists. Like `diff` but for ops, showing insertions/deletions/reorderings.

**Why it wins:** Visually clear — red lines removed, green lines added. When a layer reorders, you see the ops "moving".

#### 10. `--format colored`

ANSI color codes for terminal output: red deletes, green inserts, yellow keeps, magenta overwrite_insert, cyan \n ops, bold for changed ops.

**Why it wins:** When scanning 60 ops, color makes patterns visible. You can see "all the \n deletes are cyan" at a glance.

#### 11. `--format json`

Machine-readable JSON output for automated testing.

**Why it wins:** A test script can parse the JSON and verify "op 18 has line=2, col=1" without text parsing. Enables CI/CD integration.

#### 12. `--validate`

Check the output is structurally valid (no negative lines, no col > line length, etc.)

**Why it wins:** Catches simple bugs fast. A negative line number is always wrong.

#### 13. `--filter-type TYPE`

Only show ops of a specific type (keep, delete, insert, overwrite_insert).

**Why it wins:** "Show me all the \n deletes" is useful when debugging join issues.

#### 14. `--filter-hunk N`

Only process hunk N.

**Why it wins:** Large files have many hunks. Focus on the broken one.

#### 15. `--dump-virtual-before FILE`

Like `--dump-virtual-after` but for the input. Shows the buffer before the layer ran.

**Why it wins:** If virtual-before is already wrong, the bug is in a previous layer, not this one. Helps with bisection.

#### 16-20: Lower priority

- `--trace-ops` (print every op with before/after) — useful but verbose
- `--validate-positions` (check cursor can reach each position) — redundant with `--check-invariant`
- `--format tsv` (default, for piping) — already the default
- `--filter-changed` (only show changed ops in trace) — redundant with `--dump-changes`
- `--break LINE` (stop at a specific line) — nice for interactive use but lower priority

---

## Part 3: HTML Snapshot Generation

### The Problem

`dv_snapshot.sh` generates an HTML file showing the animation frame by frame. It's useful for visual debugging. We want layers to be able to produce similar snapshots without each layer implementing HTML generation code.

### The Solution: Layers Output Ops, dv_snapshot Produces HTML

Layers stay pure — they only manipulate ops. When you want a visual snapshot of a layer's output, the orchestrator:

1. Runs the layer, gets the output ops
2. Pipes the output ops through `pace` (to add delays)
3. Calls `dv_snapshot.sh` with the paced ops and the old file
4. `dv_snapshot.sh` produces the HTML

This keeps the layer code-free of snapshot logic. The layer just produces ops; the visualization is a separate step.

### Using the Animator Directly

Yes, we can use the animator directly instead of `dv_snapshot.sh`. The animator already has `--snapshot FILE` which writes the final buffer state. For per-op snapshots (showing the buffer after each op), the orchestrator can:

1. Take the layer's output ops
2. Inject a `snapshot /tmp/trace_N.txt` op after each op
3. Run the animator with `--no-display --speed 1000`
4. Read the snapshot files

This gives us per-op buffer states without any new code — just the existing animator with snapshot injection.

For HTML output, `dv_snapshot.sh` can take the snapshot files and generate HTML. Or we can write a small script that converts the snapshot files to an HTML page (showing each buffer state side by side).

### The Flow

```
Layer output ops
    │
    ├──→ pace → animator --snapshot → final buffer (for invariant check)
    │
    ├──→ pace + snapshot injection → animator → per-op buffers (for trace)
    │
    └──→ dv_snapshot.sh → HTML (for visual debugging)
```

The layer doesn't know about any of this. It just produces ops. The orchestrator handles visualization.

---

## Part 4: Bash Orchestrator

### The Problem

The current orchestrator is in `postprocess.c` (C code). To add/remove/reorder layers, you have to edit C and recompile. This is slow for experimentation.

### The Solution

Write the orchestrator as a bash script (`animator/ad_vim-orchestrator`). It:

1. Reads V2 TSV from stdin
2. For each enabled layer:
   a. Pipes the current op stream to the layer's standalone binary
   b. Captures the output
   c. Optionally runs validation (animator + diff)
   d. Optionally dumps debug info
3. Writes the final op stream to stdout

### The Script

```bash
#!/bin/bash
# ad_vim-orchestrator — runs postprocess layers in sequence
#
# Each layer is a standalone binary that reads V2 TSV from stdin
# and writes V2 TSV to stdout.
#
# Usage:
#   ad_vim-orchestrator [--indent-last] [--overwrite] [--debug] < raw_ops > post_ops

OPS_FILE=$(mktemp)
cat > "$OPS_FILE"

# Layer chain (edit this to add/remove/reorder layers)
LAYERS=()
[[ "$OVERWRITE" -eq 1 ]] && LAYERS+=("ad_layer_overwrite")
[[ "$INDENT_LAST" -eq 1 ]] && LAYERS+=("ad_layer_indent_last")
LAYERS+=("ad_layer_noop")          # reorder (always)
LAYERS+=("ad_layer_line_delete_in_place")  # always (when implemented)

# Run each layer
for layer in "${LAYERS[@]}"; do
    BIN="$ROOT/bin/$layer"
    if [[ -f "$BIN" ]]; then
        "$BIN" < "$OPS_FILE" > "$OPS_FILE.tmp"
        mv "$OPS_FILE.tmp" "$OPS_FILE"
    fi
done

cat "$OPS_FILE"
rm -f "$OPS_FILE"
```

### Advantages

- **No recompilation** to change layer order or enable/disable layers
- **Easy experimentation** — just edit the LAYERS array
- **Per-layer debugging** — add `--dump-changes` or `--trace-decisions` to individual layers
- **Composable** — pipe layers in any order, each produces valid output

### The C `postprocess.c` Still Exists

The C version remains as a single-binary alternative (for performance — no process spawning per layer). But the bash orchestrator is the primary tool for development and debugging.

---

## Part 5: Per-Layer Tests

### Test Structure

Each layer gets its own test directory:

```
tests/
  indent_last/
    test_basic.pl
    test_join.pl
    test_property.pl
    test_composition.pl    # test with other layers
  overwrite/
    test_basic.pl
    ...
  line_delete_in_place/
    test_basic.pl
    ...
  composition/
    test_all_combinations.sh   # test all layer combinations
```

### Composition Testing

A test script that runs all possible combinations of layers and verifies the invariant (animator produces correct output):

```bash
# For each combination of layers:
#   1. Run compute → raw ops
#   2. Run the combination of layers
#   3. Run animator → snapshot
#   4. Compare snapshot with new file
#   5. Report pass/fail

LAYERS=(ad_layer_overwrite ad_layer_indent_last ad_layer_noop ad_layer_line_delete_in_place)

# Generate all 2^4 = 16 combinations
for mask in $(seq 0 $((2**${#LAYERS[@]} - 1))); do
    COMBO=()
    for i in "${!LAYERS[@]}"; do
        [[ $((mask & (1 << i))) -ne 0 ]] && COMBO+=("${LAYERS[$i]}")
    done
    # Run the combination...
done
```

This catches interaction bugs — when layer A's output breaks layer B.

---

## Part 6: Interactive Layer Debugger

### What It Does

A scriptable tool that lets you:

1. **Load** an old file, new file, and op stream
2. **Run** a specific layer (or all layers) step by step
3. **Step** forward N operations, seeing the buffer state after each
4. **Write** the output (ops or buffer state) to a file for inspection
5. **Script** the entire session — a list of commands that can be replayed

### The Tool: `pp-debug`

A bash script (or small C program) that provides a REPL:

```
$ pp-debug old.py new.py raw_ops.txt
pp-debug> load old.py new.py raw_ops.txt
Loaded: 61 ops, 3 hunks
pp-debug> show ops              # show current op stream
pp-debug> run ad_layer_overwrite      # run overwrite layer
  → 58 ops (3 merges)
pp-debug> show changes          # show what changed
pp-debug> run ad_layer_indent_last    # run indent-last layer
  → 58 ops (0 changes)
pp-debug> run ad_layer_noop          # run reorder layer
  → 58 ops (12 reordered)
pp-debug> show buffer           # apply ops to old file, show result
pp-debug> step 5                 # step 5 ops, show buffer after each
pp-debug> write ops /tmp/out.txt
pp-debug> write buffer /tmp/buf.txt
pp-debug> write html /tmp/trace.html  # generate HTML snapshot
pp-debug> quit
```

### Scripting

The tool reads commands from a script file:

```bash
pp-debug --script /tmp/debug_session.txt old.py new.py raw_ops.txt
```

Where `/tmp/debug_session.txt` contains:
```
load old.py new.py raw_ops.txt
run ad_layer_overwrite
show changes
write ops /tmp/after_overwrite.txt
run ad_layer_noop
show changes
write buffer /tmp/buffer_after_reorder.txt
step 10
write buffer /tmp/buffer_step10.txt
```

### Output Per Operation

The `step N` command applies N ops and writes the buffer state after each to files:

```
step 5
  → /tmp/step_0.txt (buffer after op 0)
  → /tmp/step_1.txt (buffer after op 1)
  → /tmp/step_2.txt (buffer after op 2)
  → /tmp/step_3.txt (buffer after op 3)
  → /tmp/step_4.txt (buffer after op 4)
```

These files can be inspected individually or combined into an HTML page (by `dv_snapshot.sh` or a similar script).

### Implementation

The tool is a bash script that:

1. Manages the op stream (a temp file)
2. Calls layer binaries to run layers
3. Calls the animator to produce buffer snapshots
4. Calls `diff` to compare buffers
5. Provides a REPL using `read -e` (with history)

No C code needed — it orchestrates existing tools (layer binaries, animator, diff, dv_snapshot).

---

## Part 7: Addressing the Concerns

### Buffer Simulator Accuracy

Use the animator executable, do not have different code. The animator (`ad`) is the single source of truth for buffer manipulation. We call it as a subprocess:

- `--snapshot FILE` writes the final buffer after all ops
- `--no-display --speed 1000` runs it headless and fast
- For per-op snapshots: inject `snapshot /tmp/trace_N.txt` ops into the stream

The orchestrator (bash) handles calling the animator and reading the snapshots. No buffer code is duplicated.

### LayerContext — No Global State

The `LayerContext` is passed as a parameter to each layer function. It is created by the orchestrator and passed by pointer. Layers read from it but don't write to it. No global variables, no `static` state.

For standalone binaries (when layers are run via the bash orchestrator), the context is set via command-line args and env vars (which are per-process, not global).

### Debug Flag Scope

Debug flags are set per-layer (when running standalone) and at the orchestrator level (when running the full pipeline). The orchestrator passes flags down to each layer.

For the bash orchestrator:
```bash
ad_layer_overwrite --dump-changes /tmp/ow_changes.txt < ops.txt > ops2.txt
ad_layer_indent_last --dump-changes /tmp/il_changes.txt < ops2.txt > ops3.txt
```

Or globally:
```bash
ad_vim-orchestrator --debug --dump-dir /tmp/debug < raw.txt > post.txt
# This runs each layer with --dump-changes /tmp/debug/<layer>_changes.txt
```

### Output Format

Both JSON and TSV. The default is TSV (for piping). `--format json` for machine-readable output. `--format colored` for terminal. The layer supports all three via a `--format` flag.

### Debugging First

Build the debug infrastructure before fixing the per-layer adjustment. This way, when we implement per-layer adjustment, we can debug each layer's adjustment immediately using the tools we built.

### Implementation Order

1. **Bash orchestrator** — replace the C orchestrator with a bash script that calls standalone layer binaries
2. **Debug flags on layers** — add `--dump-changes`, `--trace-decisions`, `--check-invariant` to each layer binary
3. **Per-layer adjustment** — each layer adjusts its own positions (using debug tools to verify)
4. **Composition testing** — test all layer combinations
5. **Interactive debugger** — build `pp-debug`
6. **HTML snapshots** — integrate with `dv_snapshot.sh`
