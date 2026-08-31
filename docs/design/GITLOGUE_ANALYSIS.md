# gitlogue analysis — what we can learn

## Overview

[gitlogue](https://github.com/unhappychoice/gitlogue) is a Rust project
that animates git diffs, similar in goal to ad_vim. It uses ratatui +
crossterm for terminal rendering.

## What gitlogue does well

### 1. Smooth cursor movement (ease-in-out)

gitlogue generates intermediate cursor positions between hunks using
**ease_in_out_cubic** interpolation:

```rust
let t = i as f64 / num_steps as f64;
let eased = self.ease_in_out_cubic(t);
let line_progress = (eased * distance as f64).round() as usize;
```

This makes the cursor glide smoothly from one hunk to the next, rather
than jumping instantly. The animation has acceleration and deceleration.

**Our current**: cursor jumps instantly to the next op's position.
**Lesson**: we should add intermediate `MoveCursor` ops during the
postprocess or pace stage, with ease-in-out timing.

### 2. Distance-based speed

gitlogue adjusts cursor movement speed based on distance:

```rust
let base_speed = if distance <= 50 {
    CURSOR_MOVE_SHORT_MULTIPLIER   // 1.0 (every line visible)
} else if distance <= 200 {
    CURSOR_MOVE_MEDIUM_MULTIPLIER  // 0.3 (3x faster)
} else {
    CURSOR_MOVE_LONG_MULTIPLIER    // 0.05 (20x faster, jump)
};
```

Short distances: show every line scrolled through.
Long distances: jump quickly (don't bore the viewer).

**Our current**: no cursor movement animation at all (cursor just
appears at the next op's position).
**Lesson**: add cursor movement with distance-based speed.

### 3. Logarithmic step scaling

For long distances, gitlogue uses logarithmic step count:

```rust
let num_steps = if distance <= 50 {
    distance
} else {
    (distance as f64).ln() * LOG_SCALE_FACTOR
};
```

This caps the number of animation steps at 60, so even a 1000-line
scroll takes at most 60 frames.

**Lesson**: cap scroll animation steps to avoid long waits.

### 4. Pre-calculated syntax highlighting

gitlogue pre-calculates highlights for old and new content:

```rust
pub old_highlights: Vec<HighlightSpan>,
pub new_highlights: Vec<HighlightSpan>,
```

These are computed once (before animation) and cached. The animation
just reads from the cache.

**Our current**: colorize runs in parallel but the animator re-renders
every line on every frame.
**Lesson**: pre-cache syntax highlighting (we already do this with
colormap, which is good).

### 5. Viewport-following scroll

gitlogue centers the cursor in the viewport:

```rust
let half_viewport = self.viewport_height / 2;
let target_offset = if cursor_line < half_viewport {
    0
} else {
    cursor_line - half_viewport
};
```

**Our current (after fix)**: we now do the same in the C animator.
**Lesson**: implemented.

### 6. File-specific speed rules

gitlogue supports per-file speed rules via glob patterns:

```rust
// "*.java:50" → Java files at 50ms/char
// "src/**/*.rs:30" → Rust files at 30ms/char
```

**Lesson**: nice feature, could be useful for ad_vim.

### 7. Rich animation steps

gitlogue has multiple animation step types:

```rust
enum AnimationStep {
    InsertChar, InsertLine, DeleteLine,
    MoveCursor, Pause,
    SwitchFile, OpenFileDialogStart,
    DialogTypeChar, TerminalPrompt, TerminalOutput,
}
```

It simulates the ENTIRE git workflow: opening files, typing terminal
commands, git add/commit/push — not just the diff.

**Our current**: we only animate the diff itself.
**Lesson**: the terminal/file-tree simulation is a nice visual touch
but separate from our core diff animation.

## What we already do better

### 1. Architecture: clean pipeline separation

Our 4-stage pipeline (compute → postprocess → pace → animate) is
cleaner than gitlogue's monolithic animation engine. Each stage has a
single responsibility, can be tested independently, and can be replaced
(C vs Perl).

### 2. Per-op positioning

Every op carries its own (line, col). The animator doesn't need to
compute cursor positions — it just reads them. gitlogue computes
positions during animation generation.

### 3. Multiple implementations

We have C + Perl implementations of every stage, with byte-identical
output. gitlogue is Rust-only.

### 4. TSV op stream (debuggable)

Our op stream is human-readable TSV. gitlogue's animation steps are
in-memory Rust structs (not inspectable without a debugger).

### 5. Standalone tools

Each stage is a standalone CLI tool that can be piped. gitlogue's
stages are tightly coupled to the animation engine.

## Recommendations for improvement

1. **Add cursor movement animation** — generate intermediate MoveCursor
   ops during postprocess, with ease-in-out timing and distance-based
   speed (like gitlogue)

2. **Add pause types** — gitlogue has different pause durations for:
   - After deleting a line (10x base)
   - After inserting a line (6.7x base)
   - Between hunks (50x base)
   - We currently have: char, word, hunk, awd_slow, awd_fast, awd_skip

3. **Add file-specific speed rules** — glob-based speed configuration

4. **Add smooth scroll** — use ease-in-out for scroll offset changes
   (currently we jump to the new scroll position)

5. **Consider terminal simulation** — gitlogue's git workflow simulation
   (file tree, terminal, commit dialog) is visually impressive but is
   a separate feature from the diff animation itself
