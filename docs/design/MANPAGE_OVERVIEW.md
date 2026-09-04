# Manpage Overview

*Created:* `08f3cb7` (2026-08-29 01:18:34 +0000)
*Last updated:* `2fd6bed` (2026-08-29 20:09:29 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


The `man/` directory contains 25 manpages for the `ad` toolkit. Install with `make install-man` (installs to `$(PREFIX)/share/man/man1/`).

## Quick reference

| Manpage                           | Binary                              | Description                                                                        |
| --------------------------------- | ----------------------------------- | ---------------------------------------------------------------------------------- |
| `ad_vim.1`                        | `apps/vim/ad_vim`                   | Animate a code diff in vim (the primary application)                               |
| `ad_pipeline.1`                   | `pipeline/ad_pipeline`              | Run the full pipeline (compute → postprocess → pace → animate)                     |
| `ad_postprocess.1`                | `pipeline/ad_postprocess`           | Dynamic layer orchestrator (--ad-layer, --ad-layer-path, --ad-layer-profile, etc.) |
| `ad.1`                            | `bin/ad`                            | Standalone terminal animation engine (C)                                           |
| `ad_compute.1`                    | `bin/ad_compute`                    | External diff computer (C++ Patience diff)                                         |
| `ad_layer_reorder.1`              | `bin/ad_layer_reorder`              | 4-sweep reorder layer                                                              |
| `ad_layer_overwrite.1`            | `bin/ad_layer_overwrite`            | Merge delete+insert into overwrite_insert                                          |
| `ad_layer_indent_last.1`          | `bin/ad_layer_indent_last`          | Move whitespace deletes to end of line                                             |
| `ad_layer_line_delete_in_place.1` | `bin/ad_layer_line_delete_in_place` | Delete whole lines on their own line                                               |
| `ad_layer_pace.1`                 | `bin/ad_layer_pace`                 | Insert delay ops (controls animation speed)                                        |
| `ad_layer_highlight.1`            | `bin/ad_layer_highlight`            | Insert highlight/dim/fold ops                                                      |
| `ad_debug.1`                      | `scripts/ad_debug.sh`               | Interactive pipeline debugger                                                      |
| `ad_debug_bundle.1`               | `scripts/ad_debug_bundle.sh`        | Generate a debug bundle for issue reports                                          |
| `ad_snapshot.1`                   | `scripts/ad_snapshot.sh`            | Per-op HTML snapshots for documentation                                            |
| `ad_record.1`                     | `scripts/ad_record.sh`              | Record animation to a file                                                         |
| `ad_replay.1`                     | `scripts/ad_replay.sh`              | Replay a recorded animation                                                        |
| `ad_demo.1`                       | `scripts/ad_demo.sh`                | Demo runner with preset examples                                                   |
| `ad_tune.1`                       | `scripts/ad_tune.sh`                | Interactive option tuner (tmux-based)                                              |
| `ad_suggest.1`                    | `scripts/ad_suggest.sh`             | Suggest closest matching CLI option for a typo                                     |
| `ad_package.1`                    | `scripts/ad_package.sh`             | Package the project for distribution                                               |
| `ad_compare.1`                    | `scripts/ad_compare`                | Benchmark diff algorithms and option combos                                        |
| `ad_jogger.1`                     | `scripts/ad_jogger`                 | Exercise ad across many option combinations                                        |
| `ad_tmux.1`                       | `scripts/ad_tmux`                   | Animate a diff in vim inside a tmux pane                                           |
| `test_vimscript_animator.1`       | `tests/test_vimscript_animator.sh`  | Test the vimscript animator engine                                                 |
| `verify_md5.1`                    | `tests/verify_md5.sh`               | Verify pipeline output via MD5 checksums                                           |

## By category

### Core applications

| Manpage        | What it documents                                                                                                                                                                   |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ad_vim.1`     | The vim application — animates a diff in vim. Documents all CLI flags, controls (Space/n/b/q/+/-/=), config file, and presets.                                                      |
| `ad_compute.1` | The diff engine — computes Patience diff between old and new files, outputs raw char ops. Documents `--semantic-cleanup`, `--word-diff`, `--indent-aware`, `--left-to-right` flags. |

### Layers

| Manpage                | What it documents                                                                                                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ad_layer_highlight.1` | The highlight layer — inserts highlight/dim/fold/sign ops into the timed op stream. Documents `--highlight`, `--dim-unchanged`, `--fold-unchanged`, `--sign-column`, `--git-blame` flags. |

(Note: the other 5 layers — `reorder`, `overwrite`, `indent_last`, `line_delete_in_place`, `pace` — don't have manpages yet. They're internal pipeline stages, not user-facing tools.)

### Debugging and testing

| Manpage                     | What it documents                                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `ad_debug.1`                | Interactive debugger — runs each pipeline stage, shows output at each step. Useful for diagnosing animation issues.                   |
| `ad_debug_bundle.1`         | Collects debug info (compute output, postprocess output, pace output, animator output, config, env) into a tarball for issue reports. |
| `ad_snapshot.1`             | Generates per-op HTML snapshots — one frame per op, viewable in a browser. Useful for documentation and debugging.                    |
| `test_vimscript_animator.1` | Test script for the vimscript animator engine.                                                                                        |
| `verify_md5.1`              | Verifies pipeline output via MD5 checksums across all examples.                                                                       |

### Recording and replay

| Manpage       | What it documents                                 |
| ------------- | ------------------------------------------------- |
| `ad_record.1` | Records an animation's timed op stream to a file. |
| `ad_replay.1` | Replays a recorded animation.                     |

### Demo and tuning

| Manpage        | What it documents                                                                |
| -------------- | -------------------------------------------------------------------------------- |
| `ad_demo.1`    | Demo runner with preset examples (runs 3 examples at different speeds).          |
| `ad_tune.1`    | Interactive tmux-based option tuner — live-adjust pacing, highlight, speed, etc. |
| `ad_compare.1` | Benchmarks all diff algorithms and option combinations on a file pair.           |
| `ad_jogger.1`  | Exercises ad across many synthetic test cases with various option combinations.  |

### Packaging and tmux

| Manpage        | What it documents                                                                  |
| -------------- | ---------------------------------------------------------------------------------- |
| `ad_package.1` | Packages the project into a distributable tarball.                                 |
| `ad_tmux.1`    | Animate a diff in vim inside a tmux pane (alternative to `ad_vim` for tmux users). |

## Missing manpages

All user-facing tools now have manpages. The following are intentionally not documented (internal test helpers):

| Tool                         | Why                                    |
| ---------------------------- | -------------------------------------- |
| `generate_minimal_tests.sh`  | Test fixture generator — internal      |
| `run_minimal_tests.sh`       | Test runner — internal                 |
| `run_all_examples.sh`        | Test runner — internal                 |
| `verify_md5.sh`              | Already has a manpage (`verify_md5.1`) |
| `test_vimscript_animator.sh` | Already has a manpage                  |

## Installation

```bash
# Install all manpages
make install-man

# Or manually
cp man/*.1 /usr/local/share/man/man1/
mandb   # update the manpage database

# View a manpage
man ad_vim
man ad_compute
```

## Structure

Each manpage follows this structure:

```
.TH <NAME> 1 "date" "ad 2.0" "ad scripts"
.SH NAME
<name> \- <one-line description>
.SH SYNOPSIS
.B <name>
[\fIoptions\fR] [\fIargs\fR]
.SH DESCRIPTION
<full description>
.SH OPTIONS
<CLI flags>
.SH CONFIGURATION
<config file + CLI flags, no env vars>
.SH EXAMPLES
<usage examples>
.SH SEE ALSO
<cross-references to other manpages>
```

All manpages use the `AD` section header (not `DIFFVIM` or `DV`). All reference the config file at `$XDG_CONFIG_HOME/ad/config`, not environment variables.
