# diffvim API Reference

## Timed Op Stream Format (v2 TSV)

Tab-separated values, 1-indexed line/col:

```
# timed op stream v2
# format: TSV, every op carries (line, col) — 1-indexed
# delays are typed: delay\t<type>\t<ms>
hunk_start\t<del_count>\t<ins_count>
op\tkeep\t<line>\t<col>\t<char_code>
op\tdelete\t<line>\t<col>\t<char_code>
op\tinsert\t<line>\t<col>\t<char_code>
batch_delete\t<line>\t<col>\t<count>
batch_insert\t<line>\t<col>\t<code1>\t<code2>\t...
newline_delete\t<line>
newline_insert\t<line>\t<col>
delay\t<type>\t<ms>
hunk_end
done
```

## CLI Options

### diffvim-compute-cpp
```
diffvim-compute-cpp <oldfile> <newfile> <outputfile> [options]
  --semantic-cleanup    Merge adjacent delete+insert pairs
  --word-diff            Use word-level diff
  --indent-aware         Normalize indentation before line diff
  --optimize-sequence    Enable op-sequence optimization (default: on)
  --no-optimize-sequence Disable op-sequence optimization
  --left-to-right        Sort ops left-to-right by column
  --diff <patchfile>     Read unified diff instead of comparing files
  -h, --help             Show help
```

### diffvim-postprocess
```
diffvim-postprocess [options] < raw_ops > positioned_ops
  --transform NAME[:VALUE]  Apply transformation (repeatable)
    Available: op-order:natural|optimize, semantic-cleanup,
               indent-aware, overwrite
  --list-transforms    List available transforms
  --stream             Streaming mode (hunk-by-hunk)
  --op-order MODE      Shorthand for --transform op-order:MODE
  --semantic-cleanup   Shorthand for --transform semantic-cleanup
  --indent-aware       Shorthand for --transform indent-aware
  --overwrite          Shorthand for --transform overwrite
  -h, --help           Show help
```

### diffvim-pace
```
diffvim-pace [options] < positioned_ops > timed_ops
  --delete-pacing MODE   char|rapid-eol|rapid-identical|accel|word|instant
  --delete-speed MODE     slow|normal|fast|instant
  --delete-threshold N    Min chars for rapid/word modes (default: 3)
  --insert-pacing MODE    char|word|accel
  --insert-speed MODE     slow|normal|fast
  --pacing MODE           uniform|adaptive|gaussian|review
  --snapshot FILE         Insert snapshot op at end
  -h, --help              Show help
```

### diffvim-animator-c
```
diffvim-animator-c [options] <oldfile> < timed_ops
  --no-display          Process without rendering
  --speed N             Speed multiplier (default: 1.0)
  --output FILE         Write final buffer to FILE
  --snapshot FILE       Write buffer to FILE at end
  --colormap-old FILE   ANSI-colored lines for old file
  --colormap-new FILE   ANSI-colored lines for new file
  --line-numbers        Show line numbers in the margin
  --progress            Show progress bar at bottom
  --verbose             Show timing info on stderr
  --dry-run             Show what would be animated without running
  --version             Print version and exit
  -h, --help            Show help
```

### diffvim-pipeline
```
diffvim-pipeline [options] <oldfile> <newfile>
  --compute-*          Options for diffvim-compute-cpp
  --postprocess-*      Options for diffvim-postprocess
  --pace-*             Options for diffvim-pace
  --animator-*         Options for diffvim-animator-c
  (unprefixed)         Options for diffvim-animator-c
  -h, --help           Show help
```

### diffvim-colorize
```
diffvim-colorize [--backend vim|pygmentize|none] [--lang LANG] FILE OUTPUT
  --backend    Coloring backend (default: auto)
  --lang       Source language (default: auto-detect from extension)
  -h, --help   Show help
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| DIFFVIM_COMPUTE_BIN | (auto) | Override compute binary path |
| DIFFVIM_COLORIZE_BACKEND | auto | Coloring backend |
| DIFFVIM_TIMED_OPS | (unset) | Path to timed op stream (vimscript) |
| DIFFVIM_OUTPUT | (unset) | Output file path |
| DIFFVIM_SPEED | 1.0 | Speed multiplier |
| DIFFVIM_DELETE_PACING | word | Delete pacing mode |
| DIFFVIM_INSERT_PACING | char | Insert pacing mode |
| DIFFVIM_PACING | uniform | Pacing mode |
| DIFFVIM_HIGHLIGHT | none | Highlight mode |
| DIFFVIM_THEME | dark | Color theme |
| DIFFVIM_SCROLL | zz | Scroll position |

## Delay Types

| Type | Description |
|------|-------------|
| type | Typing a single char |
| keep | Scrolling past kept chars |
| delete | Single char delete |
| hunk_pause | Pause between hunks |
| rapid_eol | Rapid end-of-line delete burst |
| awd_start | AWD initial chars (slow) |
| awd_word | AWD word batch (accelerated) |
| awd_space | AWD space batch (instant) |
| word_insert | Batched word insert |
| newline_delete | After \n delete |
| newline_insert | After \n insert |
