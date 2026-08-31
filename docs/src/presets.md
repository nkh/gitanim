# Presets

*Created:* `c07e1e1` (2026-08-16 08:00:10 +0000)
*Last updated:* `4625efa` (2026-08-28 15:24:52 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


diffvim ships with **six built-in presets** that bundle a sane
combination of post-processing and timing options for common use cases.
Presets are the easiest way to get a good result without having to
learn every individual option.

## Usage

```bash
diffvim --preset NAME <oldfile> <newfile>
diffvim --preset review --git-blame old.py new.py
AD_PRESET="review --highlight-word" diffvim old.py new.py
```

You can override any preset option by passing additional flags after
`--preset NAME` — they take precedence. You can also define a personal
default via the `AD_PRESET` environment variable.

## The Six Built-in Presets

### `default`

What you get with no `--preset` flag. Raw Patience with
`--optimize-sequence` enabled. Good for everyday use on small to
medium files where you want to see exactly what changed.

```bash
diffvim old.py new.py
```

### `fast-delete`

Aggressive deletion acceleration for refactors that remove large
blocks of code. Combines `--rapid-eol-delete`, `--accel-delete`,
and `--word-accel`.

```bash
diffvim --preset fast-delete old.py new.py
```

Use this when you're reviewing a refactor that deletes whole
functions or large chunks of dead code. The trailing deletes
accelerate rapidly so the viewer doesn't have to watch each
character disappear one by one.

### `review`

Code-review mode. Pauses after each hunk so you can read the change
carefully before advancing. Highlights the entire hunk, dims
unchanged regions, and top-aligns the cursor so the change is always
near the top of the screen.

```bash
diffvim --preset review --git-blame old.py new.py
diffvim --preset review --git-rev HEAD~10..HEAD main.py
```

Press `n` to advance to the next hunk. Press `b` to go back.

### `ai-code`

Tuned for AI-generated diffs, which tend to be messy with
interleaved inserts and deletes. Enables `--highlight-inline` and
`--word-diff` so the animation reads naturally even when the underlying
Patience is chaotic.

```bash
diffvim --preset ai-code old.py new.py
diffvim --preset ai-code --highlight-word --adaptive-timing old.py new.py
```

Use this when reviewing diffs from Copilot, ChatGPT, Claude, or any
other AI coding assistant. The combination of post-processing passes
turns a confusing char-level diff into something that resembles
human edits.

### `demo`

For live demos and presentations. Slows down to 0.7x speed,
highlights typed/deleted chars, and pauses briefly after each word
so the audience can follow.

```bash
diffvim --preset demo --max-line-len 120 old.py new.py
diffvim --preset demo --scroll zz --git-blame old.py new.py
```

### `presentation`

For recording screencasts. 1.2x speed, no rapid-EOL delete (so the
video captures every deletion), cursor centered on screen.

```bash
diffvim --preset presentation --output result.py old.py new.py
```

## Comparison Table

| Preset         | Speed | Highlight | Pause       | Post-processing                  | Best for                |
| -------------- | ----- | --------- | ----------- | -------------------------------- | ----------------------- |
| `default`      | 1.0x  | off       | none        | optimize_sequence                | Everyday use            |
| `fast-delete`  | 1.0x  | off       | none        | optimize + rapid-EOL + word-accel| Large refactors         |
| `review`       | 1.0x  | hunk      | after hunk  | optimize + dim-unchanged         | Code review             |
| `ai-code`      | 1.0x  | inline    | none        | word-diff                        | AI-generated diffs      |
| `demo`         | 0.7x  | inline    | after word  | optimize + word-pause            | Live demos              |
| `presentation` | 1.2x  | off       | none        | optimize                         | Screencast recording    |

## Custom Presets

Define your own preset via the `AD_PRESET` environment variable.
The value is split on spaces and prepended to the diffvim command
line, so you can include any combination of options:

```bash
# Personal review preset
export AD_PRESET="review --highlight-word --git-blame"
diffvim old.py new.py     # uses your preset by default

# Override an option in your preset
diffvim --no-highlight-word old.py new.py
```

Put the `export` line in your `~/.bashrc` or `~/.zshrc` to make it
permanent.

## See Also

- [Command-Line Options](./options.md) — full list of every option
- [Option Combinations](../OPTION_COMBINATIONS.md) — 100 worked examples
- [Post-Processing Pipeline](../POST_PROCESSING.md) — how each pass works
- [Visual Guide](../VISUAL_GUIDE.md) — graphical overview with ASCII art
