# diffvim Vocabulary

## Files and Data

| Term | Definition |
|------|------------|
| **old file** | The original file before changes |
| **new file** | The target file after changes |
| **snapshot** | The buffer state written to a file at the end of animation (or on demand) |
| **intermediary file** | Any file produced by one pipeline stage and consumed by the next (raw ops, post-processed ops, timed ops) |

## Pipeline Stages

| Term | Definition |
|------|------------|
| **compute** | First stage. Reads old + new files, produces a char-level diff (raw ops). Implemented in C++ (Patience algorithm). |
| **postprocess** | Second stage. Reads raw ops, reorders/transforms them, adds per-op (line, col) positioning. Produces post-processed ops. |
| **pace** | Third stage. Reads post-processed ops, inserts delays between ops. Does NOT modify, reorder, or add any ops — only inserts delay lines. Produces timed ops. |
| **animate** | Fourth stage. Reads timed ops, applies them to a virtual buffer, renders to terminal or vim. |

## Diff Operations (ops)

| Term | Definition |
|------|------------|
| **op** | A single operation in the diff: keep, delete, or insert |
| **keep** | A character that exists in both old and new file — it stays in the buffer, cursor advances |
| **delete** | A character that exists in old but not new — it is removed from the buffer |
| **insert** | A character that exists in new but not old — it is added to the buffer |
| **char code** | The Unicode code point of a character (e.g., 65 for 'A', 10 for '\n') |
| **char repr** | The human-readable representation of a character in the diff format (e.g., `'A'`, `'space'`, `'\n'`, `'\t'`) |

## Positions

| Term | Definition |
|------|------------|
| **line** | 1-indexed line number in the buffer |
| **col** | 1-indexed column number in the buffer (character position, not byte) |
| **position** | The (line, col) pair identifying where an op should be applied |
| **target line** | The line in the old file where a hunk starts |

## Hunk

| Term | Definition |
|------|------------|
| **HUNK** | A group of ops that target a specific region of the file. Format: `HUNK\t<target_line>\t<del_count>\t<ins_count>\t<is_end_insert>\t<is_end_delete>` |
| **HUNK_END** | Marks the end of a hunk's ops |
| **del_count** | Number of lines deleted in this hunk |
| **ins_count** | Number of lines inserted in this hunk |
| **is_end_insert** | 1 if this hunk appends content at end of file |
| **is_end_delete** | 1 if this hunk truncates the end of the file |

## Delays

| Term | Definition |
|------|------------|
| **delay** | A pause inserted by the pace stage between ops. Format: `delay\t<milliseconds>\t<type>` |
| **delay type** | The category of delay, determined by the pacing options. Allows the animator to adjust delays per type at runtime. Multiple delays can follow each other. |
| **char** | Delay type: per-character delay (normal typing speed) |
| **word** | Delay type: pause after completing a word |
| **pause** | Delay type: pause between hunks |
| **rapid** | Delay type: rapid burst (fast consecutive deletes) |
| **start** | Delay type: initial slow delay at the start of a delete run |

## Pacing

| Term | Definition |
|------|------------|
| **delete pacing** | Strategy for how deletes are paced: char, rapid, word, instant |
| **insert pacing** | Strategy for how inserts are paced: char, word |
| **pacing mode** | Overall timing mode: uniform, adaptive, gaussian, review |
| **AWD** | Adaptive Word Delete: spaces instant, first 3 chars slow, then word batches with acceleration |

## Ghost Line

| Term | Definition |
|------|------------|
| **ghost line** | The visual artifact when a `\n` delete joins two lines and the next line's content visually jumps up onto the current line |
| **ghost-line fix** | In postprocess: when `delete '\n'` and the line has kept content, and the next ops are content deletes not followed by keeps, emit the content deletes at (line+1, 1) and the `\n` delete at (line+1) — the next line's content is deleted first, then the empty line is removed |

## Coloring

| Term | Definition |
|------|------------|
| **colormap** | A file containing ANSI-colored versions of each line of a source file. Used by the animator for syntax highlighting. |
| **colorize** | The tool that produces colormaps. Backends: vim, pygmentize, none. |
| **progressive decoloring** | Unmodified lines render with colormap colors; modified lines fall back to plain text |

## Animator

| Term | Definition |
|------|------------|
| **virtual buffer** | The in-memory representation of the file being animated. A list of lines. |
| **cursor** | The current (line, col) position in the virtual buffer |
| **render** | Drawing the virtual buffer to the terminal or vim |
| **incremental render** | Only redrawing lines that changed (avoids flashing) |
| **scroll** | Moving the viewport when the cursor goes off-screen |

## Formats

| Term | Definition |
|------|------------|
| **raw ops** | Output of compute. Char-level ops with HUNK headers. |
| **post-processed ops** | Output of postprocess. Ops with (line, col) positioning, reordered/transformed. |
| **timed ops** | Output of pace. Post-processed ops with delays inserted between them. |

## TSV

All intermediary files use **tab-separated values** (TSV). Fields are separated by `\t`. Every file ends with a blank line.

## Delay Types (updated names)

| Type | Description | When inserted |
|------|-------------|---------------|
| `char` | Per-character (normal typing speed) | After each keep or insert |
| `word` | After completing a word | After a batch of inserts forming a word |
| `hunk` | Between hunks | After HUNK_END, before next HUNK |
| `awd_slow` | AWD: initial slow chars | First 3 chars of a delete run |
| `awd_fast` | AWD: accelerated word batches | After word batches in a delete run |
| `awd_skip` | AWD: spaces deleted instantly | After deleting spaces |
