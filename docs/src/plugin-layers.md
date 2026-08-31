# Plugin Layers

*Created:* `fb14b64` (2026-08-28 15:20:07 +0000)
*Last updated:* `db72a00` (2026-08-30 08:35:56 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


The `ad` postprocess pipeline is **plugin-based**. Layers are standalone executables chained by the orchestrator (`pipeline/ad_postprocess`). The chain is supplied entirely on the command line — there is no manifest, no config file for the chain.

## At a glance

```
compute → ad_postprocess → animator
              │
              │ chains --ad-layer=<name> plugins in argv order
              │
              ├─ ad_layer_reorder      (always first)
              ├─ ad_layer_overwrite    (--overwrite)
              ├─ ad_layer_indent_last  (--indent-last)
              ├─ ad_layer_pace         (always)
              └─ ad_layer_highlight    (always)
```

Each box is a standalone executable. The orchestrator pipes stdout of one layer into stdin of the next, in the order the `--ad-layer` flags appear on the command line.

## The plugin contract

A layer is any executable that obeys these rules:

1. **Reads V2 TSV from stdin.** Lines like `HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>`, followed by op lines (`type\tline\tcol\tcode\tchar_repr`), followed by `HUNK_END`. Headers (`# ...`) and blank lines may appear before the first HUNK.

2. **Writes V2 TSV to stdout** in the same format. The layer may transform ops, reorder them, insert new ops, delete ops, or pass them through unchanged.

3. **Exits 0 on success.** Non-zero exits abort the pipeline.

4. **(Optional) Accepts `--help`.** Layers that take their own options should print usage on `--help`.

The orchestrator doesn't care what language the layer is written in. If it can be invoked from a shell and reads/writes TSV, it's a layer.

## Discovery paths

For a layer named `<name>`, the orchestrator looks for an executable in this order:

| #   | Path                                     | Language          |
| --- | ---------------------------------------- | ----------------- |
| 1   | `bin/<name>`                             | C (preferred)     |
| 2   | `layers/perl/<name>.pl`                  | Perl              |
| 3   | `<--ad-layer-path>/<name>`               | Any (search path) |
| 4   | `<absolute path>` (if name contains `/`) | Any               |

Extensions recognized:

| Extension   | Interpreter                            |
| ----------- | -------------------------------------- |
| `.pl`       | `perl`                                 |
| `.py`       | `python3`                              |
| `.rb`       | `ruby`                                 |
| `.sh`       | `bash`                                 |
| `.js`       | `node`                                 |
| (none)      | executed directly (must be executable) |

## Orchestrator CLI

The orchestrator is `pipeline/ad_postprocess`. It accepts:

| Flag                         | Behavior                                                                                |
| ---------------------------- | --------------------------------------------------------------------------------------- |
| `--ad-layer=<name>`          | Add a layer to the chain. Layers run in argv order. The same layer can be passed twice. |
| `--ad-layer-path=<dir>`      | Add a directory to the search path. Repeatable. Default: `bin/` and `layers/perl/`.     |
| `--ad-layer-arg=<L>:<arg>`   | Pass `<arg>` to layer `<L>` only (not all layers). Repeatable.                          |
| `--ad-layer-passthrough=<a>` | Pass `<a>` to ALL layers.                                                               |
| `--ad-layer-profile`         | Print per-layer timing to stderr.                                                       |
| `--ad-layer-dry-run`         | Print the chain and exit (no execution).                                                |
| `--ad-layer-keep-temps`      | Keep intermediate files in a temp dir for debugging.                                    |
| `--list-layers`              | Print discovered layers and exit.                                                       |
| `--help` / `-h`              | Print usage and exit.                                                                   |
| `--`                         | Everything after this goes to every layer as passthrough args.                          |

### I/O modes

**Pipe mode (default):** layers are chained via pipes for speed:
```
layer1 < input | layer2 | layer3 > output
```

**Temp mode (`--ad-layer-keep-temps`):** each layer reads/writes a file:
```
layer1 < 00_input.tsv > 01_output.tsv
layer2 < 01_output.tsv > 02_output.tsv
...
```
Files are kept in `/tmp/ad_postprocess_$$` (or `$AD_TEMP_DIR`) for inspection.

### Examples

```bash
# Default chain (from ad_vim): reorder → pace → highlight
ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_pace --ad-layer=ad_layer_highlight < raw_ops

# Enable indent_last between reorder and pace
ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_indent_last --ad-layer=ad_layer_pace < raw_ops

# Run a custom layer from an absolute path
ad_postprocess --ad-layer=/path/to/my_layer.sh < raw_ops

# Add a custom search path
ad_postprocess --ad-layer-path=/my/layers --ad-layer=my_layer < raw_ops

# Pass args to a specific layer only
ad_postprocess --ad-layer=ad_layer_pace --ad-layer-arg=ad_layer_pace:--delete-pacing --ad-layer-arg=ad_layer_pace:word < raw_ops

# Dry-run: see what would execute
ad_postprocess --ad-layer-dry-run --ad-layer=ad_layer_reorder --ad-layer=ad_layer_pace

# Profile: see per-layer timing
ad_postprocess --ad-layer-keep-temps --ad-layer-profile --ad-layer=ad_layer_reorder --ad-layer=ad_layer_pace < raw_ops

# Keep temp files for debugging
AD_TEMP_DIR=/tmp/my_debug ad_postprocess --ad-layer-keep-temps --ad-layer=ad_layer_reorder < raw_ops
# Then inspect: ls /tmp/my_debug/

# List available layers
ad_postprocess --list-layers
```

## Invoking from ad_vim

The `ad_vim` launcher builds the default chain and adds user-requested layers:

```bash
# Default animation
ad_vim old.py new.py

# Enable indent_last
ad_vim --indent-last old.py new.py

# Add a custom layer
ad_vim --ad-layer=my_custom_layer old.py new.py

# List available layers
ad_vim --list-layers
```

Convenience flags that map to layers:
- `--indent-last` → `--ad-layer=ad_layer_indent_last`
- `--overwrite` → `--ad-layer=ad_layer_overwrite`
- `--line-delete-in-place` → `--ad-layer=ad_layer_line_delete_in_place` (runs INSTEAD of reorder — needs original line numbers)

## Built-in layers

| Layer                           | C source                                   | Perl twin                                      | What it does                              |
| ------------------------------- | ------------------------------------------ | ---------------------------------------------- | ----------------------------------------- |
| `ad_layer_reorder`              | `layers/c/ad_layer_reorder.c`              | `layers/perl/ad_layer_reorder.pl`              | 4-sweep reorder + position adjust         |
| `ad_layer_overwrite`            | `layers/c/ad_layer_overwrite.c`            | `layers/perl/ad_layer_overwrite.pl`            | Merge delete+insert into overwrite_insert |
| `ad_layer_indent_last`          | `layers/c/ad_layer_indent_last.c`          | `layers/perl/ad_layer_indent_last.pl`          | Move whitespace deletes to end of line    |
| `ad_layer_line_delete_in_place` | `layers/c/ad_layer_line_delete_in_place.c` | `layers/perl/ad_layer_line_delete_in_place.pl` | Delete lines on their own line            |
| `ad_layer_skip_indent`          | `layers/c/ad_layer_skip_indent.c`          | `layers/perl/ad_layer_skip_indent.pl`          | Skip animation for indent-only hunks      |
| `ad_layer_pace`                 | `layers/c/ad_layer_pace.c`                 | `layers/perl/ad_layer_pace.pl`                 | Insert delay ops between ops              |
| `ad_layer_highlight`            | `layers/c/ad_layer_highlight.c`            | `layers/perl/ad_layer_highlight.pl`            | Insert highlight/dim/fold ops             |

Every layer has both a C implementation (preferred) and a Perl twin that produces byte-identical output. The orchestrator prefers C if both exist; if the C binary is missing, it falls back to Perl. Parity is verified by the per-layer tests.

## Adding a new layer

1. **Write the layer.** Any language. Save as:
   - `layers/c/ad_layer_<name>.c` (C, compiled to `bin/ad_layer_<name>`)
   - `layers/perl/ad_layer_<name>.pl` (Perl)
   - Or anywhere, invoked via `--ad-layer=<path>`

2. **Write a test.** Create `layers/tests/test_<name>.pl`. See `layers/tests/test_reorder.pl` for a template.

3. **Add Makefile target** (for C layers):
   ```makefile
   bin/ad_layer_<name>: layers/c/ad_layer_<name>.c layers/c/ad_layer_common.h
       $(CC) $(CFLAGS) -I layers/c -o $@ $<
   ```

4. **Run the test:**
   ```bash
   make test-layer-<name>
   ```

You do NOT need to edit:
- `pipeline/ad_postprocess` (orchestrator)
- `apps/vim/ad_vim` (launcher)
- `pipeline/ad_pipeline` (pipeline driver)
- Any manifest or config file

The `--ad-layer=<name>` mechanism discovers the layer automatically.

## Testing

| Test                             | What it verifies                                       |
| -------------------------------- | ------------------------------------------------------ |
| `layers/tests/test_<name>.pl`    | Per-layer: invocable, structure, C/Perl parity         |
| `tests/test_layers_discovery.pl` | Plugin contract: argv order, extensions, paths, parity |
| `tests/run_all_examples.sh`      | 36 examples through the full pipeline                  |

## Architecture diagram

```
┌──────────────────────────────────────────────────────────────────┐
│  ad_vim (bash launcher)                                          │
│    --indent-last, --overwrite                                    │
│    --line-delete-in-place  (⚠️ DISABLED — see warning above)     │
│    --ad-layer=<name>      ← generic layer addition               │
│    --list-layers          ← delegates to orchestrator            │
└──────────┬───────────────────────────────────────────────────────┘
           │ POSTPROCESS_ARGS = ["--ad-layer=ad_layer_reorder", ...]
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  ad_pipeline (bash)                                              │
│    Routes flags by prefix: --compute-*, --postprocess-*,          │
│    --pace-*, --animator-*. Plus --ad-layer=<name>.                │
└──────────┬───────────────────────────────────────────────────────┘
           │
           ▼
┌──────────────────────────────────────────────────────────────────┐
│  pipeline/ad_postprocess (orchestrator, dynamic)                  │
│    1. Parses --ad-layer=<name> flags (argv order)                │
│    2. Resolves each layer (C → Perl → search path → abs path)     │
│    3. Chains via pipes (fast) or temp files (--keep-temps)        │
│    4. On failure: captures stderr, displays last 20 lines         │
│    5. Optional: --profile (timing), --dry-run (preview)           │
└──────────┬───────────────────────────────────────────────────────┘
           │
           ▼
   (animator reads timed ops, plays animation in vim)
```

## Why this design

Earlier versions had a hardcoded pipeline: a bash script with explicit lines for every layer. Adding a layer meant editing 4–6 files (orchestrator, launcher, pipeline, Makefile, manpages, completions).

The dynamic `--ad-layer=<name>` model collapses this to **zero edits** — drop a binary in `bin/` or `layers/perl/` and it's immediately usable via `--ad-layer=<name>`.

The plugin contract (stdin TSV → stdout TSV) is language-agnostic: the orchestrator never imports or links against layer code. It just spawns processes. A layer can be prototyped in 10 lines of shell, promoted to Perl, and finally rewritten in C — all without changing the orchestrator.
