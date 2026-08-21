# Design: Smooth Cursor Movement & Distance-Based Speed

**Status:** Design only — not yet implemented.

---

## 1. Smooth Cursor Movement (Ease-In-Out Interpolation)

### Problem

diffvim jumps instantly between hunks. When a hunk at line 5 finishes
and the next hunk starts at line 50, the cursor teleports from line 5
to line 50 with no visual transition. This is jarring and makes it
hard to follow what changed.

### Current Behavior

```
Hunk 1 (line 5):  delete 'x', delete 'y', delete 'z'
--- instant jump ---
Hunk 2 (line 50): insert 'a', insert 'b', insert 'c'
```

The animator processes each op independently. There is no concept of
"moving the cursor from line 5 to line 50" — the cursor just appears
at line 50 when Hunk 2 starts.

### Proposed Design

Add an `--cursor-glide` option that interpolates the cursor position
between the end of one hunk and the start of the next.

**Option name:** `--cursor-glide MODE`
- `none` (default) — instant jump (current behavior)
- `linear` — constant-speed glide
- `ease` — ease-in-out cubic (slow start, fast middle, slow end)

**Duration:** `--cursor-glide-ms N` (default: 300ms)

**How it works:**

1. After the last op of a hunk, the animator notes the current cursor
   position `(end_line, end_col)`.
2. Before the first op of the next hunk, the animator reads the target
   cursor position `(start_line, start_col)`.
3. If `--cursor-glide` is enabled and the distance exceeds a threshold
   (see §2), the animator inserts N interpolation frames:
   - For each frame `t` (0.0 to 1.0):
     - `ease_t = t * t * (3 - 2 * t)` (smoothstep)
     - `disp_line = end_line + (start_line - end_line) * ease_t`
     - `disp_col = end_col + (start_col - end_col) * ease_t`
     - `render()` with the interpolated position
     - `sleep(glide_ms / N)`

**Implementation location:** `animator.c`, main loop. After processing
a `HUNK` or `HUNK_END` op, check if the next op is at a different
line. If so, insert glide frames before processing the next op.

**Challenges:**
- The cursor position is 1-indexed (line/col), but interpolation
  needs fractional positions. The `disp_l`/`disp_c` variables
  (currently `int`) would need to become `float` or `double`.
- The scroll offset calculation in `render()` uses `disp_l` to
  determine which lines to show. Fractional `disp_l` would need
  rounding for rendering but keeping fractional for smooth movement.
- During the glide, the buffer state doesn't change — only the cursor
  moves. This means `render()` is called with the same buffer but
  different cursor positions, which should work.

**Files affected:**
- `animator/c/animator.c` — add glide logic in main loop
- `animator/c/animator.c` — change `disp_l`/`disp_c` to `double`
- `animator/c/animator.c` — update `render()` to round for display
- `diffvim` launcher — add `--cursor-glide` and `--cursor-glide-ms` options
- `set_config` — add `DIFFVIM_CURSOR_GLIDE` and `DIFFVIM_CURSOR_GLIDE_MS`

---

## 2. Distance-Based Speed

### Problem

diffvim shows every line of every change at the same speed. For large
diffs (e.g. 100+ changed lines), this takes too long. For small diffs
(2-3 changed lines), the animation is over too fast to follow.

### Current Behavior

All ops have the same delay regardless of how far apart they are.
The `--speed` multiplier affects everything uniformly.

### Proposed Design

Add a `--distance-speed` option that adjusts the animation speed based
on the distance between consecutive changes.

**Option name:** `--distance-speed MODE`
- `off` (default) — uniform speed (current behavior)
- `adaptive` — short distances = slow (see every line), long distances
  = fast (jump quickly)

**Parameters:**
- `--distance-threshold N` — distance (in lines) above which speed
  increases (default: 10)
- `--distance-fast-mult F` — speed multiplier for long distances
  (default: 3.0)
- `--distance-slow-mult F` — speed multiplier for short distances
  (default: 0.5)

**How it works:**

1. Before processing each hunk, calculate the distance from the
   current cursor position to the hunk's target line:
   `distance = abs(target_line - current_line)`
2. If `distance > threshold`:
   - Use `--distance-fast-mult` for all delays in this hunk
   - Optionally skip per-char animation and use `word` pacing
3. If `distance <= threshold`:
   - Use `--distance-slow-mult` for all delays in this hunk
   - Show every char/line

**Example:**
```
Hunk 1 (line 5):   distance = 0   → slow (0.5x) — show every char
Hunk 2 (line 50):  distance = 45  → fast (3.0x) — quick glance
Hunk 3 (line 52):  distance = 2   → slow (0.5x) — show every char
Hunk 4 (line 200): distance = 148 → fast (3.0x) — quick glance
```

**Implementation location:** `animator.c`, main loop. Before processing
a `HUNK` op, calculate the distance and set a `current_speed_mult`
that's applied to all `delay` ops within that hunk.

**Alternative approach (simpler):** Instead of changing speed within
the animator, have the `pace` tool adjust delays based on distance.
The pace tool already knows the line numbers for each op — it can
calculate distances and adjust delays before the animator even sees
them.

**Files affected:**
- `animator/c/pace.c` — add distance-based delay adjustment
- `animator/c/animator.c` — OR add per-hunk speed multiplier
- `diffvim` launcher — add `--distance-speed` and related options
- `set_config` — add `DIFFVIM_DISTANCE_SPEED` etc.

---

## 3. Interaction Between the Two Features

When both `--cursor-glide` and `--distance-speed` are enabled:
- Long distances: fast glide (or skip glide entirely, just jump)
- Short distances: slow glide (or no glide, since distance is small)

Suggested default:
```
--cursor-glide ease --cursor-glide-ms 300
--distance-speed adaptive --distance-threshold 10
```

This means: hunks within 10 lines of each other get full animation
with smooth cursor glide. Hunks more than 10 lines apart get fast
animation with a quick (or no) glide.

---

## 4. Relationship to Existing Features

- `--speed N` — global multiplier. The distance-based speed is
  multiplied ON TOP of this. So `--speed 2 --distance-speed adaptive`
  would give 2x * 3x = 6x for long distances, 2x * 0.5x = 1x for short.
- `--max-hunk-chars N` — skips animation for large hunks. This is
  orthogonal — it skips the hunk entirely, while distance-speed
  adjusts the speed within the hunk.
- `--cursor-glide` — only affects the transition BETWEEN hunks, not
  within a hunk. Within a hunk, the cursor follows each op.

---

## 5. Open Questions

1. Should the glide show the cursor moving through intermediate lines
   (rendering each line as it passes), or should it just animate the
   cursor position without showing intermediate content?
   - **Recommendation:** just animate cursor position, don't render
     intermediate lines (too slow for large distances).

2. Should distance-based speed also affect insert pacing, or only
   delete pacing?
   - **Recommendation:** affect both — a hunk that's far away should
     be fast for both deletes and inserts.

3. Should the glide be interruptible (user presses a key to skip it)?
   - **Recommendation:** yes — pressing Space during a glide skips
     to the end of the glide.
