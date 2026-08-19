# autoload/

Vimscript autoload plugin. Contains the diffvim engine that is
sourced by the `diffvim` bash launcher.

## Files

- `diffvim/engine.vim` — The vimscript animation engine. This is the
  OLD engine (pre-refactor) that did everything in vimscript (compute,
  postprocess, pace, animate). It's kept for reference but is no longer
  used — the `diffvim` launcher now uses the external C pipeline and
  a thin timed-op-stream reader embedded in the launcher itself.

## Related

- `../diffvim` — The bash launcher (contains the embedded timed-op
  stream reader that replaced this engine)
- `../plugin/diffvim.vim` — The plugin entry point
