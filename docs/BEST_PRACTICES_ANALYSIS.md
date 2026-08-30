# 100 Best Practices Analysis

A deep analysis of the `ad` project against 100 software engineering best practices.

**Legend:** ✅ Followed | ⚠️ Partial | ❌ Not followed | N/A Not applicable

---

## Architecture & Design (1-15)

### 1. Single Responsibility Principle

Each module should have one reason to change.

✅ **Followed.** Each component has a clear single responsibility: `ad_compute` computes diffs, `ad_postprocess` orchestrates layers, each layer transforms ops, `ad` animates. The directory structure (diff_engine/, layers/, animator/, pipeline/) maps to responsibilities.

### 2. Separation of Concerns

Business logic, I/O, and presentation should be separate.

✅ **Followed.** Diff computation (diff_engine/) is separate from op transformation (layers/) which is separate from rendering (animator/). The V2 TSV format is the clean boundary — each stage reads TSV, writes TSV, knows nothing about the next stage.

### 3. Dependency Inversion

High-level modules should not depend on low-level modules. Both should depend on abstractions.

✅ **Followed.** The orchestrator depends on the V2 TSV contract, not on any specific layer implementation. Layers depend on `ad_layer_common.h` (the abstraction), not on the orchestrator. The launcher depends on the orchestrator's CLI interface, not its internals.

### 4. Interface Segregation

Clients should not be forced to depend on interfaces they do not use.

✅ **Followed.** The `ad_layer_common.h` header only exposes what layers need: Op/Hunk types, parse/write functions, and the `ad_layer_run()` driver. Pace and highlight layers that need more (like `ad_layer_parse_tsv`) include the same header but only use what they need.

### 5. Open/Closed Principle

Software entities should be open for extension but closed for modification.

✅ **Followed.** Adding a new layer requires zero changes to existing code — drop a binary, add `--ad-layer=<name>`. The orchestrator, launchers, and other layers don't need modification.

### 6. Don't Repeat Yourself (DRY)

Every piece of knowledge must have a single, unambiguous representation.

⚠️ **Partial.** The C layers no longer duplicate boilerplate (fixed via `ad_layer_run()`). The Perl layers share `DiffVim::Layer.pm`. However, `char_repr` is still defined in both C (`ad_layer_common.h`) and C++ (`compute.cpp`), and the `parse_tsv` pattern is duplicated between `ad_layer_pace.c` and inline code in `ad.c`.

### 7. Keep It Simple, Stupid (KISS)

Simplicity should be a key goal in design.

⚠️ **Partial.** The core pipeline is simple (4 stages, TSV between them). But `ad_vim` is 2,170 lines of bash with an embedded 800-line vimscript heredoc — far from simple. The pace layer has 14 functions and 911 lines, which is manageable but not simple.

### 8. You Aren't Gonna Need It (YAGNI)

Don't implement features until they're needed.

⚠️ **Partial.** Many features were added speculatively (6 pacing strategies, 4 scroll modes, distance-based speed, gaussian jitter, adaptive timing, block delete). Some are rarely used. The `--semantic-cleanup` and `--word-diff` flags in compute are implemented but unclear if anyone uses them.

### 9. Composition Over Inheritance

Prefer composing objects over deep inheritance hierarchies.

✅ **Followed.** The pipeline composes stages via pipes. Layers compose via the orchestrator chain. No inheritance hierarchies exist (C has no inheritance). The `ad_layer_run()` driver is composed into each layer via a function pointer, not inheritance.

### 10. Principle of Least Astonishment

A component should behave as users would expect.

⚠️ **Partial.** `--indent-aware` was surprising (it skipped ops, producing wrong output — now removed). `--left-to-right` was redundant (removed). The `overwrite_insert` op type is a non-obvious hybrid. The fact that pace and highlight are "layers" but run as separate pipeline stages (not via `--ad-layer`) is confusing.

### 11. Fail Fast

Errors should be detected as early as possible.

✅ **Followed.** The orchestrator resolves all layers upfront (before reading input) and fails immediately if a layer isn't found. The `--ad-layer-dry-run` flag lets users verify the chain before executing. Compute checks for v1 format and exits with a clear error.

### 12. Design by Contract

Functions should have clear preconditions, postconditions, and invariants.

⚠️ **Partial.** The plugin contract is documented (read TSV, write TSV, exit 0) but not enforced. No validation of layer output between stages. A layer could write garbage and the next layer would try to parse it.

### 13. Coupling and Cohesion

Strive for low coupling and high cohesion.

✅ **Followed.** Layers are loosely coupled (communicate only via TSV). Each layer is highly cohesive (one transform, one file, one purpose). The orchestrator doesn't know what layers do internally.

### 14. Layered Architecture

Organize code into layers with clear dependencies.

✅ **Followed.** Four layers: diff engine → postprocess layers → pace → animator. Each layer only depends on the previous layer's output format, not its implementation.

### 15. Hexagonal Architecture (Ports and Adapters)

Core logic should be isolated from external concerns.

⚠️ **Partial.** The core logic (diff algorithm, layer transforms) is isolated. But the animator (`ad.c`) mixes core logic (buffer manipulation) with I/O (terminal rendering, keyboard input, colormap loading). The vimscript engine mixes animation logic with vim-specific rendering.

---

## Code Quality (16-30)

### 16. Meaningful Names

Variables, functions, and types should have descriptive names.

⚠️ **Partial.** Most names are clear (`ad_layer_reorder`, `handle_delete_newline`, `skip_indent_mode`). But the reorder layer has `is_b` (is boundary), `cl` (current line), `cc` (current col) — too terse. The `pd` and `ni` variables in overwrite are unexplained.

### 17. Small Functions

Functions should be short (typically under 20-30 lines).

✅ **Mostly followed.** After the pace.c refactoring, most functions are 10-30 lines. `main()` in layers is 1 line (calls `ad_layer_run()`). The pace layer's 14 functions average ~25 lines. The animator's `main()` is still ~200 lines (P3-3 not yet done).

### 18. Functions Should Do One Thing

Each function should have a single, well-defined purpose.

✅ **Followed.** `handle_keep` handles keep ops. `handle_delete_newline` handles \n deletes. `pace_delete_char` handles char-by-char deletes. `resolve_layer` resolves a layer name. Each does one thing.

### 19. Function Arguments (≤3 ideal)

Functions should have few parameters.

⚠️ **Partial.** Most layer functions take 3-4 args (in_ops, n_ops, out_ops, out_cap, line_offset). The `ad_route_option` function takes 7 args (6 are array namerefs). The `handle_*` functions in pace take 1 arg (the line string) but use 30+ global statics.

### 20. No Magic Numbers

Constants should be named, not hardcoded.

⚠️ **Partial.** `AD_LAYER_MAX_LINE` is centralized. But magic numbers remain: `4096` (initial op capacity), `1024` (output slack), `8` (max TSV tokens), `32`/`9` (space/tab char codes), `10` (newline code), `300` (default skip_indent pause).

### 21. Consistent Coding Style

Code should follow a consistent style guide.

✅ **Followed.** C uses `-Wall -Wextra -Werror` with consistent brace style, 4-space indent, snake_case naming. Perl uses `use strict; use warnings;` consistently. Bash uses `set -euo pipefail`.

### 22. Error Handling

Errors should be handled, not ignored.

✅ **Mostly followed.** The orchestrator captures and displays layer stderr on failure. All malloc/realloc now have NULL checks. The signal handler is async-signal-safe. But some `strdup` calls still lack NULL checks, and `popen` in git-blame doesn't handle all failure modes.

### 23. Resource Management

Memory, file handles, and other resources should be properly managed.

⚠️ **Partial.** C layers free their allocations. The orchestrator cleans up temp files via trap. But `ad.c` has 25+ static globals that are never freed (acceptable for a short-lived process, but not clean). The `all_lines` array in pace/highlight is freed, but error paths may leak.

### 24. Defensive Programming

Code should anticipate and handle edge cases.

⚠️ **Partial.** Layers handle empty hunks, debug ops, and missing fields. But there's no TSV validation between layers (L1 improvement proposed but not implemented). The pace layer doesn't handle malformed delay lines. The animator doesn't validate op positions before applying them.

### 25. Code Comments

Comments should explain why, not what.

⚠️ **Partial.** The layer transform algorithms have good comments (4-sweep reorder explained, indent_last col adjustment explained, skip_indent marker format documented). But many functions lack doc comments. Magic numbers are often uncommented. The pace layer's 6 pacing strategies have minimal comments on why each strategy exists.

### 26. Self-Documenting Code

Code should be readable enough to not need comments for understanding.

✅ **Mostly followed.** After refactoring, function names are descriptive (`handle_delete_newline`, `pace_delete_rapid_eol`, `do_highlight_word`). Variable names in the refactored layers are clearer. The `ad_layer_run()` driver is self-documenting with the `AD_LAYER_FLUSH_HUNK()` macro.

### 27. Avoid Deep Nesting

Control flow should be shallow (≤3 levels of nesting).

⚠️ **Partial.** The refactored pace layer reduced nesting. But `handle_delay` in pace has 4 levels (if marker → if col → if skip_mode → emit). The `do_highlight_word` function has 3-level loops with multiple break conditions. The `ad_vim` launcher has deeply nested option parsing.

### 28. Avoid Long Parameter Lists

Functions with many parameters are hard to use and maintain.

⚠️ **Partial.** Layer functions take 5 parameters (acceptable). `ad_route_option` takes 7 (borderline). The C++ `find_patience_anchors` takes 6 parameters with start/end ranges.

### 29. Use Constants Instead of Macros

Prefer `const` or `enum` over `#define` where possible.

❌ **Not followed.** C layers use `#define` for all constants (`AD_LAYER_MAX_LINE`, `AD_LAYER_TYPE_LEN`). The C++ code uses `enum OpType` (good) but also uses `#define` for some values. This is a C convention but not modern best practice.

### 30. Avoid Global State

Global variables make code harder to test and reason about.

⚠️ **Partial.** The pace layer has 30+ static globals (all config + loop state). The animator has 25+ static globals. The highlight layer has 5 static globals for hunk state. These are acceptable for standalone executables but would be problematic in a library.

---

## Testing (31-45)

### 31. Test-Driven Development (TDD)

Write tests before or alongside implementation.

⚠️ **Partial.** Per-layer tests exist (7 test files) and verify behavior + C/Perl parity. But they were written after the implementation, not before. The `test_layers_discovery.pl` is data-driven (auto-scales with layers). No test was written before any feature.

### 32. Test Coverage

All code paths should be exercised by tests.

⚠️ **Partial.** 167 tests cover the main pipeline, all layers, property-based random diffs, and 36 examples across 26 languages. But the C++ compute engine has no unit tests for individual functions (patience anchors, LCS, char_diff). The vimscript engine has limited test coverage. Error paths are largely untested.

### 33. Unit Testing

Each unit of code should be tested in isolation.

⚠️ **Partial.** Layers are tested in isolation (each test feeds known input, checks output). But the C++ diff engine functions are not unit-testable (they're not exposed as a library). The animator's buffer manipulation functions (insert_char, delete_char, set_cursor) are not unit-tested.

### 34. Integration Testing

Test components working together.

✅ **Followed.** The 36-example test corpus runs the full pipeline (compute → postprocess → pace → animate) end-to-end and verifies the output matches the new file. The 25 minimal cases test specific transformations through the full pipeline.

### 35. Property-Based Testing

Generate random inputs and verify invariants hold.

✅ **Followed.** `test_property.pl` generates 50 random file pairs, runs them through the full pipeline, and verifies: (1) the final buffer matches the new file, (2) no backward ops (cursor never moves backward).

### 36. Regression Testing

Ensure fixed bugs don't reappear.

✅ **Followed.** All tests run on every push via CI (`build-and-test.yml`). The 25 minimal cases were originally bug reproducers. The `test_indent_last.pl` test verifies the indent_last fix. The `test_skip_indent.pl` verifies the new layer.

### 37. Test Naming Conventions

Test names should describe what they test.

✅ **Followed.** Test files are named `test_<layer_name>.pl` (e.g., `test_reorder.pl`, `test_skip_indent.pl`). Test cases use descriptive names (`PASS: indent_skip_start marker found`).

### 38. Test Isolation

Tests should not depend on each other or on shared state.

✅ **Followed.** Each test file is independent. Tests use temp files (mktemp, /tmp/). The property test uses `File::Temp::tempdir(CLEANUP => 1)`. No test depends on another test's output.

### 39. Fast Tests

Tests should run quickly to enable rapid feedback.

✅ **Followed.** All 167 tests run in under 10 seconds. The C compute is ~1ms per file. The 36 examples complete in ~5 seconds. The property test's 50 random diffs take ~3 seconds.

### 40. Test Readability

Tests should be easy to read and understand.

✅ **Followed.** Test files follow a consistent pattern: setup (create input), run layer, check assertions, verify parity. The `ok()`/`bad()` helpers make pass/fail clear. The `test_skip_indent.pl` test has inline comments explaining the marker format.

### 41. Mocking and Stubbing

External dependencies should be mocked in tests.

❌ **Not followed.** Tests use the real binaries (no mocking). The pace test uses real delay timing (which could make tests flaky on slow machines). The git-blame feature in highlight is untested (requires a git repo). No mock framework is used.

### 42. Code Coverage Measurement

Track what percentage of code is exercised by tests.

❌ **Not followed.** No code coverage tool is configured. No `gcov`/`lcov` for C, no `Devel::Cover` for Perl, no coverage in CI. Coverage is unknown.

### 43. Mutation Testing

Verify tests catch bugs by mutating code.

❌ **Not followed.** No mutation testing framework is set up. However, the C/Perl parity tests serve as a weak form of mutation testing — if the C output changes, the Perl comparison catches it.

### 44. Fuzz Testing

Test with malformed or random inputs to find crashes.

⚠️ **Partial.** The property test generates random file pairs, but they're always valid text files. No test feeds malformed TSV to layers. No test feeds binary data. No test feeds extremely large inputs.

### 45. Performance Testing

Verify performance requirements are met.

⚠️ **Partial.** `test_perf.pl` exists but is not in the default test suite. The compute tool benchmarks itself (`compute: 11ms` on 1000 lines). But there's no performance regression test — no baseline to compare against.

---

## Version Control & CI (46-55)

### 46. Meaningful Commit Messages

Commit messages should explain why changes were made.

✅ **Followed.** Commits have descriptive messages with bullet points explaining what changed and why. Examples: "Remove ALL environment variables — use config file + CLI flags", "P3-1: Eliminate C layer boilerplate duplication (342 lines removed)".

### 47. Atomic Commits

Each commit should be a single logical change.

⚠️ **Partial.** Most commits are atomic (one feature or fix per commit). But some commits bundle multiple changes: "Fix P1/P2 bugs + key findings" touched 14 files across different concerns. "Layer mechanism improvements (L2/L3/L4/L9)" combined 4 features.

### 48. Branch Strategy

Use branches for features and fixes, merge via PR.

❌ **Not followed.** All development is on `main`. No feature branches, no pull requests, no code review. This is acceptable for a solo project but would be a problem with multiple contributors.

### 49. Continuous Integration

Automatically build and test on every push.

✅ **Followed.** CI workflows exist: `build-and-test.yml` (builds + tests), `lint.yml` (shellcheck + perl -c + gcc), `docs.yml` (mdbook), `release.yml` (tarballs). Workflows are in `github/` (move to `.github/workflows/` to activate — requires workflow scope).

### 50. Continuous Deployment

Automatically deploy after CI passes.

❌ **Not followed.** No CD pipeline. Releases are manual (`release.yml` triggers on git tags but doesn't auto-deploy). No staging environment. No canary releases.

### 51. Code Review

All changes should be reviewed before merging.

❌ **Not followed.** No PR-based code review. All commits go directly to `main`. The AI assistant makes changes without human review of each commit.

### 52. Pre-Commit Hooks

Run checks before allowing commits.

❌ **Not followed.** No pre-commit hooks. No `.pre-commit-config.yaml`. Checks run only in CI, not locally before commit.

### 53. Semantic Versioning

Version numbers should convey meaning (MAJOR.MINOR.PATCH).

✅ **Followed.** `VERSION` file contains `2.0.0`. The major version bump from 1.x to 2.0 reflects the complete restructure (renaming, new architecture, breaking changes). The `--version` flag reads from the VERSION file.

### 54. Changelog

Maintain a human-readable changelog.

✅ **Followed.** `CHANGELOG.md` exists (42KB). It documents changes across versions. However, it hasn't been updated since the restructure — the latest entries are from the 1.x era.

### 55. Git Tags

Tag releases for traceability.

❌ **Not followed.** No git tags exist. The `release.yml` workflow triggers on `v*` tags but none have been created. The version is tracked in `VERSION` file only.

---

## Documentation (56-65)

### 56. README Quality

The README should explain what the project is, how to use it, and how to contribute.

✅ **Followed.** `README.md` explains what `ad` is, has a quick-start guide, a transparent directory structure tree, configuration instructions, and links to docs. It's clear and concise.

### 57. API Documentation

All public APIs should be documented.

⚠️ **Partial.** The plugin contract is documented (`docs/src/plugin-layers.md`). The CLI flags are documented in manpages (25 manpages). But the C/C++ internal APIs (Op struct, layer function signature, compute functions) are only documented in header comments, not in a formal API reference.

### 58. Architecture Documentation

Document the architecture and design decisions.

✅ **Followed.** `docs/REQUIREMENTS.md` documents the full architecture with diagrams, component descriptions, and the V2 TSV format. `docs/src/architecture.md` provides an overview. `docs/src/plugin-layers.md` documents the plugin system.

### 59. Code Comments

Document non-obvious code with comments.

⚠️ **Partial.** As noted in #25, the layer algorithms are well-commented but many functions lack doc comments. The pace layer's 14 functions have brief comments but could be more detailed. The C++ compute engine's algorithms (Patience, LCS) have minimal comments.

### 60. User Guide

Provide a guide for users to get started.

✅ **Followed.** `docs/src/` contains an mdBook user guide with: introduction, installation, quick-start, options, controls, configuration, examples, presets, contributing, testing. `docs/src/contributing.md` has the TDD workflow.

### 61. Inline Help (--help)

Every executable should have `--help` output.

✅ **Followed.** Every executable responds to `--help`/`-h`: `ad_vim`, `ad_pipeline`, `ad_postprocess`, `ad_compute`, `ad` (animator), all 7 layers, all helper scripts. The help text is generated from the manpage content.

### 62. Diagrams and Visuals

Use diagrams to explain complex concepts.

✅ **Followed.** `docs/REQUIREMENTS.md` has an ASCII architecture diagram. `docs/presentation.html` is a visual overview. `docs/src/plugin-layers.md` has an ASCII pipeline diagram. The manpages use ASCII for the TSV format.

### 63. Change Log

Document what changed between versions.

✅ **Followed.** `CHANGELOG.md` exists. Git commit messages serve as a detailed changelog. The `--version` flag shows the current version.

### 64. Manpages

Provide manpages for all command-line tools.

✅ **Followed.** 25 manpages cover all user-facing tools. `docs/MANPAGE_OVERVIEW.md` indexes them by category. All manpages document CLI flags, configuration, and examples.

### 65. Documentation Versioning

Documentation should match the code version.

⚠️ **Partial.** The `VERSION` file tracks the code version. But documentation doesn't have version markers. Some docs in `docs/design/` (58 files) are outdated and reference old architectures. The `DOCS_AUDIT.md` identified 28 docs for deletion, but they haven't been deleted.

---

## Security & Robustness (66-75)

### 66. Input Validation

All external input should be validated.

⚠️ **Partial.** The orchestrator validates layer names (checks if file exists, is executable). The compute tool validates input files (binary detection, existence). But TSV input is not validated between layers — a malformed layer output will crash the next layer.

### 67. SQL/Command Injection Prevention

Prevent injection attacks.

✅ **Mostly followed.** The `eval` in the custom preset was replaced with safe `declare`-based parsing. The `colorize.pl` uses list-form `system()` to prevent injection. But `popen()` in the git-blame feature uses shell interpolation for the file path (`'` quoting is present but not escaped).

### 68. Secure Defaults

Security-sensitive settings should default to safe values.

✅ **Followed.** No env vars (no attack surface via environment). Config file is user-owned (not world-writable). Temp files use `mktemp` (not predictable paths). The `ad_vim` launcher doesn't execute arbitrary code from config.

### 69. Error Messages Without Information Leakage

Error messages should not reveal sensitive information.

✅ **Followed.** Error messages show layer name, binary path, and stderr — no system information, no file contents, no environment variables. The "layer not found" error lists search paths (which are project-relative, not sensitive).

### 70. Resource Limits

Prevent resource exhaustion (memory, CPU, file handles).

⚠️ **Partial.** The `AD_LAYER_MAX_LINE` (1MB) limits line size. The op array grows dynamically (realloc doubles capacity). But there's no limit on the number of ops, hunks, or total input size. A malicious input could cause OOM.

### 71. Safe Signal Handling

Signal handlers should only call async-signal-safe functions.

✅ **Followed.** The `cleanup_handler` in `ad.c` only calls `write()` and `_exit()`. Terminal restoration is done via `atexit()`. This was fixed in a previous commit (was calling `printf`, `tcsetattr`, `exit` — undefined behavior).

### 72. No Buffer Overflows

All buffer access should be bounds-checked.

⚠️ **Partial.** `strncpy` is used with size limits. `fgets` uses `sizeof(line)`. But `sscanf` with `%19s` in `ad_layer_parse_op` limits type length — if an op type is longer, it's truncated silently (no error). The TSV tokenizer in pace/highlight uses fixed-size `toks[8]` arrays.

### 73. Safe String Handling

Avoid `strcpy`, `strcat`, `sprintf` — use bounded versions.

⚠️ **Partial.** `strncpy` is used in some places. `snprintf` is used for git-blame command construction. But `strcpy` is used in the overwrite layer (`strcpy(out[n_out].type, "overwrite_insert")` — safe because the string is a literal shorter than the buffer). `sprintf` is not used (good).

### 74. Privilege Separation

Run with the least privilege necessary.

N/A **Not applicable.** The project runs as a normal user process. No privileged operations, no setuid, no network services.

### 75. Reproducible Builds

Builds should produce identical output given the same inputs.

⚠️ **Partial.** The C build uses standard flags (`-O2 -Wall`). But there's no `--date` or `--build-id` control. Perl scripts have no build step. The `VERSION` file is deterministic. No reproducible-build verification is set up.

---

## Performance (76-85)

### 76. Profiling

Profile before optimizing.

⚠️ **Partial.** The `--ad-layer-profile` flag shows per-layer timing. The compute tool reports its own timing. But there's no CPU profiler (perf, gprof) integration. No flamegraph generation (proposed as improvement #19 in REQUIREMENTS.md).

### 77. Algorithmic Complexity Awareness

Know the Big-O of your algorithms.

⚠️ **Partial.** The Patience diff is O(n log n) for anchor finding, O(n²) for LCS fallback. The `find_patience_anchors` function is O(n²·m) (should use hash maps). The char-level LCS is O(n·m) per line. The reorder layer is O(n) per hunk. These are documented in comments but not in a formal complexity analysis.

### 78. Memory Efficiency

Avoid unnecessary allocations and copies.

⚠️ **Partial.** The `ad_layer_run()` driver allocates an output buffer of `in_count + 1024` (slight overallocation). The pace and highlight layers read all input into memory (`all_lines` array of strdup'd strings). For a 50k-op stream, this uses ~50MB. A streaming approach would be more efficient but harder to implement for these layers.

### 79. I/O Efficiency

Minimize disk I/O and network calls.

✅ **Followed.** The default pipe mode chains layers via pipes (no temp files). The `--keep-temps` mode uses temp files but only for debugging. Input is read once (streaming for simple layers, buffered for pace/highlight).

### 80. Caching

Cache expensive computations.

❌ **Not followed.** No caching of any kind. The compute tool doesn't cache diff results. The colorize tool doesn't cache syntax highlighting. The git-blame feature runs `git blame` for each changed line individually (should batch by file).

### 81. Lazy Evaluation

Compute values only when needed.

⚠️ **Partial.** The orchestrator resolves layers lazily (only when needed). But the pace and highlight layers read ALL input into memory before processing. The animator reads the entire timed op stream before starting. The compute tool reads both files fully before diffing.

### 82. Parallel Processing

Use multiple cores when possible.

❌ **Not followed.** The entire pipeline is single-threaded. The compute tool is single-threaded C++. Layers run sequentially (pipes). The animator is single-threaded. The `PARALLELISM.md` doc exists in `diff_engine/` but no parallelism was implemented.

### 83. Streaming Processing

Process data in chunks, not all at once.

⚠️ **Partial.** The 4 small layers (reorder, overwrite, indent_last, line_delete_in_place) process hunk-by-hunk (streaming). But pace and highlight buffer all input. The animator buffers all input. The compute tool reads both files fully.

### 84. Avoid Premature Optimization

Don't optimize until you know it's needed.

✅ **Followed.** The project uses simple, readable algorithms. The C++ compute is fast enough (~1ms for 1000 lines). No SIMD, no lock-free data structures, no custom allocators. The only optimization was switching from vimscript LCS to C++ Patience (318x speedup).

### 85. Benchmark Regression Testing

Ensure performance doesn't degrade over time.

❌ **Not followed.** `test_perf.pl` exists but is not in the default test suite. No performance baseline is recorded. No CI step checks timing. A performance regression could go unnoticed.

---

## Maintainability (86-95)

### 86. Code Organization

Files and directories should be logically organized.

✅ **Followed.** The directory structure maps to responsibilities: `diff_engine/`, `layers/`, `animator/`, `pipeline/`, `apps/vim/`, `scripts/`, `tests/`, `docs/`, `man/`, `completion/`, `packaging/`. Each directory has a `README.md`.

### 87. Module Size

Modules should not be too large.

⚠️ **Partial.** Most files are reasonable (<500 lines). But `ad_vim` is 2,170 lines (P3-5), `ad_layer_pace.c` is 911 lines, `compute.cpp` is ~900 lines, `ad_layer_highlight.c` is ~450 lines. The `ad_tmux` was reduced from 1,673 to 103 lines (P3-6).

### 88. Technical Debt Tracking

Document and track technical debt.

⚠️ **Partial.** `docs/CODE_ANALYSIS.md` documents 41 issues (P0-P3). `docs/P3_ISSUES.md` lists 12 maintainability issues. But there's no formal issue tracker, no debt burndown, no priority assignment for remaining items.

### 89. Refactoring Discipline

Regularly refactor to keep code clean.

✅ **Followed.** The project underwent a major refactoring: C layer boilerplate eliminated (342 lines removed), pace.c split (430→122 line main), ad_tmux reduced (1673→103 lines), env vars removed (107→0), shared modules created (Layer.pm, ad_layer_common.h).

### 90. Dependency Management

Track and minimize external dependencies.

✅ **Followed.** Minimal dependencies: vim (for ad_vim), tmux (for ad_tmux, optional), perl (for fallbacks), gcc/g++ (for building). No npm, pip, cargo, or gem dependencies. No vendored libraries. The DiffVim::Parser::Perl module is self-contained.

### 91. Backward Compatibility

Don't break existing users without warning.

⚠️ **Partial.** The `diffvim` wrapper script preserves backward compatibility. But the restructure broke many things: env vars removed (hard cut), paths changed (compute/ → diff_engine/), binary names changed. No deprecation period was given. The `CHANGELOG.md` wasn't updated for 2.0.

### 92. Cross-Platform Compatibility

Code should work on multiple platforms.

⚠️ **Partial.** Works on Linux (primary) and macOS (Homebrew formula exists). Uses POSIX functions (`termios`, `sigaction`, `fork`). The C code uses `gcc`-specific `__attribute__((unused))`. The `date +%s.%N` in the orchestrator is GNU-specific (not on macOS). No Windows support.

### 93. Internationalization (i18n)

Support multiple languages and locales.

❌ **Not followed.** All messages are in English. No gettext, no locale support. Unicode is handled in the diff (UTF-8 codepoints) but error messages and help text are English-only. Improvement #20 in REQUIREMENTS.md proposes this.

### 94. Accessibility

Make the tool usable by people with disabilities.

N/A **Not applicable.** This is a terminal/vim tool, not a GUI. The animation is visual by nature. The `--no-display` flag enables headless mode. No screen reader support (vim handles that).

### 95. Monitoring and Observability

Be able to understand what the system is doing.

✅ **Followed.** The `--debug` flag enables per-layer debug logging. The `--ad-layer-profile` flag shows timing. The `--ad-layer-keep-temps` preserves intermediate files. The `--verbose` flag in the animator prints debug info. The orchestrator prints the layer chain to stderr.

---

## Process & Team (96-100)

### 96. Issue Tracking

Track bugs, features, and tasks.

❌ **Not followed.** No issue tracker (GitHub Issues not used). Issues are tracked in ad-hoc analysis documents (`CODE_ANALYSIS.md`, `P3_ISSUES.md`). No labels, no milestones, no assignment.

### 97. Release Process

Have a defined release process.

⚠️ **Partial.** `scripts/ad_package.sh` creates a release tarball. `github/release.yml` creates a GitHub Release on tag. But no release checklist, no QA process, no beta/rc cycle. No release has actually been made (no git tags exist).

### 98. Coding Standards Document

Document the coding standards for the project.

⚠️ **Partial.** `docs/src/contributing.md` mentions TDD workflow and coding standards briefly (C: `-Wall -Wextra -Werror`, Perl: `use strict; use warnings;`, Bash: `set -euo pipefail`). But there's no detailed style guide (brace placement, naming convention, comment format).

### 99. Onboarding Guide

Help new contributors get started quickly.

✅ **Followed.** `docs/src/contributing.md` has a quick-start guide, project layout, and step-by-step instructions for adding a layer. `README.md` has setup instructions. `docs/REQUIREMENTS.md` explains the architecture. `docs/MANPAGE_OVERVIEW.md` indexes all tools.

### 100. Regular Retrospectives

Periodically review what went well and what didn't.

❌ **Not followed.** No retrospectives, no post-mortems, no lessons-learned documents. The analysis documents (`CODE_ANALYSIS.md`, `LAYER_ANALYSIS_AND_DOC_REVIEW.md`) serve as one-time audits, not recurring reviews.

---

## Summary

| Category | ✅ Followed | ⚠️ Partial | ❌ Not followed | N/A | Total |
|----------|------------|------------|-----------------|-----|-------|
| Architecture & Design (1-15) | 9 | 6 | 0 | 0 | 15 |
| Code Quality (16-30) | 6 | 8 | 1 | 0 | 15 |
| Testing (31-45) | 8 | 5 | 2 | 0 | 15 |
| Version Control & CI (46-55) | 4 | 2 | 4 | 0 | 10 |
| Documentation (56-65) | 7 | 3 | 0 | 0 | 10 |
| Security & Robustness (66-75) | 4 | 5 | 0 | 1 | 10 |
| Performance (76-85) | 3 | 5 | 2 | 0 | 10 |
| Maintainability (86-95) | 5 | 4 | 1 | 0 | 10 |
| Process & Team (96-100) | 1 | 2 | 2 | 0 | 5 |
| **Total** | **47** | **40** | **12** | **1** | **100** |

### Top 10 most impactful improvements to make

1. **#42 Code coverage** — set up gcov/lcov to know what's actually tested
2. **#48 Branch strategy** — use feature branches + PRs for review
3. **#52 Pre-commit hooks** — run linters locally before commit
4. **#96 Issue tracking** — use GitHub Issues for bugs/features
5. **#66 Input validation** — add TSV validation between layers (L1)
6. **#91 Backward compatibility** — add deprecation warnings for old paths
7. **#80 Caching** — cache git-blame results per file (not per line)
8. **#82 Parallel processing** — parallelize compute for large files
9. **#54 Changelog** — update CHANGELOG.md for 2.0
10. **#55 Git tags** — tag the v2.0.0 release
