# Debugging Tools

The ad project includes interactive debugging tools for working with op lists.

## ad_session (recommended)

Vim-only interactive debugger. Creates a session directory, copies files,
generates ops, initializes git, and launches vim with a split layout.

```bash
# New session
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder

# With annotations
./scripts/ad_session old.py new.py --ad-layer=ad_layer_reorder --annotate

# Resume latest session
./scripts/ad_session --resume-latest

# List sessions
./scripts/ad_session --list-sessions
```

### Vim layout

```
┌─────────────────┬──────────────────────┐
│ diff (new vs    │ ops.tsv              │
│ result)         │ (editing, F5/F6)     │
│                 ├──────────────────────┤
│                 │ result.txt           │
└─────────────────┴──────────────────────┘
```

### Shortcuts

| Key         | Action                                 |
| ----------- | -------------------------------------- |
| F5          | Run animation in terminal split        |
| F6          | Run snapshot, update result.txt + diff |
| `<leader>c` | Git commit                             |
| `<leader>q` | Commit and quit                        |
| `<leader>Q` | Quit without commit                    |
| `<leader>g` | Regenerate ops from layers             |
| `<leader>d` | Reopen diff split                      |
| `<leader>h` | Fold all hunks except current          |
| `<leader>H` | Unfold all                             |
| `<leader>k` | Toggle keep-op folding                 |
| `<leader>a` | Toggle annotations                     |
| `<leader>?` | Show help                              |

## ad_tmux_watch (tmux alternative)

Same session system but uses tmux panes instead of vim splits.

```bash
./scripts/ad_tmux_watch old.py new.py --ad-layer=ad_layer_reorder
```

## ad_gen_ops (standalone)

Generates ops from old/new files with optional layer chain and annotations.

```bash
./scripts/ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder > ops.tsv
./scripts/ad_gen_ops old.py new.py --ad-layer=ad_layer_reorder --annotate > ops.tsv
```

## ad_watch (standalone display)

Shows old, new, and diff — auto-refreshes on file change.

```bash
./scripts/ad_watch old.py new.py ops.tsv
```

## .ad_layers file

Optional layer group configuration in the project root:

```
# First non-comment line = active group name
default

default
ad_layer_reorder

debug_ldi
ad_layer_reorder
ad_layer_line_delete_in_place

debug_full
ad_layer_reorder
ad_layer_line_delete_in_place
ad_layer_indent_last
```

Edit the first line to switch groups. Saving the file regenerates ops
automatically (in ad_session).

## Annotations

The `--annotate` flag adds `# old:` / `# new:` comments showing the text
content before and after each bundle of ops:

```
# keep: "hello " (line 1, cols 1-6)
keep	1	1	104	'h'
keep	1	2	101	'e'
# old: "hello world"
# new: "hello rld"
delete	1	7	119	'w'
```

## EOF op

Add `EOF` on its own line in the op file to mark the end of the op list.
Any ops after `EOF` are ignored by all tools (animator, layers, pace).

```
keep	1	1	104	'h'
