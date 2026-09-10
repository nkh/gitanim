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

| Key         | Action                                      |
| ----------- | ------------------------------------------- |
| F5          | Run animation in terminal split             |
| F6          | Run snapshot, update result.txt + diff      |
| `<leader>c` | Git commit                                  |
| `<leader>q` | Commit and quit                             |
| `<leader>Q` | Quit without commit                         |
| `<leader>g` | Regenerate ops from layers                  |
| `<leader>d` | Reopen diff split                           |
| `<leader>h` | Fold all hunks except current               |
| `<leader>H` | Unfold all                                  |
| `<leader>k` | Toggle keep-op folding                      |
| `<leader>a` | Toggle annotations                          |
| `<leader>b` | Re-run L1/L2 check (also auto-runs on save) |
| `<leader>f` | Fold identical lines (lines 1..L1)          |
| `<leader>t` | Trim: create reduced files from L2          |
| `<leader>?` | Show help                                   |

## L1/L2 debugging (ad_l1l2)

Tests the **op stream** (not the animator). Applies ops to old file
using the C animator (reference implementation), compares result
against new file line-by-line.

- **L1** = last line where old+ops matches new (correct up to here)
- **L2** = first line where old+ops differs (bug starts here). 0 = all match.

```bash
# Standalone
./scripts/ad_l1l2 old.py new.py ops.tsv

# In ad_session: auto-runs on start and on ops.tsv save
# <leader>b to re-run manually
# <leader>f to fold identical lines (1..L1)
# <leader>t to trim (create reduced files from L2 onward)
```

## Animation testing (ad_anim_test)

Tests the **animation** (intermediate states), not just the final output.
Takes a snapshot after EACH op and checks:

1. Content is deleted in place (not joined to another line first)
2. `join_lines` only happens on empty lines
3. No buffer corruption

```bash
# Basic test
./scripts/ad_anim_test old.py new.py ops.tsv

# With in-place deletion checks (for testing LDI layer)
./scripts/ad_anim_test old.py new.py ops.tsv --check-in-place

# Test with a layer chain
./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_line_delete_in_place < raw.tsv > post.tsv
./scripts/ad_anim_test old.py new.py post.tsv --check-in-place
```

### How it works

Injects `snapshot\t<file>` ops at interesting points in the op stream
(before/after each `join_lines`, `split_line`, and `keep_line`), then
runs the C animator once. The animator (a dumb buffer) writes the
buffer state to each snapshot file when it encounters the `snapshot`
op. This catches visual issues that L1/L2 cannot detect, without
re-running the animator per checkpoint.

### What L1/L2 vs ad_anim_test detect

| Issue                                       | L1/L2   | ad_anim_test  |
| ------------------------------------------- | ------- | ------------- |
| Final output wrong (old+ops ≠ new)          | ✓       | ✓             |
| Content jumps between lines before deletion | ✗       | ✓             |
| join_lines on non-empty line                | ✗       | ✓             |
| Indent deletes before content deletes       | ✗       | ✓             |

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
keep    1       1       104     'h'
keep    1       2       101     'e'
# old: "hello world"
# new: "hello rld"
delete  1       7       119     'w'
```

## EOF op

Add `EOF` on its own line in the op file to mark the end of the op list.
Any ops after `EOF` are ignored by all tools (animator, layers, pace).

```
keep    1       1       104     'h'
