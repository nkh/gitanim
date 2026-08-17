# diffvim-animator — Standalone Animation Pipeline

## Overview

The diffvim-animator is a standalone terminal animation system that
replaces the vim-based diffvim engine. It uses a **pipeline of
independent tools** instead of a monolithic vimscript engine.

## Pipeline Architecture

```
compute → postprocess → pace → animator
```

Each tool reads from stdin and writes to stdout, enabling:
- Independent testing of each stage
- Mixing implementations (Perl postprocess + Go animator)
- Using the animator without animation (`--no-display`) for testing

### Tools

| Tool | Purpose | Languages |
|------|---------|-----------|
| `diffvim-compute` | Compute raw char ops (LCS/Myers/Patience) | C, C++, Rust, Go (existing) |
| `diffvim-postprocess` | Reorder ops (op-order, semantic-cleanup, etc.) | Perl, C, Go |
| `diffvim-pace` | Transform ops into a timed op stream | Perl, C, Go |
| `diffvim-animator` | Play back timed ops in a terminal | Go, Perl, C |
| `diffvim-pipeline` | Run all 4 stages with prefixed option routing | Bash |

## Quick Start

```bash
# Full pipeline via diffvim-pipeline
animator/diffvim-pipeline old.py new.py

# With specific options (prefixed by stage)
animator/diffvim-pipeline \
  --pace-delete-pacing word \
  --pace-pacing gaussian \
  --animator-no-display \
  --animator-snapshot result.txt \
  old.py new.py

# Manual pipeline (pipe tools directly)
compute/bin/diffvim-compute-c old.py new.py /tmp/raw.txt
perl animator/perl/postprocess.pl --op-order optimize < /tmp/raw.txt |
  perl animator/perl/pace.pl --delete-pacing word |
  animator/bin/diffvim-animator old.py
```

## Building

```bash
# Build all C tools
cc -O2 -o animator/bin/diffvim-postprocess animator/c/postprocess.c
cc -O2 -o animator/bin/diffvim-pace animator/c/pace.c
cc -O2 -o animator/bin/diffvim-animator-c animator/c/animator.c

# Build Go tools
go build -o animator/bin/diffvim-postprocess-go animator/go/postprocess.go
go build -o animator/bin/diffvim-pace-go animator/go/pace.go
go build -o animator/bin/diffvim-animator animator/go/animator.go

# Perl tools need no build
```

## Option Routing

`diffvim-pipeline` routes options by prefix:

| Prefix | Stage | Example |
|--------|-------|---------|
| `--compute-*` | compute | `--compute-algorithm patience` |
| `--postprocess-*` | postprocess | `--postprocess-op-order optimize`, `--postprocess-semantic-cleanup` |
| `--pace-*` | pace | `--pace-delete-pacing word`, `--pace-pacing gaussian` |
| `--animator-*` | animator | `--animator-no-display`, `--animator-snapshot out.txt` |
| (none) | animator | `--speed 2.0`, `--output result.txt` |
| `--tool` | compute | `--tool rust` (selects compute language) |

## Timed Op Stream Format

The pace tool produces a timed op stream that the animator reads:

```
# timed op stream v1
hunk_start 2 1 1
glide 2:1
delay 480
op keep 32
delay 1
op insert 102
delay 50
batch_delete 4
delay 15
newline_delete
delay 40
snapshot /tmp/test.txt
hunk_end
done
```

### Op Types

| Op | Description |
|----|-------------|
| `op <type> <code>` | Apply a char op (keep/delete/insert) |
| `delay <ms>` | Wait N milliseconds |
| `batch_delete <count>` | Delete N chars instantly |
| `batch_insert <codes...>` | Insert multiple chars instantly |
| `glide <line>:<col>` | Move cursor to position |
| `newline_delete` | Delete \n (join lines) |
| `newline_insert` | Insert \n (split line) |
| `snapshot <file>` | Write buffer to file |
| `hunk_start` / `hunk_end` | Mark hunk boundaries |
| `done` | Animation complete |

## The `\n` Problem — Solved

When a whole line is deleted, the `\n` is deleted after the line content.
Since the line is already empty, joining it with the next line just
removes the empty line — the next line's content takes its place. No
content is "pulled up" because there's nothing to pull.

This is exactly how a human edits: delete the line's content, then
delete the line break, and the next line moves up.

## Testing

```bash
# All animator round-trip tests (15 cases × 3 animators = 45 tests)
perl animator/tests/test_all_animators.pl

# Cross-language parity (postprocess + pace, all 3 languages)
perl animator/tests/test_cross_language.pl

# \n merge bug verification
perl animator/tests/test_newline_fix.pl
```

### Test Results

| Test | Assertions | Status |
|------|-----------|--------|
| test_all_animators.pl | 45 | ✅ All pass |
| test_cross_language.pl | 38 | ✅ All pass |
| test_newline_fix.pl | 8 | ✅ All pass |
| **Total** | **91** | ✅ All pass |

## Comparison with vim-based diffvim

| Aspect | diffvim (vim) | animator (standalone) |
|--------|---------------|----------------------|
| `\n` delete | Pulls next line up (bug) | ✅ Correct |
| Dependencies | vim 8+ | ✅ None (Go static binary) |
| Architecture | Monolithic (4,500 lines) | ✅ Pipeline (4 tools) |
| Testability | Hard (timer-based) | ✅ Easy (stdin/stdout) |
| Performance | Slow (vim overhead) | ✅ 10-100x faster |
