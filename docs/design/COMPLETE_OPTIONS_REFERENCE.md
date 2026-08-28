# diffvim Complete Options Reference

This document lists every option, what it does, when to use it, and
the exact command line to run it. Options are grouped by category.

---

## Table of Contents

1. [Timing Options](#1-timing-options)
2. [Pacing Options](#2-pacing-options)
3. [Delete Pacing Modes](#3-delete-pacing-modes)
4. [Insert Pacing Modes](#4-insert-pacing-modes)
5. [Cursor Movement](#5-cursor-movement)
6. [Distance-Based Speed](#6-distance-based-speed)
7. [Op Ordering](#7-op-ordering)
8. [Postprocess Transforms](#8-postprocess-transforms)
9. [Highlight Options](#9-highlight-options)
10. [Display Options](#10-display-options)
11. [Colormap / Syntax Highlighting](#11-colormap--syntax-highlighting)
12. [Scroll Modes](#12-scroll-modes)
13. [Presets](#13-presets)
14. [Controls (During Animation)](#14-controls-during-animation)
15. [Common Combinations](#15-common-combinations)

---

## 1. Timing Options

### --speed N
Speed multiplier. 0.5 = half speed, 2 = double, 5 = 5x.
```bash
diffvim --speed 2 old.py new.py
diffvim --speed 0.5 old.py new.py
```

### --tick-ms N
Animation frame interval in ms (default: 200).
```bash
diffvim --tick-ms 100 old.py new.py
```

### --type-delay-ms N
Delay between typed characters (default: 80).
```bash
diffvim --type-delay-ms 40 old.py new.py
```

### --delete-delay-ms N
Delay between deleted characters (default: 80).
```bash
diffvim --delete-delay-ms 40 old.py new.py
```

### --hunk-pause-ms N
Pause between hunks (default: 200).
```bash
diffvim --hunk-pause-ms 500 old.py new.py
```

### --word-pause-ms N
Pause after a word (default: 150).
```bash
diffvim --word-pause-ms 300 old.py new.py
```

---

## 2. Pacing Options

### --pacing MODE
Overall pacing mode: `uniform|adaptive|gaussian|review` (default: uniform).
```bash
diffvim --pacing gaussian old.py new.py
diffvim --pacing review old.py new.py
diffvim --pacing adaptive old.py new.py
```

### --gaussian-jitter-pct N
Jitter percentage for gaussian mode (default: 20).
```bash
diffvim --pacing gaussian --gaussian-jitter-pct 30 old.py new.py
```

### --pause-after-lines N
Pause after N changed lines (0 = off, default: 0).
```bash
diffvim --pause-after-lines 5 old.py new.py
```

### --pause-after-threshold N
Only pause if file has >N lines (default: 50).
```bash
diffvim --pause-after-lines 5 --pause-after-threshold 100 old.py new.py
```

### --pause-after-ms N
Pause duration (default: 500).
```bash
diffvim --pause-after-lines 5 --pause-after-ms 1000 old.py new.py
```

---

## 3. Delete Pacing Modes

### --delete-pacing MODE
Deletion strategy: `char|rapid-eol|rapid-identical|word|instant|flash` (default: word).

```bash
# char: delete one char at a time
diffvim --delete-pacing char old.py new.py

# rapid-eol: accelerate deletion of trailing chars
diffvim --delete-pacing rapid-eol old.py new.py

# rapid-identical: accelerate runs of the same char (e.g. ------)
diffvim --delete-pacing rapid-identical old.py new.py

# word: delete word-by-word (default)
diffvim --delete-pacing word old.py new.py

# instant: delete everything instantly (no animation)
diffvim --delete-pacing instant old.py new.py

# flash: highlight whole line, pause, delete in one shot
diffvim --delete-pacing flash old.py new.py
```

### --delete-speed MODE
Delete speed: `slow|normal|fast|instant` (default: normal).
```bash
diffvim --delete-speed fast old.py new.py
diffvim --delete-speed instant old.py new.py
```

### --delete-threshold N
Min chars to trigger rapid/word modes (default: 3).
```bash
diffvim --delete-pacing word --delete-threshold 5 old.py new.py
```

### --flash-pause-ms N
Flash mode: pause after highlight (default: 400).
```bash
diffvim --delete-pacing flash --flash-pause-ms 600 old.py new.py
```

### --flash-highlight-ms N
Flash mode: highlight duration (default: 300).
```bash
diffvim --delete-pacing flash --flash-highlight-ms 500 old.py new.py
```

### --accel-delete
Enable accelerated multi-line delete.
```bash
diffvim --accel-delete old.py new.py
```

### --block-delete-size N
Group deletes into blocks of N (default: 3).
```bash
diffvim --block-delete-size 5 old.py new.py
```

### --pause-before-delete-ms N
Pause before delete block (default: 200).
```bash
diffvim --pause-before-delete-ms 300 old.py new.py
```

### --pause-after-delete-ms N
Pause after delete block (default: 200).
```bash
diffvim --pause-after-delete-ms 300 old.py new.py
```

---

## 4. Insert Pacing Modes

### --insert-pacing MODE
Insert strategy: `char|word` (default: char).
```bash
# char: type one char at a time (default)
diffvim --insert-pacing char old.py new.py

# word: type words instantly, pause after whitespace
diffvim --insert-pacing word old.py new.py
```

### --insert-speed MODE
Insert speed: `slow|normal|fast` (default: normal).
```bash
diffvim --insert-speed fast old.py new.py
```

---

## 5. Cursor Movement

### --cursor-glide-ms N
Glide duration between hunks in ms (0 = off, default: 0). When >0,
the cursor animates smoothly from the end of one hunk to the start
of the next using ease-in-out interpolation.
```bash
diffvim --cursor-glide-ms 300 old.py new.py
```

### --cursor-glide-show-intermediate 0|1
Show intermediate lines during glide (1 = yes, default; 0 = just
animate cursor position without full re-render — faster for large
distances).
```bash
diffvim --cursor-glide-ms 300 --cursor-glide-show-intermediate 0 old.py new.py
```

---

## 6. Distance-Based Speed

### --distance-speed adaptive|off
Adaptive speed based on hunk distance (default: off). When enabled,
hunks far from the current cursor position animate fast (quick
glance), while nearby hunks animate slowly (show every char).
```bash
diffvim --distance-speed adaptive old.py new.py
```

### --distance-threshold N
Lines above which speed increases (default: 10).
```bash
diffvim --distance-speed adaptive --distance-threshold 5 old.py new.py
```

### --distance-fast-mult F
Speed multiplier for long distances (default: 3.0).
```bash
diffvim --distance-speed adaptive --distance-fast-mult 5.0 old.py new.py
```

### --distance-slow-mult F
Speed multiplier for short distances (default: 0.5).
```bash
diffvim --distance-speed adaptive --distance-slow-mult 0.3 old.py new.py
```

---

## 7. Op Ordering

### --op-order MODE
Op reordering: `natural|optimize|left-to-right|end-first|end-first-smart` (default: optimize).
```bash
diffvim --op-order natural old.py new.py
diffvim --op-order optimize old.py new.py
diffvim --op-order left-to-right old.py new.py
diffvim --op-order end-first old.py new.py
diffvim --op-order end-first-smart old.py new.py
```

---

## 8. Postprocess Transforms

### --semantic-cleanup
Merge adjacent delete+insert pairs that cancel out.
```bash
diffvim --semantic-cleanup old.py new.py
```

### --indent-aware
Normalize indentation before line diff.
```bash
diffvim --indent-aware old.py new.py
```

### --indent-last
Delete leading whitespace LAST when deleting a whole line (prevents
text from shifting left during animation).
```bash
diffvim --indent-last old.py new.py
```

### --overwrite
Transform delete+insert into in-place overwrite.
```bash
diffvim --overwrite old.py new.py
```

---

## 9. Highlight Options

### --highlight MODE
Highlight mode: `none|inline|word|hunk` (default: none).
```bash
diffvim --highlight none old.py new.py
diffvim --highlight inline old.py new.py
diffvim --highlight word old.py new.py
diffvim --highlight hunk old.py new.py
```

### --highlight-duration-ms N
Highlight duration (default: 200).
```bash
diffvim --highlight inline --highlight-duration-ms 500 old.py new.py
```

### --highlight-color GROUP
Highlight group (default: DiffChange).
```bash
diffvim --highlight hunk --highlight-color DiffAdd old.py new.py
```

### --dim-unchanged
Dim unchanged lines.
```bash
diffvim --dim-unchanged old.py new.py
```

### --dim-unchanged-pct N
Dim percentage (default: 60).
```bash
diffvim --dim-unchanged --dim-unchanged-pct 40 old.py new.py
```

### --fold-unchanged
Fold unchanged regions.
```bash
diffvim --fold-unchanged old.py new.py
```

### --context N
Show N lines of context around changes (default: 3).
```bash
diffvim --fold-unchanged --context 5 old.py new.py
```

### --sign-column
Show +/- signs in the sign column.
```bash
diffvim --sign-column old.py new.py
```

### --git-blame
Insert git blame markers.
```bash
diffvim --git-blame old.py new.py
```

### --max-hunk-chars N
Skip animation for hunks >N chars (0 = off, default: 0).
```bash
diffvim --max-hunk-chars 1000 old.py new.py
```

---

## 10. Display Options

### --diff-stat
Show diff statistics overlay (changed/total line counts).
```bash
diffvim --diff-stat old.py new.py
```

### --diff-highlight
Highlight modified lines with a subtle background color.
```bash
diffvim --diff-highlight old.py new.py
```

### --bell
Ring the terminal bell on errors.
```bash
diffvim --bell old.py new.py
```

### --line-numbers
Show line numbers in the margin (C animator only).
```bash
ad --line-numbers old.py < timed_ops.txt
```

### --progress
Show progress bar at bottom (C animator only).
```bash
ad --progress old.py < timed_ops.txt
```

---

## 11. Colormap / Syntax Highlighting

### --colormap-old FILE
Load ANSI-colored lines for the old file (from `colorize.pl` or
external highlighter like `bat`). Unmodified lines are rendered
using these colors.
```bash
# Generate colormap files
perl animator/perl/colorize.pl old.py > old.colormap
perl animator/perl/colorize.pl new.py > new.colormap

# Run with colormaps
ad --colormap-old old.colormap --colormap-new new.colormap old.py < timed_ops.txt
```

### --colormap-new FILE
Load ANSI-colored lines for the new file. Modified lines (lines
that have been touched by a delete or insert) are rendered using
these colors. Unmodified lines use `--colormap-old` colors.
```bash
ad --colormap-old old.colormap --colormap-new new.colormap old.py < timed_ops.txt
```

### How to generate colormap files

1. **Using `colorize.pl` (built-in):**
```bash
perl animator/perl/colorize.pl --backend vim old.py > old.colormap
perl animator/perl/colorize.pl --backend vim new.py > new.colormap
```

2. **Using `pygmentize` (external):**
```bash
pygmentize -f terminal256 -l python old.py > old.colormap
pygmentize -f terminal256 -l python new.py > new.colormap
```

3. **Using `bat` (external):**
```bash
bat --color=always --plain --paging=never old.py > old.colormap
bat --color=always --plain --paging=never new.py > new.colormap
```

4. **Using `ad_pipeline` (auto-generates):**
```bash
ad_pipeline --animator-colormap-old old.colormap \
                 --animator-colormap-new new.colormap \
                 old.py new.py
```

### How colormap rendering works

- **Unmodified lines**: rendered with `colormap-old` colors
  (original syntax highlighting)
- **Modified lines**: rendered with `colormap-new` colors
  (new syntax highlighting)
- **As the animation progresses**: lines transition from old colors
  to new colors, providing visual feedback of what changed

---

## 12. Scroll Modes

### --scroll MODE
Scroll behavior: `zz|zt|zb|none` (default: zz).
```bash
# Center cursor in viewport (default)
diffvim --scroll zz old.py new.py

# Cursor at top of viewport
diffvim --scroll zt old.py new.py

# Cursor at bottom of viewport
diffvim --scroll zb old.py new.py

# No scroll (start at line 1, never move)
diffvim --scroll none old.py new.py
```

---

## 13. Presets

### --preset NAME
Apply a preset configuration.
```bash
diffvim --preset default old.py new.py
diffvim --preset review old.py new.py
diffvim --preset demo old.py new.py
diffvim --preset fast old.py new.py
```

**Preset details:**
- `default`: balanced timing, word delete pacing, optimize op-order
- `review`: slow timing, hunk highlight, dim unchanged, left-to-right
- `demo`: gaussian jitter, inline highlight, 0.7x speed
- `fast`: fast timing, 2x speed, adaptive pacing

Or use directly:
```bash
diffvim --pacing review --highlight hunk --dim-unchanged --op-order left-to-right old.py new.py
diffvim --pacing gaussian --speed 0.7 --highlight inline old.py new.py
diffvim --delete-pacing word --delete-speed fast --op-order optimize old.py new.py
```

---

## 14. Controls (During Animation)

During animation in vim normal mode:

| Key | Action |
|-----|--------|
| `Space` | Pause / resume |
| `n` | Skip to next hunk (apply instantly) |
| `q` | Stop animation — `:q` quits cleanly |
| `+` | Speed up (1.5x) |
| `-` | Slow down (1/1.5x) |
| `=` | Reset speed to 1.0x |
| `?` | Show help |

---

## 15. Common Combinations

### Code review (slow, careful)
```bash
diffvim --preset review old.py new.py
# or
diffvim --pacing review --highlight hunk --dim-unchanged --op-order left-to-right --speed 0.7 old.py new.py
```

### Demo (smooth, visually appealing)
```bash
diffvim --preset demo old.py new.py
# or
diffvim --pacing gaussian --speed 0.7 --highlight inline --cursor-glide-ms 300 old.py new.py
```

### Fast overview (quick glance)
```bash
diffvim --preset fast old.py new.py
# or
diffvim --speed 3 --delete-pacing instant --distance-speed adaptive old.py new.py
```

### Debugging (full control)
```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --diff-stat --diff-highlight --bell old.py new.py
```

### Flash delete (highlight before delete)
```bash
diffvim --delete-pacing flash --flash-pause-ms 500 --flash-highlight-ms 400 old.py new.py
```

### With colormaps (syntax highlighting)
```bash
perl animator/perl/colorize.pl --backend vim old.py > old.colormap
perl animator/perl/colorize.pl --backend vim new.py > new.colormap
ad_pipeline --animator-colormap-old old.colormap \
                 --animator-colormap-new new.colormap \
                 --highlight inline old.py new.py
```

### Smooth with distance-based speed
```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3 --distance-slow-mult 0.5 old.py new.py
```

### Indent-aware + indent-last (Python)
```bash
diffvim --indent-aware --indent-last old.py new.py
```

### Everything at once
```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --highlight hunk --dim-unchanged --indent-last --diff-stat --diff-highlight old.py new.py
```
