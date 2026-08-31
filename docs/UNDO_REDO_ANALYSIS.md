# Undo/Redo Analysis

*Created:* `c1827e8` (2026-08-30 07:57:50 +0000)
*Last updated:* `17560bf` (2026-08-30 15:05:02 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


**Date:** 2026-08-30  
**Status:** Design document — not yet implemented

---

## 1. The Problem

The animator applies ops sequentially: keep, delete, insert, delay, highlight,
etc. To undo, you need to reverse each op and restore the previous buffer state.

### 1.1 Ops that are easy to undo

| Op type            | Undo action                                      | Why it's easy                      |
| ------------------ | ------------------------------------------------ | ---------------------------------- |
| `keep`             | Move cursor back 1 position                      | No buffer change, just cursor      |
| `delete`           | Insert the deleted char back at current position | Char was removed, re-insert it     |
| `insert`           | Delete the inserted char at current position     | Char was added, remove it          |
| `overwrite_insert` | Restore original char at position                | Need to know what was there before |

### 1.2 Ops that are hard or impossible to undo

| Op type     | Problem                         | Solution                                            |
| ----------- | ------------------------------- | --------------------------------------------------- |
| `delay`     | No buffer effect — just timing  | Skip on undo. Undo is instant.                      |
| `highlight` | Visual overlay — not in buffer  | Skip. Re-derive from op position.                   |
| `dim`       | Visual overlay                  | Same as highlight — skip                            |
| `fold`      | Visual overlay                  | Same — skip                                         |
| `sign`      | Visual overlay                  | Same — skip                                         |
| `glide`     | Cursor movement instruction     | Re-derive. Position cursor directly at previous op. |
| `snapshot`  | Side effect (write file)        | Skip. One-way operation.                            |
| `marker`    | Visual overlay (e.g. git blame) | Same as highlight — skip                            |

---

## 2. How Layers Affect Undo/Redo

Layers transform the op list **before** it reaches the animator. By the time
the animator sees the timed stream, layers have already run. The animator
doesn't know about layers — it sees a flat list of ops.

```
                    Layer transforms          Animator applies
                    the op list               ops sequentially
                    ──────────────            ──────────────────
Raw ops:            del_a, ins_b     →   ...   del_a, delay, ins_b, delay, highlight, ...
                                          ↑
                                    Animator sees THIS stream.
                                    It doesn't know about layers.
                                    It just reverses what it sees.
```

The `delete` op in the animator's stream might have been moved by
`ad_layer_reorder`, merged by `ad_layer_overwrite`, or repositioned by
`ad_layer_indent_last`. The animator doesn't care — it sees "delete char 'a'
at line 1, col 3" and knows the inverse is "insert char 'a' at line 1, col 3".

### 2.1 The one complication: `overwrite_insert`

The overwrite layer merges a delete+insert pair into a single
`overwrite_insert` op. To undo this, the animator needs to know what char
was **originally** at that position before the overwrite.

**Option A (recommended):** Store the original char in the op.

```
Current:   overwrite_insert\t<line>\t<col>\t<new_code>\t<char_repr>
Proposed:  overwrite_insert\t<line>\t<col>\t<new_code>\t<char_repr>\t<orig_code>
```

The overwrite layer sets `<orig_code>`. The animator reads it on undo.
If `<orig_code>` is absent (old-format ops), undo falls back to "delete the
char" (imperfect but safe).

**Option B:** Un-merge on undo — delete the inserted char, then insert the
deleted char. But the animator doesn't have the deleted char (it was consumed
by the overwrite layer). Requires the overwrite layer to embed it. Same as
Option A but messier.

---

## 3. Implementation Design

### 3.1 Op-level undo (the core mechanism)

The animator maintains an **op history stack** — a record of every op applied,
plus enough info to reverse it.

```
Forward:  op_N applied → buffer state S_N
Undo:     reverse op_N → buffer state S_{N-1}
Redo:     re-apply op_N → buffer state S_N
```

For each op type:

| Op type                          | Store for undo                      | Undo action                                                       |
| -------------------------------- | ----------------------------------- | ----------------------------------------------------------------- |
| `keep`                           | Nothing                             | `cursor_col--` (or `cursor_line--; cursor_col=end_of_line` if \n) |
| `delete`                         | Char code + position                | `insert_char(code)` at position, cursor back                      |
| `insert`                         | Char code + position                | `delete_char()` at position, cursor back                          |
| `overwrite_insert`               | New code + original code + position | Restore original code                                             |
| `delay`                          | Nothing                             | Skip                                                              |
| `highlight/dim/fold/sign/marker` | Nothing                             | Skip                                                              |
| `glide`                          | Previous cursor position            | Set cursor directly                                               |
| `snapshot`                       | Nothing                             | Skip                                                              |

### 3.2 Buffer state checkpoints (alternative approach)

Instead of computing inverses, the animator checkpoints the full buffer state
at key points (e.g. at each HUNK boundary). To undo to op N:

1. Find the nearest checkpoint before op N
2. Restore the buffer from that checkpoint
3. Replay ops from the checkpoint to op N (without delays)

**Trade-off:** Uses more memory (~1MB per checkpoint for a 1000-line file)
but is simpler and handles all op types uniformly.

**Recommended:** Use checkpoints at HUNK boundaries + op-level inverse
within a hunk. This gives O(1) undo to the previous hunk and O(hunk_size)
undo within a hunk.

### 3.3 Interaction with pacing delays

Undo is **instant** — no delay replay. The viewer presses `u` to go back
one op, `Ctrl-r` to go forward one. The buffer jumps to the new state
immediately. If the viewer wants to watch the animation again from a point,
they press `Space` to resume normal playback.

### 3.4 Interaction with the vimscript engine

The vimscript engine (inside `ad_vim`) is more complex because it uses
timers and has a state machine. To add undo/redo:

1. **Snapshot approach is better here** — the vimscript engine already has
   a `s:snapshots` array (used for `--snapshot`). Extend it to capture buffer
   state at each op, not just at the end.

2. **Memory concern:** For a 10,000-op animation, storing 10,000 buffer
   snapshots could use ~10GB. Solution: store snapshots at HUNK boundaries
   (sparse), and use op-level inverse within hunks. For a typical 100-hunk
   animation, that's 100 snapshots (~100MB for a 1000-line file) — acceptable.

3. **Keyboard:** `u` for undo (vim convention), `Ctrl-r` for redo (vim
   convention). The animation pauses when undoing.

---

## 4. What Needs to Change

| Component                       | Change                                                                                               | Effort   |
| ------------------------------- | ---------------------------------------------------------------------------------------------------- | -------- |
| `ad_layer_overwrite` (C + Perl) | Store original char code in overwrite_insert op (6th TSV field)                                      | Low      |
| `animator/c/ad.c`               | Op history stack, undo/redo functions, `u`/`Ctrl-r` shortcuts, buffer checkpoints at HUNK boundaries | Medium   |
| `animator/perl/ad.pl`           | Same (Perl twin)                                                                                     | Medium   |
| `apps/vim/ad_vim` (vimscript)   | `u`/`Ctrl-r` handling, buffer snapshots at HUNK boundaries                                           | Medium   |
| All other layers                | No change needed                                                                                     | —        |
| `pipeline/ad_postprocess`       | No change needed                                                                                     | —        |
| Config / CLI flags              | No change needed                                                                                     | —        |

---

## 5. Why Layers Don't Need to Change (Except Overwrite)

Layers run **before** the animator. By the time the animator sees the stream,
the layers are done. The animator reverses what it sees — it doesn't need to
know which layer produced which op.

The **only** layer that needs a change is `ad_layer_overwrite`, because it
**merges** two ops (delete + insert) into one (overwrite_insert), and the
merged op loses information (the original deleted char). The fix is to embed
that information in the op itself.

All other layers (reorder, indent_last, line_delete_in_place, pace,
highlight) only **reorder**, **insert delays**, or **insert visual ops**.
None of them merge or destroy ops, so the animator's undo logic works
without any layer-specific knowledge.

---


### What it does
# Appendix: `--indent-aware` and `--left-to-right` — Removed

Both `--indent-aware` and `--left-to-right` have been **removed** from
`ad_compute`.

## `--indent-aware` (removed)

`--indent-aware` normalized indentation before line-level diffing — lines
that differed only in indentation were treated as "keep". The problem: this
caused the ops to be skipped, so the new file would be wrong (the indent
change wasn't applied to the buffer).

**Replaced by:** `ad_layer_skip_indent` — a layer that detects indent-only
hunks and marks them for instant application (ops are applied but not
animated). The buffer ends up correct; only the animation is skipped.

## `--left-to-right` (removed)

`--left-to-right` reordered ops within change regions (deletes before
inserts). This was **redundant** with `ad_layer_reorder`, which does the
same thing (and more: handles \n deletes/inserts separately, recomputes
positions, tracks cross-hunk line_offset).

The reorder layer always runs as the first layer in the default chain, so
the behavior is already "left-to-right" via the layer. The compute flag
added nothing and has been removed.
