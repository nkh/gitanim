#!/usr/bin/env bash
# ad_layer_line_delete_in_place.sh — Delete content BEFORE joining lines.
#
# Bash implementation using a pipeline of Unix tools running in parallel.
#
# Architecture (each HUNK is processed by an independent pipeline):
#
#   csplit — split the input into per-HUNK files (each HUNK is independent)
#   awk   — minimal state machine: detects J-D+-J patterns and emits a
#           transformation plan. NO field manipulation is done in awk.
#   sed   — applies the transformation plan:
#             E <line>        → emit unchanged
#             N <new_L>       → emit "join_lines\t<new_L>" (new J replacing 2nd J)
#             R <new_L> <op>  → emit <op> with its line field rewritten to <new_L>
#   cat   — reassemble the per-HUNK outputs in original order
#
# The awk script is intentionally tiny (≈25 lines, pattern detection only).
# All field-level work (line-number rewriting, new J emission) is done by sed.
# Multiple HUNKs are processed in parallel via & and wait.
#
# Two modes: --mode batch (default) or --mode=interleaved (pass-through)
# Usage: ad_layer_line_delete_in_place.sh [--mode batch|interleaved] < ops.tsv
#
# Pattern: join_lines(L) + delete(content at col 1)+ + join_lines(L)
# Batch:   delete(content at L+1)+ + join_lines(L+1), first J kept as chain joiner
# Only matches full-line deletions (col 1). Partial content at col > 1 is left alone.

set -euo pipefail

MODE="batch"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)        MODE="$2"; shift 2 ;;
        --mode=*)      MODE="${1#--mode=}"; shift ;;
        --help|-h)
            cat <<'HELP'
ad_layer_line_delete_in_place.sh — delete content before joining lines

Usage: ad_layer_line_delete_in_place.sh [--mode batch|interleaved] < ops.tsv

Pipeline (per HUNK, run in parallel):
  csplit  → awk (plan)  → sed (apply plan)  → cat (reassemble)

Options:
  --mode batch        Delete all content first, then join all (default)
  --mode interleaved  Pass-through (diff engine's natural output)
  --help, -h          Show this help
HELP
            exit 0 ;;
        *) shift ;;
    esac
done

# Interleaved = pass-through
if [[ "$MODE" == "interleaved" ]]; then
    cat
    exit 0
fi

# Save input to a work directory (parallel jobs need scratch space).
WORK=$(mktemp -d)
trap "rm -rf '$WORK'" EXIT
cat > "$WORK/input.tsv"

# Stage 1: Split the input into per-HUNK files using csplit.
# csplit -s (silent) -z (no empty files) -f <prefix> splits BEFORE each /^HUNK\t/.
# Result: hunk_00 = header (comments before first HUNK),
#         hunk_01, hunk_02, ... = one HUNK each (HUNK header + body + HUNK_END).
csplit -s -z -f "$WORK/hunk_" "$WORK/input.tsv" '/^HUNK\t/' '{*}' 2>/dev/null || true

# If csplit produced no splits (e.g. empty input or no HUNK markers), pass through.
if ! compgen -G "$WORK/hunk_*" >/dev/null 2>&1; then
    cat "$WORK/input.tsv"
    exit 0
fi

# Stage 2 (PARALLEL): Each HUNK is processed by an independent pipeline.
#   awk → emits a transformation plan (one line per output op, in output order)
#   sed → applies the plan (rewrites L fields, emits new J's, passes through)
#
# Plan line format:  <out_pos>\t<action>\t<arg>\t<original_line>
#   E - <line>            → emit <line> unchanged
#   N <new_L> <old_j>     → emit "join_lines\t<new_L>" (second J becomes new J)
#   R <new_L> <old_d>     → emit <old_d> with its line field rewritten to <new_L>
#
# Because each HUNK is independent (the awk state machine flushes at HUNK_END),
# we can safely run all HUNKs in parallel.
for hf in "$WORK/hunk_"*; do
    (
        awk -F'\t' '
        BEGIN { state = "normal"; buf_n = 0; buf_join_line = 0; out_pos = 0 }
        function emit(action, arg, line) {
            printf "%d\t%s\t%s\t%s\n", ++out_pos, action, arg, line
        }
        function flush() {
            # Flush the buffer: every buffered op is emitted unchanged.
            # This handles the leftover joiner (the first J of a completed
            # chain) — it gets emitted at its natural position (right before
            # whatever triggered the flush), which is exactly what the C
            # version does.
            for (i = 0; i < buf_n; i++) emit("E", "-", buf[i])
            buf_n = 0; state = "normal"
        }
        # Passthrough lines (flush the buffer, then emit unchanged).
        /^#/      { if (buf_n > 0) flush(); emit("E", "-", $0); next }
        /^HUNK\t/ { if (buf_n > 0) flush(); emit("E", "-", $0); next }
        /^HUNK_END/ { if (buf_n > 0) flush(); emit("E", "-", $0); next }
        /^$/      { if (buf_n > 0) flush(); emit("E", "-", $0); next }
        # Op lines — minimal state machine (pattern detection only).
        {
            type = $1
            if (state == "normal") {
                if (type == "join_lines") {
                    state = "after_join"; buf_join_line = $2
                    buf[0] = $0; buf_n = 1
                } else {
                    emit("E", "-", $0)
                }
            } else if (state == "after_join") {
                if (type == "delete" && $3 == "1") {
                    state = "in_content"; buf[buf_n++] = $0
                } else if (type == "join_lines") {
                    # J after J (no D between): emit the first J as a leftover
                    # and start a NEW pattern with the second J as the joiner.
                    # This matches the C version: at i=first_J it emits
                    # unchanged (no pattern), then at i=second_J it looks for
                    # a new pattern starting there.
                    emit("E", "-", buf[0])
                    buf[0] = $0; buf_n = 1; buf_join_line = $2
                    # state stays "after_join"
                } else {
                    flush(); emit("E", "-", $0)
                }
            } else if (state == "in_content") {
                if (type == "delete" && $3 == "1") {
                    buf[buf_n++] = $0
                } else if (type == "join_lines") {
                    # Pattern complete: J(L) + D(col=1)+ + J(L).
                    # Emit plan: rewrite each D line field to L+1, replace
                    # the second J with a new J at L+1. Keep the first J in
                    # buf[0] as the joiner for the next pattern (chained).
                    for (i = 1; i < buf_n; i++) {
                        emit("R", buf_join_line + 1, buf[i])
                    }
                    emit("N", buf_join_line + 1, $0)
                    buf_n = 1; state = "after_join"
                } else {
                    flush(); emit("E", "-", $0)
                }
            }
        }
        END { if (buf_n > 0) flush() }
        ' "$hf" \
        | sed -n -E '
            # Apply each plan action. The `t end` after each `s` skips the
            # remaining actions if the substitution succeeded.
            s/^[0-9]+[[:space:]]+E[[:space:]]+-[[:space:]]+//p; t end
            s/^[0-9]+[[:space:]]+N[[:space:]]+([0-9]+)[[:space:]]+.*$/join_lines\t\1/p; t end
            s/^[0-9]+[[:space:]]+R[[:space:]]+([0-9]+)[[:space:]]+([^\t]+)\t[0-9]+\t(.*)$/\2\t\1\t\3/p; t end
            :end
        ' \
        > "$hf.out"
    ) &
done
wait

# Stage 3: Reassemble in order, then rewrite the header comment.
# csplit produces files in lexicographic order (hunk_00, hunk_01, ...),
# which matches the original input order.
# The header rewrite (raw diff → post-processed) matches what the C common
# layer runtime does (layers/c/ad_layer_common.h:353).
cat "$WORK/hunk_"*.out \
    | sed -E 's/^# diffvim (raw diff|post-processed) v2$/# diffvim post-processed v2/'
