# Animation Quality Strategy — Reframing the Problem

## Why we've been failing

Every bug report about "the animation looks bad" has been treated as a
byte-level correctness problem. We verify `snap == new` and declare
victory. But `snap == new` only proves the final buffer is right — it
says **nothing** about whether the *path* the animation took to get
there looks like a human typed it.

The architecture is the problem:

```
char-level LCS diff  →  postprocess layers  →  pace  →  animator
       ↑                        ↑
   produces ops           try to fix the ops
   that don't map          into something human
   to human edits          but can only reorder
```

The diff engine emits character-level insert/delete operations. The
layers (`reorder`, `overwrite`, `indent_last`, `line_delete_in_place`,
`split_in_place`, `join_insert_in_place`, `batch_whitespace`,
`skip_indent`, `line_replace`) are all **patch-up layers** — they
reorder, batch, or atomicize char ops, but none of them *understand
what the change is*.

### Concrete evidence: `hello` → `greet`

For the change `def hello():` → `def greet():`, the current pipeline
produces:

```
keep d e f space
delete h
insert g r
keep e
delete l l o
insert e t
keep ( ) :
```

The LCS found `e` as a common character and split the change there.
So the animation does:

1. Backspace `h`
2. Type `g`, `r`
3. Leave `e` alone
4. Backspace `l`, `l`, `o`
5. Type `e`, `t`

That is not how any human replaces a word. A human either selects the
word and types over it, or backspaces the whole word and retypes. The
LCS minimal-edit-property is **wrong** for animation — it optimizes
for char count, not for human legibility.

### The same pattern at every scale

- **Line move**: a block of 5 lines moves up 10 lines. The LCS sees
  this as "delete 5 lines here, insert 5 lines there" — 10 separate
  ops. A human sees "cut, paste."
- **Indentation change**: a block is re-indented by 4 spaces. The LCS
  emits 4 space-deletes per line × N lines. A human sees "re-indent
  the block."
- **Rename**: `getUser` → `fetchUser` across 8 occurrences. The LCS
  emits 8 independent char-diffs. A human sees "rename, applied
  everywhere at once" (multi-cursor).
- **Argument reorder**: `f(a, b, c)` → `f(c, a, b)`. The LCS deletes
  and re-inserts. A human sees "swap."

Every layer we have is trying to detect these patterns *after the
fact* from the char op stream. That is too late and too lossy.

---

## The reframe

**Stop treating the diff as the source of truth.** The diff is one
input. The source of truth is the **edit category** — what kind of
change the human was making. The pipeline should be:

```
old + new
    ↓
 ┌──────────────────────────────┐
 │  Edit categorizer            │
 │  (classifies each hunk as    │
 │   a semantic edit type)      │
 └──────────────────────────────┘
    ↓
 edit categories (one per hunk)
    ↓
 ┌──────────────────────────────┐
 │  Per-category renderer       │
 │  (each category has its own  │
 │   animation pattern)         │
 └──────────────────────────────┘
    ↓
 animator op stream
    ↓
 animator
```

The categorizer is the new piece. The renderers replace most existing
layers. The animator itself stays the same.

---

## Phase 1 — Corpus analysis (do this first, before any code)

**Goal:** Build an empirical histogram of what real code changes
actually look like, so the taxonomy in Phase 2 is grounded in data,
not vibes.

### Source corpora

1. **Existing test corpus** — `tests/minimal/*` (27 cases) and
   `tests/examples/*` (41 cases). Tag each case with its dominant
   edit category.
2. **Open-source git histories** — clone ~10 popular repos across
   languages (Python: requests, flask; JS: express, lodash; Go: gorilla/mux,
   cobra; Rust: serde, tokio; Java: guava; Ruby: rails subset). Sample
   ~500 commits total, evenly distributed across the repos. For each
   commit, take the diff of every modified file and categorize each
   hunk.
3. **This project's own history** — `git log` on gitanim itself, since
   we know the context. Useful as a small validation set.

### Method

For each hunk in each diff:

- Run the current char-level diff.
- Also run a structural diff (difftastic or gumtree-style AST diff).
- Record: line count, char count, AST node count, whether lines were
  added / deleted / modified / moved, whether the change is
  intra-line or multi-line, whether whitespace-only, whether it
  touches identifiers, etc.
- Cluster the hunks by these features.
- Name each cluster.

### Output

A table like:

```
Category              % of hunks   Median lines   Example
-------------------   ----------   ------------   --------------------
typo_fix              12%          1              recieve → receive
word_replace          18%          1              getUser → fetchUser
literal_replace       9%           1              x = 5 → x = 10
line_insert           14%          1              (new line at EOF)
line_delete           11%          1              (removed statement)
line_replace          8%           1              print(a) → print(b)
block_insert          7%           4-12           (new function body)
block_delete          4%           3-10           (removed method)
block_move            3%           3-8            (cut-paste)
indent_change         5%           2-15           re-indent block
rename_multi          2%           5-30           getUser → fetchUser ×8
reorder_args          1%           1              f(a,b) → f(b,a)
comment_add           4%           1-5            // new comment
import_change         2%           1-3            add/remove imports
format_only           6%           1-20           whitespace/clippy
other                 4%           varies         (uncategorized)
```

(Numbers are illustrative — Phase 1 produces the real ones.)

### Deliverable

- `analysis/edit_taxonomy.md` — the table + per-category examples
  + the raw data CSV.
- `analysis/corpus_sampler.py` — script that pulls the OS corpus and
  runs the categorization, so it can be re-run as the taxonomy
  evolves.

---

## Phase 2 — Edit taxonomy

Based on Phase 1 data, lock in a closed set of edit categories. The
set must be:

- **Disjoint** — each hunk maps to exactly one primary category.
  (Mixed hunks get decomposed into multiple category instances.)
- **Animation-meaningful** — each category implies a distinct
  animation pattern. If two categories would animate the same way,
  merge them.
- **Small** — aim for 10–15 categories. More than that and we're back
  to char-ops with extra steps.

Proposed starting taxonomy (to be revised after Phase 1):

```
intra_line:
  typo_fix           # 1-3 char change inside a word
  word_replace       # whole token/identifier change
  literal_replace    # numeric/string literal change
  punct_change       # syntax/punctuation only (, ; ( [ etc.)

line_level:
  line_insert        # new line, no neighbor change
  line_delete        # removed line
  line_replace       # one line swapped for another

block_level:
  block_insert       # 2+ contiguous new lines
  block_delete       # 2+ contiguous removed lines
  block_move         # 2+ lines relocated (cut-paste)
  block_replace      # 2+ lines swapped for 2+ others

structural:
  indent_change      # whitespace-only re-indentation
  rename_multi       # same identifier changed on N lines
  reorder            # arguments/fields/methods permuted

noise:
  format_only        # whitespace-only, no semantic change
  comment_change     # comment add/remove/edit
  import_change      # import/using/require line changes
```

### Disambiguation rules

The categorizer needs deterministic rules for "which category wins"
when a hunk matches several. Examples:

- `getUser` → `fetchUser` on 1 line = `word_replace` (not `rename_multi`
  unless N≥2 lines).
- A block that is re-indented *and* has one line modified = split into
  `indent_change` (the whitespace) + `line_replace` (the content).
- A line that is deleted in one place and an identical line inserted
  elsewhere = `block_move` (move detection, not separate
  `line_delete` + `line_insert`).

These rules are the hard part of Phase 2. They get encoded in the
categorizer.

### Deliverable

- `docs/design/EDIT_TAXONOMY.md` — the locked taxonomy with rules.
- `animator/categorize/` — new directory for the categorizer code.

---

## Phase 3 — Per-category renderers

Each category gets its own renderer that emits animator ops in the
pattern a human would produce. Examples:

### `typo_fix` (1–3 char correction inside a word)

```
Pattern: backspace N times, type M chars
Cursor: stays at the error
Speed: fast (a real typo correction is quick)
```

Renderer emits: `delete × N` (contiguous), then `insert × M`
(contiguous), no interleaving. No need for `reorder` — the renderer
already emits them in the right order.

### `word_replace` (whole token changes)

```
Pattern: select word, type over it
Visual: word highlights briefly, then chars overwrite in place
```

Renderer emits: `select word` (a new animator op type), then
`overwrite_insert × M` with the new word. The animator renders
"select" as a brief highlight, then the overwrite happens in place
without the backspace flicker.

This **requires adding a `select` op** to the animator. That is a
real change, but a small one — the animator already has `keep`,
`insert`, `delete`, `overwrite_insert`; adding `select` is one more.

### `line_insert` / `line_delete` / `line_replace`

These already have layers (`line_delete_in_place`, `line_replace`).
The difference is that the categorizer *guarantees* they only fire
when the change really is a single line, not when a char-diff happens
to span one line. No more heuristic detection.

### `block_move`

```
Pattern: cut at source, paste at destination
Visual: source block lifts out (brief flash), cursor jumps to dest,
        block materializes line-by-line
```

Renderer emits: `block_cut` (new op) at source, `cursor_jump` (new
op) to destination, then `line_insert × N`. The animator renders
`block_cut` as a brief fade-out, `cursor_jump` as a fast slide.

### `indent_change`

```
Pattern: re-indent whole block in one motion
Visual: block shifts left/right by N columns simultaneously,
        not 4 space-deletes × N lines
```

Renderer emits: `indent_shift` (new op) with delta. Animator applies
the shift in one animated step.

### `rename_multi`

```
Pattern: multi-cursor rename
Visual: all N occurrences highlight simultaneously, then change
        in lockstep
```

Renderer emits: `select × N` (one per occurrence), then
`overwrite_insert × M` per occurrence. Animator renders the
multi-cursor effect.

### `reorder` (arguments/fields)

```
Pattern: cut A, paste after B
Visual: argument A lifts, slides past B, drops
```

Renderer emits: `select A`, `cut`, `cursor_jump to after B`,
`paste`. Three ops instead of N deletes + N inserts.

### Categories that don't need a new renderer

`format_only`, `comment_change`, `import_change` — these can use
existing insert/delete patterns. They're in the taxonomy so the
categorizer can route them to a "fast/quiet" pacing profile (don't
dwell on reformatting).

### Deliverable

- `animator/render/` — one renderer file per category.
- New animator op types: `select`, `block_cut`, `cursor_jump`,
  `indent_shift`, `paste`. (Not all at once — see Phase 4.)
- The existing layers (`reorder`, `overwrite`, `indent_last`,
  `split_in_place`, `join_insert_in_place`, `batch_whitespace`,
  `skip_indent`, `line_replace`) become **deprecated** — kept around
  for one release as a fallback, then removed. The categorizer +
  renderers should make them obsolete.

---

## Phase 4 — Validation (this is the part we've been skipping)

`snap == target` is necessary but not sufficient. We need tests that
actually catch "looks bad."

### Structural op-stream tests

For each (category, example) pair, assert the rendered op stream
matches a hand-written expected pattern. Example for `word_replace`:

```
input:    hello → greet
expected: select word[4:9], overwrite_insert 'g','r','e','e','t'
forbidden: any delete op inside the word
```

This test would have caught the `hello → greet` bug at the head of
this doc. We have no such test today.

### Property tests per category

- `word_replace`: the rendered stream contains exactly 1 `select` and
  0 `delete` ops inside the word.
- `block_move`: the rendered stream contains exactly 1 `block_cut` and
  1 `paste`, 0 standalone `delete` or `insert` for the moved lines.
- `indent_change`: the rendered stream contains exactly 1
  `indent_shift` per affected line, 0 individual space ops.
- `rename_multi`: the rendered stream contains N `select` ops (one
  per occurrence), all sharing the same target identifier, followed
  by N `overwrite_insert` sequences — no deletes.

These are checkable properties of the op stream, not subjective.

### Side-by-side comparison harness

Render each corpus case to an animated GIF (or a sequence of
terminal snapshots). Put the current-pipeline output next to the
categorized-pipeline output. Manually review the diff. This is the
subjective layer — but it's bounded (68 cases) and produces a list of
specific cases that still look bad, which feeds back into the
taxonomy.

### A/B test on real commits

Take 20 commits from the OS corpus from Phase 1. Render each with
both pipelines. Score by:
- Op count (lower = better, generally)
- Number of "delete then insert same position" pairs (lower = better)
- Cursor travel distance (lower = better)
- Time-to-completion at fixed speed (lower = better for noise
  categories, higher = better for substantive changes)

### Deliverable

- `tests/test_category_rendering.pl` — structural op-stream tests.
- `tests/test_category_properties.pl` — per-category property tests.
- `tests/render_compare.sh` — side-by-side harness.
- `analysis/quality_scores.csv` — A/B scores on 20 OS commits.

---

## Research to lean on

This isn't novel territory. The categorization approach mirrors work
that already exists:

- **GumTree** (Falleri et al., 2014) — AST-based edit classification
  into `INSERT`, `DELETE`, `MOVE`, `UPDATE`. We're proposing a
  finer-grained taxonomy optimized for *animation*, not just
  display.
- **difftastic** (Wilfred Barnes) — structural diff that ignores
  whitespace and matches by AST. Useful as the structural-diff
  backend for the categorizer.
- **SemanticMerge** (Plastic SCM) — classifies changes as
  Add/Delete/Modify/Move at method granularity.
- **git's `--color-moved`** — move detection at line level. Cheap
  heuristic we can adopt for `block_move`.
- **JetBrains diff viewer** — classifies changes as
  Conflicts/Changes/Moves/Conflicts-within-moves. Their renderer
  animates moves as "lift from source, drop at dest" — exactly the
  pattern we want.
- **CodeMirror merge view** — uses word-level diffs for inline
  changes, char-level only when the word overlap is high. The
  threshold is empirically tuned.
- **Tversky, B. (2002) — "Animation: does it facilitate?"** —
  animation helps when it shows a *causal* or *structural* transition,
  hurts when it shows a *sequence* of independent changes. Our
  current pipeline shows independent char-changes; the category-based
  pipeline shows structural transitions.
- **Sweller's cognitive load theory** — chunking into 7±2 units. The
  taxonomy caps the number of "things to track" per hunk.
- **Kim, S. et al. — "Empirical Studies of Code Review"** —
  reviewers focus on *what changed semantically*, not *which chars
  moved*. Our animation should match that focus.

The `docs/design/DIFF_STUDY.md` doc already covers reading-speed and
cognitive-load research. This strategy is the missing *architectural*
piece that translates that research into a pipeline design.

---

## What to throw away

After the categorizer + renderers are working:

- `ad_layer_reorder` — the categorizer produces correctly-ordered
  ops by construction.
- `ad_layer_overwrite` — replaced by the `word_replace` renderer's
  `select + overwrite_insert` pattern.
- `ad_layer_indent_last` — replaced by the `indent_change` renderer.
- `ad_layer_split_in_place`, `ad_layer_join_insert_in_place` —
  replaced by line/block-level renderers that don't produce
  split/join char ops in the first place.
- `ad_layer_batch_whitespace`, `ad_layer_skip_indent` — folded into
  `indent_change` and `format_only` renderers.
- `ad_layer_line_delete_in_place`, `ad_layer_line_replace` — kept as
  primitives the renderers use; not user-facing.

`ad_layer_pace` and `ad_layer_highlight` stay — they're orthogonal
(timing and visual decoration).

---

## Sequencing

| Phase | Effort | Output | Risk |
|-------|--------|--------|------|
| 1. Corpus analysis | 2-3 days | taxonomy grounded in data | low — read-only |
| 2. Lock taxonomy | 1 day | `EDIT_TAXONOMONY.md` + rules | medium — getting disambiguation right |
| 3a. Categorizer | 3-5 days | `animator/categorize/` | high — the hard part |
| 3b. Renderers (start with 3: `word_replace`, `line_insert`, `block_move`) | 3 days | first visible win | medium |
| 3c. New animator op types (`select`, `block_cut`, `cursor_jump`) | 2 days | animator changes | medium — touches the C core |
| 3d. Remaining renderers | 5 days | full taxonomy covered | low — pattern is set |
| 4. Validation harness | 2 days | structural + property tests | low |
| 5. Migrate corpus tests to category-based | 2 days | all 68 cases pass new tests | low |
| 6. Deprecate old layers | 1 day | cleanup | low |

**First visible win: Phase 3b** — once `word_replace`, `line_insert`,
and `block_move` are working, the `hello → greet` case stops looking
terrible. That's the demo to validate the direction before
investing in the rest.

---

## What I need from you

This is a real refactor — 3-4 weeks of work, not a weekend. Before
starting:

1. **Confirm the reframe is right.** The core claim is: char-level
   LCS is the wrong primitive, semantic categorization is the right
   one. If you don't buy that, none of the rest follows.
2. **Pick the first 3 categories to ship.** I proposed
   `word_replace`, `line_insert`, `block_move` because they cover
   the most common visible bugs. If you want a different set, say so.
3. **Decide on the AST diff backend.** Difftastic is the obvious
   choice but it's a heavy dependency. Alternative: write a small
   tree-sitter-based classifier. Or skip AST entirely and use
   line+word heuristics — cheaper, less accurate.
4. **Accept that `snap == target` is no longer the success metric.**
   The new metric is "op stream matches expected category pattern."
   If we keep optimizing for byte-level correctness we'll keep
   producing bad animations that "pass."

I'll start Phase 1 (corpus analysis) on confirmation. It's read-only
and low-risk, and its output is what makes Phase 2 grounded instead
of vibes-driven.
