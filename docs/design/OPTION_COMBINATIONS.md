# Option Combinations

Practical recipes for common diffvim use cases. Each recipe shows
the exact command line to run — copy and paste.

---

## Code Review (Slow, Careful)

**Goal:** See every change slowly, with highlighting.

```bash
diffvim --preset review old.py new.py
# or explicitly:
diffvim --pacing review --highlight hunk --dim-unchanged --op-order left-to-right --speed 0.7 old.py new.py
```

**With smooth cursor movement:**
```bash
diffvim --pacing review --highlight hunk --dim-unchanged --op-order left-to-right --cursor-glide-ms 300 --speed 0.7 old.py new.py
```

---

## Demo (Smooth, Visually Appealing)

**Goal:** Show off the diff in a presentation or demo video.

```bash
diffvim --preset demo old.py new.py
# or explicitly:
diffvim --pacing gaussian --speed 0.7 --highlight inline --cursor-glide-ms 300 old.py new.py
```

**With distance-based speed (skip far-away changes):**
```bash
diffvim --pacing gaussian --speed 0.7 --highlight inline --cursor-glide-ms 300 --distance-speed adaptive old.py new.py
```

---

## Fast Overview (Quick Glance)

**Goal:** Get through a large diff quickly.

```bash
diffvim --preset fast old.py new.py
# or explicitly:
diffvim --speed 3 --delete-pacing instant --distance-speed adaptive old.py new.py
```

**Even faster (skip animation entirely):**
```bash
diffvim --speed 10 --delete-pacing instant --insert-pacing word --distance-speed adaptive old.py new.py
```

---

## Flash Delete (Highlight Before Delete)

**Goal:** When a whole line is deleted, flash it first so the viewer
sees what's being removed.

```bash
diffvim --delete-pacing flash --flash-pause-ms 500 --flash-highlight-ms 400 old.py new.py
```

**With indent-last (delete indentation last):**
```bash
diffvim --delete-pacing flash --indent-last old.py new.py
```

---

## Debugging (Full Control)

**Goal:** See exactly what's happening, with stats and highlights.

```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --diff-stat --diff-highlight --bell old.py new.py
```

**With step mode (Space advances one op):**
```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --diff-stat --diff-highlight --bell --step-mode old.py new.py
```

---

## Python (Indent-Aware)

**Goal:** Handle Python indentation correctly.

```bash
diffvim --indent-aware --indent-last old.py new.py
```

**With overwrite (in-place replacement):**
```bash
diffvim --indent-aware --indent-last --overwrite old.py new.py
```

---

## With Colormaps (Syntax Highlighting)

**Goal:** Show syntax highlighting that transitions from old to new.

```bash
# Generate colormaps
perl animator/perl/colorize.pl --backend vim old.py > old.colormap
perl animator/perl/colorize.pl --backend vim new.py > new.colormap

# Run with colormaps (via ad_pipeline)
ad_pipeline --animator-colormap-old old.colormap --animator-colormap-new new.colormap --highlight inline old.py new.py
```

---

## Smooth + Distance + Indent + Flash (Everything)

**Goal:** All new features at once.

```bash
diffvim --cursor-glide-ms 300 --distance-speed adaptive --distance-threshold 10 --distance-fast-mult 3 --distance-slow-mult 0.5 --indent-last --delete-pacing flash --highlight hunk --dim-unchanged --diff-stat --diff-highlight old.py new.py
```

---

## Using dv_snapshot for Debugging

**Goal:** Inspect the buffer state after every op.

```bash
# Basic
bash scripts/dv_snapshot.sh old.py new.py

# With all the same options as diffvim
bash scripts/dv_snapshot.sh --op-order left-to-right --delete-pacing flash --highlight inline --indent-last --cursor-glide-ms 300 old.py new.py

# With trace UI (click ops to collect them)
bash scripts/dv_snapshot.sh --trace --diff-stat --diff-highlight old.py new.py
```

---

## Presets Summary

| Preset | Speed | Pacing | Highlight | Op-Order |
|--------|-------|--------|-----------|----------|
| default | 1.0x | uniform | none | optimize |
| review | 0.7x | review | hunk | left-to-right |
| demo | 0.7x | gaussian | inline | optimize |
| fast | 2.0x | adaptive | none | optimize |

```bash
diffvim --preset default old.py new.py
diffvim --preset review old.py new.py
diffvim --preset demo old.py new.py
diffvim --preset fast old.py new.py
```
