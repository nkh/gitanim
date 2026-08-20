# Pipeline-based feature architecture — analysis

## The decision

Move as much vimscript logic as possible into the pipeline. Add a new
pipeline stage (or stages) that emit generic ops both vim and the C
animator can handle. This:

1. Keeps the vimscript minimal (just apply ops)
2. Makes the C animator a first-class citizen (same ops, same behavior)
3. Enables reuse — one implementation, two consumers

## Current pipeline

```
compute → postprocess → pace → [animator | vimscript]
```

The animator and vimscript each independently interpret the timed op
stream. Currently they only understand:
- `keep\t<line>\t<col>\t<code>`
- `delete\t<line>\t<col>\t<code>`
- `insert\t<line>\t<col>\t<code>`
- `delay\t<ms>\t<type>`
- `HUNK` / `HUNK_END`
- `snapshot\t<file>`

## Proposed new stage: `decorate`

```
compute → postprocess → pace → DECORATE → [animator | vimscript]
```

The `decorate` stage reads the timed op stream and inserts **decoration
ops** that tell the renderer what visual effects to apply. Both vim
and the C animator interpret these ops the same way.

## New op types

### `highlight` — mark a char/word/hunk region

```
highlight\t<start_line>\t<start_col>\t<end_line>\t<end_col>\t<type>\t<duration_ms>
```

Where `<type>` is:
- `insert` — green highlight (newly typed char)
- `delete` — red highlight + strikethrough (deleted char)
- `hunk` — blue highlight (entire hunk background)
- `word` — highlight the word containing the changed char

The renderer applies the highlight, waits `<duration_ms>`, then removes it.

**Vim implementation**: `matchadd()` with a timer to clear.
**C animator implementation**: ANSI color codes with a timer.

### `dim` — dim a line range

```
dim\t<start_line>\t<end_line>\t<pct>
```

Dims the specified line range to `<pct>`% opacity.

**Vim**: `matchadd()` with a dim foreground color.
**C animator**: ANSI dim attribute.

### `fold` — fold a line range

```
fold\t<start_line>\t<end_line>
```

Folds the specified line range.

**Vim**: `:set fold` / `:fold` commands.
**C animator**: Skip rendering those lines, show `[...]` placeholder.

### `sign` — place a sign

```
sign\t<line>\t<type>
```

Where `<type>` is `add`, `del`, or `keep`.

**Vim**: `sign place` command.
**C animator**: Show `+`/`-`/` ` in a margin column.

### `marker` — set a visual marker

```
marker\t<line>\t<col>\t<text>
```

Shows `<text>` at the given position (e.g., git blame info).

**Vim**: `echo` at cursor or `sign define`.
**C animator**: Render text in a status line.

## What this enables

### Feature → op mapping

| Feature | Op type | Emitted by |
|---------|---------|------------|
| `--highlight inline` | `highlight` (per-char) | decorate |
| `--highlight word` | `highlight` (per-word) | decorate |
| `--highlight hunk` | `highlight` (per-hunk) | decorate |
| `--dim-unchanged` | `dim` | decorate |
| `--fold-unchanged` / `--context` | `fold` | decorate |
| `--sign-column` | `sign` | decorate |
| `--git-blame` | `marker` | decorate |

### Vimscript simplification

Current vimscript (73 functions, 3064 lines) → reduced to:

1. `ApplyOp(op)` — switch on op type:
   - keep/delete/insert → modify buffer
   - highlight → matchadd
   - dim → matchadd
   - fold → fold command
   - sign → sign place
   - marker → echo
   - delay → sleep
   - snapshot → write file
2. `Render()` — minimal, just redraw buffer
3. `KeyboardHandler()` — q/Space/n/+/-/=?

**Estimated vim code**: ~200 lines (down from 3064).

### C animator parity

The C animator gains the same op types:
- `highlight` → ANSI color
- `dim` → ANSI dim
- `fold` → skip rendering
- `sign` → margin column
- `marker` → status line

Both renderers share the same op stream, same semantics.

## Implementation plan

### New tool: `diffvim-decorate`

```
diffvim-decorate [--highlight MODE] [--dim-unchanged] [--context N]
                 [--sign-column] [--git-blame] [--theme NAME]
                 < timed_ops > decorated_ops
```

Reads the timed op stream, inserts decoration ops, writes the decorated
stream. Both vim and C animator consume the decorated stream.

### Pipeline update

```
compute → postprocess → pace → decorate → [animator | vimscript]
```

The bash launcher runs decorate between pace and the renderer.

### Stage responsibilities

| Stage | What it does |
|-------|-------------|
| compute | Diff → raw ops (keep/delete/insert) |
| postprocess | Reorder, transform, compute positions |
| pace | Insert delays |
| **decorate** | **Insert highlight/dim/fold/sign/marker ops** |
| animator/vimscript | Apply ops to buffer, render |

## Advantages

1. **Minimal vim code** — just an op dispatcher
2. **Reuse** — one decorate implementation, two renderers
3. **Testable** — decorate is a standalone tool with its own tests
4. **Separation of concerns** — rendering doesn't decide WHAT to highlight
5. **Future-proof** — new visual features go in decorate, not in each renderer

## Disadvantages

1. **More complexity** — one more pipeline stage
2. **Performance** — extra pass over ops (but O(n), negligible)
3. **Op stream grows** — decoration ops add to the stream size

## Migration path

1. Implement `diffvim-decorate` with `--highlight` first
2. Add `highlight` op handling to vim and C animator
3. Move `--dim-unchanged`, `--fold-unchanged`, `--sign-column`, `--git-blame`
   one by one
4. Each step: implement in decorate → update renderers → test → commit

## What stays in vimscript

Only what CANNOT be expressed as ops:
- Cursor rendering (vim-specific)
- Window management (vim-specific)
- Keyboard input (vim-specific)
- Timer management (vim-specific)

Everything else moves to decorate.
