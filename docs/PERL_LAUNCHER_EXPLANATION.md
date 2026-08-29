# Perl Launcher Explanation

The user asked: "what do you mean with 'Deleting 12 Perl launcher duplicates (or aligning)'?"

## What was meant

In `docs/ENV_VAR_ANALYSIS.md`, Category 3 lists "12 vars" that are "Perl launcher only (duplicate of bash)". This refers to the **environment variables** that only `apps/vim/ad_vim.pl` reads — not 12 copies of the launcher itself.

## The situation

There are **two launchers** that do the same job:

1. `apps/vim/ad_vim` — a 2,170-line Bash script (the primary launcher)
2. `apps/vim/ad_vim.pl` — a 2,128-line Perl script (a parallel implementation)

Both launchers:
- Parse the same CLI flags
- Read the same config file (`~/.config/ad/config`)
- Invoke the same pipeline (compute → postprocess → pace → animate)
- Launch vim with the same vimscript engine

The Perl launcher was originally created as a fallback for environments without Bash, but today Bash is universally available.

## The 12 "duplicate" env vars

These 12 env vars were only read by `ad_vim.pl`, not by the Bash `ad_vim`:

```
AD_ADAPTIVE_WORD_DELETE                AD_RAPID_EOL_MIN_CHARS
AD_ADAPTIVE_WORD_DELETE_ACCEL          AD_RAPID_IDENTICAL_ACCEL
AD_ADAPTIVE_WORD_DELETE_MIN_MS         AD_RAPID_IDENTICAL_CHARS
AD_ADAPTIVE_WORD_DELETE_START_CHARS    AD_RAPID_IDENTICAL_MIN
AD_ADAPTIVE_WORD_DELETE_START_MS       AD_SCROLL_DEBUG
AD_ADAPTIVE_WORD_DELETE_WORD_PAUSE_MS AD_TUNE_WORKDIR
AD_MAX_WORD_CHARS
```

After the env var removal (commit `3c35719`), the Perl launcher was rewritten to read from the config file instead of env vars, so these 12 are no longer read by anyone.

## The two options

The analysis said "delete or align" the Perl launcher:

**Option A — Delete `ad_vim.pl`:** The Bash launcher is canonical. The Perl duplicate adds maintenance burden (every CLI flag change must be made in both files) without value. Deleting it removes ~2,128 LOC and eliminates the maintenance hazard.

**Option B — Align:** Keep `ad_vim.pl` but make it a thin wrapper that calls the Bash launcher, rather than reimplementing everything. This preserves the `ad_vim.pl` name for backward compat without the duplication.

## User's decision

The user said: "keep the perl launcher." So we kept it. It's now aligned — both launchers read from the same config file and use the same `_write_vimconfig()` approach to pass values to vimscript. The 12 env vars that were "Perl-only" have been removed entirely (no env vars remain in either launcher).
