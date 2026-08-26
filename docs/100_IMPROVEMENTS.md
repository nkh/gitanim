# 100 Improvements for Animated Diffs (diffvim/gitanim)

A catalogue of **exactly 100 improvements** — each one implementable as
either (a) a **postprocess layer** that reorders/groups/modifies ops,
(b) a **pace layer** that controls *when* ops are applied, (c) a
**decorate layer** that controls *how* ops are rendered, or
(d) an **animator feature** that the playback loop itself supports.

The four op types in the pipeline are: `keep`, `delete`, `insert`,
`overwrite_insert`. Each op carries `(type, code, line, col)`.

## Background: the current pipeline

```
compute (raw ops)
  │
  ▼
overwrite           [optional, --overwrite]   merges delete+insert pairs
                                            into overwrite_insert
delete-indent-last  [optional, --indent-last] moves leading-whitespace
                                            DELETE ops to end of line
reorder             [always]                 4-sweep: content del →
                                            content ins → \n del → \n ins
adjust_positions    [always]                 fixes (line, col) based on
                                            \n deletes
  │
  ▼
postprocess output → pace → decorate → animator
```

## Table of Contents

- [Op Ordering (1–12)](#op-ordering-112) — Reorder ops for better visual flow
- [Op Grouping (13–24)](#op-grouping-1324) — Group related ops into clusters
- [Timing & Pacing (25–38)](#timing--pacing-2538) — Control delays, speeds, rhythms
- [Visual Highlighting (39–52)](#visual-highlighting-3952) — Color, emphasis, dimming
- [Semantic (53–65)](#semantic-5365) — Group by meaning
- [Context (66–76)](#context-6676) — Show surrounding context, anchors
- [Progressive Disclosure (77–85)](#progressive-disclosure-7785) — Reveal complexity gradually
- [Accessibility & UX (86–92)](#accessibility--ux-8692) — Keyboard, reduced motion, pause points
- [Advanced/Experimental (93–100)](#advancedexperimental-93100) — Cutting-edge ideas

---

## Op Ordering (1–12)

Reorder ops within line groups / hunks for a more natural visual flow.

### 1. Left-to-Right Cursor Sweep
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** default-on (`--op-order natural` to disable; already partially implemented via `left_to_right`)
- **Description:** Within each line group (between keeps or `\n` ops), emit all DELETE ops sorted ascending by `col`, then all INSERT ops sorted ascending by `col`. This guarantees the cursor never moves backward within a single line, eliminating the "flicker back" effect.
- **Example:** Before: `del 'x' @col5, ins 'y' @col3, del 'z' @col7`. After: `del 'x' @col5, del 'z' @col7, ins 'y' @col3`.
- **Test:** Property test — for any output, within each line group, the `col` sequence of deletes is non-decreasing and the `col` sequence of inserts is non-decreasing.

### 2. Column-Monotonic Cursor Path
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--col-monotonic` (off by default; stricter than #1)
- **Description:** After Layer 1's sweep, run a repair pass that ensures the cursor's effective column never decreases within a line, even across the delete→insert boundary. If a later op would force a backward jump, insert a synthetic "fast-forward keep" hint so the animator can hide the jump.
- **Example:** After `del 'z' @col7, ins 'y' @col3` the layer emits `del 'z' @col7, [ff-keep col=3], ins 'y' @col3` so the animator knows to teleport silently.
- **Test:** Snapshot test asserting the cursor's running max column never decreases without an `ff-keep` op in between.

### 3. Newline-Last Insert Sweep
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--newline-last` (default-on as part of reorder's 4th sweep)
- **Description:** Push every `\n` insert to the very end of its enclosing hunk, after all content inserts and after every `\n` delete. This prevents the viewer from seeing a half-built line on a brand-new line — instead, the line appears complete when the `\n` finally arrives.
- **Example:** Hunk that adds two lines: insert content of line 1, insert content of line 2, then `\n` insert, then `\n` insert — instead of inserting line 1 content + its `\n`, then line 2.
- **Test:** Property test — no `\n` insert op precedes a content insert op within the same hunk.

### 4. Newline-Delete-Early Alternative
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--newline-delete-early` (off by default; experimental opposite of #3)
- **Description:** Alternative ordering where `\n` deletes happen *before* content deletes on the merged line. Useful when the user wants to see "line vanished" before "content vanished", giving a sense of "this line is going away" before the chars are stripped. Trade-off: chars from the next line briefly appear attached to the previous one.
- **Example:** Lines `foo` and `bar` merging into `foobar`: delete `\n` between them first, then delete the now-trailing chars you don't want.
- **Test:** Visual snapshot test comparing the two orderings on the same hunk; assert both produce identical final buffer.

### 5. Adjacent Delete-Insert Lockstep
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--lockstep-pairs` (off by default; alternative to `--overwrite`)
- **Description:** Detect a DELETE op immediately followed (after reordering) by an INSERT at the same `(line, col)` and tag the pair with a shared `pair_id` field so the animator can render them as one atomic swap (delete char, insert char in same frame) without flicker. Unlike `--overwrite`, the ops remain separate in the stream — only a metadata tag is added.
- **Example:** `del 'a' @col3` + `ins 'b' @col3` → tagged `pair_id=42` so animator paints 'a' red and 'b' green in the same frame.
- **Test:** Parity test — output of `--lockstep-pairs` equals output of `--overwrite` after the animator applies the pairing (same final buffer, different intermediate timing).

### 6. Trailing-Whitespace Delete Defer
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--defer-trailing-ws` (off by default; opposite of `--indent-last`)
- **Description:** Move trailing-whitespace DELETE ops (whitespace at the end of a line, just before the `\n`) to the END of the line's op group, after all content deletes. Mirrors `--indent-last` but for trailing whitespace. Helps the viewer focus on content changes first, then the cosmetic whitespace cleanup.
- **Example:** Deleting `foo  ` (with trailing spaces) → `del 'f','o','o', del ' ',' '`. With this layer: `del 'f','o','o', del ' ',' '` reordered to `del 'f','o','o'` then trailing-space deletes last.
- **Test:** Snapshot test — trailing whitespace deletes are the last non-`\n` ops in their line group.

### 7. Indent-First Reordering
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--indent-first` (off by default; opposite of `--indent-last`)
- **Description:** When a line's indentation changes, emit the indent DELETE+INSERT ops *first*, before any content ops. Useful when the viewer's mental model is "fix the indentation, then edit the content" — e.g., when un-indenting a block. Trade-off: looks odd for re-indentations of unchanged content.
- **Example:** Line `    foo` becomes `  foo`: with this layer the indent delete (2 spaces) happens before the (nonexistent) content changes, so the viewer sees the indent shrink first.
- **Test:** Snapshot test asserting all indent-only ops precede all content ops in their line group.

### 8. Reinsertion Folding
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--fold-reinsertion` (default-on; supersedes `--semantic-cleanup`)
- **Description:** Generalize `--semantic-cleanup`: any DELETE of char `c` at `(line, col)` immediately followed by an INSERT of the same char `c` at the same `(line, col)` is folded into a `keep` op. Reduces op count and prevents "delete then re-add the same char" flicker. Distinct from `--overwrite` because the chars are identical, not different.
- **Example:** `del 'a' @col3, ins 'a' @col3` → `keep 'a' @col3`.
- **Test:** Property test — round-trip equality (running the layer on random inputs yields the same final buffer); also op count strictly decreases.

### 9. Identifier-Atomic Reordering
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--identifier-atomic` (off by default)
- **Description:** Within a line group, detect maximal runs of identifier characters (ASCII alphanumerics + `_`) that are being deleted or inserted as a unit, and ensure those runs stay contiguous in the op stream — no non-identifier op interleaves. Prevents the visual oddity of an identifier's chars being animated interspersed with surrounding punctuation changes.
- **Example:** Changing `count` to `totalCount` in `count += 1` → ensure the `count`→`total` swap happens as one block, then the `Count` insert as another, then `+= 1` unchanged.
- **Test:** Snapshot test — identifier char runs in the op stream are never split by punctuation ops.

### 10. Line-Sequential Staging
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--line-sequential` (off by default)
- **Description:** Ensure that all ops on line N complete (delete + insert + `\n` ops) before any op on line N+1 begins. Strict line-by-line playback. Trade-off: may slow down long diffs because parallelizable changes are serialized; benefit is a much stronger "I'm editing this line" mental model.
- **Example:** A two-line hunk where line 1 has 5 ops and line 2 has 3: layer guarantees all 5 line-1 ops come first, then all 3 line-2 ops.
- **Test:** Property test — for any op on line N+1, all ops on line N precede it in the stream.

### 11. Brace-Pair Closure Ordering
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--brace-pair-order` (off by default; language-aware)
- **Description:** When a matched pair of brackets (`()`, `[]`, `{}`, `<>` for generics) is being inserted or deleted on the same line, emit the opening bracket op, then any inner content ops, then the closing bracket op — even if compute emitted them in column order. Produces the natural "open, fill, close" visual that matches how a human would type.
- **Example:** Inserting `[x]` at col 3 — compute emits `ins '['` then `ins 'x'` then `ins ']'` (already correct). But inserting `[x]` and `()` together, compute might interleave; this layer keeps each pair's content contiguous.
- **Test:** Snapshot test on a brace-pair fixture; assert opening op, content ops, closing op are in order with no foreign ops between.

### 12. Cursor-Backtrack Repair
- **Category:** Op Ordering
- **Layer type:** postprocess layer
- **Trigger:** `--repair-backtrack` (off by default; safety net)
- **Description:** Final safety-net pass after all other ordering layers. Walks the op stream, simulating the cursor; if any op would force the cursor to move *backward* by more than `K` columns (configurable), it inserts an explicit `keep` op tagged `repair=true` so the animator can flash the cursor's path. Helps debug pathological diffs where ordering layers couldn't fix things.
- **Example:** After all layers, op at col 12 is followed by op at col 3 → layer inserts `keep ' ' @col3 repair=true` between them.
- **Test:** Property test — no two adjacent ops have a col delta less than `-K`.

---

## Op Grouping (13–24)

Group related ops into clusters (multi-op units the animator treats as one).

### 13. Word Boundary Grouping
- **Category:** Op Grouping
- **Layer type:** decorate layer
- **Trigger:** `--group word` (off by default; mutually exclusive with `--group char`)
- **Description:** Tags consecutive non-whitespace ops within the same line as a single "word" cluster via a `cluster_id` field. The pace layer can then treat each word as a unit (e.g., animate word-by-word instead of char-by-char). Falls back to char grouping if disabled.
- **Example:** Changing `foo` to `bar` → 6 char ops tagged with `cluster_id=42` so pace can render them as one "swap word" animation.
- **Test:** Snapshot test — op stream has `cluster_id` field; adjacent non-whitespace ops in the same line share an ID.

### 14. Line Hunk Grouping
- **Category:** Op Grouping
- **Layer type:** decorate layer
- **Trigger:** `--group hunk` (off by default)
- **Description:** Tags all ops in the same git hunk (contiguous changed lines) with a shared `hunk_id`. Lets the pace layer animate the entire hunk as a unit (e.g., "type out the whole hunk in one fast burst, then pause").
- **Example:** A 5-line hunk → all 30 ops tagged `hunk_id=3`; pace layer applies them with no inter-op delay.
- **Test:** Snapshot test — all ops with the same `hunk_id` are contiguous in the stream.

### 15. Statement/Expression Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group statement` (off by default; requires `--lang` or autodetect)
- **Description:** Tags ops with `stmt_id` corresponding to the source statement (delimited by `;` in C-like languages, newline in Python, etc.). When a statement is being modified, all its ops share an ID; the pace layer can then animate the statement as a single "thought".
- **Example:** Changing `x = 1;` to `x = 2;` → all 2 char ops share `stmt_id=7`.
- **Test:** Snapshot test on a multi-statement fixture; assert ops within each statement share an ID.

### 16. Token Coalescing
- **Category:** Op Grouping
- **Layer type:** postprocess layer
- **Trigger:** `--coalesce-tokens` (off by default)
- **Description:** Coalesce consecutive ops of the same type (e.g., 5 deletes in a row) into a single "token" op carrying a `count` field. The animator applies them as one logical step but may still render each char individually. Reduces op count for high-density diffs.
- **Example:** `del 'a', del 'b', del 'c', del 'd', del 'e'` → `del_token {chars: "abcde", count: 5}`.
- **Test:** Property test — round-trip equality; op count strictly decreases for runs of ≥2 same-type ops.

### 17. Whitespace Cluster Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer
- **Trigger:** `--group whitespace` (off by default)
- **Description:** Tags maximal runs of whitespace-only ops (spaces, tabs, `\n`) with a shared `ws_cluster_id`. Lets pace layer animate "indentation adjustments" as one quick step rather than char-by-char. Pairs naturally with `--indent-first` or `--indent-last`.
- **Example:** A re-indentation of a 10-line block → 40 whitespace ops tagged `ws_cluster_id=15`, animated as one fast burst.
- **Test:** Snapshot test — whitespace runs share an ID; non-whitespace ops break the run.

### 18. Brace-Content Pair Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group brace-pair` (off by default)
- **Description:** Tags an opening brace, its matched closing brace, and all ops *between* them with a shared `brace_pair_id`. Useful for "this whole block was rewritten" cases — the viewer sees the block boundaries flash together.
- **Example:** Refactoring a function body: `{ ... 50 ops ... }` all tagged `brace_pair_id=4`.
- **Test:** Snapshot test on a brace-balanced fixture; assert paired braces and their contents share an ID.

### 19. String Literal Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group string` (off by default)
- **Description:** Tags all ops *inside* a string literal (between matching quotes) with a `string_id`. Prevents the animator from splitting a string into fragments visually — the whole string is treated as one unit. Handles escape sequences (e.g., `\"` doesn't end the string).
- **Example:** Changing `"hello world"` to `"hello there"` → the 6 changed chars inside the quotes share `string_id=9`.
- **Test:** Snapshot test on a string-containing fixture; assert chars between matching quotes share an ID; escaped quotes don't break the run.

### 20. Comment Block Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group comment` (off by default)
- **Description:** Tags all ops within a single comment (line comment `//` to EOL, or block comment `/* */`) with a `comment_id`. Multi-line comments are tagged as one block regardless of line breaks.
- **Example:** Editing a 3-line block comment → all 12 ops share `comment_id=2`.
- **Test:** Snapshot test on comment fixtures for several languages; assert comment chars (including `\n` within block comments) share an ID.

### 21. Import Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group imports` (off by default)
- **Description:** Tags all ops in a contiguous block of import statements with an `imports_id`. Lets the pace layer animate "all imports changed at once" as a single fast step rather than 30 separate import edits.
- **Example:** Reordering 5 Python imports → all 30 ops share `imports_id=1`, animated as one burst.
- **Test:** Snapshot test — ops in the import region of a file share an ID; non-import ops don't.

### 22. Function Signature Grouping
- **Category:** Op Grouping
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--group signature` (off by default)
- **Description:** Tags all ops within a function/method signature (from `def`/`func`/`fn` keyword through the closing `)` of the parameter list) with a `sig_id`. Helps viewers parse "the function's interface changed" as one event.
- **Example:** Changing `def foo(a, b):` to `def foo(a, b, c=1):` → all 4 new param ops share `sig_id=8`.
- **Test:** Snapshot test on function-definition fixtures across languages.

### 23. Diff-Hunk Coalescing
- **Category:** Op Grouping
- **Layer type:** postprocess layer
- **Trigger:** `--coalesce-hunks` (off by default)
- **Description:** Coalesces all ops within a single hunk into one "hunk op" carrying a list of sub-ops. The animator can apply the entire hunk in one frame, or expand it on demand. Useful for "summary mode" — show all hunks as blocks first, then expand.
- **Example:** A 10-op hunk → 1 `hunk_op { ops: [...] }`. The animator's `--expand` flag unpacks it.
- **Test:** Property test — round-trip equality; op count = number of hunks.

### 24. Adjacent Modification Pairing
- **Category:** Op Grouping
- **Layer type:** postprocess layer
- **Trigger:** `--pair-modifications` (off by default)
- **Description:** Tags every DELETE op with the immediately following INSERT op at the same `(line, col)` as a modification pair, even if not adjacent in the stream. Distinct from `--overwrite` (which *merges* them); this layer only *tags* them with `pair_id`, leaving the ops separate so the animator can choose how to render the pair (e.g., red-then-green vs. amber swap).
- **Example:** `del 'a' @col3` ... (3 other ops) ... `ins 'b' @col3` → both tagged `pair_id=11`.
- **Test:** Parity test — paired ops have matching `pair_id`; unpaired ops have `pair_id=0`.

---

## Timing & Pacing (25–38)

Pace-layer improvements controlling WHEN ops fire and at what speed.

### 25. Beat-Based Pacing
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--bpm N` (default off; takes precedence over `--delay`)
- **Description:** Snaps op fire-times to a musical beat grid at N beats per minute. Inserts and deletes that fall within the same beat interval are batched into one frame. Gives animations a rhythmic, almost musical quality — pleasant for demos and screencasts.
- **Example:** `--bpm 120` → beats every 500 ms; an op stream of 10 ops at 50 ms each becomes 5 frames at 500 ms each.
- **Test:** Snapshot test — op fire-times are all integer multiples of `60000/bpm` ms.

### 26. Distance-Based Cursor Speed
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--cursor-distance-speed` (off by default)
- **Description:** When the cursor must move between ops, scale the inter-op delay by the Euclidean distance moved. Long jumps take longer (smoother visual travel); adjacent ops fire quickly. Models real typing — fingers take longer to reach far keys.
- **Example:** Move from `(line 1, col 1)` to `(line 50, col 30)` → 250 ms travel; adjacent ops → 30 ms.
- **Test:** Property test — delay between two ops is monotonically non-decreasing in cursor distance.

### 27. Acceleration Ramp
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--ramp N` (default off; N = seconds to full speed)
- **Description:** Starts the animation slowly and accelerates over the first N seconds to the target speed. Mimics the natural ramp-up of watching a video — gives the viewer a moment to settle in before the pace picks up.
- **Example:** `--ramp 3 --delay 30` → first op at 120 ms delay, linearly decreasing to 30 ms by t=3 s.
- **Test:** Snapshot test — first op's delay ≥ target delay × 4; by t=N, delay equals target.

### 28. Deceleration Toward Hunk Boundary
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--slow-at-hunks` (off by default)
- **Description:** Inverse of #27: slows down in the last 5 ops of each hunk so the viewer can register "this hunk is done" before the next begins. Creates natural breathing room between semantic units.
- **Example:** Hunk of 20 ops at 30 ms each → last 5 ops at 30, 50, 80, 120, 180 ms (quadratic ease-out).
- **Test:** Snapshot test — last 5 ops of each hunk have monotonically increasing delays.

### 29. Micro-Pause at Statement Boundaries
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--pause-at-stmt N` (default off; N = ms pause)
- **Description:** Inserts a brief pause (default 150 ms) after every op whose `stmt_id` (from #15) changes, signaling to the viewer "this statement is done, here's the next one". Helps parse dense diffs by giving them natural punctuation.
- **Example:** 3 statements changing back-to-back → 3 visible "bursts" with 150 ms pauses between.
- **Test:** Snapshot test — delay between ops with different `stmt_id` is ≥ 150 ms.

### 30. Variable Insert/Delete Speed
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--insert-faster` / `--delete-slower` (default off)
- **Description:** Inserts animate faster than deletes (e.g., insert at 20 ms, delete at 50 ms). Models real typing: typing new content is fluid; deleting requires backspacing one char at a time. Reduces overall animation time without making deletes feel rushed.
- **Example:** 5 deletes + 5 inserts → 250 ms (deletes) + 100 ms (inserts) = 350 ms total instead of 500 ms uniform.
- **Test:** Snapshot test — insert ops have shorter delays than delete ops.

### 31. Cluster Burst Pacing
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--cluster-burst` (default off; uses `cluster_id` from grouping layers)
- **Description:** Within a cluster (word, statement, hunk — whichever grouping is active), ops fire as fast as possible (~5 ms); between clusters, a 100 ms pause. Gives the animation a "burst, breathe, burst" rhythm that's far easier to follow than uniform pacing.
- **Example:** A 3-word line change → 3 fast bursts with 100 ms gaps.
- **Test:** Property test — within-cluster delays ≤ 5 ms; between-cluster delays ≥ 100 ms.

### 32. Idle Timeout Auto-Pause
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--idle-pause N` (default off; N = seconds of idle)
- **Description:** If the animator has been paused (or no user input) for ≥ N seconds, automatically pauses playback. Resumes on keypress. Prevents the animation from running away while the viewer is reading a particular section.
- **Example:** User pauses to read line 47; after 5 s of no input, animator enters "soft pause" (no progress, but speed bar still indicates 1×).
- **Test:** Integration test — simulate idle; assert animator state transitions to "soft paused".

### 33. Reading-Time Pause After Major Change
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--reading-pause N` (default off; N = ms pause)
- **Description:** After every hunk that modifies ≥ 5 lines, inserts a longer pause (default 500 ms) to let the viewer absorb the change before the next hunk. Tunable per-hunk-size: bigger hunks → longer pause.
- **Example:** A 10-line hunk → 800 ms pause; a 2-line hunk → no extra pause.
- **Test:** Property test — delay after hunk scales linearly with hunk size above threshold.

### 34. Per-Language Pacing Profile
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--lang-profile` (default off; reads `~/.config/diffvim/profiles.toml`)
- **Description:** Loads a per-language profile that sets default `--delay`, `--ramp`, `--pause-at-stmt`, etc. based on file type. E.g., Python (statement-per-line) gets shorter inter-stmt pauses than C (multiple statements per line).
- **Example:** `.py` → `delay=40, pause-at-stmt=80`; `.c` → `delay=30, pause-at-stmt=120`.
- **Test:** Config test — given a profile and a `.py` file, the pace layer applies the Python profile.

### 35. Anticipation Hold
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--anticipation N` (default off; N = ms)
- **Description:** Before every cluster (word, statement, or hunk — whichever is active), inserts a brief 50 ms hold where the cursor is visible but no op fires. Mimics the animation principle of "anticipation" — the viewer subconsciously braces for the next change.
- **Example:** Before deleting a 5-char word → 50 ms hold, then 5 fast deletes.
- **Test:** Snapshot test — every cluster boundary is preceded by a 50 ms gap.

### 36. Follow-Through Decay
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--follow-through N` (default off; N = ms)
- **Description:** After every cluster, the cursor "settles" for N ms with no movement, letting the viewer's eye finish tracking. Pairs with `--anticipation` to create the classic anticipation-action-follow-through rhythm from animation theory.
- **Example:** After typing a word → 80 ms settle where the cursor sits at the final position.
- **Test:** Snapshot test — every cluster boundary is followed by an N ms gap.

### 37. Squash-and-Stretch Pacing
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--squash-stretch` (default off)
- **Description:** For overwrite_insert ops (replacements), fire the delete and insert with a 20 ms "squash" delay between them, then a 40 ms "stretch" settle. Models the physical metaphor of "the char squashes, then springs back as the new char".
- **Example:** Replace `a` with `b` → del `a`, 20 ms pause, ins `b`, 40 ms settle.
- **Test:** Snapshot test — overwrite_insert ops have a 20 ms inter-half delay and 40 ms trailing settle.

### 38. Rhythm Snapping (Quantize)
- **Category:** Timing & Pacing
- **Layer type:** pace layer
- **Trigger:** `--quantize N` (default off; N = ms grid)
- **Description:** Quantizes every op's fire-time to the nearest N ms grid (default 60 ms). Produces a steady, metronomic feel — useful for sync-to-audio or sync-to-narration scenarios.
- **Example:** Op scheduled at 47 ms → snaps to 60 ms; op at 73 ms → snaps to 60 ms; op at 91 ms → snaps to 120 ms.
- **Test:** Property test — every op's fire-time is a multiple of N.

---

## Visual Highlighting (39–52)

Decorate-layer improvements controlling HOW ops are displayed.

### 39. Insertion Green Fade
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight inline` (default off; existing flag, extend semantics)
- **Description:** Newly inserted chars flash bright green for 200 ms, then fade to the normal syntax-highlighted color over the next 300 ms. Gives a clear "this is new" signal without permanent visual noise.
- **Example:** Char `b` inserted → bright green for 200 ms, fading to default for 300 ms.
- **Test:** Visual snapshot — frame at t=100 ms shows green; frame at t=600 ms shows default color.

### 40. Deletion Red Fade
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight inline` (paired with #39)
- **Description:** About-to-be-deleted chars flash bright red for 150 ms *before* they vanish, so the viewer sees "this is being removed" rather than just disappearing. The char then animates out (fade or shrink).
- **Example:** Char `a` to be deleted → red flash 150 ms, then fade-out 100 ms.
- **Test:** Visual snapshot — frame at t=75 ms shows red; frame at t=300 ms shows no char.

### 41. Overwrite Amber Pulse
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight inline` (extends to `overwrite_insert` ops)
- **Description:** For `overwrite_insert` ops (replace-in-place), the replaced char pulses amber (orange-yellow) for 250 ms — distinct from the green/red of pure inserts/deletes. Visually signals "this char was swapped, not added/removed".
- **Example:** `a` → `b` at col 3 → amber pulse on col 3 for 250 ms.
- **Test:** Visual snapshot — frame at t=125 ms shows amber; no green or red flash.

### 42. Dim Unchanged Lines
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--dim-unchanged` (default off; existing flag, extend)
- **Description:** Lines with no ops (pure keeps) are rendered at 50% brightness (or a configurable `--dim-level`). Focuses the viewer's eye on changed regions. Already partially implemented; extend to support smooth fade-in/out as a line transitions from changed to unchanged.
- **Example:** A 50-line file with 3 changed lines → 47 lines at 50% brightness, 3 at 100%.
- **Test:** Visual snapshot — unchanged lines have brightness < 60%; changed lines at 100%.

### 43. Active Line Highlight
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight-active-line` (default off)
- **Description:** The line currently being edited (containing the active op) gets a subtle background highlight, like an IDE's cursor line. Helps the viewer track which line the animation is on, especially during fast bursts.
- **Example:** Cursor at `(line 47, col 5)` → line 47 has a faint blue background.
- **Test:** Visual snapshot — only one line has the highlight at any time; it follows the active op.

### 44. Cursor Glow
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--cursor-glow` (default off)
- **Description:** Renders a soft radial glow (8 px radius, 30% opacity) around the cursor cell. Makes the cursor more visible during fast animation and gives a subtle "spotlight" feel.
- **Example:** Cursor at `(line 5, col 10)` → a soft yellow glow centered on that cell.
- **Test:** Visual snapshot — glow rendered at cursor position; opacity falls off radially.

### 45. Word-Under-Cursor Bold
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--bold-active-word` (default off)
- **Description:** The whole word containing the cursor (identifier or whitespace run) is rendered bold while the cursor is on it. Helps the viewer track "what is being edited" at a glance, especially when individual char changes are too fast to perceive.
- **Example:** Cursor on the `o` of `foobar` → `foobar` is bold.
- **Test:** Visual snapshot — only the word containing the cursor is bold; neighboring words are normal weight.

### 46. Hunk Background Tint
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--tint-hunks` (default off)
- **Description:** Each hunk gets a faint background tint (green for additions-only, red for deletions-only, yellow for mixed). The tint persists for the duration of the hunk's animation, then fades. Provides a "this is one logical change" visual signal.
- **Example:** A mixed 3-line hunk → 3 lines with faint yellow background.
- **Test:** Visual snapshot — hunks have appropriate tint by type; non-hunk lines have no tint.

### 47. Indent Guide Highlight
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight-indent-guides` (default off)
- **Description:** When a line's indentation changes, the indent guides (vertical lines at each tab stop) for that line are highlighted brightly; other lines' guides stay dim. Helps the viewer see "this block was re-indented" at a glance.
- **Example:** Re-indenting a 5-line block → 5 lines of indent guides flash bright blue.
- **Test:** Visual snapshot — only changed-indent lines have bright guides.

### 48. Bracket Match Pulse
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--pulse-matching-brackets` (default off; language-aware)
- **Description:** When an opening or closing bracket is inserted or deleted, its matched partner pulses briefly (250 ms) to draw the viewer's eye to the pair. Helps understand structural changes like "this `if` block was closed one line earlier".
- **Example:** Insert `}` at line 50 → the matching `{` at line 42 pulses for 250 ms.
- **Test:** Visual snapshot — both brackets in a matched pair pulse together.

### 49. Trailing Whitespace Marker
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--show-trailing-ws` (default off)
- **Description:** On lines whose trailing whitespace changes, render the trailing whitespace chars with a visible marker (red `·` for spaces, `»` for tabs) for the duration of the animation. Helps the viewer see "this line's trailing whitespace was cleaned up".
- **Example:** Line `foo  ` → renders as `foo··` (red dots) while ops are firing.
- **Test:** Visual snapshot — trailing whitespace chars are marked on changed lines; unmarked on unchanged lines.

### 50. Conflict Marker Highlighting
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--highlight-conflicts` (default off; for merge diffs)
- **Description:** When animating a merge conflict resolution, highlights the `<<<<<<<`, `=======`, `>>>>>>>` markers with a distinct color (e.g., magenta) so the viewer can track which side is being kept/discarded.
- **Example:** A 3-way merge hunk → conflict markers magenta, kept-side content normal, discarded-side content dim red.
- **Test:** Visual snapshot — conflict markers are magenta; surrounding content is normal.

### 51. Highlight Only Differences (Inline Diff)
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--inline-diff` (default off)
- **Description:** When a line is modified, only the changed chars are highlighted — the unchanged prefix/suffix are dimmed. Mimics GitHub's inline diff view. Helps the viewer focus on what actually changed within a long line.
- **Example:** `foo = calculateTotal(items)` → `calculateTotal` (the changed word) is highlighted; the rest of the line is dimmed.
- **Test:** Visual snapshot — only changed chars are highlighted; surrounding chars dimmed.

### 52. Color-Blind Safe Default Palette
- **Category:** Visual Highlighting
- **Layer type:** decorate layer
- **Trigger:** `--colorblind-safe` (default off; recommend default-on)
- **Description:** Replaces red/green insert/delete highlights with a color-blind-safe palette (blue/orange or with patterns in addition to color). Uses the Okabe-Ito palette which is tested for all common color-vision deficiencies.
- **Example:** Inserts → blue, deletes → orange; both also get a subtle pattern (solid vs. striped).
- **Test:** Visual snapshot — colors match Okabe-Ito palette; both color and pattern differ between insert/delete.

---

## Semantic (53–65)

Group ops by meaning (function, block, import, etc.) — language-aware layers.

### 53. Function Boundary Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-functions` (default off; requires tree-sitter or `--lang`)
- **Description:** Tags every op with the `function_id` of the enclosing function (or `0` for module-level code). Lets the pace layer animate "all of function `foo`'s changes" as one logical unit, or let the viewer jump "to next function change".
- **Example:** Two functions changed → ops in `fn foo()` have `function_id=1`, ops in `fn bar()` have `function_id=2`.
- **Test:** Snapshot test on multi-function fixtures across languages; assert function IDs partition ops correctly.

### 54. Block-Scope Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-blocks` (default off)
- **Description:** Tags every op with the `block_id` of the enclosing `{...}` or indentation block. Finer-grained than function grouping — useful for "this inner `if` block was modified" navigation.
- **Example:** Function `foo` with a nested `if` → ops in the function but outside the `if` have `block_id=1`; ops in the `if` body have `block_id=2`.
- **Test:** Snapshot test — block IDs are nested correctly; ops in nested blocks have higher IDs.

### 55. Import Reorder Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-import-reorder` (default off)
- **Description:** Detects when imports are *reordered* (not modified) — e.g., `import a; import b` → `import b; import a`. Instead of animating as delete+insert, marks the ops as a `move` with a `from_line` and `to_line`. The animator can render this as a smooth slide rather than delete+insert.
- **Example:** Python: 3 imports reordered → 3 `move` ops with `from_line`/`to_line` instead of 3 deletes + 3 inserts.
- **Test:** Snapshot test on import-reorder fixtures; assert ops are `move` type with correct from/to.

### 56. Rename Refactor Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-rename` (default off)
- **Description:** Detects when an identifier is renamed across multiple locations (e.g., `oldName` → `newName` in 5 places). Tags all the related delete+insert pairs with a shared `rename_id` and the old/new names. The animator can render all 5 changes simultaneously (multi-cursor style) rather than sequentially.
- **Example:** Renaming `foo` to `bar` in 5 places → 5 pairs tagged `rename_id=7, old="foo", new="bar"`.
- **Test:** Snapshot test — rename-paired ops share an ID; old/new names match.

### 57. Extract Method Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-extract-method` (default off; experimental)
- **Description:** Detects the extract-method refactor: code is deleted from one function and a very similar block is inserted into a new function, with a call site added. Tags the three regions (delete, insert, call-site-insert) with `extract_id`. The animator can render them as "code moved from here to there, with a call inserted".
- **Example:** 10 lines extracted from `fn foo` into new `fn bar`, with `bar()` inserted at the original location → all three regions tagged `extract_id=3`.
- **Test:** Snapshot test on an extract-method fixture; assert three regions share an ID.

### 58. Parameter Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-params` (default off)
- **Description:** Tags all ops within a function's parameter list with `params_id`. When a function signature changes (add/remove/reorder params), the whole parameter list is animated as one unit, rather than char-by-char. Helps viewers parse "the function's interface changed" as a single event.
- **Example:** `def foo(a, b)` → `def foo(a, b, c)` → the 3 new chars (` , c`) share `params_id=5`.
- **Test:** Snapshot test on signature-change fixtures; assert param-list ops share an ID.

### 59. Comment Movement Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-comment-move` (default off)
- **Description:** Detects when a comment is moved (not modified) — similar to #55 but for comments. Marks the ops as a `comment_move` with `from_line`/`to_line`. Prevents the visual oddity of "comment deleted here, identical comment inserted 10 lines down".
- **Example:** A 3-line comment moved from line 10 to line 25 → 3 `comment_move` ops instead of 3 deletes + 3 inserts.
- **Test:** Snapshot test — moved comments are `comment_move` type; identical comments are detected via fuzzy match.

### 60. String-Literal Movement Detection
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-string-move` (default off)
- **Description:** Like #59, but for string literals. Detects when a string (especially a long one) is moved verbatim. Marks the ops as `string_move` so the animator can slide the string rather than delete+insert.
- **Example:** `"Hello, world!"` moved from one variable to another → `string_move` op instead of delete+insert.
- **Test:** Snapshot test — moved strings are `string_move` type; fuzzy match handles whitespace-only changes.

### 61. Numeric Literal Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-numbers` (default off)
- **Description:** Tags consecutive digit characters within a numeric literal (e.g., `12345`) with `num_id`. When a number changes, all its digits animate as one cluster — preventing the visual oddity of one digit changing at a time. Handles hex (`0x...`), octal, binary, and floats.
- **Example:** `count = 100` → `count = 250` → 3 digit ops share `num_id=12`.
- **Test:** Snapshot test on numeric-literal fixtures; assert digit runs share an ID.

### 62. Operator-Aware Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-operators` (default off)
- **Description:** When the operator in an expression changes (e.g., `x += 1` → `x -= 1`, or `a == b` → `a != b`), tags the operator chars with `op_id` so they animate as one unit. Prevents the "deletion of `=` then insertion of `=` while `-` is added separately" confusion.
- **Example:** `+=` → `-=` → the 2 changed chars share `op_id=4`.
- **Test:** Snapshot test on operator-change fixtures; assert operator chars share an ID.

### 63. Annotation / Decorator Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-annotations` (default off)
- **Description:** Tags all ops within an annotation (`@decorator(...)` in Python/Java, `#[attr]` in Rust, `@interface` in Java) with `ann_id`. Helps viewers parse "this annotation was added/modified" as one event.
- **Example:** Adding `@dataclass` to a Python class → 9 chars share `ann_id=2`.
- **Test:** Snapshot test on annotation fixtures across languages.

### 64. Type Signature Grouping
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-types` (default off)
- **Description:** Tags all ops within a type signature (e.g., `: int` in Python type hints, `<T, U>` in Java generics, `-> Result<T>` in Rust) with `type_id`. When types change, they animate as one cluster.
- **Example:** `def foo() -> int` → `def foo() -> str` → 3 changed chars share `type_id=6`.
- **Test:** Snapshot test on type-annotation fixtures.

### 65. Punctuation Pair Locking
- **Category:** Semantic
- **Layer type:** postprocess layer (language-aware)
- **Trigger:** `--semantic-punct-pairs` (default off)
- **Description:** Tags matched punctuation pairs (`()`, `[]`, `{}`, `""`, `''`) and all ops *between* them with `punct_pair_id`. When a pair is inserted or deleted, the entire pair (and contents) animates as one unit — preventing the "open paren appears, content trickles in, close paren appears" confusion.
- **Example:** Adding `[1, 2, 3]` → all 7 chars share `punct_pair_id=8`.
- **Test:** Snapshot test on punct-pair fixtures; assert matched pairs and contents share an ID.

---

## Context (66–76)

Layers that preserve or reveal surrounding context.

### 66. Sticky Anchor Lines
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--sticky-anchors` (default off)
- **Description:** When the animation is inside a function body, the function's signature line is "sticky" — it stays visible at the top of the viewport even when the body scrolls past. Helps the viewer remember "I'm inside `fn foo(a, b)`" without scrolling back up.
- **Example:** Animating changes at line 200 of a 250-line function → line 1 (the signature) sticks to the top of the viewport.
- **Test:** Visual snapshot — sticky line is at viewport top; scrolls away only when the function ends.

### 67. Pre-Change Snapshot Preview
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--show-old-ghost` (default off)
- **Description:** Before deleting a line's content, briefly shows a "ghost" of the original line in dim red strikethrough for 300 ms. Helps the viewer register "this is what was here" before it vanishes. Pairs with #40 (red fade).
- **Example:** Line `foo = bar` is being deleted → for 300 ms, `foo = bar` shows in dim red strikethrough, then fades out.
- **Test:** Visual snapshot — ghost rendered for 300 ms before deletion.

### 68. Post-Change Preview Fade-In
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--show-new-ghost` (default off)
- **Description:** Before inserting a new line, briefly shows a "ghost" of the new line in dim green for 300 ms — then the line "solidifies" as the insert ops fire. Gives the viewer a preview of "here's what's coming".
- **Example:** About to insert `foo = bar` → dim green `foo = bar` for 300 ms, then chars type out in bright green.
- **Test:** Visual snapshot — ghost rendered for 300 ms before insertion begins.

### 69. Surrounding Hunk Context
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--context N` (default 3; like `git diff --context`)
- **Description:** Always shows N lines of context above and below each hunk, even when those lines are pure keeps. Helps the viewer maintain spatial orientation ("this hunk is inside the `for` loop, 5 lines after the function start").
- **Example:** A hunk at line 50 → lines 47–53 are shown, with 47–49 and 51–53 dimmed (per #42).
- **Test:** Visual snapshot — N context lines visible around each hunk.

### 70. Minimap Overlay
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--minimap` (default off)
- **Description:** Renders a tiny minimap of the entire file on the right side of the viewport, with the changed regions highlighted in bright colors. A vertical "you are here" indicator tracks the current animation position. Like VS Code's minimap.
- **Example:** A 1000-line file with 5 hunks → minimap shows 5 bright bars; cursor at line 250 → "you are here" arrow at the 25% mark.
- **Test:** Visual snapshot — minimap rendered; hunks highlighted; position indicator correct.

### 71. File Outline Side Panel
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--outline` (default off; requires tree-sitter)
- **Description:** Shows a side panel with the file's outline (classes, functions, methods) and highlights the one currently being animated. Lets the viewer navigate "by structure" — click `fn foo` to jump to its changes.
- **Example:** Python file with 3 classes → side panel lists them; cursor in `Bar.baz()` → that outline entry is highlighted.
- **Test:** Visual snapshot — outline matches file structure; current location highlighted.

### 72. Breadcrumb Path
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--breadcrumbs` (default off)
- **Description:** Renders a breadcrumb trail at the top of the viewport: `src/foo.py › class Bar › fn baz › line 47`. Updates as the cursor moves through the file. Helps the viewer maintain "where am I in the file structure" without mental bookkeeping.
- **Example:** Cursor moves from `Bar.baz` line 47 to `Bar.qux` line 80 → breadcrumb updates `Bar.baz` → `Bar.qux`.
- **Test:** Visual snapshot — breadcrumb matches the cursor's enclosing scopes.

### 73. Lineage Indicator
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--lineage` (default off)
- **Description:** For moved lines (detected via #55, #59, #60), shows a faint arrow from the line's old position to its new position. Helps the viewer track "this line came from over there".
- **Example:** Line moved from line 10 to line 25 → faint arrow drawn from `(line 10, col 1)` to `(line 25, col 1)`.
- **Test:** Visual snapshot — arrow drawn between matched from/to positions.

### 74. Diff Stat HUD
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--diff-stat-hud` (default off)
- **Description:** Renders a persistent HUD (top-right corner) showing `+N -M` (lines added/removed) and a progress bar (ops applied / total ops). Updates in real time. Helps the viewer gauge "how big is this diff, how far through am I".
- **Example:** 50-op diff, 20 applied → HUD shows `+15 -10` and a 40% progress bar.
- **Test:** Visual snapshot — HUD renders; values match actual op counts.

### 75. Hunk Number Indicator
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--hunk-indicator` (default off)
- **Description:** Renders a small "Hunk 3/7" indicator that updates as the animation moves between hunks. Helps the viewer track "how many logical changes are in this diff, which one am I on".
- **Example:** 7-hunk diff, currently animating hunk 3 → "Hunk 3/7" shown in the corner.
- **Test:** Visual snapshot — indicator updates when the active hunk changes.

### 76. Where-Am-I Marker
- **Category:** Context
- **Layer type:** decorate layer
- **Trigger:** `--whereami` (default off)
- **Description:** Renders a persistent vertical line in the left margin marking the active line. Even when the viewport scrolls, the marker stays visible (like a bookmark). Helps the viewer track "where in the file is the animation right now" without re-finding the cursor.
- **Example:** Active line 47 → a vertical bar in the left margin at row 47's position.
- **Test:** Visual snapshot — marker rendered at active line; updates as cursor moves.

---

## Progressive Disclosure (77–85)

Reveal complexity gradually — start simple, deepen on demand.

### 77. Hunk-by-Hunk Mode
- **Category:** Progressive Disclosure
- **Layer type:** animator feature
- **Trigger:** `--hunk-step` (default off; space advances to next hunk)
- **Description:** Pauses after each hunk completes; the user presses `space` to start the next hunk. Lets the viewer control the pace at hunk granularity — review the change, then move on. Pairs well with `--context N` (#69).
- **Example:** 5-hunk diff → hunk 1 animates, pauses; user reviews; space → hunk 2; etc.
- **Test:** Integration test — animator pauses after each hunk; space advances.

### 78. Zoom-In Detail Reveal
- **Category:** Progressive Disclosure
- **Layer type:** animator feature
- **Trigger:** `--zoom-reveal` (default off)
- **Description:** Starts the animation at file-level view (whole file visible, hunks as bright bars), then progressively zooms into the active hunk as the animation proceeds. Three levels: file → hunk → char. Helps the viewer build a mental model of "the whole change" before drilling in.
- **Example:** Start: file-level (10 px per line). 1 s in: zoom to hunk-level (20 px per line). 2 s in: zoom to char-level (full size).
- **Test:** Visual snapshot at t=0, t=1s, t=2s — zoom level matches schedule.

### 79. Layered Highlight Reveal
- **Category:** Progressive Disclosure
- **Layer type:** decorate layer
- **Trigger:** `--layered-reveal` (default off)
- **Description:** For each hunk, first highlights the entire changed region at line-level (300 ms), then zooms to word-level (300 ms), then to char-level (animation). Three-tier progressive disclosure helps the viewer parse "what region changed, what words changed, what chars changed" in that order.
- **Example:** Hunk with 3 changed lines → all 3 lines highlighted (300 ms), then 5 changed words highlighted (300 ms), then 12 char ops animate.
- **Test:** Visual snapshot at t=0, t=300, t=600 — highlight granularity matches schedule.

### 80. Summary-First Animation
- **Category:** Progressive Disclosure
- **Layer type:** animator feature
- **Trigger:** `--summary-first` (default off)
- **Description:** Shows the diff stat (`+N -M lines`) and a list of hunks (one-line summaries) for 2 seconds before starting the animation. Lets the viewer build expectations ("this is a 50-line change in 3 hunks") before the char-level animation begins.
- **Example:** Start: `+15 -10 in 3 hunks` + hunk summaries. 2 s later: animation begins.
- **Test:** Integration test — summary shown for 2 s; then animation starts.

### 81. Branching Replay
- **Category:** Progressive Disclosure
- **Layer type:** animator feature
- **Trigger:** `--branch-replay` (default off; for git branches)
- **Description:** When animating a diff between two branches, first shows all the commits on each branch as nodes, then animates each commit's diff one at a time. Helps the viewer understand "what does each commit contribute" rather than seeing only the cumulative diff.
- **Example:** Branch `feature` has 3 commits → show 3 nodes; animate commit 1, then 2, then 3.
- **Test:** Integration test — node graph shown; each commit's diff animated in order.

### 82. Stepwise Refinement
- **Category:** Progressive Disclosure
- **Layer type:** postprocess layer
- **Trigger:** `--stepwise` (default off)
- **Description:** Produces multiple op streams at different granularities: hunk-level (one op per hunk), word-level (one op per word), char-level (current default). The animator can switch between granularities on demand (e.g., `1`/`2`/`3` keys). Useful for "give me the overview, then the details".
- **Example:** `--stepwise` produces three streams; user presses `1` for hunk view, `3` for char view.
- **Test:** Property test — three streams all round-trip to the same final buffer.

### 83. Hover-to-Expand
- **Category:** Progressive Disclosure
- **Layer type:** animator feature
- **Trigger:** `--hover-expand` (default off; interactive mode)
- **Description:** In hunk-level or word-level mode, hovering over a collapsed region expands it to char-level (in a tooltip or inline) without advancing the animation. Lets the viewer "drill in" on a specific change without disrupting the overall flow.
- **Example:** Hunk view; user hovers over hunk 2 → hunk 2 expands to show char-level changes in a tooltip.
- **Test:** Integration test — hover triggers expansion; un-hover collapses.

### 84. Expandable Diff Stats
- **Category:** Progressive Disclosure
- **Layer type:** decorate layer
- **Trigger:** `--expandable-stats` (default off; pairs with #74)
- **Description:** The diff stat HUD (from #74) is clickable — click a hunk's bar to expand into a detailed view of that hunk's ops, click again to collapse. Lets the viewer explore the diff structure without leaving the main animation view.
- **Example:** HUD shows `+15 -10`; click → expands to show 5 hunks with per-hunk stats; click a hunk → shows its 12 ops.
- **Test:** Integration test — click expands; click again collapses.

### 85. Skip-Identical Sections
- **Category:** Progressive Disclosure
- **Layer type:** postprocess layer
- **Trigger:** `--skip-identical N` (default off; N = threshold lines)
- **Description:** Auto-collapses runs of >N unchanged lines into a "⋯ N unchanged lines ⋯" marker instead of animating through them. Speeds up long diffs by skipping dead space, while preserving the changed regions at full fidelity.
- **Example:** A 200-line diff with a 50-line unchanged run in the middle → the run collapses to `⋯ 50 unchanged ⋯`.
- **Test:** Snapshot test — runs > N are collapsed; runs ≤ N are kept.

---

## Accessibility & UX (86–92)

Keyboard, reduced motion, pause points — for diverse viewers.

### 86. Reduced Motion Mode
- **Category:** Accessibility & UX
- **Layer type:** pace layer
- **Trigger:** `--reduced-motion` (default off; auto-on if `$DIFFVIM_REDUCED_MOTION=1` or terminal reports `prefers-reduced-motion`)
- **Description:** Skips all animations: shows the final buffer immediately with no char-by-char playback. Only the diff highlighting (insert = green, delete = red) is shown statically. Essential for viewers with vestibular disorders or those who find animation distracting.
- **Example:** 50-op diff → no animation; final buffer shown with green/red highlights only.
- **Test:** Visual snapshot — no intermediate frames; final buffer matches expected.

### 87. Keyboard Step Mode
- **Category:** Accessibility & UX
- **Layer type:** animator feature
- **Trigger:** `--step` (default off; `space` advances one op, `b` goes back)
- **Description:** Pauses the animation at op 0; each `space` press advances exactly one op, each `b` goes back one. Lets the viewer inspect each individual change at their own pace. Essential for accessibility (keyboard-only users) and for code review.
- **Example:** 50-op diff → start at op 0; user presses space 50 times to walk through.
- **Test:** Integration test — space advances one op; b goes back one; no auto-advance.

### 88. Pause-on-Click
- **Category:** Accessibility & UX
- **Layer type:** animator feature
- **Trigger:** default-on (click anywhere to pause/resume)
- **Description:** Clicking anywhere in the viewport pauses the animation; clicking again resumes. Provides a low-friction way to "stop the world" without hunting for a key. Especially useful for mouse-driven users.
- **Example:** Animation playing; user clicks → paused; user clicks → resumed.
- **Test:** Integration test — click toggles paused state.

### 89. Bookmark / Jump Points
- **Category:** Accessibility & UX
- **Layer type:** animator feature
- **Trigger:** `m` to set bookmark, `'` to jump to next bookmark
- **Description:** Lets the user set bookmarks at specific op indices (press `m` while paused) and jump back to them (press `'`). Useful for "I want to come back to this change later" workflows, e.g., during code review.
- **Example:** At op 23, user presses `m` → bookmark set. At op 50, presses `'` → jumps back to op 23.
- **Test:** Integration test — bookmark set; jump returns to bookmarked op.

### 90. Speed Slider
- **Category:** Accessibility & UX
- **Layer type:** animator feature
- **Trigger:** `--slider` (default off; or `+`/`-` for discrete control)
- **Description:** Renders a horizontal speed slider at the bottom of the viewport, draggable from 0.1× to 10×. Provides finer speed control than the existing `+`/`-` keys (which step in fixed increments). Especially useful for finding the "right" speed for a given diff.
- **Example:** User drags slider to 1.5× → animation runs at 1.5× default speed.
- **Test:** Integration test — slider drag changes speed; current speed displayed.

### 91. Color-Blind Patterns
- **Category:** Accessibility & UX
- **Layer type:** decorate layer
- **Trigger:** `--patterns` (default off; auto-on if `--colorblind-safe`)
- **Description:** In addition to colors (#52), overlays subtle patterns on inserts (diagonal stripes) and deletes (dots). Doubles up the visual signal so color-blind viewers can distinguish insert vs. delete even without color.
- **Example:** Inserted chars → green with diagonal stripes; deleted chars → red with dots.
- **Test:** Visual snapshot — patterns rendered on top of colors.

### 92. Screen Reader ARIA Live Region
- **Category:** Accessibility & UX
- **Layer type:** animator feature
- **Trigger:** `--aria` (default off; for web-based animator)
- **Description:** In the web-based animator (#99-style), emits ARIA live-region announcements for each hunk: "Hunk 3 of 7: 5 lines added, 2 lines removed in function `calculate_total`". Lets screen-reader users follow the diff without seeing the animation.
- **Example:** Hunk completes → ARIA region updated with the announcement.
- **Test:** Integration test — ARIA region text matches hunk summary.

---

## Advanced/Experimental (93–100)

Cutting-edge ideas — higher risk, higher reward.

### 93. AI-Powered Semantic Grouping
- **Category:** Advanced/Experimental
- **Layer type:** postprocess layer (LLM-assisted)
- **Trigger:** `--ai-group` (default off; requires API key)
- **Description:** Sends the diff to an LLM with a prompt like "group these changes into semantic units (refactor, bugfix, style, etc.) and tag each op with a `semantic_group_id` and a one-line label". The animator can show the labels as hunk headers ("Refactor: extract method", "Bugfix: null check"). Experimental — depends on LLM quality and cost.
- **Example:** Diff with 3 logical changes → LLM tags ops with 3 group IDs and labels: "Refactor: extract method", "Bugfix: null check", "Style: rename variable".
- **Test:** Integration test with a mock LLM — given a fixed response, assert ops are tagged correctly.

### 94. Predictive Cursor Path
- **Category:** Advanced/Experimental
- **Layer type:** pace layer
- **Trigger:** `--predictive-cursor` (default off; experimental)
- **Description:** Pre-computes the cursor's path through the next N ops (default 10) and renders a faint "ghost trail" of the path before the cursor actually moves there. Helps the viewer anticipate "the cursor is going to jump up to line 47 next" rather than being surprised. Trade-off: visual clutter if too long.
- **Example:** 10 ops ahead → ghost trail rendered from current position through the next 10 op positions, fading out.
- **Test:** Visual snapshot — ghost trail rendered; trail length matches N.

### 95. Multi-Cursor Animation
- **Category:** Advanced/Experimental
- **Layer type:** animator feature
- **Trigger:** `--multi-cursor` (default off; pairs with #56 rename detection)
- **Description:** When multiple ops are tagged with the same `rename_id` (#56), the animator renders a separate cursor at each location and animates them simultaneously. Mimics multi-cursor editing in modern editors. Visually striking for rename refactors — "watch the rename ripple across the file".
- **Example:** Rename `foo` to `bar` in 5 places → 5 cursors render at the 5 locations, all typing `bar` simultaneously.
- **Test:** Visual snapshot — N cursors rendered; all advance in lockstep.

### 96. Replay Branching Tree
- **Category:** Advanced/Experimental
- **Layer type:** animator feature
- **Trigger:** `--branch-tree` (default off; for git history)
- **Description:** For a range of commits, shows a tree of branches/merges alongside the animation. As the animation proceeds through commits, the corresponding node in the tree is highlighted. Helps the viewer understand "this change came from branch X, merged into main at commit Y".
- **Example:** 10 commits with 2 branches → tree shown; animation at commit 5 → node 5 highlighted.
- **Test:** Integration test — tree matches git log; current commit highlighted.

### 97. Heatmap Overlay
- **Category:** Advanced/Experimental
- **Layer type:** decorate layer
- **Trigger:** `--heatmap` (default off; for long-running animations)
- **Description:** Overlays a heatmap on the file showing which lines have been "active" (changed) the most frequently over the course of a long animation (e.g., a 100-commit replay). Hot lines = frequently changed; cold lines = untouched. Helps identify "hotspots" in the codebase.
- **Example:** 100-commit replay → lines changed 50+ times glow bright red; lines never changed stay blue.
- **Test:** Visual snapshot — heatmap intensity matches change frequency.

### 98. Time-Travel Scrubbing
- **Category:** Advanced/Experimental
- **Layer type:** animator feature
- **Trigger:** `--time-travel` (default off)
- **Description:** Renders a scrubbable timeline (like a video player) at the bottom of the viewport. The user can drag the playhead to any point in the op stream and see the buffer state at that point. Lets the viewer "rewind" to inspect an earlier change without restarting the animation.
- **Example:** 100-op animation; user drags playhead to op 50 → buffer shows state at op 50.
- **Test:** Integration test — playhead position matches buffer state.

### 99. Collaborative Replay Sync
- **Category:** Advanced/Experimental
- **Layer type:** animator feature
- **Trigger:** `--sync URL` (default off; experimental, requires server)
- **Description:** Multiple viewers can watch the same animation in sync over a network (WebRTC or WebSocket). Any viewer can pause/resume/seek, and all others follow. Useful for remote code review, teaching, or pair-programming demos.
- **Example:** Viewer A pauses at op 23 → viewer B's animation also pauses at op 23.
- **Test:** Integration test with two mock clients — pause on A reflects on B within 200 ms.

### 100. Generative Soundtrack
- **Category:** Advanced/Experimental
- **Layer type:** decorate layer
- **Trigger:** `--soundtrack` (default off; experimental)
- **Description:** Generates ambient sound tied to op types: insert = soft "click" (high pitch), delete = soft "thud" (low pitch), `\n` = soft "chime". Volume and tempo scale with op density. Creates a meditative, ASMR-like experience for long diffs. Especially nice for screen recordings.
- **Example:** 50-op diff with mixed inserts/deletes → ambient soundscape with rhythmic clicks and thuds.
- **Test:** Audio snapshot — sound events match op types; volume scales with density.

---

## Summary

| Category | Range | Count |
|----------|-------|-------|
| Op Ordering | 1–12 | 12 |
| Op Grouping | 13–24 | 12 |
| Timing & Pacing | 25–38 | 14 |
| Visual Highlighting | 39–52 | 14 |
| Semantic | 53–65 | 13 |
| Context | 66–76 | 11 |
| Progressive Disclosure | 77–85 | 9 |
| Accessibility & UX | 86–92 | 7 |
| Advanced/Experimental | 93–100 | 8 |
| **Total** | | **100** |

## Layer Type Distribution

| Layer type | Count | Examples |
|------------|-------|----------|
| postprocess layer | ~45 | Op Ordering, Op Grouping, Semantic |
| pace layer | ~14 | Timing & Pacing |
| decorate layer | ~25 | Visual Highlighting, Context, parts of Progressive Disclosure |
| animator feature | ~16 | Accessibility, parts of Progressive Disclosure, Advanced |

## Trigger Conventions

- **default-on**: applied automatically; disable with a `--no-<name>` flag.
- **default-off**: opt-in via `--<name>` flag.
- **env var**: `$DIFFVIM_<NAME>=1` (e.g., `DIFFVIM_REDUCED_MOTION`).
- **language-aware**: requires `--lang <lang>` or auto-detection from file extension; uses tree-sitter or a simpler regex-based parser.

## Testing Strategy

Every layer should have:

1. **Unit test** — input op stream → expected output op stream (snapshot).
2. **Round-trip property test** — applying the layer's output to the old buffer yields the new buffer (i.e., the layer preserves semantic correctness).
3. **Visual snapshot test** — for decorate/pace layers, golden-image comparison of rendered frames at specific timestamps.
4. **Performance test** — layer completes in <100 ms for a 10,000-op stream (the upper bound of real-world diffs).

## Research Basis

These improvements draw on:

- **Cognitive load theory** (Sweller): small chunks, progressive disclosure (#77–85).
- **Animation principles** (Disney): anticipation (#35), follow-through (#36), squash-stretch (#37).
- **Code visualization research** (e.g., Nakano et al.): preserving spatial context (#66–76).
- **Diff tool UX** (GitHub, GitLab, difftastic): inline diff (#51), word-level highlighting (#45).
- **Accessibility guidelines** (WCAG 2.1): reduced motion (#86), patterns in addition to color (#91), screen reader support (#92).
- **Eye-tracking research** on code reading (Busjahn et al.): active line highlight (#43), breadcrumbs (#72).

## Next Actions

1. **Prioritize** — rank by impact/cost. Recommended high-impact, low-cost first: #1, #8, #25, #39–#41, #42, #69, #86.
2. **Prototype** — implement each as a standalone `pp_layer_*.c` binary for isolated testing (matches the existing `pp_overwrite` / `pp_indent_last` / `pp_layer1` pattern).
3. **Integrate** — wire into `postprocess.c` (for postprocess layers), `pace.c` (for pace layers), `decorate.c` (for decorate layers), or the animator loop (for animator features).
4. **Document** — each layer gets a `docs/PP_LAYER_<NAME>.md` file (matching the existing `PP_LAYER_OVERWRITE.md` pattern).
5. **Test** — add a `tests/test_<layer_name>.pl` for each (matching the existing `test_indent_last.pl` / `test_overwrite_layer.sh` pattern).
