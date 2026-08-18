# Visual Guide — How diffvim Works

This document graphically explains what diffvim does, using ASCII
drawings. It is the canonical "explain it to a newcomer in 5 minutes"
reference. If you only read one document in this repo, read this one.

> **Audience:** developers who want to understand what diffvim produces
> on screen, what happens under the hood, and why the animation looks
> the way it does.
>
> **Status:** up to date with diffvim 1.4 (rapid-EOL delete, keep-dirty,
> post-processing pipeline, presets, external compute).

---

## 1. The One-Sentence Pitch

> diffvim opens the **old** version of a file in vim and animates the
> transformation into the **new** version character by character, as if
> a human were typing it.

That's it. Everything else is options that change *how* the animation
feels.

---

## 2. The Big Picture

```
   ┌──────────────┐                     ┌──────────────┐
   │   old.py     │     ──────────▶     │   new.py     │
   │  (on disk)   │   diffvim a.py b.py │  (on disk)   │
   └──────────────┘                     └──────────────┘
          │                                     │
          │                                     │
          ▼                                     │
   ┌────────────────────────────────────────────────────┐
   │                  diffvim                            │
   │                                                     │
   │   1. Read old.py and new.py                         │
   │   2. Compute the line-level diff                    │
   │   3. Group changes into hunks                       │
   │   4. For each hunk, compute char-level LCS          │
   │   5. Open old.py in vim                             │
   │   6. Animate: glide cursor → delete → type          │
   │                                                     │
   └────────────────────┬───────────────────────────────┘
                        │
                        ▼
        ┌────────────────────────────────────────┐
        │             vim (terminal)              │
        │                                        │
        │   ~                                     │
        │   ~                                     │
        │   def greet(name):                      │
        │       print(f"Hello, {name}!")          │
        │   ~                                     │
        │   ~                                     │
        │   :q                                    │
        └────────────────────────────────────────┘
```

After the animation finishes, the buffer contains the **new** file's
content. By default the buffer is marked "not modified" so `:q` quits
cleanly (use `--keep-dirty` to require `:q!`).

---

## 3. What the User Sees, Frame by Frame

Take this tiny diff:

```
old.py                           new.py
─────                            ─────
def greet(name):                 def greet(name):
    print("Hello, " + name)          print(f"Hello, {name}!")
```

Here is what the user sees in vim, frame by frame (each `|` is one
frame, ~50ms apart):

```
Frame 0   Frame 1   Frame 2   Frame 3   Frame 4   Frame 5   Frame 6
────────  ────────  ────────  ────────  ────────  ────────  ────────

def greet             def greet             def greet
    print("Hello          print("Hello          print("Hello
+ name)              + name)                + name)
                                          ▲ cursor glides
                                            to position 27

Frame 7   Frame 8   Frame 9   Frame 10  Frame 11  Frame 12  Frame 13
────────  ────────  ────────  ────────  ────────  ────────  ────────

def greet             def greet             def greet
    print("Hello          print("Hello          print(f"Hello,
+ name)              + name)                + name)!

              ▲ delete ' name)'    ▲ type 'f"Hello, '    ▲ type '{name}!"'
                char by char           char by char          char by char
```

Notice:

1. **Cursor glides** smoothly between change locations (ease-in-out
   cubic, ~250-1600ms depending on distance).
2. **Only the actually-changed characters are touched.** The
   `def greet(name):` line is never rewritten.
3. **Deletes come before inserts** at each change location
   (configurable with `--left-to-right` and `--delete-end-first`).

---

## 4. The Diff Pipeline

```
       ┌──────────────────────────────────────────────────────────┐
       │                    INPUT                                 │
       │   old.py                       new.py                    │
       │   "def greet(name):\n"         "def greet(name):\n"      │
       │   "    print(\"Hello, \"       "    print(f\"Hello, "     │
       │         + name)\n"                 + \"{name}!\")\n"     │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              STEP 1: Line-level diff                     │
       │                                                          │
       │   LCS / Patience algorithm compares line by      │
       │   line. Identical lines are "keep"; changed lines are    │
       │   paired into (old_line, new_line) and handed to         │
       │   the char-level diff.                                   │
       │                                                          │
       │   Result:                                                │
       │     keep  "def greet(name):"                             │
       │     pair  "    print(\"Hello, \" + name)"                │
       │           "    print(f\"Hello, {name}!\")"               │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              STEP 2: Hunk grouping                       │
       │                                                          │
       │   Consecutive non-keep line ops are merged into a hunk.  │
       │   Each hunk has a target_line (where to position the     │
       │   cursor in vim) and a list of char_ops.                 │
       │                                                          │
       │   Result: 1 hunk at line 2.                              │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              STEP 3: Char-level LCS                      │
       │                                                          │
       │   Within each hunk, compute the minimal char-level       │
       │   diff between the old and new line content.             │
       │                                                          │
       │   Result for the hunk above:                             │
       │     keep  '    print('                                   │
       │     insert 'f'                                           │
       │     keep  '"Hello, '                                     │
       │     insert '{name}!'                                     │
       │     keep  '"'                                            │
       │     delete ' + name'                                     │
       │     keep  ')'                                            │
       │     keep  '\n'                                           │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              STEP 4: Post-processing                     │
       │                                                          │
       │   Optional passes reorder ops for readability:           │
       │                                                          │
       │     • optimize_sequence  (default on)                    │
       │         — within a line, deletes before inserts          │
       │     • left_to_right      (default off)                   │
       │         — keeps first, then deletes, then inserts        │
       │     • semantic_cleanup   (off by default)                │
       │         — merge adjacent delete/insert pairs into keeps  │
       │     • indent_aware       (off by default)                │
       │         — preserve indentation                            │
       │     • delete_end_first   (off by default)                │
       │         — delete trailing chars before inserting new ones│
       │     • overwrite          (off by default)                │
       │         — overwrite in place instead of delete+insert    │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              STEP 5: Animation in vim                    │
       │                                                          │
       │   Open old.py in vim. For each hunk:                     │
       │                                                          │
       │     a) glide cursor from current pos to target_line      │
       │        (ease-in-out cubic, 250-1600ms)                   │
       │                                                          │
       │     b) for each char op:                                 │
       │          keep    → cursor advances                       │
       │          delete  → x key, cursor stays                   │
       │          insert  → i <char> <Esc>, cursor advances       │
       │                                                          │
       │     c) short pause between hunks (250ms by default)      │
       │                                                          │
       │   Result: viewer sees the file morph in real time.       │
       └──────────────────────────────────────────────────────────┘
                                  │
                                  ▼
       ┌──────────────────────────────────────────────────────────┐
       │              OUTPUT                                      │
       │   Buffer now contains new.py. User can edit, save, quit. │
       └──────────────────────────────────────────────────────────┘
```

---

## 5. Anatomy of a Hunk

A hunk is a contiguous block of changed lines. Here is what one hunk
looks like internally:

```
   Hunk {
       target_line:  2              ← where to position the cursor
       old_text:     '    print("Hello, " + name)'
       new_text:     '    print(f"Hello, {name}!")'
       char_ops: [
           { op: 'keep',   code: 32 },    ← ' '
           { op: 'keep',   code: 32 },    ← ' '
           { op: 'keep',   code: 32 },    ← ' '
           { op: 'keep',   code: 32 },    ← ' '
           { op: 'keep',   code: 112 },   ← 'p'
           { op: 'keep',   code: 114 },   ← 'r'
           { op: 'keep',   code: 105 },   ← 'i'
           { op: 'keep',   code: 110 },   ← 'n'
           { op: 'keep',   code: 116 },   ← 't'
           { op: 'keep',   code: 40 },    ← '('
           { op: 'insert', code: 102 },   ← 'f'        ★ new
           { op: 'keep',   code: 34 },    ← '"'
           { op: 'keep',   code: 72 },    ← 'H'
           ...                            ← 'ello, '
           { op: 'insert', code: 123 },   ← '{'        ★ new
           { op: 'insert', code: 110 },   ← 'n'        ★ new
           { op: 'insert', code: 97 },    ← 'a'        ★ new
           { op: 'insert', code: 109 },   ← 'm'        ★ new
           { op: 'insert', code: 101 },   ← 'e'        ★ new
           { op: 'insert', code: 125 },   ← '}'        ★ new
           { op: 'insert', code: 33 },    ← '!'        ★ new
           { op: 'keep',   code: 34 },    ← '"'
           { op: 'keep',   code: 41 },    ← ')'
           { op: 'delete', code: 32 },    ← ' '        ✗ deleted
           { op: 'delete', code: 43 },    ← '+'        ✗ deleted
           { op: 'delete', code: 32 },    ← ' '        ✗ deleted
           { op: 'delete', code: 110 },   ← 'n'        ✗ deleted
           { op: 'delete', code: 97 },    ← 'a'        ✗ deleted
           { op: 'delete', code: 109 },   ← 'm'        ✗ deleted
           { op: 'delete', code: 101 },   ← 'e'        ✗ deleted
           { op: 'keep',   code: 41 },    ← ')'
           { op: 'keep',   code: 10 },    ← '\n'
       ]
   }
```

The animation engine walks `char_ops` in order. `keep` advances the
cursor. `delete` removes the char under the cursor. `insert` types a
new char at the cursor and advances.

---

## 6. The Three diffvim Flavours

```
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │     diffvim      │   │  diffvim-tmux    │   │   diffvim.pl     │
   │  (bash+vimscrip) │   │  (bash + tmux)   │   │  (Perl + tmux)   │
   └────────┬─────────┘   └────────┬─────────┘   └────────┬─────────┘
            │                      │                      │
            ▼                      ▼                      ▼
   ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐
   │   single vim     │   │  bash + vim      │   │  Perl + vim      │
   │   process        │   │  (tmux pane)     │   │  (tmux pane)     │
   │                  │   │                  │   │                  │
   │  timer_start()   │   │  bash loop       │   │  Perl fork       │
   │  drives anim     │   │  + send-keys     │   │  + send-keys     │
   │                  │   │  + FIFO          │   │  + FIFO          │
   │                  │   │                  │   │                  │
   │  user input via  │   │  user input via  │   │  user input via  │
   │  normal-mode     │   │  named pipe      │   │  named pipe      │
   │  mappings        │   │                  │   │                  │
   │                  │   │                  │   │  pluggable       │
   │                  │   │                  │   │  parsers         │
   └──────────────────┘   └──────────────────┘   └──────────────────┘
   No race conditions      Race conditions       Race conditions
   No external deps        Needs tmux            Needs tmux + Perl
   Best for daily use      Best for scripting    Best for parser work
```

**Recommendation for newcomers:** start with `diffvim`. Switch to
`diffvim --precomputed` (with an external compute tool) for large files (>1000 lines) where the in-vim
LCS becomes slow.

---

## 7. Where the Compute Tools Fit

```
   ┌────────────────────────────────────────────────────────────────┐
   │                  diffvim --precomputed                          │
   │                                                                │
   │   1. Calls compute/bin/diffvim-compute-<c|cpp|rust|go>         │
   │      to pre-compute the diff into a temp file.                 │
   │                                                                │
   │   2. Calls diffvim --precomputed <tempfile>                    │
   │      which skips the in-vim LCS step entirely.                 │
   └────────────────────────────────────────────────────────────────┘
                          │             │
              ┌───────────┘             └────────────┐
              ▼                                       ▼
   ┌──────────────────────┐                ┌──────────────────────┐
   │  diffvim-compute-cpp │                │       diffvim        │
   │                      │                │   (loads precomputed │
   │  10-100x faster      │                │    diff, just anims) │
   │  than vimscript LCS  │                │                      │
   │                      │                │  Animation only      │
   │  Falls back to       │                │                      │
   │  Perl builtin        │                │                      │
   │  if binary missing   │                │                      │
   └──────────────────────┘                └──────────────────────┘
```

Use `compute/bin/diffvim-compute-cpp` (then `diffvim --precomputed`) — it's
the only compute implementation. When the C++ binary is missing,
`diffvim` falls back to the in-vim LCS and `diffvim-pipeline` falls
back to `compute/perl/compute_builtin.pl` (a Perl wrapper around
`DiffVim::Parser::Perl`). Both produce byte-for-byte identical output.

---

## 8. Cursor Glide Geometry

The cursor does not jump between hunks. It glides with ease-in-out
cubic acceleration:

```
   Position
       ▲
   100 │                                ▄██████████▄
       │                            ▄███▘          ▀███▄
       │                         ▄███▘                ▀███▄
       │                      ▄███▘                      ▀███▄
       │                   ▄███▘                            ▀███▄
       │                ▄███▘                                  ▀███▄
       │             ▄███▘                                        ▀███▄
       │          ▄███▘                                              ▀███▄
       │       ▄███▘                                                    ▀███▄
       │    ▄███▘                                                          ▀███▄
       │ ▄███▘                                                                ▀███▄
     0 └────────────────────────────────────────────────────────────────────────▶ Time
       0ms                250ms                              1600ms            1850ms
                          (min)                              (max)

   ────────────────────────────────────────────────────────────────────────────
   • min duration:  250 ms  (DIFFVIM_MOVE_MIN_MS)
   • max duration: 1600 ms  (DIFFVIM_MOVE_MAX_MS)
   • per-unit:        6 ms  (DIFFVIM_MOVE_MS_PER_UNIT)
   • actual:          min + min(max-min, distance * per-unit)
   ────────────────────────────────────────────────────────────────────────────
```

The viewer perceives the cursor "moving with intent" rather than
teleporting, which makes it much easier to follow long jumps.

---

## 9. The Post-Processing Pipeline (Visualised)

Raw char ops can be confusing — characters deleted in one place, then
inserted elsewhere on the same line, then more deletes elsewhere.
Post-processing reorders them for human readability.

```
   RAW char ops                    After post-processing
   (from LCS)                      (optimize_sequence + left_to_right)

   keep    '    print('            keep    '    print('
   insert  'f'                     insert  'f'
   keep    '"Hello, '              keep    '"Hello, '
   insert  '{name}!'               insert  '{name}!'
   keep    '"'                     keep    '"'
   delete  ' + name'               keep    ')'
   keep    ')'                     keep    '\n'
   keep    '\n'                    delete  ' + name'    ← trailing deletes
                                                   come last

   ────────────────────────────────────────────────────────────────
   Without post-processing:                With post-processing:
   viewer sees characters                  viewer sees: insert new
   disappear in the middle,                chars first, then trailing
   then reappear elsewhere,                chars are deleted in one
   then disappear at the end.              shot at the end.
   ────────────────────────────────────────────────────────────────
```

The full pipeline (applied in order):

```
   raw char_ops
        │
        ▼
   ┌─────────────────┐
   │ semantic_cleanup│  ← merge adjacent del/ins pairs into keeps
   └────────┬────────┘
            ▼
   ┌─────────────────┐
   │ optimize_seq    │  ← within each line, deletes before inserts
   └────────┬────────┘
            ▼
   ┌─────────────────┐
   │ left_to_right   │  ← within each line: keeps, then dels, then ins
   └────────┬────────┘
            ▼
   ┌─────────────────┐
   │ delete_end_first│  ← move trailing deletes to the end of the line
   └────────┬────────┘
            ▼
   ┌─────────────────┐
   │ overwrite       │  ← replace delete+insert with in-place overwrite
   └────────┬────────┘
            ▼
   final char_ops (what the animator consumes)
```

Each pass is independently toggleable. See `docs/POST_PROCESSING.md`
for the full reference.

---

## 10. The Six Presets

Presets bundle a sane combination of post-processing and timing options
for common use cases.

```
   ┌──────────────────┬──────────────────────────────────────────────┐
   │  default         │  No flags. Raw LCS with optimize_sequence    │
   │                  │  (on). Good for everyday use.                │
   ├──────────────────┼──────────────────────────────────────────────┤
   │  fast-delete     │  --rapid-eol-delete --accel-delete           │
   │                  │  --word-accel                                │
   │                  │  For long monotonous deletes (refactors).    │
   ├──────────────────┼──────────────────────────────────────────────┤
   │  review          │  --step-mode --highlight-hunk                │
   │                  │  --dim-unchanged --scroll zt                 │
   │                  │  For code review: pause after each hunk.     │
   ├──────────────────┼──────────────────────────────────────────────┤
   │  ai-code         │  --semantic-cleanup --left-to-right          │
   │                  │  --highlight-inline --word-diff              │
   │                  │  For AI-generated diffs (often messy).       │
   ├──────────────────┼──────────────────────────────────────────────┤
   │  demo            │  --speed 0.7 --word-pause-ms 200             │
   │                  │  --highlight-inline                          │
   │                  │  For live demos and presentations.           │
   ├──────────────────┼──────────────────────────────────────────────┤
   │  presentation    │  --speed 1.2 --scroll zz                     │
   │                  │  --no-rapid-eol-delete                       │
   │                  │  For recording screencasts.                  │
   └──────────────────┴──────────────────────────────────────────────┘

   Usage:
       diffvim --preset review old.py new.py
       diffvim --preset ai-code old.py new.py
       DIFFVIM_PRESET="review --highlight-word" diffvim old.py new.py
```

---

## 11. Controls Cheat Sheet (Visual)

```
   ┌─────────────────────────────────────────────────────────────────┐
   │                     diffvim cheat sheet                         │
   │                                                                 │
   │   During the animation (normal mode):                          │
   │                                                                 │
   │     Space   ▶/⏸  pause / resume                                 │
   │     n       ⏭    apply current hunk instantly, move to next    │
   │     b       ⏮    revert current hunk, restart previous         │
   │     q       ⏹    stop animation (buffer left as-is)            │
   │     +       ⏩    speed up × 1.5                                 │
   │     -       ⏪    slow down ÷ 1.5                                │
   │     =       ⤺    reset speed to 1.0x                            │
   │     ?       ❓   show in-vim help                                │
   │     ]       →    next file (--multi mode)                       │
   │     [       ←    previous file (--multi mode)                   │
   │                                                                 │
   │   After the animation:                                          │
   │                                                                 │
   │     :q        quit cleanly (buffer marked nomodified by default)│
   │     :q!       force quit (use when --keep-dirty was passed)     │
   │     :w FILE   save the result to FILE                           │
   │                                                                 │
   └─────────────────────────────────────────────────────────────────┘
```

---

## 12. Multi-File Animation

```
   ┌────────────────────────────────────────────────────────────────┐
   │   diffvim --multi old1:new1 old2:new2 old3:new3                │
   │                                                                │
   │  vim loads file 1   ──▶  animate  ──▶  ]  ──▶  vim loads file 2│
   │                                                                │
   │                                                      │         │
   │                                                      ▼         │
   │                                                     ...        │
   │                                                                │
   │   • Press ] to advance to the next file.                       │
   │   • Press [ to go back to the previous file.                   │
   │   • Each file gets its own animation pass with its own diff.   │
   │   • Status line shows "file 2/3: src/parser.rs".               │
   └────────────────────────────────────────────────────────────────┘
```

For multi-file on large repos, use
the compute tools to pre-compute all diffs, then `diffvim --multi --precomputed`
before animating.

---

## 13. Git History Replay

```
   ┌────────────────────────────────────────────────────────────────┐
   │   diffvim --replay main.py --from HEAD~5 --to HEAD             │
   │                                                                │
   │   HEAD~5      HEAD~4      HEAD~3      HEAD~2      HEAD~1     HEAD│
   │   ●───────────●───────────●───────────●───────────●──────────●  │
   │   v1          v2          v3          v4          v5         v6 │
   │                                                                │
   │   For each pair (v_i, v_{i+1}):                                │
   │     1. Extract the file content at both revs.                  │
   │     2. Run the diffvim animation.                              │
   │     3. Pause between commits (hunk_pause_ms).                  │
   │                                                                │
   │   Status line shows "commit 3/5: a1b2c3d — fix parser bug".    │
   └────────────────────────────────────────────────────────────────┘
```

Shorthand: `diffvim --git-rev HEAD~5..HEAD main.py`.

---

## 14. End-to-End Example: A Real Refactor

```
   BEFORE                              AFTER
   ──────                              ─────
   def get_db():                       @contextmanager
       return sqlite3.connect(         def session_scope():
           DB_PATH                     db = sqlite3.connect(DB_PATH)
       )                               try:
                                           yield db
                                           db.commit()
                                       except Exception:
                                           db.rollback()
                                           raise
                                       finally:
                                           db.close()

   ──────────────────────────────────────────────────────────────────
   Animation timeline (≈12 seconds at default speed):
   ──────────────────────────────────────────────────────────────────

   t=0.0s    vim opens, buffer shows BEFORE.
   t=0.3s    cursor glides to line 1, column 5.
   t=0.6s    delete 'get_db' char by char (6 chars × 40ms = 240ms).
   t=1.0s    type '@contextmanager' (16 chars × 50ms = 800ms).
   t=1.9s    press Enter, type 'def session_scope():'.
   t=2.6s    cursor moves to line 3.
   t=2.9s    delete 'return sqlite3.connect(' (rapid-EOL burst).
   t=3.1s    type 'db = sqlite3.connect(DB_PATH)'.
   ...       (continues for ~9 more seconds)
   t=12.0s   animation complete. Buffer shows AFTER.
   t=12.3s   status line: "Done. Press :q to quit."

   ──────────────────────────────────────────────────────────────────
```

---

## 15. Common Option Combos (Visualised)

```
   REFERENCE REVIEW                     AI-GENERATED CODE
   ────────────────────                 ──────────────────
   diffvim \                            diffvim \
     --preset review \                    --preset ai-code \
     --git-blame \                        --speed 0.5 \
     --sign-column \                      --highlight-word \
     --scroll zt \                        --adaptive-timing \
     old.py new.py                        old.py new.py

   • pause after each hunk              • batch word runs
   • show git blame line                • semantic cleanup
   • show +/- sign column               • left-to-right reading order
   • top-aligned scroll                 • adaptive timing on dense regions

   ──────────────────────────────────────
   LIVE DEMO                            SCREENCAST RECORDING
   ──────────────────────────────────────
   diffvim \                            diffvim \
     --preset demo \                      --preset presentation \
     --speed 0.7 \                        --output result.py \
     --max-line-len 120 \                 old.py new.py
     old.py new.py

   • slower speed for audience          • no rapid-EOL (smoother on video)
   • highlight typed/deleted chars      • save result to file
   • warn on long lines                 • scroll: center cursor
```

---

## 16. Where to Go Next

| If you want to...                    | Read this                                   |
| ------------------------------------ | ------------------------------------------- |
| Install diffvim                      | `docs/src/installation.md`                  |
| See every CLI option                 | `docs/src/options.md`                       |
| Understand the architecture          | `docs/ARCHITECTURE.md`                      |
| Tune timing and pacing               | `docs/CONFIGURATION.md`                     |
| See how post-processing works        | `docs/POST_PROCESSING.md`                   |
| See 100 option combinations          | `docs/OPTION_COMBINATIONS.md`               |
| Use the external compute tools       | `docs/PARALLEL_COMPUTE.md`                  |
| Diff AI-generated code well          | `docs/AI_CODE_DIFFING.md`                   |
| Reduce cognitive load while watching | `docs/FOLLOW_IMPROVEMENTS.md`               |
| Bring diffvim to your team           | `docs/ADOPTION_GUIDE.md`                    |
| Read the manpages                    | `man/diffvim.1`, `man/diffvim-compute.1`    |
| Show a one-page overview             | `docs/presentation.html`                    |

---

## Change Log

| Date       | Change                                                   |
| ---------- | -------------------------------------------------------- |
| 2026-08-16 | Initial version. Covers diffvim 1.4 (rapid-EOL, presets, external compute, post-processing pipeline). |
