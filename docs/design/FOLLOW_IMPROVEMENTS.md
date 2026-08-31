# 50 Improvements to Help Users Follow Patching

A focused list of UX improvements that would make it easier for a viewer to
**follow what is happening** while ad_vim patches a file. Every item is
framed from the viewer's perspective: "what am I seeing, what just changed,
what's coming next, and where should I look?"

Items are grouped by theme and ordered roughly by impact-within-group.
Status markers:
- ✅ already implemented in `ad_vim` (at least partially)
- ⬜ not yet implemented (a concrete proposal)

---

## A. Visual cues for *what just changed* (1–10)

1. ✅ **Sign column markers** — `+`/`-` signs in the vim sign column flag
   inserted/deleted lines as they happen. (`--sign-column`)

2. ⬜ **Inline char-level highlight while typing** — paint each freshly-typed
   char green for 200ms, each freshly-deleted char red for 200ms, using
   `matchaddpos()`. Lets the eye lock onto the exact change even on long lines.

3. ⬜ **Ghost text for deletions** — show the deleted text as a struck-through
   "ghost" overlay for 400ms before it actually disappears, so the viewer
   sees *what was there* rather than just watching chars vanish.

4. ⬜ **Cursor trail** — leave a fading trail behind the cursor for ~300ms
   after each move, so the eye can follow the path the cursor took between
   hunks (especially useful for large distance glides).

5. ✅ **Hunk region highlight before animation** — paint the lines about to
   change with `DiffChange` for a moment so the viewer knows where to look.
   (`--highlight-hunk`)

6. ⬜ **Persistent side-by-side "shadow" of the old text** — keep a frozen
   readonly copy of the original file in a left split, with the current diff
   hunk mirrored, so the viewer always has the "before" visible.

7. ⬜ **Color-coded hunk boundaries** — draw a thin colored bar above and
   below each hunk while it's being animated, so the visual scope of the
   change is obvious even when scrolling.

8. ⬜ **"Just changed" line background** — briefly tint the entire line a
   subtle yellow for 500ms after any char op lands on it, so the viewer can
   spot the active line in their peripheral vision.

9. ⬜ **Deletion counter on the status line** — show `−14 +8` next to the
   hunk progress so the viewer sees the cumulative net change at a glance.

10. ⬜ **Per-hunk "minimap" highlight** — color the corresponding region of
    vim's scrollbar/minimap so the viewer can see where the current hunk
    sits in the whole file.

---

## B. Information display (11–20)

11. ✅ **Hunk progress counter** — `hunk 3/7 (42%)` in the message line.

12. ⬜ **Hunk description in plain English** — before each hunk, briefly
    announce what kind of change it is: `Hunk 3/7: replaced 1 line in
    function hello()`. Generated from the diff structure + nearest enclosing
    scope.

13. ✅ **Git blame for the changed line** — `--git-blame` echoes author +
    date + commit for the target line.

14. ⬜ **File-path header that stays visible** — pin the file name + hunk
    counter in a `statusline` that doesn't scroll away, so the viewer
    always knows which file they're looking at.

15. ⬜ **Total estimated time remaining** — `~14s remaining` based on the
    number of pending ops × average delay. Recomputed after each hunk.

16. ⬜ **"What's coming next" preview** — show a one-line teaser of the next
    hunk before this one starts: `next: +3 lines at line 47`.

17. ⬜ **Change-type icon next to the line** — `+`, `-`, `~` (modified),
    `↪` (moved), `↻` (refactor) — picked by a tiny heuristic on the hunk.

18. ⬜ **Net line-count delta indicator** — `Δ +12 lines` in the corner,
    updated live, so the viewer sees the overall direction of the change.

19. ✅ **Active config echo at startup** — `ad_vim config: tick=16ms
    type=50ms ...` so a viewer can verify the speed they're watching at.

20. ⬜ **"Why didn't this hunk animate?" notice** — when `--max-hunk-chars`
    skips a hunk, briefly show `hunk 4 skipped (312 chars > 200 threshold)
    — press b to step into it`.

---

## C. Timing & pacing (21–30)

21. ✅ **Adaptive timing** — auto-slow for complex hunks. (`--adaptive-timing`)

22. ✅ **Adaptive mode** — slow start, accelerate, pause at hunk end.
    (`--adaptive`)

23. ✅ **Rapid end-of-line deletion** — when the cursor is at end of line
    and all trailing text is being deleted, apply in one shot.
    (`--rapid-eol-delete`, default on)

24. ⬜ **"Thinking pause" before complex hunks** — auto-pause ~600ms before
    hunks with > 30 changed chars, to let the viewer brace for a big change.

25. ⬜ **Variable typing speed (Gaussian jitter)** — vary per-char delay
    using a normal distribution so the typing feels human, not metronomic.

26. ✅ **Per-word instant typing with pause** — short words typed as a unit,
    followed by a pause. (`--max-word-chars`)

27. ⬜ **Indentation block-shift animation** — when only the indentation
    changes, shift the whole block as one unit with a slide animation
    instead of deleting and re-typing whitespace.

28. ⬜ **Slow-motion on the first hunk** — automatically run the very first
    hunk at 0.5× speed so the viewer has time to settle in; subsequent
    hunks run at normal speed.

29. ⬜ **Pause-after-N-lines for very large hunks** — auto-pause every N
    lines of a > 50-line hunk so the viewer doesn't lose context.
    (Partially implemented in `--adaptive` mode.)

30. ⬜ **"Reading time" after inserts** — after typing a long inserted line
    (> 40 chars), wait 300ms before moving on, to give the viewer time to
    read what was just added.

---

## D. Navigation & control (31–40)

31. ✅ **Pause / resume** — `<Space>` toggles pause.

32. ✅ **Skip current hunk** — `n` applies the current hunk instantly and
    pauses (review mode).

33. ✅ **Back to previous hunk** — `b` reverts and replays.

34. ✅ **Speed up / slow down** — `+` / `-` / `=`.

35. ✅ **Step mode** — `<Space>` advances one char op at a time.
    (`--step-mode`)

36. ⬜ **Jump to specific hunk** — `:DiffvimHunk 5` jumps directly to hunk
    #5, skipping the in-between (or animating them instantly).

37. ⬜ **Bookmark a hunk** — `m` marks the current hunk; `` ` `` returns to
    it later. Useful when reviewing a long diff and wanting to revisit a
    specific change.

38. ⬜ **"Replay last hunk slowly"** — `r` rewinds one hunk and replays it
    at 0.5× speed, then continues at normal speed.

39. ⬜ **Pan/zoom the viewport** — `<C-Up>` / `<C-Down>` to scroll the
    viewport without moving the cursor, so the viewer can peek ahead while
    the animation continues.

40. ⬜ **Toggle a "diff lens" overlay** — `L` pops up a floating window
    showing a magnified char-diff of just the current line, so the viewer
    can see exactly which chars are changing on a long line.

---

## E. Diff presentation & layout (41–50)

41. ✅ **Fold unchanged regions** — `--context N` folds runs of unchanged
    lines, keeping N context lines around each hunk.

42. ⬜ **Side-by-side old/new view** — open the new file in a `vsplit` and
    keep both visible; the old file animates, the new file is the goal.

43. ⬜ **"Goal line" preview** — before typing an inserted line, briefly
    show a dimmed preview of the line below the cursor (like vim's
    `ins-completion` preview), then fade it out as the actual chars are
    typed over it.

44. ⬜ **Highlight unchanged anchor lines** — dim unchanged lines slightly
    (90% opacity via `cursorline`-style highlight) so the eye is drawn to
    the changed lines.

45. ⬜ **Semantic hunk grouping** — when multiple consecutive hunks are in
    the same function/block, group them visually with a bracket in the
    sign column, so the viewer sees "these 3 hunks are all in
    `calculate_total()`".

46. ⬜ **Syntax-aware token boundaries** — use Tree-sitter to never split
    a string literal or identifier across delete+insert; replace the whole
    token instead. Reduces visual noise mid-token.

47. ⬜ **Indent guides during animation** — show faint vertical indent
    guides so the viewer can see scoping at a glance, especially in
    Python/YAML where indentation is semantic.

48. ⬜ **Color the new file by change-type** — in side-by-side mode, color
    each line of the new file by what happened: green=inserted,
    yellow=modified, white=kept. Lets the viewer scan the goal.

49. ⬜ **"Diff heat-map" sidebar** — a 1-column sidebar where each row is
    a line of the file, colored by change density. The viewer sees the
    overall shape of the patch at a glance.

50. ⬜ **Post-animation summary screen** — after the animation finishes,
    show a 3-second summary: `Done. 7 hunks applied. +42 / −28 lines.
    Press u to undo last hunk, :w to save, :q to quit.`

---

## Implementation priority

If we had to pick the top 10 to implement next, in order:

1. **#2** Inline char-level highlight while typing — highest "I can see it
   change" payoff per line of code.
2. **#12** Plain-English hunk description — closes the "what is this doing"
   gap for non-author viewers.
3. **#24** Thinking pause before complex hunks — cheap to add, big
   readability win.
4. **#8** "Just changed" line tint — peripheral-vision cue.
5. **#50** Post-animation summary screen — gives the viewer closure.
6. **#36** Jump to specific hunk — essential for reviewing large diffs.
7. **#15** Estimated time remaining — sets viewer expectations.
8. **#42** Side-by-side old/new view — the single biggest "followability"
   upgrade for complex patches.
9. **#46** Syntax-aware token boundaries — removes the most confusing
   mid-token flicker.
10. **#9** Deletion/insertion counter on the status line — instant
    orientation without visual clutter.

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
