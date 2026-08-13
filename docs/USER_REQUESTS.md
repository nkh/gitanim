# Complete User Request Log

This document contains every feature request, bug report, and design
direction the user has given during the diffvim project. It serves as
a master reference for what was asked and what was implemented.

---

## Session 1: Initial Features

1. **Animate code diffs in vim** as if a human were typing them.
2. **Two-level LCS diff**: line-level → char-level.
3. **Ease-in-out cubic cursor glide** between hunks.
4. **Timer-based animation engine** using vimscript `timer_start()`.
5. **Self-contained bash + vimscript** implementation (no Python, no tmux).
6. **Three implementations**: `diffvim` (bash+vimscript), `diffvim-tmux`
   (bash+tmux), `diffvim.pl` (Perl+tmux with pluggable parsers).

---

## Session 2: Options & Controls

7. `--speed N` — speed multiplier (0.5=half, 2=double, 5=5x).
8. `--output FILE` — write result to FILE after animation, then quit.
9. `--context N` — fold unchanged regions >2N lines, keep N context.
10. `--max-hunk-chars N` — skip char-by-char for hunks > N changed chars.
11. `--max-word-chars N` — type words <= N chars instantly, pause after.
12. `--word-pause-ms N` — pause after instant word (default: 150).
13. `--scroll zz|zt|zb|none` — cursor scroll position (default: zz).
14. `--multi` — treat args as old:new pairs for multi-file animation.
15. `--replay` — animate git history for given file(s).
16. `--from REV` / `--to REV` — git rev range for replay.
17. `--version, -V` — print version and exit.
18. `--dry-run` — print diff hunks without launching vim.
19. `--word-diff` — enable word-level diff.
20. `--step-mode` — Space advances one op at a time.
21. `--sign-column` — show +/- signs in the sign column.
22. `--git-blame` — echo git blame for the target line of each hunk.
23. `--git-rev REV..REV` — shorthand for --replay --from REV1 --to REV2.
24. `--max-line-len N` — warn on lines longer than N characters.
25. Controls: Space=pause, n=skip, b=back, q=quit, +=speed up, -=slow down,
   ==reset speed, ?=help.

---

## Session 3: Bug Fixes & Architecture

26. **Boolean env var fix** — `export DIFFVIM_STEP_MODE="0"` was truthy.
27. **`cur_hunk` not set before `ApplyHunkInstantly`** — fixed.
28. **`redraw` after keep ops** — fixed stale display.
29. **`-T dumb` removed** — was preventing alternate screen.
30. **`set syntax=` caused E216** — changed to `runtime syntax/X.vim`.
31. **VIMRUNTIME detection fixed** — `vim -es` doesn't output to stdout.
32. **35+ CLI options** across all scripts.
33. **3 diff algorithms**: LCS, Myers, Patience.
34. **Word-level diff, semantic cleanup, indent-aware diffing**.
35. **Vim plugin**: `:Diffvim`, `:DiffvimCommit`, `:DiffvimPick`.
36. **Shell completion** (bash/zsh/fish), Homebrew formula.
37. **32 example file pairs** in 15+ languages.
38. **378+ test assertions**.

---

## Session 4: Rapid EOL, Keep-Dirty, Followability

39. **Rapid end-of-line deletion** — when cursor is at end of line and
   all text after cursor is being deleted, delete rapidly. Add option to
   control and disable: `--rapid-eol-delete`, `--no-rapid-eol-delete`,
   `--rapid-eol-delay-ms`, `--rapid-eol-min-chars`.
40. **`:q` should quit vim by default** — don't require `:q!`. Add
   `--keep-dirty` option to keep buffer modified and force `:q!`.
41. **List 50 improvements** for following what's happening while patching.
42. **Verify all documentation**, update it, make it better.

---

## Session 5: N Key, Syntax, Adaptive Mode

43. **`n` key review mode** — apply next hunk and PAUSE, waiting for `n`
   again for the next hunk.
44. **Syntax highlighting** — fix colors not working.
45. **`--adaptive` mode** — move to beginning of next hunk, start slowly,
   accelerate, pause at end, with user-settable variables. For large
   hunks: insert pauses after N lines patched.

---

## Session 6: Word Highlight, Diff2html, Tests

46. **`--highlight-word`** — highlight words in the current line before
   they are changed, like `--highlight-hunk` but finer granularity.
47. **Install diff2html** and fix all test failures.
48. **"What good are tests if you keep them failing?!"** — make all tests
   pass.

---

## Session 7: Vimrc Colors, External Compute

49. **Vimrc colors ignored** — use the same colors as the user's vimrc.
   Don't use `-u NONE` by default; add `--no-vimrc` for isolated mode.
50. **External diff computation** — the computation takes too long. Keep
   the current implementation but add the possibility to compute in a
   separate application. Create Rust, Go, C, and C++ applications with
   a Makefile and timing. Create a bash script to run it with diffvim.
51. **Analyze parallel compute** — can both run in parallel to speed up
   startup?

---

## Session 8: External Tools Features

52. **Word-level diff** in vimscript engine and compute tools (flag existed
   but was never used in BuildHunks).
53. **Semantic cleanup** in vimscript engine (existed in Perl, missing
   from vimscript and compute tools).
54. **Indent-aware diffing** in vimscript engine and compute tools.
55. **Detailed documentation** for external tools — usage, schema, examples.
56. **Do all external tools support the same options?** — ensure parity.

---

## Session 9: No Startup Interaction

57. **"Press ENTER or type command to continue"** — remove this! No
   interaction before starting the animation unless asked for.
58. **Implement Myers, Patience, semantic cleanup** without stopping.
59. **Batch git blame** — pre-compute all blame at startup instead of
   per-hunk.

---

## Session 10: Large Examples, UX Features

60. **Accelerated multi-line deletion** — when consecutive lines are
   deleted, don't delete all at once. Delete first lines slowly, then
   accelerate, then decelerate. Options for acceleration, max speed,
   deceleration. Good values for 2-100 line blocks.
61. **Overwrite mode** (propose a name) — when a word replaces another,
   overwrite in place. Shorter=overwrite+delete-extra, same=overwrite-only,
   longer=overwrite+insert-remainder.
62. **Delete-end-first** — when a line is patched with inserts and end
   deletes, delete the end first, then insert. Add option.
63. **10 long examples** (200-1000 lines) in different languages including
   Perl, for testing how options feel.
64. **Startup feedback** — when computation is not external, startup takes
   seconds with no feedback. Add option to show progress in status line.
65. **Inline char highlight** (#2) — paint typed chars green for 200ms,
   deleted chars red for 200ms.
66. **Variable typing speed** (#25) — Gaussian jitter for human-like typing.
67. **Highlight unchanged anchor lines** (#44) — dim unchanged lines.
68. **Pause-after-N-lines** (#29) — auto-pause every N lines in >50-line
   hunks. N is an option.
69. **Implement all of the above for all 3 applications + external tools.**
70. **Multi-file animation documentation** — how to jump from file to file,
   how external tools speed up multi-file.
71. **Are external tools running in parallel internally?** Can the C version
   be made parallel?
72. **Diff comparison study** — generate diff files with many combinations
   of options and algorithms, compare for efficiency and readability.
   Research human reading behavior.

---

## Session 11: Apply to All Apps, Fix All Tests

73. **"Always apply new features to all apps!"** — parity is mandatory.
74. **"Do all apps support external diff generation?"** — verify and fix.
75. **"Not a single test fails!"** — fix ALL failures, including
   pre-existing ones.

---

## Session 12: Highlight-Hunk, Fold, Word-Diff, Block Delete, Logging

76. **`--highlight-hunk` doesn't highlight all changed lines** — sometimes
   whole blocks disappear without highlight. Fix to highlight ALL lines
   that will change.
77. **`--fold-unchanged` documented but not implemented** — diffvim says
   "unknown option". Implement it.
78. **In `--word-diff`, characters are deleted one by one** — fix to batch
   word runs.
79. **When deleting multiple lines, take a short pause before and after** —
   add option.
80. **Block-based multi-line deletion** — instead of deleting all lines,
   delete in blocks of 3 lines (customizable), take a slight pause, then
   accelerate deleting blocks faster and decelerate at the end. (User
   notes they asked about this already.)
81. **Create a document containing everything typed in this project.**
82. **Is the combination document up to date with the latest options?** Add
   what's missing.
83. **Delete-end-first consolidation** — the user specifically asked that
   when the end of a line is deleted, change all the words till the EOL
   deletion is reached, THEN delete the end. Instead, the current
   implementation modifies here and there, forcing the user to follow
   multiple changes at different places, then deletes the end.
84. **Characters are deleted in different places, jumping back and forth,
   then the whole line is deleted** — complete nonsense! Add an option to
   post-process the change list and optimize the sequence. Write a document
   about the post-process explaining what is done, when, why, and the
   effect, backed by research.
85. **Log mode 1** — doesn't start vim, generates a file showing what is
   done to each line. The line to be changed is output; for deletions,
   mark deleted character positions with a unicode emoji; for insertions,
   write a line with the inserted characters at the position.
86. **Log mode 2** — the line to be changed is added, then for each
   operation, add the same line with the position highlighted, then a
   third line with the operation done.

---

## Summary

**Total user requests: 86** (and counting)

All requests have been implemented or are in progress. The project has
grown from a simple vimscript animation to a multi-language, multi-tool
ecosystem with external compute tools, comprehensive test coverage, and
extensive documentation.
