13. **Support running inside an existing vim** via `:Diffvim` command — load the engine as a plugin and drive it from within vim using timers, no tmux needed.

37. **Add `zz` / `zt` / `zb` cursor positioning** — keep the cursor centered/top/bottom of the screen during animation for better visibility.

38. **Support variable speed via `+`/`-` keys** — let the user dynamically speed up or slow down the animation without pausing.

39. **Add a progress bar in the vim status line** — show "hunk 3/7 (42%)" in the status line so the user knows how much is left.

43. **Add a `--speed` flag** — set the overall animation speed multiplier (0.5x, 1x, 2x, 5x) without needing to set individual delay env vars.

50. **Support `--output` flag** — after animation, write the result to a file instead of leaving it in the vim buffer.

54. **Support multi-file animation** — animate diffs across multiple files, transitioning between files with a brief "next file: X" message.

55. **Add a `--context` flag** — set the number of context lines shown around each hunk (default: 3, like unified diff).

60. **Implement `--max-chars` limit** — if a hunk has more than N changed characters, skip the char-by-char animation and apply it instantly (useful for large changes).

86. **Write a comprehensive man page** — document all flags, env vars, controls, and architecture with examples.

98. **Implement `--replay` from git history** — given a file and a commit range, animate each commit's changes to the file in sequence.


> **Note:** The project now uses an external pipeline (diffvim-compute-cpp → diffvim-postprocess → diffvim-pace → animator). See `docs/PIPELINE.md` and `docs/DEVELOPER_GUIDE.md` for the current architecture. Coloring (`diffvim-colorize`), streaming mode (`--stream`), and typed delays are described in the Developer Guide.
