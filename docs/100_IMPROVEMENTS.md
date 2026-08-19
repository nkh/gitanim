# 100 Improvements for diffvim

A prioritized list of improvements, bug fixes, and new features.

## Correctness (1-10)

1. **Ghost-line fix**: when delete \n and line has content, don't delete
   the \n — move cursor to next line. Requires postprocess to emit
   content deletes at (line+1, 1) instead of (line, col).

2. **Snapshot-after-each-op test**: create a test that snapshots the
   buffer after every op and compares with expected visual output.

3. **UTF-8 boundary testing**: verify the animator handles multi-byte
   UTF-8 correctly (insert, delete, batch_delete at multi-byte boundaries).

4. **Empty file edge cases**: old empty, new empty, both empty,
   old non-empty → new empty, old empty → new non-empty.

5. **Trailing newline handling**: verify files with and without trailing
   newlines produce correct output.

6. **Very long lines (>8192 chars)**: the MAX_LINE_LEN limit may cause
   truncation. Increase or make dynamic.

7. **Binary file detection**: refuse to animate binary files (detect
   NUL bytes in the first 8K).

8. **Line ending normalization**: handle \r\n (Windows) vs \n (Unix)
   consistently.

9. **BOM handling**: strip UTF-8 BOM from the start of files.

10. **File encoding detection**: handle UTF-16, Latin-1, etc.

## Performance (11-20)

11. **Streaming pipeline end-to-end**: make pace and animator stream
    hunks too (currently only postprocess has --stream).

12. **Parallel coloring**: colorize old and new files in parallel
    (already done in diffvim-pipeline, but not in diffvim launcher).

13. **Memory-mapped file reading**: for very large files, use mmap
    instead of reading into memory.

14. **Cache diff results**: if the same file pair is animated again,
    reuse the cached timed op stream (mtime-checked).

15. **Lazy op loading**: for very large diffs, load ops from disk
    on demand instead of reading the entire timed stream into memory.

16. **Render throttling**: in the C animator, limit render rate to
    60fps (skip renders if ops are faster than 16ms apart).

17. **Batch render**: render multiple ops' changes in one screen update
    (already done in vimscript; add to C).

18. **Precompute diff for git replay**: when animating a range of
    commits, precompute all diffs in parallel before starting.

19. **Profile-guided optimization**: use profiling to find hot spots
    in the C animator on large files.

20. **Zero-copy buffer**: avoid strdup/strpart in the animator's
    hot path for char insert/delete.

## Visual Quality (21-40)

21. **Smooth cursor movement**: interpolate cursor position between
    ops (currently jumps instantly with set_cursor).

22. **Cursor trail**: show a brief trail/fade when the cursor jumps
    more than 3 lines.

23. **Syntax highlighting in standalone animator**: integrate the
    colormap system into the C animator's rendering (already
    supported via --colormap-old/--colormap-new).

24. **Diff highlighting**: highlight inserted chars in green, deleted
    chars in red (before they disappear).

25. **Hunk boundary indicators**: show a visual separator between hunks.

26. **Progress bar**: show a progress bar at the bottom indicating
    how far through the animation we are.

27. **Line numbers**: optionally show line numbers in the margin.

28. **Minimap**: show a minimap of the file on the right side with
    changed regions highlighted.

29. **Dim unchanged regions**: dim unchanged lines (already supported
    via --dim-unchanged).

30. **Word-level highlighting**: highlight the specific word being
    changed (already supported via --highlight word).

31. **Hunk-level highlighting**: highlight the entire hunk before
    animating (already supported via --highlight hunk).

32. **Inline char highlighting**: paint freshly typed chars green,
    deleted chars red, with a fade (already supported via
    --highlight inline).

33. **Color theme support**: dark/light/high-contrast themes
    (already supported via --theme).

34. **Custom color schemes**: allow user-defined color schemes for
    syntax highlighting.

35. **Git blame integration**: show git blame info for changed lines
    (already supported via --git-blame).

36. **Sign column**: show +/- signs in vim's sign column for changed
    lines (already supported via --sign-column).

37. **Fold unchanged regions**: fold long unchanged regions between
    hunks (already supported via --fold-unchanged).

38. **Smooth scroll**: when the viewport scrolls, animate the scroll
    instead of jumping.

39. **Typing sound**: optionally play a typing sound for each char
    insert/delete.

40. **Terminal bell on error**: ring the bell when an error occurs
    (e.g., buffer overflow, missing file).

## Architecture (41-55)

41. **Remove old vimscript code**: the old compute/postprocess/pace
    code was removed (~2800 lines). The engine is now a ~200-line
    timed-op-stream reader. DONE.

42. **Unify C and Perl animators**: the C and Perl animators share
    the same logic but are separate codebases. Consider generating
    one from the other, or merging into a single codebase.

43. **Plugin architecture for compute**: allow different diff
    algorithms to be plugged in (Patience, Myers, difftastic).

44. **Plugin architecture for postprocess**: allow custom transforms
    to be loaded as shared libraries.

45. **Plugin architecture for coloring**: allow custom colorizers
    (bat, pygmentize, vim, tree-sitter, etc.).

46. **Single binary**: compile all pipeline stages into a single
    binary with subcommands (diffvim compute, diffvim postprocess, etc.).

47. **Configuration file**: support a .diffvimrc file for default
    options.

48. **Environment variable consolidation**: reduce the number of
    DIFFVIM_* env vars; use a single config dict instead.

49. **Thread-safe animator**: make the C animator thread-safe so it
    can render and accept user input concurrently.

50. **Network protocol**: allow the animator to stream ops over a
    network (for remote collaboration).

51. **File watcher**: watch for file changes and re-animate
    automatically when the file changes.

52. **Plugin mode in vim**: improve the :Diffvim command to support
    multi-file, git replay, and preset selection.

53. **VS Code extension**: port the animator to VS Code.

54. **Web-based animator**: render the animation in a browser using
    WebAssembly.

55. **Record/replay**: record an animation and replay it later
    without re-computing the diff.

## Testing (56-65)

56. **Fuzzing**: fuzz the compute tool with random file pairs to
    find crashes.

57. **Property-based testing**: generate random file pairs and verify
    that animate(old, new) == new for all inputs.

58. **Visual regression testing**: capture screenshots of the
    animation at specific points and compare with golden images.

59. **Performance regression testing**: track timing for each example
    and alert on regressions.

60. **Cross-language parity tests**: expand test_cross_language.pl to
    cover more edge cases (empty files, single-char files, etc.).

61. **Test all 42 examples with Perl animator**: currently only the C
    animator is tested in verify_md5.sh. Add Perl animator column.

62. **Test streaming mode**: verify --stream produces the same output
    as batch mode.

63. **Test colormap rendering**: verify the C animator renders
    correctly with --colormap-old and --colormap-new.

64. **Test all delete-pacing modes**: char, rapid-eol, rapid-identical,
    accel, word, instant — each should produce correct output.

65. **Test all insert-pacing modes**: char, word, accel.

## UX / Developer Experience (66-80)

66. **Better error messages**: when a pipeline stage fails, show
    which stage and what went wrong.

67. **Verbose mode**: --verbose to show each pipeline stage's timing
    and output summary.

68. **Dry-run mode**: --dry-run to show what would be animated without
    actually running vim or the animator.

69. **Interactive speed control**: allow the user to change speed
    during animation with a slider (not just +/- keys).

70. **Seek bar**: allow jumping to a specific hunk or op index.

71. **Bookmark ops**: allow the user to bookmark specific points in
    the animation and jump back to them.

72. **Copy-on-select**: allow the user to select text during animation
    and copy it to the clipboard.

73. **Search within buffer**: allow searching for text in the current
    buffer during animation.

74. **Undo/redo**: allow undoing the last N ops during animation.

75. **Split view**: show old and new files side by side with the
    animation in the middle.

76. **Diff stat overlay**: show a summary of changes (+N -M lines)
    at the start of the animation.

77. **Language detection**: auto-detect the language from the file
    extension and set vim's filetype accordingly.

78. **Preset browser**: an interactive picker for presets
    (fast-delete, review, demo, ai-code).

79. **Custom presets**: allow users to define their own presets in
    the config file.

80. **Shell completion improvements**: complete file paths, commit
    hashes, and preset names.

## Documentation (81-90)

81. **Quick start guide**: a 5-minute getting started guide. (DONE —
    docs/src/quick-start.md)

82. **Developer guide**: comprehensive onboarding for contributors.
    (DONE — docs/DEVELOPER_GUIDE.md)

83. **API reference**: document the timed op stream format, all CLI
    options, and all environment variables.

84. **Architecture diagrams**: visual diagrams of the pipeline
    stages and data flow.

85. **Man pages**: keep man pages up to date with every CLI change.
    (DONE — man/*.1 updated)

86. **Shell completion docs**: document how to install completions
    for bash, fish, and zsh. (DONE — docs/src/completion.md)

87. **Video tutorials**: record short videos showing the animation
    for common use cases.

88. **FAQ**: common questions and answers (e.g., "why does my file
    flash?", "how do I slow down the animation?").

89. **Changelog**: keep CHANGELOG.md updated with every change.
    (DONE)

90. **Migration guide**: for users upgrading from the old multi-
    language version to the new single-C++ version.

## Polish (91-100)

91. **Clean up warnings**: fix all compiler warnings in the C code
    (unused variables, strncpy truncation, etc.).

92. **Remove dead code**: remove unused functions, variables, and
    includes.

93. **Consistent naming**: ensure all functions follow the same
    naming convention (snake_case in C, camelCase in Perl).

94. **Consistent error handling**: use a consistent error reporting
    mechanism (stderr + exit code) across all tools.

95. **Version string**: add --version to all tools.

96. **License header**: add license headers to all source files.

97. **Code formatting**: run a formatter (clang-format, perltidy)
    on all source files.

98. **CI pipeline**: set up GitHub Actions to run tests on every
    push.

99. **Release packaging**: create a release tarball with pre-built
    binaries for common platforms.

100. **Homebrew formula**: update packaging/diffvim.rb for the new
     single-binary architecture.
