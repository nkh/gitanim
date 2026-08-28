# Flexibility & Dynamic Layer Architecture

Diffvim's postprocess pipeline is **plugin-based**. Layers are discovered
dynamically at runtime — adding a new layer does not require editing the
diffvim launcher, the ad_pipeline script, the Makefile's layer list,
or any other code. You drop a binary in place and add one line to a
manifest.

This document describes the plugin contract, the discovery mechanism, and
how to add a layer in any language.

## At a glance

```
compute → ad_postprocess → animator
              │
              │ reads animator/layers.conf (the manifest)
              │
              ├─ ad_layer_reorder         (always)        ← order 10
              ├─ ad_layer_overwrite       (--overwrite)    ← order 20
              ├─ ad_layer_indent_last     (--indent-last)  ← order 30
              ├─ ad_layer_line_delete_in_place (--line-delete-in-place) ← order 40
              ├─ ad_layer_pace            (always)         ← order 100
              └─ ad_layer_highlight       (always)         ← order 200
```

Each box is a standalone executable. The orchestrator (`animator/bin/
ad_postprocess`) chains them by piping stdout of one into stdin of
the next, in the order declared in the manifest.

## The plugin contract

A layer is any executable that obeys these four rules:

1. **Reads V2 TSV from stdin.** The input format is the diffvim op-stream
   format: lines like `HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>`,
   followed by op lines (`type\tline\tcol\tcode\tchar_repr`), followed by
   `HUNK_END`. Headers (`# ...`) and blank lines may appear before the
   first HUNK.

2. **Writes V2 TSV to stdout** in the same format. The layer may transform
   ops, reorder them, insert new ops, delete ops, or pass them through
   unchanged.

3. **Exits 0 on success.** Non-zero exits abort the pipeline.

4. **(Optional) Accepts `--help`.** Layers that take their own options
   should print usage on `--help`.

That's it. The orchestrator doesn't care what language the layer is written
in, what libraries it uses, or how it's compiled. If it can be invoked
from a shell and reads/writes TSV, it's a layer.

## Discovery paths

For a layer named `<name>` (e.g. `indent_last`), the orchestrator looks
for an executable in this order:

| # | Path                                          | Language           |
|---|-----------------------------------------------|--------------------|
| 1 | `animator/bin/pp_<name>`                      | C (preferred)      |
| 2 | `animator/perl/pp_<name>.pl`                  | Perl               |
| 3 | `animator/<lang>/pp_<name>.<ext>`              | Any (Python, Ruby, …) |
| 4 | `<absolute path>` (if name contains `/`)      | Any                |

Extensions recognized for path 3:

| Extension | Interpreter |
|-----------|-------------|
| `.pl`     | `perl`      |
| `.py`     | `python3`   |
| `.rb`     | `ruby`      |
| `.sh`     | `bash`      |
| `.js`     | `node`      |
| (none)    | executed directly |

This means you can write a layer in Python, drop it at
`animator/python/pp_word_split.py`, add a line to the manifest, and it
will be discovered and run automatically.

## The manifest

`animator/layers.conf` is the single source of truth. Format:

```
# <name>  <order>  <flag>  "<description>"
reorder                10   always                   "4-sweep reorder + position adjust"
overwrite              20   --overwrite              "Merge delete+insert pairs into overwrite_insert"
indent_last            30   --indent-last            "Move leading whitespace deletes to end of line"
line_delete_in_place   40   --line-delete-in-place   "Delete whole lines on their own line"
pace                   100  always                   "Insert delay ops between ops"
highlight              200  always                   "Insert highlight/dim/fold ops into timed stream"
```

Fields (whitespace-separated):

| Field        | Meaning                                                            |
|--------------|--------------------------------------------------------------------|
| `name`       | Layer identifier. Looked up via the discovery paths above.         |
| `order`      | Integer sort key. Layers run in ascending order.                   |
| `flag`       | `"always"` to run unconditionally, or `--flag-name` to enable on demand. |
| `description`| Human-readable. Shown by `--list-layers`. Double-quoted.          |

### Adding a layer (zero-edit checklist)

1. Write the binary. Save it as `animator/bin/pp_<name>` (compiled C),
   `animator/perl/pp_<name>.pl` (Perl), `animator/python/pp_<name>.py`
   (Python), etc. Make it executable.
2. Add ONE line to `animator/layers.conf`:
   ```
   <name>   <order>   <--flag-or-always>   "<description>"
   ```
3. Run `diffvim --list-layers` to verify it was discovered.
4. (Optional) Run `perl tests/test_layers_discovery.pl` to confirm it
   obeys the plugin contract (parses TSV, writes TSV, exit 0).

You do NOT need to edit:

- `diffvim` (the launcher)
- `animator/ad_pipeline` (the pipeline driver)
- `bin/ad_postprocess` (the orchestrator)
- `Makefile`'s `LAYER_BINS` list (unless you want a build target)
- Any test file (`test_layers_discovery.pl` is data-driven — it
  iterates the manifest, so it auto-asserts new layers)

### Removing a layer

Comment out the manifest line. The binary stays on disk (you can still
invoke it explicitly via `--layers=<name>`).

### Reordering layers

Change the `order` numbers in the manifest. Layers always run in
ascending order.

### Renaming a flag

Change the `flag` column. (Users now invoke it with the new flag name.)

## Invoking the orchestrator

The orchestrator is `bin/ad_postprocess`. It accepts:

| Flag                       | Behavior                                                |
|----------------------------|---------------------------------------------------------|
| `--<flag>`                 | Enable the layer whose manifest flag is `--<flag>`.    |
| `--pp-<name>`              | Alias for `--<name>` (symmetry with the launcher).     |
| `--enable=<name>[,name…]`  | Add layers to the default chain (by name).              |
| `--layers=<name>[,name…]`  | Run ONLY these layers (override default chain).         |
| `--list-layers`            | Print discovered layers and exit.                       |
| `--help` / `-h`            | Print usage and exit.                                   |
| `--`                       | Everything after this goes to every layer as args.      |
| (unknown `--flag`)         | Passed through to every layer that accepts it.          |

Examples:

```bash
# Default chain (always-on layers): reorder → pace → highlight
ad_postprocess < raw_ops > post_ops

# Enable indent_last
ad_postprocess --indent-last < raw_ops > post_ops

# Same thing, using the --pp-<name> convention
ad_postprocess --pp-indent-last < raw_ops > post_ops

# Run only reorder + indent_last (skip pace and highlight)
ad_postprocess --layers=reorder,indent_last < raw_ops > post_ops

# Add indent_last and overwrite to the default chain
ad_postprocess --enable=indent_last,overwrite < raw_ops > post_ops

# Pass --foo bar to every layer (passthrough args)
ad_postprocess --indent-last -- --foo bar < raw_ops > post_ops

# List all discovered layers
ad_postprocess --list-layers
```

## Invoking from the diffvim launcher

The `diffvim` script transparently forwards layer flags to the orchestrator.
Three equivalent ways to enable the `indent_last` layer:

```bash
diffvim --indent-last old.py new.py         # explicit (convenience)
diffvim --pp-indent-last old.py new.py      # generic --pp-<name> form
diffvim --list-layers                        # see all available layers
```

The `--pp-<name>` form is the **zero-edit convention**. When you add a
new layer `pp_foo` with flag `--foo`, you can immediately run:

```bash
diffvim --pp-foo old.py new.py
```

No launcher edit required.

The `ad_pipeline` script honors the same `--pp-<name>` form, plus
its existing `--postprocess-<name>` prefix.

## Language parity

Some layers have both a C implementation (preferred) and a Perl fallback:

| Layer            | C source                       | Perl source                       |
|------------------|--------------------------------|-----------------------------------|
| `reorder`        | `animator/c/ad_layer_reorder.c`      | (C only)                          |
| `overwrite`      | `animator/c/ad_layer_overwrite.c`    | (C only)                          |
| `indent_last`    | `animator/c/ad_layer_indent_last.c`  | `animator/perl/ad_layer_indent_last.pl` |
| `line_delete_in_place` | `animator/c/ad_layer_line_delete_in_place.c` | (C only) |
| `pace`           | `animator/c/ad_layer_pace.c`         | `layers/perl/ad_layer_pace.pl`           |
| `highlight`      | `animator/c/ad_layer_highlight.c`    | `layers/perl/ad_layer_highlight.pl`       |

The orchestrator prefers C if both exist; if the C binary is missing
(e.g. `make` hasn't been run, or you're on a platform without a C
compiler), it transparently falls back to Perl. C and Perl
implementations of the same layer must produce byte-identical output
for the same input — this is asserted by `test_layers_discovery.pl`'s
parity check.

The `ad_layer_noop.pl` file in `animator/perl/` is a template you can
copy to start a new Perl layer. It implements the full plugin contract
(hunk parsing, debug dumps, exit codes) with a no-op transform —
replace `layer_transform` with your own logic and you're done.

## Ad-hoc discovery

If a layer isn't declared in the manifest but the binary exists on disk
(e.g. `animator/bin/pp_word_split`), you can still run it via:

```bash
ad_postprocess --layers=reorder,word_split,pace < raw > post
```

The orchestrator resolves the binary, assigns it order 50 (middle of
the pipeline), and runs it. This lets you prototype a layer before
adding it to the manifest.

## Testing

| Test                                  | What it verifies                                              |
|---------------------------------------|---------------------------------------------------------------|
| `tests/test_layers_discovery.pl`      | Every manifest layer: parses, resolves, runs, parity.        |
| `tests/test_indent_last.pl`           | `indent_last` layer behavior + C/Perl parity + `--pp-` form.  |
| `tests/test_pipeline_options.sh`      | End-to-end pipeline with each layer flag.                     |
| `animator/tests/test_property.pl`     | Generic invariants over random diffs (50 random cases).       |

The discovery test is data-driven: it iterates `animator/layers.conf`
and emits one assertion per layer. So when you add a new layer to the
manifest, the test count automatically scales with it — adding a layer
will show up in the test results.

## Architecture diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  diffvim (bash launcher)                                          │
│    --indent-last, --overwrite, --line-delete-in-place             │
│    --pp-<name>      ← generic, zero-edit layer forwarding         │
│    --list-layers    ← delegates to orchestrator                   │
└──────────┬───────────────────────────────────────────────────────┘
           │ POSTPROCESS_ARGS = ["--indent-last", "--pp-foo", …]
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  ad_pipeline (bash)                                          │
│    Routes flags by prefix: --compute-*, --postprocess-*,          │
│    --pace-*, --animator-*. Plus --pp-<name> generic form.         │
└──────────┬───────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  bin/ad_postprocess (orchestrator, dynamic)         │
│    1. Reads animator/layers.conf                                  │
│    2. For each entry (sorted by order):                          │
│         if flag == "always" OR flag is in argv:                 │
│             resolve binary (C → Perl → any lang → abs path)      │
│             run: bin < stdin > tmp; mv tmp stdin                  │
│    3. Cat final result to stdout                                  │
└──────────┬───────────────────────────────────────────────────────┘
           │
           ▼
   (animator reads timed ops, plays animation in vim)
```

## Why this design

Earlier versions of the codebase had a hardcoded pipeline: a bash script
with explicit `[[ -n "$OVERWRITE_MODE" ]] && "$BIN/ad_layer_overwrite" …`
lines for every layer. Adding a layer meant editing:

1. The orchestrator bash script (add a `[[ ]] && "$BIN/pp_foo"` line)
2. The diffvim launcher (add a `--foo` case in the option parser)
3. The ad_pipeline script (add a routing case)
4. The Makefile's `LAYER_BINS` variable
5. The manpages
6. The completions

Every layer addition touched 4–6 files. The dynamic discovery model
collapses this to **one file** (the manifest) plus the binary itself.

The plugin contract (stdin TSV → stdout TSV) is also language-agnostic:
the orchestrator never imports or links against layer code. It just
spawns processes. This means a layer can be prototyped in 10 lines of
shell, promoted to Perl when it grows complex, and finally rewritten in
C for performance — all without changing the orchestrator.
