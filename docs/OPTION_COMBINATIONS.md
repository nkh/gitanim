# 100 Option Combination Examples

This document shows 100 practical examples of using diffvim with different
combinations of options, across all 32 example file pairs and 15 programming
languages. Each example explains what the combination does and when to use it.

---

## Speed & Timing (1–10)

### 1. Half-speed presentation mode

```bash
diffvim --speed 0.5 examples/01_small_python/old.py examples/01_small_python/new.py
```

Slows the entire animation to half speed. Useful for live presentations where
the audience needs time to read each character as it appears. The `--speed`
flag divides all timing values (type delay, delete delay, move duration, hunk
pause) by the multiplier, so `0.5` doubles every delay.

### 2. Double-speed quick review

```bash
diffvim --speed 2 examples/02_large_python/old.py examples/02_large_python/new.py
```

Doubles the animation speed for a fast review of a large refactoring (76→123
lines). The cursor glides and types twice as fast, letting you scan through 21
hunks in roughly half the normal time.

### 3. 5x speed for a 60-second overview

```bash
diffvim --speed 5 examples/06_typescript/old.ts examples/06_typescript/new.ts
```

Five times normal speed. The TypeScript UserService class expansion (23→58
lines) flashes by in seconds. Good for getting a high-level sense of what
changed before doing a detailed review.

### 4. Custom typing speed via environment variables

```bash
DIFFVIM_TYPE_DELAY_MS=100 \
DIFFVIM_DELETE_DELAY_MS=80 \
DIFFVIM_MOVE_MAX_MS=3000 \
diffvim examples/03_json_config/old.json examples/03_json_config/new.json
```

Instead of using `--speed`, set individual delays. Here each typed character
takes 100ms (about 10 chars/second), each deletion 80ms, and the cursor glide
can take up to 3 seconds. The JSON config update (package.json scripts and
dependencies) will feel deliberate and readable.

### 5. Slow typing, fast movement

```bash
DIFFVIM_TYPE_DELAY_MS=80 \
DIFFVIM_MOVE_MIN_MS=50 \
DIFFVIM_MOVE_MAX_MS=200 \
diffvim examples/04_shell_script/old.sh examples/04_shell_script/new.sh
```

Characters are typed slowly (80ms each) but the cursor jumps quickly between
hunks (50–200ms). This creates a natural rhythm: the cursor snaps to the next
change, then types deliberately. The shell script improvement (26→54 lines)
shows logging and error handling additions.

### 6. Pause between hunks for discussion

```bash
DIFFVIM_HUNK_PAUSE_MS=2000 \
diffvim examples/05_go_code/old.go examples/05_go_code/new.go
```

Two-second pause between each hunk. During the Go code expansion (16→81 lines,
adding graceful shutdown and health checks), the presenter has time to explain
each change before the cursor moves to the next.

### 7. Adaptive timing for complex regions

```bash
diffvim --adaptive-timing examples/07_text_prose/old.txt examples/07_text_prose/new.txt
```

The animation automatically slows down in complex regions (many changes close
together) and speeds up in simple regions. The text prose rewrite (24→36 lines)
has dense paragraphs of changes that benefit from slower pacing.

### 8. Very slow for teaching

```bash
DIFFVIM_TYPE_DELAY_MS=150 \
DIFFVIM_DELETE_DELAY_MS=120 \
DIFFVIM_MOVE_MS_PER_UNIT=15 \
DIFFVIM_HUNK_PAUSE_MS=1000 \
diffvim examples/13_java/old.java examples/13_java/new.java
```

Extremely slow timing for teaching scenarios. Each character takes 150ms, each
glide is slow (15ms per unit), and there's a full second between hunks. The
Java Calculator class expansion (adding multiply and divide methods) becomes a
step-by-step walkthrough.

### 9. Fast typing, slow gliding

```bash
DIFFVIM_TYPE_DELAY_MS=10 \
DIFFVIM_MOVE_MIN_MS=500 \
DIFFVIM_MOVE_MAX_MS=5000 \
diffvim examples/14_kotlin/old.kt examples/14_kotlin/new.kt
```

Characters appear almost instantly (10ms) but the cursor glides slowly between
hunks (500ms–5s). This creates a dramatic effect where the cursor floats to
each change location, then rapidly types the new content. The Kotlin User data
class expansion (adding email and role fields) looks cinematic.

### 10. Default speed with debug logging

```bash
diffvim --debug examples/15_swift/old.swift examples/15_swift/new.swift
```

Normal speed with all Ex commands logged to `/tmp/diffvim-debug.log`. Useful
for debugging timing issues or understanding what the engine sends to vim. The
Swift Task struct expansion (adding Priority enum and UUID) runs normally while
every `:call DvInsert(...)` command is timestamped in the log.

---

## Scroll & Display (11–20)

### 11. Center cursor during animation

```bash
diffvim --scroll zz examples/16_ruby/old.rb examples/16_ruby/new.rb
```

The cursor stays centered on screen as the animation moves between hunks. The
Ruby Person class refactoring (adding keyword arguments and `to_h` method) is
always visible without manual scrolling.

### 12. Cursor at top of screen

```bash
diffvim --scroll zt examples/17_php/old.php examples/17_php/new.php
```

The cursor is positioned at the top of the viewport. Useful when you want to
see the context below each change. The PHP Logger class update (adding
timestamps, levels, and type declarations) shows the changes at the top with
remaining code below.

### 13. Cursor at bottom of screen

```bash
diffvim --scroll zb examples/18_scala/old.scala examples/18_scala/new.scala
```

The cursor stays at the bottom of the viewport, showing context above each
change. The Scala MathUtils expansion (adding power and factorial functions)
shows the existing code above the cursor as new functions are added below.

### 14. Highlight hunks before changing them

```bash
diffvim --highlight-hunk examples/19_elixir/old.ex examples/19_elixir/new.ex
```

Before animating each hunk, the hunk's line range is highlighted with the
default `DiffChange` color for 1 second. The Elixir Greeter module expansion
(adding @moduledoc, @spec, and i18n) pauses at each change so the viewer can
see what's about to be modified.

### 15. Custom highlight color and duration

```bash
diffvim --highlight-hunk \
  --highlight-color Search \
  --highlight-duration-ms 2000 \
  examples/20_clojure/old.clj examples/20_clojure/new.clj
```

Hunks are highlighted with the `Search` color (typically yellow/orange) for 2
seconds. The Clojure namespace expansion (adding multiply and format-result)
gets a prominent visual cue before each change.

### 16. Highlight only large hunks

```bash
diffvim --highlight-hunk \
  --highlight-min-chars 20 \
  examples/21_haskell/old.hs examples/21_haskell/new.hs
```

Only hunks with 20+ changed characters are highlighted. Small hunks are
animated directly without the highlight pause. The Haskell module expansion
(adding Fibonacci and sort) skips highlighting for small changes and only
highlights the larger function additions.

### 17. Fold unchanged regions

```bash
diffvim --fold-unchanged examples/22_lua/old.lua examples/22_lua/new.lua
```

Unchanged regions between hunks are folded, so only the changes are visible.
The Lua module expansion (adding greeting table support) shows just the new
functions without the unchanged boilerplate. Press `f` to toggle folding.

### 18. Dark theme for presentation

```bash
diffvim --theme dark --scroll zz examples/23_perl/old.pl examples/23_perl/new.pl
```

Sets vim's background to dark and centers the cursor. The Perl script expansion
(adding `say`, `greet_all`, and multiple calls) is presented in a dark color
scheme suitable for projector displays.

### 19. High-contrast theme for accessibility

```bash
diffvim --theme high-contrast examples/24_r/old.R examples/24_r/new.R
```

Vivid diff highlight colors: green for additions, red for deletions, yellow for
changes. The R script expansion (adding `calculate_stats` with mean, median, sd,
min, max) is clearly visible for users who need high contrast.

### 20. Combine scroll, theme, and highlight

```bash
diffvim --scroll zz \
  --theme high-contrast \
  --highlight-hunk \
  --highlight-color DiffAdd \
  examples/25_sql/old.sql examples/25_sql/new.sql
```

Full presentation setup: cursor centered, high-contrast colors, hunks
highlighted in green (`DiffAdd`) before animation. The SQL query expansion
(from a simple SELECT to a JOIN with GROUP BY, HAVING, and LIMIT) gets the
full visual treatment.

---

## Diff Algorithms (21–30)

### 21. Default LCS algorithm

```bash
diffvim examples/26_markdown/old.md examples/26_markdown/new.md
```

The default LCS (Longest Common Subsequence) algorithm. The Markdown document
expansion (adding TOC, config table, code blocks) is diffed with the standard
dynamic programming approach. Works well for most files.

### 22. Patience diff for human-readable hunks

```bash
diffvim --algorithm patience examples/27_xml/old.xml examples/27_xml/new.xml
```

The patience algorithm anchors on unique common lines (like `<project>` or
`<dependencies>`), producing more intuitive hunk boundaries. The XML/Maven POM
expansion (adding properties, dev-dependencies, and profile) gets cleaner hunks
that align with the XML structure.

### 23. Myers diff for large files

```bash
diffvim --algorithm myers examples/02_large_python/old.py examples/02_large_python/new.py
```

The Myers algorithm is O(ND) (where D is the edit distance) vs LCS's O(N×M).
For the large Python refactoring (76→123 lines, 21 hunks), Myers is
theoretically faster. Note: currently falls back to LCS for correctness, but
the option is accepted and produces correct results.

### 24. Word-level diff

```bash
diffvim --word-diff examples/28_toml/old.toml examples/28_toml/new.toml
```

Instead of character-by-character, the diff operates on words (non-space
sequences). The TOML/Cargo.toml expansion (adding features, dev-deps, and
profile) shows whole words appearing at once, which feels more like natural
typing.

### 25. Word diff with patience algorithm

```bash
diffvim --word-diff --algorithm patience examples/29_dockerfile/old.Dockerfile examples/29_dockerfile/new.Dockerfile
```

Combines word-level char diff with patience line diff. The Dockerfile
expansion (from simple single-stage to multi-stage with non-root user) gets
both human-readable hunk boundaries and word-level typing.

### 26. Semantic cleanup to reduce unnecessary ops

```bash
diffvim --semantic-cleanup examples/30_makefile/old.Makefile examples/30_makefile/new.Makefile
```

Post-processes the char ops to merge adjacent insert/delete pairs that cancel
out. The Makefile expansion (adding test, install, and pattern rules) has
fewer unnecessary typing operations, resulting in a cleaner animation.

### 27. Indent-aware diffing

```bash
diffvim --indent-aware examples/31_javascript/old.js examples/31_javascript/new.js
```

Normalizes indentation before line-level diff, so lines that differ only in
indentation are treated as "keep" at the line level. The JavaScript Express
app expansion (converting from CommonJS to ESM with CORS and morgan) has
smoother indentation changes.

### 28. Combine word-diff, semantic-cleanup, and patience

```bash
diffvim --word-diff --semantic-cleanup --algorithm patience \
  examples/32_python_classes/old.py examples/32_python_classes/new.py
```

Full diff refinement: patience for line-level, word-level for char-level, and
semantic cleanup to remove canceling ops. The Python classes expansion (from
simple inheritance to ABC, dataclass, and type hints) gets the most
human-readable diff possible.

### 29. Compare parsers

```bash
perl diffvim.pl --parser-compare examples/01_small_python/old.py examples/01_small_python/new.py
```

Runs both the Perl LCS parser and the diff2html CLI parser, then compares the
hunks and char ops. Exits 0 if they match, 1 if any difference is found.
Useful for continuous validation.

### 30. Dry run to inspect ops

```bash
perl diffvim.pl --dry-run examples/08_rust_code/old.rs examples/08_rust_code/new.rs
```

Computes and prints all diff ops without launching vim. Shows each hunk's
target line, deleted/inserted counts, and every char op (keep/insert/delete
with character code). Useful for debugging parser issues with the Rust code
expansion.

---

## Word & Hunk Limits (31–40)

### 31. Skip large hunks entirely

```bash
diffvim --max-hunk-chars 100 examples/02_large_python/old.py examples/02_large_python/new.py
```

Any hunk with more than 100 changed characters is applied instantly (no
char-by-char animation). The large Python refactoring has several big hunks
(like the ProcessingResult dataclass addition with 578 ops) that would take
too long to animate — they're applied in one shot with a message.

### 32. Type short words instantly, animate long sequences

```bash
diffvim --max-word-chars 5 examples/09_c_code/old.c examples/09_c_code/new.c
```

Sequences of 6+ contiguous modified (non-space) characters are applied in one
shot with a pause. Sequences of 5 or fewer are animated character by character.
The C code expansion (adding argc/argv, sizeof, and average calculation) types
short identifiers like `avg` one char at a time but applies long sequences like
`(double)sum / n` instantly.

### 33. Custom word pause duration

```bash
diffvim --max-word-chars 3 --word-pause-ms 300 examples/10_yaml_config/old.yaml examples/10_yaml_config/new.yaml
```

Sequences of 4+ modified characters are applied instantly, with a 300ms pause
after each. The YAML/docker-compose expansion (adding cache service, volumes,
and restart policies) has a readable rhythm: type short words, pause after
longer sequences.

### 34. Combine max-hunk-chars and max-word-chars

```bash
diffvim --max-hunk-chars 200 --max-word-chars 8 \
  examples/11_html/old.html examples/11_html/new.html
```

Hunks with 200+ changed chars are applied instantly. Within remaining hunks,
sequences of 9+ chars are applied in one shot. The HTML expansion (adding
meta tags, nav, header, footer, and script) balances between skipping very
large hunks and batching medium-sized changes.

### 35. No limits — animate everything character by character

```bash
diffvim examples/12_css/old.css examples/12_css/new.css
```

Default behavior: every character is animated individually, no hunk is too
large. The CSS expansion (from simple rules to CSS variables, media queries,
and responsive design) shows every character being typed and deleted.

### 36. Aggressive skipping for quick review

```bash
diffvim --max-hunk-chars 50 --max-word-chars 3 --speed 3 \
  examples/02_large_python/old.py examples/02_large_python/new.py
```

Skip hunks with 50+ changed chars, batch sequences of 4+ chars, and run at 3x
speed. The large Python refactoring flies by — only small hunks are animated,
and even those are fast.

### 37. Conservative limits for detailed review

```bash
diffvim --max-hunk-chars 500 --max-word-chars 20 \
  examples/05_go_code/old.go examples/05_go_code/new.go
```

Only very large hunks (500+ chars) are skipped, and only very long sequences
(21+ chars) are batched. The Go code expansion (adding Server struct, handlers,
and graceful shutdown) is mostly animated character by character, with only
the largest blocks applied instantly.

### 38. Word batching with scroll and highlight

```bash
diffvim --max-word-chars 5 --scroll zz --highlight-hunk \
  examples/13_java/old.java examples/13_java/new.java
```

Sequences of 6+ chars are batched, cursor is centered, and hunks are
highlighted before animation. The Java Calculator expansion (adding multiply
and divide methods) gets a polished, readable presentation.

### 39. Step mode for detailed inspection

```bash
diffvim --step-mode examples/14_kotlin/old.kt examples/14_kotlin/new.kt
```

Space advances one char op at a time instead of toggling pause/resume. Each
press of Space processes exactly one keep/insert/delete op. The Kotlin User
data class expansion can be inspected character by character.

### 40. Step mode with highlight

```bash
diffvim --step-mode --highlight-hunk --highlight-color Visual \
  examples/15_swift/old.swift examples/15_swift/new.swift
```

Step mode with each hunk highlighted in `Visual` color before starting. The
Swift Task struct expansion (adding Priority enum and UUID) can be inspected
one character at a time with visual cues for each hunk boundary.

---

## Multi-File & Git (41–50)

### 41. Multi-file animation

```bash
diffvim --multi \
  examples/01_small_python/old.py:examples/01_small_python/new.py \
  examples/13_java/old.java:examples/13_java/new.java
```

Animate two file pairs in sequence. After finishing the Python f-string
conversion, the animation transitions to the Java Calculator expansion with a
"next file" message.

### 42. Multi-file with scroll and speed

```bash
diffvim --multi --speed 2 --scroll zz \
  examples/03_json_config/old.json:examples/03_json_config/new.json \
  examples/10_yaml_config/old.yaml:examples/10_yaml_config/new.yaml
```

Animate two config file updates at double speed with centered cursor. The JSON
package.json and YAML docker-compose updates are presented quickly with the
cursor always centered.

### 43. Three-file animation

```bash
diffvim --multi \
  examples/04_shell_script/old.sh:examples/04_shell_script/new.sh \
  examples/29_dockerfile/old.Dockerfile:examples/29_dockerfile/new.Dockerfile \
  examples/30_makefile/old.Makefile:examples/30_makefile/new.Makefile
```

Animate three DevOps file changes in sequence: shell script improvement,
Dockerfile multi-stage build, and Makefile build system. Good for a
"DevOps improvements" presentation.

### 44. Git replay last 5 commits

```bash
diffvim --replay src/main.py
```

Animate the last 5 commits of `src/main.py`. For each commit, extracts the old
version and animates the transformation to the next commit, ending with the
working copy.

### 45. Git replay specific range

```bash
diffvim --replay src/main.py --from v1.0 --to HEAD
```

Animate all changes to `src/main.py` between the `v1.0` tag and `HEAD`.

### 46. Git rev syntax

```bash
diffvim --git-rev HEAD~3..HEAD src/main.py
```

Shorthand for `--replay --from HEAD~3 --to HEAD`. Animates the last 3 commits.

### 47. Multi-file git replay

```bash
diffvim --replay src/main.py src/utils.py src/config.py
```

Animate git history for three files in sequence. Each file's commit history is
animated separately with a "next file" message between them.

### 48. Git replay with highlight

```bash
diffvim --replay --highlight-hunk --scroll zz src/main.py
```

Git replay with hunk highlighting and centered cursor. Each change in the
commit history is highlighted before animation, making it easy to see what
each commit modified.

### 49. Git blame during animation

```bash
diffvim --git-blame examples/01_small_python/old.py examples/01_small_python/new.py
```

Shows git blame information for each line being changed. Before each hunk, the
commit hash and author are displayed, so the viewer knows who last touched the
code.

### 50. Git diff via pipe

```bash
git diff HEAD~1 -- src/main.py | diffvim --diff -
```

Pipe `git diff` output directly into diffvim. The diff is parsed and animated
without needing separate old/new files. Useful for reviewing the latest commit.

---

## Diff Input & Output (51–60)

### 51. Animate from a patch file

```bash
diffvim --diff my-changes.patch
```

Read a unified diff file and animate it. The patch file's `---`/`+++` headers
are parsed to find the file paths, and the old version is extracted from git
or disk.

### 52. Animate from stdin

```bash
cat my-changes.patch | diffvim --diff -
```

Read the diff from stdin. Enables piping from `git diff`, `diff -u`, or any
other diff-producing command.

### 53. Write result to file

```bash
diffvim --output /tmp/result.py examples/01_small_python/old.py examples/01_small_python/new.py
```

After the animation completes, write the buffer to `/tmp/result.py` and quit
vim. Useful for scripted use where you want the result saved without manual
intervention.

### 54. Output with dry run

```bash
perl diffvim.pl --dry-run --output /tmp/result.py \
  examples/02_large_python/old.py examples/02_large_python/new.py
```

Print the diff ops AND write the result. The dry run shows the computed ops,
and the output file contains the final state.

### 55. Output with speed and scroll

```bash
diffvim --output /tmp/result.go --speed 2 --scroll zz \
  examples/05_go_code/old.go examples/05_go_code/new.go
```

Animate at 2x speed with centered cursor, then save the result. The Go code
expansion is reviewed quickly and the final state is saved to `/tmp/result.go`.

### 56. No-tmux mode

```bash
perl diffvim.pl --no-tmux examples/01_small_python/old.py examples/01_small_python/new.py
```

Run vim directly in the terminal without tmux. Simpler single-shot use, but
no FIFO-based user input (controls like pause/skip/back are not available).
The animation runs autonomously inside vim.

### 57. Remote mode (vim server)

```bash
perl diffvim.pl --remote examples/01_small_python/old.py examples/01_small_python/new.py
```

Use `vim --remote-send` with `--servername` instead of tmux send-keys.
Eliminates tmux race conditions entirely. The vim server receives Ex commands
via the remote protocol.

### 58. Debug logging

```bash
diffvim --debug examples/06_typescript/old.ts examples/06_typescript/new.ts
# Then inspect the log:
cat /tmp/diffvim-debug.log
```

Every Ex command sent to vim is logged with a timestamp. Useful for debugging
race conditions, timing issues, or understanding the animation engine's
behavior with the TypeScript UserService expansion.

### 59. Version info

```bash
diffvim --version
```

Prints the version number, parser info, and dependency versions (vim, tmux,
perl, diff, git, diff2html). Useful for bug reports and troubleshooting.

### 60. Sign column display

```bash
diffvim --sign-column examples/07_text_prose/old.txt examples/07_text_prose/new.txt
```

Show `+`/`-` signs in vim's sign column to indicate deleted/added lines. The
text prose rewrite (architecture document enhancement) gets visual markers in
the sign column for each changed line.

---

## Language-Specific Combinations (61–80)

### 61. Python f-string conversion with highlight

```bash
diffvim --highlight-hunk --highlight-color DiffAdd --scroll zz \
  examples/01_small_python/old.py examples/01_small_python/new.py
```

The small Python f-string conversion (3 lines) is highlighted in green before
each change, with the cursor centered. A clean, focused presentation of a
single-line change.

### 62. Large Python refactoring with patience and folding

```bash
diffvim --algorithm patience --fold-unchanged --max-hunk-chars 300 \
  examples/02_large_python/old.py examples/02_large_python/new.py
```

Patience diff for clean hunks, fold unchanged regions, and skip hunks with
300+ changed chars. The large Python refactoring (76→123 lines) shows only
the relevant changes, with large blocks applied instantly.

### 63. JSON config with word diff

```bash
diffvim --word-diff examples/03_json_config/old.json examples/03_json_config/new.json
```

Word-level diff for the package.json update. Version numbers and script names
appear as whole words rather than character-by-character, which feels more
natural for config files.

### 64. Shell script with adaptive timing

```bash
diffvim --adaptive-timing --sign-column \
  examples/04_shell_script/old.sh examples/04_shell_script/new.sh
```

Adaptive timing slows down in complex regions (the logging and status
functions), and sign column shows +/- for each changed line. The shell script
improvement (26→54 lines) gets a balanced presentation.

### 65. Go code with step mode

```bash
diffvim --step-mode --scroll zt \
  examples/05_go_code/old.go examples/05_go_code/new.go
```

Step through the Go code expansion one character at a time with the cursor at
the top of the screen. Press Space to advance each op. Useful for detailed
code review of the Server struct and handler additions.

### 66. TypeScript with semantic cleanup

```bash
diffvim --semantic-cleanup --highlight-hunk \
  examples/06_typescript/old.ts examples/06_typescript/new.ts
```

Semantic cleanup removes unnecessary insert/delete pairs, and hunks are
highlighted before animation. The TypeScript UserService expansion (23→58
lines) gets a clean, readable animation.

### 67. Rust code with high-contrast theme

```bash
diffvim --theme high-contrast --max-word-chars 8 \
  examples/08_rust_code/old.rs examples/08_rust_code/new.rs
```

High-contrast colors for vivid diff highlights, and sequences of 9+ chars are
batched. The Rust code expansion (5→18 lines, adding fold, average, and
HashMap) gets bold visual cues.

### 68. C code with fold and highlight

```bash
diffvim --fold-unchanged --highlight-hunk --highlight-color DiffDelete \
  examples/09_c_code/old.c examples/09_c_code/new.c
```

Fold unchanged regions and highlight hunks in red (`DiffDelete`) before
animation. The C code expansion (9→18 lines, adding argc/argv and average
calculation) shows only the changes with red highlights.

### 69. Java with dark theme and centered cursor

```bash
diffvim --theme dark --scroll zz --speed 0.8 \
  examples/13_java/old.java examples/13_java/new.java
```

Dark theme, centered cursor, and 80% speed for a relaxed presentation of the
Java Calculator class expansion (adding multiply and divide methods).

### 70. Kotlin with word diff and highlight

```bash
diffvim --word-diff --highlight-hunk --highlight-color IncSearch \
  examples/14_kotlin/old.kt examples/14_kotlin/new.kt
```

Word-level diff with hunks highlighted in `IncSearch` color (typically
bright yellow). The Kotlin User data class expansion (adding email and role
fields) shows words appearing at once with prominent highlights.

### 71. Swift with step mode and sign column

```bash
diffvim --step-mode --sign-column --scroll zz \
  examples/15_swift/old.swift examples/15_swift/new.swift
```

Step through the Swift Task struct expansion one character at a time, with
sign column markers and centered cursor. Each press of Space reveals one
more character of the Priority enum and UUID additions.

### 72. Ruby with patience and semantic cleanup

```bash
diffvim --algorithm patience --semantic-cleanup --highlight-hunk \
  examples/16_ruby/old.rb examples/16_ruby/new.rb
```

Patience diff for clean hunks aligned on unique lines (like `class Person`),
semantic cleanup to remove canceling ops, and hunk highlighting. The Ruby
Person class refactoring (adding keyword args and `to_h`) gets a polished
animation.

### 73. PHP with adaptive timing and fold

```bash
diffvim --adaptive-timing --fold-unchanged \
  examples/17_php/old.php examples/17_php/new.php
```

Adaptive timing slows down in the dense logging function changes, and
unchanged regions are folded. The PHP Logger class update (adding timestamps,
levels, and type declarations) focuses attention on the modified code.

### 74. Scala with highlight and theme

```bash
diffvim --highlight-hunk --theme high-contrast --highlight-color DiffAdd \
  examples/18_scala/old.scala examples/18_scala/new.scala
```

Hunks highlighted in green (`DiffAdd`) with high-contrast theme. The Scala
MathUtils expansion (adding power and factorial functions) gets vivid green
highlights before each new function is typed.

### 75. Elixir with word diff and scroll

```bash
diffvim --word-diff --scroll zt --highlight-hunk \
  examples/19_elixir/old.ex examples/19_elixir/new.ex
```

Word-level diff with cursor at top and hunk highlighting. The Elixir Greeter
module expansion (adding @moduledoc, @spec, and i18n) shows words appearing
at the top of the screen with highlights.

### 76. Clojure with step mode and fold

```bash
diffvim --step-mode --fold-unchanged \
  examples/20_clojure/old.clj examples/20_clojure/new.clj
```

Step through the Clojure namespace expansion one character at a time, with
unchanged regions folded. Each press of Space reveals one more character of
the `multiply` and `format-result` function additions.

### 77. Haskell with patience and highlight

```bash
diffvim --algorithm patience --highlight-hunk --highlight-min-chars 5 \
  examples/21_haskell/old.hs examples/21_haskell/new.hs
```

Patience diff with hunk highlighting for any hunk with 5+ changed chars. The
Haskell module expansion (adding Fibonacci and sort) highlights even small
function additions.

### 78. Lua with semantic cleanup and sign column

```bash
diffvim --semantic-cleanup --sign-column --scroll zz \
  examples/22_lua/old.lua examples/22_lua/new.lua
```

Semantic cleanup for cleaner ops, sign column for visual markers, and centered
cursor. The Lua module expansion (adding greeting table support) gets a clean,
focused presentation.

### 79. Perl with word diff and adaptive timing

```bash
diffvim --word-diff --adaptive-timing \
  examples/23_perl/old.pl examples/23_perl/new.pl
```

Word-level diff with adaptive timing. The Perl script expansion (adding `say`,
`greet_all`, and multiple calls) slows down in the dense `greet_all` function
and speeds up in simpler regions.

### 80. R with highlight and theme

```bash
diffvim --highlight-hunk --theme dark --highlight-color Search \
  examples/24_r/old.R examples/24_r/new.R
```

Hunks highlighted in `Search` color (yellow) with dark theme. The R script
expansion (adding `calculate_stats` with mean, median, sd, min, max) gets
prominent yellow highlights on a dark background.

---

## Advanced Combinations (81–90)

### 81. Full presentation setup

```bash
diffvim \
  --speed 0.7 \
  --scroll zz \
  --theme high-contrast \
  --highlight-hunk \
  --highlight-color DiffAdd \
  --highlight-duration-ms 1500 \
  --highlight-min-chars 5 \
  --fold-unchanged \
  --sign-column \
  examples/02_large_python/old.py examples/02_large_python/new.py
```

Every visual option combined: 70% speed, centered cursor, high-contrast
colors, green hunk highlights for 1.5s (min 5 chars), folded unchanged
regions, and sign column markers. The large Python refactoring gets the full
presentation treatment.

### 82. Quick review setup

```bash
diffvim \
  --speed 3 \
  --max-hunk-chars 100 \
  --max-word-chars 5 \
  --fold-unchanged \
  examples/02_large_python/old.py examples/02_large_python/new.py
```

Fast review: 3x speed, skip hunks with 100+ changed chars, batch sequences of
6+ chars, and fold unchanged regions. The large Python refactoring is reviewed
in under 30 seconds.

### 83. Detailed code review

```bash
diffvim \
  --step-mode \
  --highlight-hunk \
  --sign-column \
  --scroll zz \
  --adaptive-timing \
  examples/06_typescript/old.ts examples/06_typescript/new.ts
```

Step through the TypeScript UserService expansion one character at a time,
with hunk highlighting, sign column, centered cursor, and adaptive timing.
The most detailed review mode possible.

### 84. Multi-file presentation

```bash
diffvim --multi \
  --speed 0.8 \
  --scroll zz \
  --theme dark \
  --highlight-hunk \
  --highlight-duration-ms 2000 \
  examples/01_small_python/old.py:examples/01_small_python/new.py \
  examples/13_java/old.java:examples/13_java/new.java \
  examples/14_kotlin/old.kt:examples/14_kotlin/new.kt
```

Three-file presentation at 80% speed with dark theme, centered cursor, and 2s
hunk highlights. Python f-string → Java Calculator → Kotlin User class — a
multi-language code evolution showcase.

### 85. Debug a parser issue

```bash
perl diffvim.pl --dry-run --debug \
  examples/20_clojure/old.clj examples/20_clojure/new.clj
```

Print all diff ops AND log debug info. Useful for investigating why the
Clojure namespace expansion produces specific ops. The dry run shows the ops,
and the debug log shows the timing.

### 86. Compare all algorithms

```bash
# Run the same file pair with each algorithm and compare:
for algo in lcs myers patience; do
    echo "=== $algo ==="
    perl diffvim.pl --algorithm $algo --dry-run \
      examples/27_xml/old.xml examples/27_xml/new.xml | grep "Hunks:"
done
```

Compare hunk counts across all three algorithms for the XML/Maven POM
expansion. Patience may produce different hunk boundaries than LCS due to
its unique-line anchoring.

### 87. Git replay with full presentation

```bash
diffvim --replay \
  --speed 0.8 \
  --scroll zz \
  --highlight-hunk \
  --fold-unchanged \
  --theme dark \
  src/main.py
```

Git replay with full presentation setup: 80% speed, centered cursor, hunk
highlights, folded unchanged regions, and dark theme. Each commit in the
file's history is presented with the full visual treatment.

### 88. Diff from git pipe with highlight

```bash
git diff HEAD~1 -- src/main.py | diffvim --diff - \
  --highlight-hunk \
  --highlight-color DiffAdd \
  --scroll zz
```

Pipe the latest commit's diff into diffvim with green hunk highlights and
centered cursor. A quick way to review the most recent change with visual
cues.

### 89. Output with dry-run verification

```bash
# Verify the diff is correct before animating:
perl diffvim.pl --dry-run examples/05_go_code/old.go examples/05_go_code/new.py
# Then animate with output:
diffvim --output /tmp/result.go --speed 2 \
  examples/05_go_code/old.go examples/05_go_code/new.go
# Verify the output matches:
diff /tmp/result.go examples/05_go_code/new.go && echo "CORRECT"
```

Three-step workflow: dry-run to verify ops, animate with output, then diff
the output against the expected new file. The Go code expansion is verified
end-to-end.

### 90. Benchmark all examples

```bash
perl tests/test_benchmark.pl
# View results:
cat /tmp/diffvim-benchmark-results.txt | head -20
```

Run the benchmark suite across all 32 examples × 5 algorithm variants (160
benchmarks). Measures compute time, estimated animation time, and DP table
memory for each combination.

---

## Plugin & Integration (91–100)

### 91. Plugin mode inside vim

```vim
:Diffvim old.py new.py
```

Run the animation inside an existing vim session using the `:Diffvim` command.
No tmux or external process needed — uses vim's native `timer_start()`.

### 92. Plugin mode in a new tab

```vim
:Diffvim old.py new.py tabnew
```

Open the animation in a new tab. The original buffer remains in the first tab.

### 93. Plugin mode in a vertical split

```vim
:Diffvim old.py new.py vsplit
```

Open the animation in a vertical split window. Useful for comparing the
animation with the expected result side by side.

### 94. Plugin with vimrc config

```vim
" In ~/.vimrc:
let g:diffvim = {
    \ 'type_delay_ms': 50,
    \ 'scroll': 'zz',
    \ 'highlight_hunk': 1,
    \ 'highlight_color': 'DiffAdd',
    \ 'max_word_chars': 5,
    \ 'fold_unchanged': 1,
    \ }

:Diffvim old.py new.py
```

Configure diffvim defaults in your vimrc. The `:Diffvim` command uses these
settings without needing CLI flags. All options available via `g:diffvim`:
`type_delay_ms`, `delete_delay_ms`, `move_min_ms`, `move_max_ms`,
`move_ms_per_unit`, `hunk_pause_ms`, `tick_ms`, `word_pause_ms`, `scroll`,
`max_hunk_chars`, `max_word_chars`, `output_file`, `word_diff`, `step_mode`,
`adaptive_timing`, `sign_column`, `git_blame`, `highlight_hunk`,
`highlight_color`, `highlight_duration`, `highlight_min_chars`,
`fold_unchanged`.

### 95. Shell completion (bash)

```bash
source completion/diffvim.bash
diffvim --<TAB>
# Shows: --algorithm --debug --diff --dry-run --fold-unchanged --git-blame ...
diffvim --scroll <TAB>
# Shows: zz zt zb none
diffvim --parser <TAB>
# Shows: perl diff2html
```

Bash completion for all options, option values, and file paths.

### 96. Shell completion (zsh)

```bash
# Install:
cp completion/_diffvim /usr/local/share/zsh/site-functions/
# Use:
diffvim --<TAB>
```

Zsh completion with descriptions for each option.

### 97. Shell completion (fish)

```bash
# Install:
cp completion/diffvim.fish ~/.config/fish/completions/
# Use:
diffvim --<TAB>
```

Fish shell completion for all diffvim options.

### 98. Homebrew installation

```bash
brew install ./packaging/diffvim.rb
# Then use:
diffvim old.py new.py
diffvim-tmux old.py new.py
perl diffvim.pl old.py new.py
man diffvim
```

Install all three scripts, Perl modules, vim plugin, man page, and shell
completions via Homebrew.

### 99. Manual installation with PERL5LIB

```bash
git clone https://github.com/nkh/gitanim.git
cd gitanim
chmod +x diffvim diffvim-tmux diffvim.pl
export PATH="$(pwd):$PATH"
export PERL5LIB="$(pwd):$PERL5LIB"
diffvim --version
perl diffvim.pl --version
```

Manual installation without copying files. Set `PATH` and `PERL5LIB` to use
the scripts directly from the clone directory.

### 100. Full CI pipeline test

```bash
#!/bin/bash
set -e

# Run all tests
perl tests/test_parsers.pl
perl tests/test_correctness.pl
perl tests/test_vim_correctness.pl
perl tests/test_features.pl
perl tests/test_integration.pl
perl tests/test_comprehensive.pl
perl tests/test_highlight_hunk.pl
perl tests/test_fold_theme_debug.pl
perl tests/test_diff_input.pl
perl tests/test_semantic_cleanup.pl
perl tests/test_parser_compare.pl
perl tests/test_benchmark.pl

# Verify all examples produce correct results
for d in examples/*/; do
    old=$(ls "$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$d"/new.* 2>/dev/null | head -1)
    [[ -z "$old" || -z "$new" ]] && continue
    perl diffvim.pl --dry-run "$old" "$new" | grep -q "Hunks:" || {
        echo "FAIL: $d"
        exit 1
    }
done

echo "All tests passed!"
```

Complete CI pipeline: run all 12 test suites, then verify all 32 example file
pairs produce valid diff output. 378+ assertions, 32 examples, 12 test suites.
