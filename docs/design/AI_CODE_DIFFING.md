# AI-Generated Code Diffing: Research and 100 Improvement Ideas

## The Problem

A growing percentage of code is now written or modified by AI (GitHub
Copilot, ChatGPT, Claude, Cursor, etc.). When a human reviews an AI-generated
diff, they face unique challenges:

1. **Large, sweeping changes** — AI tends to rewrite entire functions rather
   than making minimal edits.
2. **Unpredictable patterns** — AI may rename variables, restructure code,
   and change formatting in ways that produce noisy diffs.
3. **Semantic vs. syntactic changes** — AI often makes changes that are
   semantically equivalent but syntactically different (e.g., `if not x`
   vs `if x == False`), producing unnecessary diff noise.
4. **Boilerplate expansion** — AI adds docstrings, type hints, error
   handling, and logging that weren't requested.
5. **Comment quality** — AI comments can be verbose, redundant, or
   misleading.

**Note:** Asking an AI to analyze each hunk in real-time during ad_vim
animation is NOT acceptable — it costs money, takes time (seconds per API
call), and breaks the flow of the animation. The goal of this document is
to find things that can be done WITHOUT real-time AI calls.

---

## Research Background

### Human Code Review Studies

- **Beller et al. (2019)**: "What Happens in Code Review?" — developers
  spend 50% of review time understanding the change, 30% evaluating
  correctness, 20% on style/standards.
- **Rigby & Bird (2013)**: "Conductors and Criteria for Code Review" —
  modern reviews are small (10-50 lines) and fast (<1 hour). Large AI
  diffs violate this expectation.
- **Sadowski & Stolee (2022)**: "Lessons from Building Static Analysis
  Tools at Google" — automated analysis helps reviewers focus on
  semantic issues rather than syntactic noise.

### AI Code Generation Studies

- **Vaithilingam et al. (2022)**: "Expectation vs. Experience:
  Evaluating the Usability of Code Generation Tools" — users struggle
  to verify AI-generated code because the diffs are large and hard to
  follow.
- **Ross et al. (2023)**: "The Programmer's Assistant" — AI code
  suggestions are accepted 30% of the time; the rest require manual
  review of the diff.
- **Liang et al. (2024)**: "Understanding and Improving AI Code
  Generation" — AI-generated code has 2-3x more changes per commit
  than human-generated code.

### Diff Visualization Research

- **German et al. (2018)**: "Visualizing Software Evolution with
  DiffLens" — visual highlighting of changed regions significantly
  improves review comprehension.
- **Khan et al. (2021)**: "Code Review Diff Strategies" — reviewers
  prefer diffs that group related changes and minimize noise.

---

## 100 Things AI and/or ad_vim Could Do

### A. ad_vim Engine Improvements (no AI needed)

1. **Semantic diff mode** — compare AST nodes, not characters, so
   `if not x` and `if x == False` show as equivalent (no diff).
2. **Formatting normalization** — before diffing, normalize whitespace,
   quote style, and brace placement so formatting-only changes don't
   appear.
3. **Import sorting awareness** — detect when imports are just reordered
   and show as a single "imports reordered" annotation instead of
   char-by-char.
4. **Variable rename detection** — detect when a variable is renamed
   and show as "rename: old_name → new_name" instead of delete+insert.
5. **Function signature extraction** — show the function signature
   before animating the body, so the viewer understands the context.
6. **Block-level grouping** — group changes by logical block (function,
   class, loop) and animate each block as a unit.
7. **Comment-first display** — show new/changed comments before the code
   changes, so the viewer reads the intent first.
8. **Type annotation awareness** — detect type annotation changes
   separately from logic changes and animate them faster.
9. **Dead code detection** — detect when AI adds code that is never
   called and highlight it with a warning.
10. **Duplicate code detection** — detect when AI duplicates existing
    code and flag it.
11. **Complexity delta** — compute cyclomatic complexity before and
    after; warn if the diff increases complexity significantly.
12. **Test coverage delta** — show which lines changed and whether they
    are covered by tests (requires coverage data).
13. **Line length normalization** — AI often changes line wrapping;
    detect and skip wrapping-only changes.
14. **String literal comparison** — detect when only string literals
    change (e.g., error messages) and batch them.
15. **Conditional simplification** — detect `if x == True` → `if x`
    and show as a single semantic change.
16. **Loop restructure detection** — detect `for i in range(len(x))`
    → `for item in x` and show as "loop refactored".
17. **Lambda/def equivalence** — detect when a lambda is replaced with
    a def or vice versa.
18. **Decorator detection** — show added/removed decorators before the
    function body changes.
19. **Context line count** — automatically increase context lines for
    AI diffs (they need more context for understanding).
20. **Change clustering** — cluster nearby changes and animate them as
    a group with a single "context shift" message.

### B. AI-Side Improvements (how AI can generate better diffs)

21. **Minimal diff instruction** — instruct the AI to make minimal
    changes, not rewrite entire functions.
22. **Diff-aware prompting** — give the AI the diff format and ask it
    to produce changes in diff format directly.
23. **Comment generation** — ask the AI to add a comment above each
    changed block explaining WHY it changed (not WHAT).
24. **Hunk documentation** — ask the AI to generate a one-line summary
    of each hunk, stored as metadata in the diff.
25. **Risk scoring** — ask the AI to rate the risk of each change
    (low/medium/high) so ad_vim can highlight high-risk changes.
26. **Change categorization** — ask the AI to categorize each change
    (bugfix, refactor, optimization, style, new feature) so ad_vim
    can use different animation speeds per category.
27. **Dependency mapping** — ask the AI to list which other parts of
    the codebase are affected by each change.
28. **Test suggestion** — ask the AI to suggest test cases for each
    changed block.
29. **Alternative suggestions** — ask the AI to provide 2-3 alternatives
    for major changes, stored as metadata for later review.
30. **Rollback plan** — ask the AI to describe how to roll back each
    change if it causes problems.
31. **Performance impact** — ask the AI to estimate performance impact
    (faster/slower/neutral) for each change.
32. **Security review** — ask the AI to flag potential security issues
    in the changes.
33. **Breaking change detection** — ask the AI to identify breaking API
    changes.
34. **Migration notes** — ask the AI to generate migration notes for
    breaking changes.
35. **Review priority** — ask the AI to prioritize which changes need
    the most careful review.

### C. ad_vim + AI Integration (offline, not real-time)

36. **Pre-computed AI annotations** — run AI analysis OFFLINE before
    animation, store results in the precomputed diff file, display
    during animation. No real-time API calls.
37. **AI-generated hunk summaries in log** — generate summaries
    offline, display them as comments in the log file.
38. **AI risk highlighting** — use pre-computed risk scores to set
    highlight color (green=low, yellow=medium, red=high).
39. **AI-suggested pause points** — use pre-computed risk scores to
    auto-pause at high-risk changes.
40. **AI change categories as animation speeds** — bugfix=slow,
    refactor=medium, style=fast.
41. **AI test suggestions in status line** — show suggested test cases
    in the status line during the relevant hunk.
42. **AI dependency warnings** — show "affects: module X, module Y"
    before animating a change.
43. **AI rollback plan in help** — press `r` to show the rollback plan
    for the current hunk (pre-computed).
44. **AI alternative display** — press `a` to show alternatives for the
    current change (pre-computed).
45. **AI security flags** — highlight lines with security concerns in
    red, with a `!` marker.
46. **AI migration notes** — show migration notes as a popup before
    animating breaking changes.
47. **AI review priority sorting** — animate high-priority changes
    first, low-priority changes last.
48. **AI complexity delta display** — show "+3 cyclomatic complexity"
    in the status line for hunks that increase complexity.
49. **AI duplicate detection** — highlight duplicated code blocks with
    a "DUPLICATE of line N" annotation.
50. **AI dead code warning** — highlight unused code with a
    "UNREFERENCED" annotation.

### D. ad_vim Visualization Improvements for AI Code

51. **Side-by-side old/new view** — show the goal (new file) alongside
    the animation so the viewer knows where it's heading.
52. **Change magnitude indicator** — show "this hunk changes 45% of
    the function" so the viewer knows how big the change is.
53. **Before/after snapshot** — press `s` to snapshot the current state
    and compare with the new file.
54. **Function boundary markers** — draw lines between functions so the
    viewer knows when the animation crosses a function boundary.
55. **Import change summarization** — show "3 imports added, 1 removed"
    as a single line instead of animating each import.
56. **Docstring change summarization** — show "docstring updated" as a
    single line instead of animating each char of the docstring.
57. **Whitespace-only change detection** — skip animating
    whitespace-only changes with a "formatting only" annotation.
58. **Comma/bracket change batching** — batch trailing comma and bracket
    changes as "syntax adjustment".
59. **Type hint change summarization** — show "type hints added" as a
    single line.
60. **Error handling change summarization** — show "try/except added"
    as a single annotation.
61. **Logging change summarization** — show "logging added" as a single
    annotation.
62. **Config change summarization** — show "config updated" for
    environment variable / config file changes.
63. **Test file detection** — detect when the diff is in a test file
    and use a different animation style (faster, less highlighting).
64. **Generated file detection** — detect generated files (e.g.,
    package-lock.json) and skip animation entirely.
65. **Large file detection** — for files > 500 lines, offer to show a
    summary instead of full animation.

### E. ad_vim Post-Processing for AI Code

66. **AI noise reduction** — post-process the diff to remove
    formatting-only changes, import reordering, and docstring whitespace.
67. **Semantic merge** — merge changes that are semantically equivalent
    (e.g., `True` → `true` in Python where they mean the same).
68. **Context expansion** — automatically expand context around AI
    changes because they tend to be less obvious.
69. **Change grouping by AST** — group changes by AST node (function,
    class, method) rather than by line proximity.
70. **Rename tracking** — track variable/function renames and show them
    as a single "rename" op instead of delete+insert.
71. **Extract method detection** — detect when code is extracted into a
    new method and show "extracted to method X()".
72. **Inline method detection** — detect when a method is inlined and
    show "inlined from method X()".
73. **Pattern replacement detection** — detect common AI patterns
    (e.g., `for i in range(len(x))` → `for item in x`) and annotate.
74. **Error message normalization** — detect when only error messages
    change and batch them.
75. **String format change detection** — detect f-string vs. .format()
    vs. % changes and show as "format changed".

### F. AI Tooling Integration (offline)

76. **Pre-commit hook** — run AI analysis as a pre-commit hook, store
    results in a `.ad_vim-annotations` file, ad_vim reads it.
77. **CI/CD integration** — generate annotations in CI, ad_vim reads
    them during animation.
78. **Git notes** — store AI annotations as git notes on the commit.
79. **Diff metadata format** — extend the precomputed diff format with
    `# AI_SUMMARY: ...`, `# AI_RISK: high`, `# AI_CATEGORY: bugfix`
    lines that ad_vim reads and displays.
80. **Annotation cache** — cache AI annotations so re-running ad_vim
    on the same diff doesn't require re-analysis.
81. **Batch analysis** — analyze all hunks in one AI call (not per-hunk)
    to minimize cost.
82. **Model selection** — use a cheap model (e.g., Haiku) for simple
    categorization, expensive model only for complex hunks.
83. **Local model** — use a local LLM (e.g., CodeLlama) for annotation
    to avoid API costs entirely.
84. **Static analysis** — use linters/type checkers instead of AI for
    risk scoring (free, fast, deterministic).
85. **Test runner** — run tests before and after the diff to identify
    which changes break tests.

### G. Documentation and Communication

86. **AI change report** — generate a markdown report summarizing all
    changes with AI annotations, for review without animation.
87. **Change log generation** — use AI to generate a changelog entry
    from the diff.
88. **PR description generation** — use AI to generate a PR description
    from the diff.
89. **Review checklist** — generate a review checklist based on the
    types of changes in the diff.
90. **Risk heatmap** — generate a visual heatmap of risk across the
    file, showing which regions need the most attention.
91. **Dependency graph** — generate a dependency graph showing which
    modules are affected by the changes.
92. **Timeline view** — show a timeline of changes with timestamps,
    categories, and risk levels.
93. **Comparison report** — compare this diff with previous diffs by
    the same AI to identify patterns (e.g., "this AI always adds
    unnecessary type hints").
94. **Learning material** — for educational use, generate explanations
    of why the AI made each change.
95. **Best practices** — generate best-practice recommendations based
    on the patterns in the diff.

### H. Future Research Directions

96. **Eye tracking study** — track where reviewers look during AI diff
    animation to identify which features help the most.
97. **Comprehension testing** — after watching an AI diff animation,
    test the viewer's understanding of what changed and why.
98. **A/B testing** — compare different animation styles (char-by-char
    vs. word-by-word vs. block) for AI diff comprehension.
99. **Cognitive load measurement** — use EEG or pupil dilation to
    measure cognitive load during AI diff review.
100. **Long-term retention** — test whether reviewers who watch AI diff
     animations remember the changes better than those who read
     static diffs.

---

## Recommendation: What to Implement First

### High Impact, Low Effort (no AI needed)
- #1 Semantic diff mode (AST comparison)
- #4 Variable rename detection
- #55-61 Summarization modes (imports, docstrings, type hints, etc.)
- #66 AI noise reduction (post-processing)
- #79 Diff metadata format (extend precomputed format)

### High Impact, Medium Effort (offline AI)
- #24 Hunk documentation (AI generates summaries offline)
- #36 Pre-computed AI annotations (stored in diff file)
- #81 Batch analysis (one AI call for all hunks)
- #83 Local model (CodeLlama for free annotation)

### Research Needed
- #96-100 User studies to validate which features actually help

---

## Note on Real-Time AI

Asking an AI for each hunk during ad_vim animation is **not acceptable**
because:
1. **Cost**: Each API call costs $0.01-0.10. A 20-hunk diff = $0.20-2.00.
2. **Latency**: Each call takes 1-5 seconds. A 20-hunk diff = 20-100
   seconds of waiting.
3. **Flow**: The animation is meant to be continuous. Pausing for AI
   calls breaks the viewer's concentration.
4. **Offline**: ad_vim should work without internet access.

**Solution**: All AI analysis should be done **offline**, before the
animation starts. Results are stored in the precomputed diff file as
metadata comments. ad_vim reads and displays them during animation
without any API calls.

```bash
# Example workflow:
ad_vim-ai-annotate old.py new.py > annotated.diff  # offline AI call
ad_vim --precomputed annotated.diff old.py new.py   # animation with annotations
```

The annotated diff file would look like:
```
# ad_vim precomputed diff v1
# AI_SUMMARY: Changed print() to f-string, added type hints
# AI_RISK: low
# AI_CATEGORY: refactor
# hunk_count 1
HUNK 2 1 1 0 0
# AI_HUNK_SUMMARY: Replaced string concatenation with f-string
# AI_HUNK_RISK: low
keep 32
...
```

> **Note:** The project now uses an external pipeline (ad_compute → ad_postprocess → ad_layer_pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`ad_colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
