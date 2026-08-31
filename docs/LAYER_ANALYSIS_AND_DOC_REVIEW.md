# Layer Mechanism Analysis & Document Review

*Created:* `2d5bf64` (2026-08-29 06:31:19 +0000)
*Last updated:* `78e882f` (2026-08-29 15:55:36 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


This document covers two things:
1. Analysis of the dynamic layer mechanism with improvement proposals
2. Review of all analysis documents — what was implemented, what wasn't, what's still relevant

---

# Part 1: Dynamic Layer Mechanism Analysis

## Current architecture

The layer system is a **user-driven pipeline**. The orchestrator (`pipeline/ad_postprocess`) is a bash script that:

1. Parses `--ad-layer=<name>` flags from argv (in order, no sorting, no dedup)
2. Parses `--ad-layer-path=<dir>` flags (repeatable, default: `bin/` and `layers/perl/`)
3. Resolves each layer name to an executable (path or search-path lookup)
4. Chains them: reads stdin into a temp file, runs each layer `cmd < tmp > tmp.2; mv tmp.2 tmp`, writes final result to stdout

### Resolution algorithm

```
For each --ad-layer=<name>:
  if <name> contains '/':
    treat as path (relative or absolute)
    pick interpreter by extension (.pl → perl, .py → python3, etc.)
    if no extension: must be executable
  else:
    search each --ad-layer-path dir in order
    first dir containing a file named <name> (verbatim) wins
    pick interpreter by extension
    if no extension: must be executable
  if not found: error + exit 1
```

### Strengths

1. **Simple**: ~240 lines of bash. No manifest, no config file, no magic.
2. **Language-agnostic**: Any executable that reads/writes TSV is a layer.
3. **Extensible**: `--ad-layer-path` lets users put layers anywhere.
4. **Transparent**: `--list-layers` shows what's available; stderr shows what's running.
5. **Composable**: Layers run in argv order. Same layer can run twice.
6. **No env vars**: State is passed via CLI flags (passthrough args) and the TSV stream itself.

## Weaknesses and gaps

### #L1 No TSV validation between layers

The orchestrator doesn't validate that a layer's output is well-formed V2 TSV. If a layer outputs garbage, the next layer may crash silently or produce corrupt output.

**Problem**: A buggy layer can corrupt the entire downstream pipeline without any error message.

**Fix**: Add a lightweight TSV validator between layers. Check that:
- First non-comment line is a HUNK header (starts with `HUNK\t`)
- Every HUNK has a matching HUNK_END
- Op lines have at least 4 tab-separated fields
- Line/col/code fields are numeric

Implementation: a 30-line bash function `validate_tsv()` called after each layer.

### #L2 No error propagation from layers

When a layer fails (non-zero exit), the orchestrator prints "layer 'X' failed (exit N)" and exits. But it doesn't capture or display the layer's stderr — it's redirected to `/dev/null`.

**Problem**: Users can't diagnose why a layer failed.

**Fix**: Capture stderr to a temp file. On failure, display the last 20 lines of stderr.

```bash
if ! $bin ... < "$T" > "$T.2" 2>"$T.err"; then
    echo "ad_postprocess: layer '$name' failed (exit $?)" >&2
    echo "--- stderr (last 20 lines) ---" >&2
    tail -20 "$T.err" >&2
    exit 1
fi
```

### #L3 No way to pass layer-specific args

Currently, all unknown `--flags` are collected as `PASSTHROUGH_ARGS` and sent to EVERY layer. If layer A needs `--foo` and layer B needs `--bar`, both get both flags.

**Problem**: Layers can't have conflicting CLI flags (e.g., `--speed` means different things to pace vs. animator).

**Fix**: Add `--ad-layer-arg=<name>:<arg>` syntax:
```bash
ad_postprocess \
  --ad-layer=ad_layer_reorder \
  --ad-layer=ad_layer_pace \
  --ad-layer-arg=ad_layer_pace:--delete-pacing \
  --ad-layer-arg=ad_layer_pace:word
```

Or per-layer args after the layer name:
```bash
--ad-layer=ad_layer_pace:--delete-pacing:word
```

### #L4 No profiling or timing

There's no way to see how long each layer takes. For a slow pipeline, you can't tell which layer is the bottleneck.

**Problem**: Performance debugging requires manual instrumentation.

**Fix**: Add `--ad-layer-profile` flag that prints timing per layer:
```
ad_postprocess: profile:
  ad_layer_reorder      0.003s
  ad_layer_indent_last  0.001s
  ad_layer_pace         0.012s
  ad_layer_highlight    0.008s
  total                 0.024s
```

Implementation: wrap each layer invocation with `date +%s.%N` before/after.

### #L5 No dry-run mode

There's no way to see what layers WOULD run without actually running them.

**Problem**: Users can't verify their `--ad-layer` chain before committing to a long pipeline run.

**Fix**: Add `--ad-layer-dry-run` flag that resolves and prints the chain without executing:
```
ad_postprocess: dry run — would execute:
  1. ad_layer_reorder   (bin/ad_layer_reorder)
  2. ad_layer_indent_last (bin/ad_layer_indent_last)
  3. ad_layer_pace      (bin/ad_layer_pace)
  args: --delete-pacing word
```

### #L6 No layer versioning or metadata

There's no way to ask a layer "what version are you?" or "what do you do?". The `--list-layers` output shows the filename and whether it's executable, but no description or version.

**Problem**: Users can't tell what a layer does without reading its source or running it.

**Fix**: Layers can optionally support `--ad-layer-info` flag that outputs JSON:
```json
{"name": "ad_layer_reorder", "version": "1.0", "description": "4-sweep reorder", "author": "ad"}
```

`--list-layers` would call this for each discovered layer and display the metadata.

### #L7 No layer dependency declaration

Some layers need to run after others (e.g., `pace` needs `reorder` to have run first). Currently this is implicit — the user must know the right order.

**Problem**: Users can accidentally run `pace` without `reorder`, producing malformed output.

**Fix**: Layers can declare dependencies via `--ad-layer-info`:
```json
{"name": "ad_layer_pace", "requires": ["ad_layer_reorder"]}
```

The orchestrator would warn (not error) if a dependency is missing from the chain:
```
ad_postprocess: warning: layer 'ad_layer_pace' recommends 'ad_layer_reorder' to run first
```

### #L8 No old-file path passing

The old `AD_OLD_FILE` env var was removed, but some layers might need access to the original file (e.g., for syntax-aware diffing). There's no CLI way to pass it.

**Problem**: Layers that need the old file path can't get it.

**Fix**: Add `--ad-layer-old-file=<path>` flag that passes `--old-file=<path>` to every layer as a passthrough arg. Layers that need it parse it from argv; layers that don't ignore it.

### #L9 Temp file I/O is O(N×L)

The orchestrator reads the entire input into a temp file, then for each layer: reads the file, runs the layer writing to a new file, then moves the new file over the old. For N ops and L layers, that's L file reads and L file writes of the full stream.

**Problem**: For large diffs (50k ops) with 4 layers, that's 200k file I/O operations.

**Fix**: Use a pipe chain when possible:
```bash
layer1 < input | layer2 | layer3 | layer4 > output
```

But this breaks if a layer needs to read its own output or if the orchestrator needs to validate between layers. A hybrid approach: pipe by default, fall back to temp files if `--ad-layer-validate` is set.

### #L10 `--list-layers` doesn't show descriptions

The current `--list-layers` output shows filename, status (exec/perl/python3/etc.), and full path. But no description of what the layer does.

**Problem**: Users see `ad_layer_reorder [exec]` but don't know it's the 4-sweep reorder layer.

**Fix**: If the layer supports `--ad-layer-info`, display the description. Otherwise, show the first comment line from the source file.

---

## Improvement proposals (prioritized)

| # | Proposal | Effort | Impact |
|---|----------|--------|--------|
| L1 | TSV validation between layers | 30 min | High — catches corrupt output |
| L2 | Capture and display layer stderr on failure | 10 min | High — debugging |
| L3 | Per-layer args (`--ad-layer-arg=<name>:<arg>`) | 1 hour | Medium — complex chains |
| L4 | `--ad-layer-profile` timing | 20 min | Medium — perf debugging |
| L5 | `--ad-layer-dry-run` | 15 min | Medium — verification |
| L6 | `--ad-layer-info` metadata | 1 hour | Low — nice-to-have |
| L7 | Layer dependency warnings | 2 hours | Low — most chains are simple |
| L8 | `--ad-layer-old-file=<path>` passthrough | 10 min | Low — rarely needed |
| L9 | Pipe chain instead of temp files | 2 hours | Medium — perf for large diffs |
| L10 | Descriptions in `--list-layers` | 30 min | Low — cosmetic |

Recommended to implement L1, L2, L4, L5 first (highest impact, lowest effort).

---

# Part 2: Analysis Document Review

## Summary

| Document | Status | Action |
|----------|--------|--------|
| `RESTRUCTURE_ANALYSIS.md` | 60/64 proposals done | Archive to `docs/design/` |
| `ENV_VAR_ANALYSIS.md` | Mostly done; ~8 bridge vars remain | Update to note reality |
| `CODE_ANALYSIS.md` | P0: 6/7, P1: 11/14, P2: 4/8 fixed | Update to mark fixed items |
| `P3_ISSUES.md` | 0/12 done; 3 regressed | Keep as backlog |
| `DOCS_AUDIT.md` | 0 deletions executed | Keep; execute deletions |
| `MANPAGE_OVERVIEW.md` | Accurate | Keep as-is |
| `PERL_LAUNCHER_EXPLANATION.md` | Accurate | Keep as-is |
| `docs/src/plugin-layers.md` | **BADLY OUTDATED** | **Rewrite immediately** |

---

## `docs/RESTRUCTURE_ANALYSIS.md` — 64 proposals

**Implemented: 60/64**

| Done? | # | Proposal |
|-------|---|----------|
| ✅ | #1-16 | Rename project, binaries, directories |
| ❌ | #17 | scripts/ → tools/bin/ (reversed — scripts/ kept) |
| ❌ | #19 | Delete DiffVim/ (kept as perl/DiffVim/) |
| ✅ | #18,20-28 | Delete junk, flatten pipeline, Makefile, install targets |
| ❌ | #26 | Makefile layer deps on test files (not done) |
| ✅ | #29-39 | Layer discovery rewrite (--ad-layer, no manifest) |
| ✅ | #40-46 | Per-layer TDD tests |
| ✅ | #47-52 | CI workflows + book.toml + contributing |
| ✅ | #53-57 | Config: XDG, no env vars, no .diffvimrc |
| ✅ | #58 | FLEXIBILITY.md → plugin-layers.md (but content is stale!) |
| ❌ | #59 | Delete obsolete design docs (audit done, deletions not executed) |
| ✅ | #60-64 | Update SUMMARY, README, manpages, completions |

**Status**: Largely complete. The 4 unimplemented items are either reversed decisions (#17, #19) or deferred (#26, #59).

**Action**: Move to `docs/design/` as historical record. Remove link from `SUMMARY.md`.

---

## `docs/ENV_VAR_ANALYSIS.md` — 107 vars → 0

**Reality: 107 → ~8**

All user-facing env vars were removed. ~8 internal bridge/debug vars remain:
- `AD_TICK_MS`, `AD_TYPE_DELAY_MS`, `AD_DELETE_DELAY_MS` — bash→vimscript bridge
- `AD_SCROLL`, `AD_THEME` — bash→vimscript bridge
- `AD_LEFT_TO_RIGHT` — bash→compute bridge (in ad_pipeline)
- `AD_COMPUTE_BIN` — advanced override (in ad_pipeline)
- `AD_DEBUG_LAYERS` — debug flag (in ad_postprocess)

**Status**: The "107 → 0" claim is technically wrong. The user-facing outcome (no env vars to set) is correct, but the internal bridge vars remain.

**Action**: Update the doc to note the ~8 remaining bridge vars, or move to `docs/design/` as historical.

---

## `docs/CODE_ANALYSIS.md` — 41 issues

### P0 (7 items) — 6/7 fixed

| # | Issue | Status |
|---|-------|--------|
| ✅ | #1 ad_demo.sh path | Fixed |
| ❌ | #2 ad_package.sh paths | **NOT fixed** — still references old paths |
| ✅ | #3 ad_compare binary name | Fixed |
| ✅ | #4 ad_jogger path | Fixed |
| ✅ | #5 ad_pipeline $dp_val | Fixed |
| ✅ | #6 ad_pipeline DECORATE_ARGS | Fixed |
| ✅ | #7 ad_debug_bundle export | Fixed |

### P1 (14 items) — 11/14 fixed

| # | Issue | Status |
|---|-------|--------|
| ✅ | #8-12 | ad_tune.sh fixes |
| ❌ | #13 | Dead preset branch `if [[ -n "" ]]` — **NOT fixed** |
| ✅ | #14 | Self-assignment removed |
| ✅ | #15 | compute.pl CLI flags wired through |
| ✅ | #16 | optimize_sequence removed |
| ✅ | #17 | --seek fixed (suppress_render) |
| ✅ | #18 | Dead ternary fixed |
| ✅ | #19 | last_changed_line reset per hunk |
| ❌ | #20 | pace.c word-pacing \n changed_lines — **NOT fixed** |
| ✅ | #21 | Dead Myers diff deleted |

### P2 (8 items) — 4/8 fixed

| # | Issue | Status |
|---|-------|--------|
| ✅ | #22 | colorize.pl command injection — Fixed (list-form system) |
| ❌ | #23 | eval on user input in ad_vim:630 — **NOT fixed** |
| ❌ | #24 | Unescaped placeholder in ad_vim.pl — **NOT fixed** |
| ❌ | #25 | Unquoted $NEW in vim -c — **NOT fixed** |
| ⚠️ | #26 | ad_debug.sh stderr — Partially fixed (compute stage still 2>&1) |
| ⚠️ | #27 | ad_record.sh temp path — Partially fixed ($$ suffix, not mktemp) |
| ⚠️ | #28 | ad_replay.sh output path — Partially fixed ($$ suffix, no --output flag) |
| ✅ | #29 | Signal handler — Fixed (async-signal-safe + atexit) |

### P3 (12 items) — 0/12 done, 3 regressed

| # | Issue | Status |
|---|-------|--------|
| ❌ | P3-1 | C layer boilerplate — not done |
| ❌ | P3-2 | Perl layer boilerplate — not done |
| ❌ | P3-3 | ad.c 360-line main() — not done |
| ❌ | P3-4 | pace.c 430-line main() — not done |
| ❌ | P3-5 | ad_vim 2,170-line monolith — not done (2,169 lines) |
| ❌ | P3-6 | ad_tmux 1,673-line duplicate — not done |
| ❌ | P3-7 | Magic 1048576 ×4 — **REGRESSED** (now ×6) |
| ❌ | P3-8 | TSV tokenizer ×9 — not done |
| ❌ | P3-9 | char_repr ×3 — **REGRESSED** (now ×9) |
| ❌ | P3-10 | Option routing ×4 — not done |
| ❌ | P3-11 | Dead stubs (do_highlight_word, git_blame) — not done |
| ❌ | P3-12 | Version ×2 — **REGRESSED** (now ×3) |

**Action**: Update CODE_ANALYSIS.md to mark fixed items. Create a `REMAINING_ISSUES.md` with only the unfixed items.

---

## `docs/src/plugin-layers.md` — CRITICAL: badly outdated

This user-facing doc still describes the **old manifest-based design** that was completely replaced. Specifically:

| Claim in doc | Reality |
|---|---|
| "add one line to a manifest" | **Manifest is gone** — use `--ad-layer=<name>` |
| `animator/layers.conf` | **File does not exist** |
| `animator/bin/pp_<name>` | Renamed to `bin/ad_layer_<name>` |
| `--pp-<name>` forwarding | **Removed** — use `--ad-layer=<name>` |
| `--enable=<name>` | **Removed** |
| `--layers=<csv>` | **Removed** |
| "Reads animator/layers.conf" | Orchestrator reads **argv only** |

**Action**: **Rewrite immediately.** The correct documentation is in the `ad_postprocess --help` output and the script's header comment.

---

## `docs/DOCS_AUDIT.md` — 0 deletions executed

The audit lists 58 design docs with relevance scores. 28 were marked LOW relevance (candidates for deletion). **None were deleted.**

**Action**: Execute the deletion script provided in the doc, or manually review and delete the LOW-relevance docs.

---

## Remaining unfixed issues (consolidated)

### Must fix (broken/misleading)

1. **`docs/src/plugin-layers.md`** — Rewrite (describes old design)
2. **`scripts/ad_package.sh`** — Still has wrong paths (P0 #2)
3. **`ad_vim:626`** — Dead preset branch `if [[ -n "" ]]` (P1 #13)
4. **`ad_vim:630`** — `eval` on user input (P2 #23, security)
5. **`ad_vim.pl:1059-1063`** — Unescaped placeholder (P2 #24, security)
6. **`ad_vim:2154`** — Unquoted `$NEW` in vim -c (P2 #25, security)
7. **`ad_debug.sh:119`** — Compute stage `2>&1` mixes stderr into TSV (P2 #26)
8. **`pace.c:766`** — Word-pacing `continue` skips `changed_lines++` (P1 #20)

### Should fix (cosmetic but confusing)

9. **`scripts/ad_compare`** — Help text still says `diffvim-compare`
10. **`scripts/ad_jogger`** — Help text still says `diffvim-jogger`
11. **`scripts/ad_record.sh` / `ad_replay.sh`** — Comments say `dv_record.sh` / `dv_replay.sh`
12. **`apps/vim/ad_vim`** — Line 1 comment says `# diffvim` (should be `# ad_vim`)
13. **Version string** — Hardcoded in 3 places (P3-12 regressed)

### Nice to have (P3 backlog)

14. C/Perl layer boilerplate extraction (~1050 LOC duplication)
15. Split long main() functions in ad.c and pace.c
16. Centralize magic numbers and TSV parsing
17. Delete obsolete design docs (28 files)
18. Add manpages for ad_pipeline, ad_postprocess, ad
