# Parallel Compute + ad_vim Startup Analysis

## Problem

When ad_vim starts, it does two things sequentially:

1. **Diff computation** — vimscript patience diff at line level + char level (can take
   100ms–10s for large files)
2. **Vim startup** — loading vimrc, syntax highlighting, reading the old file
   (typically 50–200ms)

Currently these are sequential: vim starts, then computes the diff. If we
could compute the diff *in parallel* with vim startup, we'd save the entire
diff-computation time.

## Feasibility Analysis

### What's needed

The external compute tools (C++) already produce a precomputed
diff file. The `--precomputed FILE` option makes ad_vim load this file
instead of computing the diff in vimscript. So the question is: **can we
start the compute tool and vim simultaneously, and have vim wait for the
compute tool to finish before loading the precomputed file?**

### Approach 1: Background compute + wait (simple, recommended)

```bash
# Start compute in background
bin/ad_compute "$OLD" "$NEW" /tmp/diff.txt &
COMPUTE_PID=$!

# Start vim immediately (it will read the old file, load vimrc, etc.)
# Vim's VimEnter autocmd waits for the precomputed file to appear.
vim ... -c "let g:diffvim_precomputed = '/tmp/diff.txt'" ...

# Wait for compute to finish
wait $COMPUTE_PID
```

**Problem:** vim's `VimEnter` autocmd fires immediately after startup. If
the precomputed file doesn't exist yet (compute still running), ad_vim
will fall back to inline computation — defeating the purpose.

**Solution:** Add a "wait for file" loop in the engine. Before
`BuildHunks()`, if `g:diffvim.precomputed` is set, spin-wait (with
`gettimeofday` + `timer_start` polling) until the file exists and is
readable, with a timeout (e.g., 10 seconds). This adds ~1ms of latency
once the file appears.

**Pros:** Simple, robust, no IPC complexity.
**Cons:** Spin-waiting wastes a tiny bit of CPU; if compute crashes, vim
hangs until timeout.

### Approach 2: Named pipe (FIFO)

```bash
# Create a FIFO
mkfifo /tmp/diff.fifo

# Start compute writing to FIFO (blocks until reader connects)
bin/ad_compute "$OLD" "$NEW" /tmp/diff.fifo &

# Start vim reading from FIFO
# vim's readfile() will block until the writer closes the FIFO
vim ... -c "let g:diffvim_precomputed = '/tmp/diff.fifo'" ...
```

**Problem:** vim's `readfile()` blocks on a FIFO, freezing the UI until
the compute finishes. This defeats the purpose of parallelism — vim can't
render the buffer or respond to user input while blocked.

**Solution:** Use a non-blocking read with a timer, but this is complex
in vimscript.

**Pros:** No spin-waiting, natural synchronization.
**Cons:** Blocks vim during read; complex to make non-blocking.

### Approach 3: File marker (recommended for production)

```bash
# Start compute in background, write to temp file, then rename to final
COMPUTE_OUT=/tmp/diff.txt.ready
COMPUTE_TMP=/tmp/diff.txt.tmp
(bin/ad_compute "$OLD" "$NEW" "$COMPUTE_TMP" && mv "$COMPUTE_TMP" "$COMPUTE_OUT") &

# Vim polls for .ready file
vim ... -c "let g:diffvim_precomputed = '$COMPUTE_OUT'" ...
```

The engine polls for the `.ready` file with a timer (every 50ms). Once it
appears, it loads the file. The `mv` (rename) is atomic on the same
filesystem, so vim never sees a partial file.

**Pros:** No blocking, no partial reads, clean fallback (if file never
appears, fall back to inline computation after timeout).
**Cons:** Slightly more complex than Approach 1.

### Approach 4: Shared memory / socket

Not practical for vimscript — vim has no socket API, and shared memory
would require a plugin with Python/Neovim support.

## Recommendation

**Approach 1 (background compute + file-poll wait)** is the simplest and
most practical. Here's the implementation:

### Bash wrapper (`ad_vim-parallel`)

```bash
#!/usr/bin/env bash
OLD="$1"; NEW="$2"; shift 2
WORKDIR=$(mktemp -d); trap 'rm -rf "$WORKDIR"' EXIT
PC="$WORKDIR/diff.txt"

# Start compute in background
bin/ad_compute "$OLD" "$NEW" "$PC" 2>/dev/null &
PID=$!

# Start vim with --precomputed; the engine will poll for the file
ad_vim --precomputed "$PC" "$@" "$OLD" "$NEW"

wait $PID 2>/dev/null
```

### Engine change (polling)

In `BuildHunks()`, before loading the precomputed file, wait for it to
exist:

```vim
if !empty(g:diffvim.precomputed)
    " Wait for the file to appear (parallel compute mode).
    " Poll every 50ms, timeout after 10 seconds.
    let l:waited = 0
    while !filereadable(g:diffvim.precomputed) && l:waited < 10000
        sleep 50m
        let l:waited += 50
    endwhile
    if filereadable(g:diffvim.precomputed)
        return s:LoadPrecomputed(g:diffvim.precomputed)
    endif
    " Timeout — fall back to inline computation
    echo 'ad_vim: precomputed file timeout, falling back to inline'
endif
```

### Expected speedup

| File size | Inline vimscript | External compute (C++) | Parallel total |
|-----------|-----------------|---------------------|----------------|
| 10 lines  | ~5ms            | ~0.3ms              | ~50ms (vim startup dominates) |
| 100 lines | ~50ms           | ~0.5ms              | ~50ms (vim startup dominates) |
| 1000 lines| ~500ms          | ~2ms                | ~52ms (10x speedup) |
| 5000 lines| ~5s             | ~10ms               | ~60ms (83x speedup) |

For small files, the parallel approach doesn't help (vim startup dominates).
For large files (1000+ lines), the speedup is dramatic because the compute
runs concurrently with vim startup.

### When to use parallel mode

- **Large files (500+ lines):** Parallel mode saves 50–99% of startup time.
- **Small files (<100 lines):** Not worth the complexity; inline is fast
  enough.
- **Repeated runs:** If you're animating the same file multiple times
  (e.g., `--replay`), pre-compute once and reuse the file.

## Current status

The infrastructure is in place:
- External compute tools produce the precomputed file format.
- `--precomputed FILE` loads the file in the engine.
- the compute tool computes then ad_vim animates sequentially.

The **parallel** wrapper (`ad_vim-parallel`) with the polling engine
change is left as a future enhancement — it requires adding a `sleep` loop
to the vimscript engine, which blocks the UI during the wait. For now, the
sequential compute+ad_vim approach is sufficient because the external
compute is so fast (sub-millisecond for typical files) that the sequential
overhead is negligible.
