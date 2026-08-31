# New Features: Glide, Distance-Speed, Indent-Last, Flash, Scroll, Colormap-New

## Smooth Cursor Movement (--cursor-glide-ms)

**Options:**
- `--cursor-glide-ms N` — glide duration in ms (0 = off, default: 0)
- `--cursor-glide-show-intermediate 0|1` — show intermediate lines during
  glide (1 = yes, default; 0 = just animate cursor position)

**How it works:** Between hunks, the pace stage emits a `glide` op:
```
glide\t<from_line>\t<to_line>\t<duration_ms>\t<show_intermediate>
```

The animator interprets this op and animates the cursor moving from
`from_line` to `to_line` using ease-in-out (smoothstep) interpolation.
If `show_intermediate` is 1, the buffer is re-rendered at each step
(intermediate lines scroll past). If 0, only the cursor position is
updated (no full re-render — faster for large distances).

**Interruptible:** Press any key during the glide to skip to the end.

**Example:**
```bash
ad_vim --cursor-glide-ms 300 old.py new.py
ad_pipeline --cursor-glide-ms 300 --cursor-glide-show-intermediate 0 old.py new.py
```

**Env vars:** `config var: CURSOR_GLIDE_MS`, `config var: CURSOR_GLIDE_SHOW_INTERMEDIATE`

---

## Distance-Based Speed (--distance-speed)

**Options:**
- `--distance-speed adaptive|off` — enable adaptive speed (default: off)
- `--distance-threshold N` — lines above which speed increases (default: 10)
- `--distance-fast-mult F` — speed multiplier for long distances (default: 3.0)
- `--distance-slow-mult F` — speed multiplier for short distances (default: 0.5)

**How it works:** When a hunk starts, the pace stage calculates the
distance from the previous op's line to the hunk's target line. If the
distance exceeds `--distance-threshold`, delete delays are multiplied
by `--distance-fast-mult` (quick glance). Otherwise, they're multiplied
by `--distance-slow-mult` (show every char). Only delete delays are
affected — insert delays and keep delays are unchanged.

**Example:**
```bash
ad_vim --distance-speed adaptive --distance-threshold 10 old.py new.py
```

**Env vars:** `config var: DISTANCE_SPEED`, `config var: DISTANCE_THRESHOLD`,
`config var: DISTANCE_FAST_MULT`, `config var: DISTANCE_SLOW_MULT`

---

## Indent-Last (--indent-last)

**Option:** `--indent-last` or `--transform indent-last`

When a line is being **entirely deleted** (all chars are deletes, no
keeps), moves leading whitespace deletes (spaces/tabs) to the END of
the line group, just before the `\n` delete. The content is deleted
first (text shrinks from the right), then indentation is removed last
(the whole line disappears).

Only applies when the entire line is being deleted. If there are keeps
on the line, the transform is a no-op.

**Example:**
```bash
ad_vim --indent-last old.py new.py
ad_pipeline --postprocess-indent-last old.py new.py
```

**Env var:** `AD_INDENT_LAST=1`

---

## Flash Delete-Pacing (--delete-pacing flash)

**Options:**
- `--delete-pacing flash` — highlight whole line, pause, delete in one shot
- `--flash-pause-ms N` — pause after highlight (default: 400)
- `--flash-highlight-ms N` — highlight duration (default: 300)

When a line's content is being deleted, the pace stage emits a `highlight`
op for the whole line, then pauses, then deletes all content instantly.
Different from `instant` (which just deletes with no highlight/pause).

**Example:**
```bash
ad_vim --delete-pacing flash --flash-pause-ms 500 old.py new.py
```

**Env vars:** `config var: DELETE_PACING=flash`, `config var: FLASH_PAUSE_MS`,
`config var: FLASH_HIGHLIGHT_MS`

---

## Insert Pacing Word (--insert-pacing word)

**Option:** `--insert-pacing word` (default: char)

When enabled, inserts are grouped into words (runs of non-whitespace
chars). Each word is typed instantly, then a pause is inserted after
each whitespace char. This produces a more natural "typing words" feel
compared to the default char-by-char pacing.

**Example:**
```bash
ad_vim --insert-pacing word old.py new.py
```

---

## Scroll Modes (--scroll)

**Option:** `--scroll zz|zt|zb|none` (default: zz)

Controls how the viewport scrolls to follow the cursor:
- `zz` — center cursor in viewport (default)
- `zt` — cursor at top of viewport
- `zb` — cursor at bottom of viewport
- `none` — no scroll (start at line 1, never move)

**Example:**
```bash
ad_vim --scroll zt old.py new.py
```

**Env var:** `config var: SCROLL`

---

## Colormap-New Rendering

The `--colormap-new` option (which was previously parsed but never used)
is now fully wired. When a line is modified (has been touched by a
delete or insert), the animator renders it using `colormap-new` colors
(the new file's syntax highlighting). Unmodified lines use `colormap-old`
colors (the original file's syntax highlighting).

This provides visual feedback: you see the old colors change to new
colors as the animation progresses.

**Example:**
```bash
ad_pipeline --animator-colormap-old old.colormap --animator-colormap-new new.colormap old.py new.py
```

---

## Launcher Wiring

The `ad_vim` launcher and `ad_pipeline` now forward ALL options
to the C pipeline stages:

- **Postprocess:** `[REMOVED: --semantic-cleanup]`, `[REMOVED: --indent-aware]`, `--overwrite`,
  `--indent-last`, `[REMOVED: --op-order]` (all 5 modes)
- **Pace:** `--delete-pacing`, `--insert-pacing`, `--delete-speed`,
  `--insert-speed`, `--delete-threshold`, `--pacing`, `--gaussian-jitter-pct`,
  `--pause-after-lines`, `--pause-after-threshold`, `--pause-after-ms`,
  `--accel-delete` (+ sub-options), `--block-delete-size`,
  `--pause-before-delete-ms`, `--pause-after-delete-ms`,
  `--flash-pause-ms`, `--flash-highlight-ms`,
  `--cursor-glide-ms`, `--cursor-glide-show-intermediate`,
  `--distance-speed`, `--distance-threshold`,
  `--distance-fast-mult`, `--distance-slow-mult`
- **Decorate:** `--highlight`, `--highlight-duration-ms`, `--dim-unchanged`,
  `--dim-unchanged-pct`, `--context`, `--fold-unchanged`, `--sign-column`,
  `--git-blame`, `--max-hunk-chars`, `--theme`
