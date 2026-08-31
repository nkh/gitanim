# ad_vim Options: Bird's Eye View

This document shows how all the options influence the animation at a
high level. It is NOT a reference — it is a visual guide to understand
what can be done and how options interact.

---

## The Animation Pipeline

```
  ┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
  │  Old File   │     │  Diff Engine  │     │  Animation      │
  │  New File   │ ──► │  (Patience/Patience/  │ ──► │  Engine (vim)   │
  │             │     │   Patience)   │     │                 │
  └─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                    ┌──────────────────────────────┘
                    │
                    ▼
          ┌──────────────────┐
          │  Post-Processing │  optimize-sequence, left-to-right,
          │  (char ops)      │  semantic-cleanup, overwrite, delete-end-first
          └────────┬─────────┘
                   │
                   ▼
          ┌──────────────────┐
          │  Animation       │  accel-delete, word-accel, rapid-eol,
          │  Timing & Visual │  highlight-hunk, dim-unchanged, etc.
          └──────────────────┘
```

---

## Option Categories

### 1. DIFF ALGORITHM (how the diff is computed)

```
  --algorithm patience       ──►  Classic Patience, O(N×M), good for small files
  --algorithm patience  ──►  Anchors on unique lines, more human-readable hunks
```

(Myers was removed: it OOMs on 15K-line files and produces the same
op count as Patience.)

**Example:**
```
  # Patience: fewer, more coherent hunks
  ad_vim --algorithm patience old.py new.py
```

### 2. DIFF GRANULARITY (char vs word level)

```
  (default)              ──►  Char-level diff (every char is a separate op)
  --word-diff            ──►  Word-level diff (groups chars into word tokens)
                               + batches word runs as instant ops
  [REMOVED: --indent-aware]         ──►  Normalize indent before line diff
                               (indent-only changes = "keep", not animated)
```

**Example:**
```
  Char-level:    del 'h', del 'e', del 'l', del 'l', del 'o', ins 'w', ins 'o', ins 'r', ins 'l', ins 'd'
  Word-level:    del "hello" (instant), ins "world" (instant), pause
```

### 3. POST-PROCESSING (how char ops are reordered/cleaned)

```
  ┌─────────────────────────────────────────────────────────────┐
  │                    POST-PROCESSING PIPELINE                  │
  │                                                             │
  │  Raw char_ops                                               │
  │    │                                                        │
  │    ├──► [REMOVED: --semantic-cleanup]   (merge canceling del+ins pairs)│
  │    │                                                         │
  │    ├──► --optimize-sequence  (consolidate interleaved ops)  │
  │    │     del a, ins x, del b  ──►  del a, del b, ins x     │
  │    │                                                         │
  │    ├──► --left-to-right      (sort ops within each line)    │
  │    │     non-whitespace deletes first, whitespace last      │
  │    │                                                         │
  │    ├──► --overwrite          (replace words in place)       │
  │    │     shorter: overwrite + delete extra                   │
  │    │     same:    overwrite only                             │
  │    │     longer:  overwrite + insert remainder               │
  │    │                                                         │
  │    └──► --delete-end-first   (delete EOL before inserting)  │
  │                                                             │
  │  Cleaned char_ops ──► Animation Engine                      │
  └─────────────────────────────────────────────────────────────┘
```

### 4. DELETION SPEED (how fast things disappear)

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    DELETION SPEED OPTIONS                     │
  │                                                              │
  │  Single char:  --delete-delay-ms 40 (default)               │
  │       x = old_value  ──►  x = (delay 40ms per char)         │
  │                                                              │
  │  End-of-line:  --rapid-eol-delete (default: on)             │
  │       print("hello world")  ──►  print(" (rapid 80ms shot)  │
  │                                                              │
  │  Multi-line blocks:  --accel-delete                         │
  │       ┌─────────────┐                                       │
  │       │ line 1      │  ▓▓▓░░  (block 1: slow, 200ms)       │
  │       │ line 2      │  ▓▓░░░  (block 2: faster, 170ms)     │
  │       │ line 3      │  ▓░░░░  (block 3: fast, 144ms)       │
  │       │ ...         │  ░░░░░  (accelerating...)             │
  │       │ line N-2    │  ▓░░░░  (decelerating...)             │
  │       │ line N-1    │  ▓▓░░░  (slower, 170ms)              │
  │       │ line N      │  ▓▓▓░░  (slow, 200ms)                │
  │       └─────────────┘                                       │
  │       pause_after = 200ms                                    │
  │                                                              │
  │  Word-by-word:  --adaptive-word-delete                      │
  │       def foo():          ← delete first 3 chars slowly     │
  │       ef foo():           ← then word by word:              │
  │          foo():           ← "def" gone (80ms)               │
  │             ():           ← "foo" gone (68ms, accelerating) │
  │                    :      ← "()" gone (58ms)                │
  │                           ← ":" gone (49ms)                 │
  │       (rest deleted rapidly)                                 │
  │                                                              │
  │  Identical chars:  --rapid-identical-chars                  │
  │       ---------------------------                           │
  │       ───────────────── (40ms)                              │
  │       ──────────────── (20ms)                               │
  │       ─────────────── (10ms)                                │
  │       ────────────── (5ms)    ← exponential acceleration    │
  │       ───────────── (2ms)                                  │
  │       ──────────── (1ms)                                   │
  └──────────────────────────────────────────────────────────────┘
```

### 5. INSERTION SPEED (how fast things appear)

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    INSERTION SPEED OPTIONS                    │
  │                                                              │
  │  Single char:  --type-delay-ms 50 (default)                 │
  │       x = _    x = v_   x = va_   x = val_  (50ms each)    │
  │                                                              │
  │  Word acceleration:  --word-accel                            │
  │       x = v     ← 1.5x base (75ms) — slow start            │
  │       x = va    ← 1.5x base (75ms)                         │
  │       x = val   ← 1.5x base (75ms)                         │
  │       x = valu  ← 0.3x base (15ms) — rapid!                │
  │       x = value ← 0.09x base (4ms) — very rapid!           │
  │       (pause 150ms — read the complete word)                │
  │                                                              │
  │  Gaussian jitter:  --gaussian-jitter                        │
  │       x = v   (52ms)                                        │
  │       x = va  (47ms)  ← varies ±20% for human-like typing   │
  │       x = val (55ms)                                        │
  └──────────────────────────────────────────────────────────────┘
```

### 6. VISUAL HIGHLIGHTS (what the user sees)

```
  ┌──────────────────────────────────────────────────────────────┐
  │                    VISUAL HIGHLIGHT OPTIONS                   │
  │                                                              │
  │  --highlight-hunk    ┌─────────────────────────────────┐     │
  │     (before hunk)    │  ████ highlighted lines ████    │     │
  │                      │  ████ (all changed lines) ████  │     │
  │                      └─────────────────────────────────┘     │
  │                                                              │
  │  --highlight-word    def greet(name):                        │
  │     (before op)          ████ ← word highlighted             │
  │                      def greet(name):                        │
  │                                                              │
  │  --highlight-inline  def greet(name):                        │
  │     (after each op)      ▲ ← green for 200ms (insert)        │
  │                          ▲ ← red for 200ms (delete)          │
  │                      (multiple highlights persist + fade)    │
  │                                                              │
  │  --dim-unchanged     ░░░░ unchanged lines (dimmed) ░░░░     │
  │     (always on)      ████ changed lines (normal) ████       │
  │                                                              │
  │  --sign-column       +│    inserted line                     │
  │     (during op)      -│    deleted line                      │
  │                      *│    modified line                      │
  └──────────────────────────────────────────────────────────────┘
```

### 7. PAUSES (when the animation stops)

```
  ┌──────────────────────────────────────────────────────────────┐
  │                       PAUSE OPTIONS                          │
  │                                                              │
  │  Between hunks:     --hunk-pause-ms 250                      │
  │       [hunk 1 done] ──250ms── [hunk 2 starts]              │
  │                                                              │
  │  After N lines:     --pause-after-lines 5                    │
  │                    --pause-after-threshold 50                │
  │       (only for hunks > 50 lines, pause every 5 lines)      │
  │                                                              │
  │  After word:        --word-end-pause-ms 150                  │
  │       typing "value" ──150ms── next op                      │
  │                                                              │
  │  At line boundary:  --line-change-pause-ms 200               │
  │       line 1 done ──200ms── line 2 starts                   │
  │                                                              │
  │  Before/after delete: --pause-before-delete-ms 200          │
  │                       --pause-after-delete-ms 200            │
  │       [200ms] ── del block ── [200ms]                       │
  │                                                              │
  │  Adaptive mode:     --adaptive                               │
  │       slow start ──► accelerate ──► pause at hunk end        │
  │       (user presses Space to continue)                      │
  └──────────────────────────────────────────────────────────────┘
```

### 8. PRESETS (one flag sets many options)

```
  --preset fast-delete   ──►  accel-delete + adaptive-word-delete
                               + rapid-identical + rapid-eol
                               + optimize-sequence + left-to-right
                               + semantic-cleanup

  --preset review        ──►  highlight-hunk + highlight-word
                               + highlight-inline + dim-unchanged
                               + pause-after-lines 5
                               + optimize-sequence + left-to-right

  --preset present       ──►  speed 0.5 + highlight-hunk
                               + sign-column + word-diff

  --preset ai-code       ──►  optimize-sequence + left-to-right
                               + semantic-cleanup + accel-delete
                               + adaptive-word-delete + rapid-identical
                               + highlight-inline + dim-unchanged
                               + pause-after-lines 7

  --preset custom        ──►  reads AD_PRESET_CUSTOM env var
                               (your personal preferred options)
```

### 9. EXTERNAL COMPUTE (faster diff for large files)

```
  ┌───────────────────────────────────────────────────┐
  │  --auto-precompute                                │
  │                                                   │
  │  old.py ─┐                                        │
  │          ├──► [C++ compute tool] ──► diff.txt ──┐   │
  │  new.py ─┘                                    │   │
  │                                               ▼   │
  │  ad_vim ──► [vim + --precomputed diff.txt] ──► animation
  │                                                   │
  │  Speed: ~1ms (C++) vs 500ms (vimscript)         │
  │  The C++ binary is searched for automatically      │
  └───────────────────────────────────────────────────┘
```

### 10. SCROLLING (how the viewport moves)

```
  --scroll zz (default)    ──►  cursor centered on screen
  --scroll zt              ──►  cursor at top of screen
  --scroll zb              ──►  cursor at bottom of screen
  --scroll none            ──►  no forced scroll

  Between hunks:     smooth glide with ease-in-out acceleration
                     line 32 ──► 33 ──► 35 ──► 40 ──► 60 ──► 114
                     (slow start, fast middle, slow end)

  During typing:     if cursor jumps > 3 lines (due to line count
                     changes from insert/delete), smooth scroll
                     through each intermediate line instead of
                     jumping instantly
```

---

## Quick Reference: What to Use When

```
  ┌──────────────────────┬──────────────────────────────────────┐
  │  Use case            │  Recommended options                │
  ├──────────────────────┼──────────────────────────────────────┤
  │  Quick review        │  --preset review                     │
  │  Presentation        │  --preset present                    │
  │  AI code review      │  --preset ai-code                    │
  │  Large files         │  --auto-precompute --algorithm patience │
  │  Fast deletion       │  --preset fast-delete                │
  │  Detailed inspection │  --step-mode --highlight-inline      │
  │  Custom preferences  │  --preset custom (via env var)       │
  └──────────────────────┴──────────────────────────────────────┘
```
