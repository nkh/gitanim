# Option audit: what works, what's ignored, what's broken

## How ad_vim works after refactoring

The launcher runs the external pipeline:
```
compute → postprocess → pace → timed ops → vimscript animator
```

The vimscript animator reads a pre-computed timed op stream. It does
NOT compute, postprocess, or pace — those are done externally.

## Options that WORK (passed to pipeline or used by vimscript)

| Option | Where it's used | Status |
|--------|----------------|--------|
| `--speed N` | Exported as DIFFVIM_SPEED, read by vimscript | ✅ Fixed |
| `--output FILE` | Exported as DIFFVIM_OUTPUT | ✅ |
| `--no-vimrc` | Controls vim -u flag | ✅ |
| `--sync` | Runs without timers | ✅ |
| `--dry-run` | Prints hunks without vim | ✅ |
| `--semantic-cleanup` | Passed to postprocess | ✅ |
| `--indent-aware` | Passed to postprocess | ✅ |
| `--word-diff` | Passed to compute | ✅ |
| `--delete-pacing` | Passed to pace | ✅ |
| `--insert-pacing` | Passed to pace | ✅ |
| `--algorithm` | Passed to compute (patience/lcs) | ✅ |
| `--left-to-right` | Exported as AD_LEFT_TO_RIGHT | ✅ |
| `--op-order` | Exported as DIFFVIM_OP_ORDER | ✅ (but pace/postprocess don't read it) |

## Options that are IGNORED (parsed but not used)

### Options parsed by bash, exported as env vars, but NOT read by the vimscript timed reader

The vimscript timed reader section only reads `g:diffvim.output_file`.
All other config fields are set but never accessed:

| Option | Env var | Ignored because |
|--------|--------|-----------------|
| `--context N` | DIFFVIM_CONTEXT | Timed reader doesn't fold |
| `--max-hunk-chars N` | DIFFVIM_MAX_HUNK_CHARS | Timed reader doesn't check |
| `--scroll zz|zt|zb` | DIFFVIM_SCROLL | Timed reader always uses `zz` |
| `--sign-column` | DIFFVIM_SIGN_COLUMN | No sign column in timed reader |
| `--git-blame` | DIFFVIM_GIT_BLAME | No git blame in timed reader |
| `--step-mode` | DIFFVIM_STEP_MODE | No step mode in timed reader |
| `--no-startup-pause` | DIFFVIM_NO_STARTUP_PAUSE | No startup pause logic |
| `--language` | DIFFVIM_LANGUAGE | Not used (syntax is in colormap) |
| `--highlight` | DIFFVIM_HIGHLIGHT | No highlight in timed reader |
| `--highlight-color` | DIFFVIM_HIGHLIGHT_COLOR | Not used |
| `--highlight-duration-ms` | DIFFVIM_HIGHLIGHT_DURATION_MS | Not used |
| `--dim-unchanged` | DIFFVIM_DIM_UNCHANGED | Not used |
| `--dim-unchanged-pct` | DIFFVIM_DIM_UNCHANGED_PCT | Not used |
| `--fold-unchanged` | DIFFVIM_FOLD_UNCHANGED | Not used |
| `--theme` | DIFFVIM_THEME | Not used |
| `--max-line-len` | DIFFVIM_MAX_LINE_LEN | Not used |
| `--gaussian-jitter` | DIFFVIM_GAUSSIAN_JITTER | Not used |
| `--pause-after-lines` | DIFFVIM_PAUSE_AFTER_LINES | Not used |
| `--accel-delete` | DIFFVIM_ACCEL_DELETE | Not used |
| `--overwrite` | DIFFVIM_OVERWRITE | Not used |
| `--delete-end-first` | DIFFVIM_DELETE_END_FIRST | Not used |
| `--rapid-eol-delete` | DIFFVIM_RAPID_EOL_DELETE | Not used |
| `--adaptive-word-delete` | DIFFVIM_ADAPTIVE_WORD_DELETE | Not used |
| `--rapid-identical-chars` | DIFFVIM_RAPID_IDENTICAL_CHARS | Not used |
| `--word-accel` | DIFFVIM_WORD_ACCEL | Not used |

### Options parsed by bash but NOT exported at all

| Option | Status |
|--------|--------|
| `--delete-speed` | Exported but pace doesn't read it |
| `--insert-speed` | Exported but pace doesn't read it |
| `--delete-threshold` | Exported but pace doesn't read it |
| `--pacing` | Exported but pace doesn't read it |
| `--startup-feedback` | Not exported |
| `--inline-highlight` | Not exported |
| `--highlight-word` | Not exported |
| `--highlight-hunk` | Not exported |
| `--keep-dirty` | Exported, used for nomodified |
| `--log-mode` | Not implemented |
| `--log-file` | Not implemented |
| `--no-log-timing` | Not implemented |
| `--debug` | Not implemented |

### Options that need the vimscript engine (old features, removed in refactor)

These features existed in the old vimscript engine but were removed
when the timed op stream reader replaced it:

- `--context N` — fold unchanged regions (needs vim folding)
- `--sign-column` — show +/- signs (needs vim sign API)
- `--git-blame` — echo blame info (needs vim + git)
- `--step-mode` — space advances one op (needs vim input loop)
- `--highlight inline|word|hunk` — highlight changed chars (needs vim matchadd)
- `--dim-unchanged` — dim unchanged lines (needs vim syntax manipulation)
- `--fold-unchanged` — fold unchanged regions (needs vim folding)
- `--theme` — color scheme (needs vim highlight groups)
- `--gaussian-jitter` — random typing delay (needs pace support)
- `--pause-after-lines` — pause after N lines (needs pace support)
- `--accel-delete` — accelerated multi-line delete (needs pace support)
- `--overwrite` — in-place overwrite (needs postprocess support)
- `--delete-end-first` — delete end before insert (needs postprocess support)

## Speed control: +/- keys

The `+` and `-` keys map to:
```vim
nnoremap <buffer> <silent> + :let s:timed_speed = s:timed_speed * 1.5<CR>
nnoremap <buffer> <silent> - :let s:timed_speed = s:timed_speed / 1.5<CR>
```

The `s:timed_speed` variable IS read by `TimedProcessBatch`:
```vim
let l:ms = float2nr(l:ms / s:timed_speed)
```

So +/- SHOULD work. If they don't, the issue is that the keymap isn't
being set up (the `nnoremap` lines might not be reached in some code
paths, or the buffer-local mapping isn't active).

## Summary

- **Working**: ~15 options (speed, output, pipeline options, l2r)
- **Ignored**: ~30 options (highlight, context, sign-column, etc.)
- **Need old engine**: ~15 options (features that require vim APIs)

The ignored options are from the old vimscript engine. They were
removed when the timed op stream reader replaced the engine. To
re-add them, they'd need to be implemented either:
1. In the pipeline stages (postprocess/pace) — for pacing/highlighting
2. In the vimscript timed reader — for vim-specific features (folding, signs)
