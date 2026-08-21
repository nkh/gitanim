#!/usr/bin/env bash
# verify_md5.sh — Round-trip MD5 verification using xargs -P for parallelism.
#
# For each example pair, runs TWO pipelines in parallel:
#   - diffvim-pipeline (C animator): compute-cpp → postprocess (C) → pace (C) → animator-c
#   - diffvim-pipeline (Perl):       compute_builtin.pl → postprocess.pl → pace.pl → animator.pl
#
# Both must produce a buffer whose MD5 matches the new file's MD5.
# This verifies that:
#   1. The C pipeline produces the correct output (existing claim)
#   2. The Perl pipeline produces byte-identical output to the C pipeline
#      (so the Perl tools are first-class, not just a fallback)
#
# The previous version of this script also tested the vimscript engine
# (simple-loop and ProcessCharOp modes). Those modes referenced engine
# functions (s:BuildHunks, s:DeleteCharAtCursor, s:ProcessCharOp) that
# were removed in the refactor — the vimscript engine is now a thin
# timed-op-stream reader. Those tests have been removed.
#
# Outputs MD5 of saved buffer for each, compares with MD5 of new file.

show_help() {
cat <<'HELP'
NAME
    verify_md5.sh — Round-trip MD5 verification of the diffvim pipelines

SYNOPSIS
    verify_md5.sh [-h|--help]

DESCRIPTION
    For every example pair under examples/ (matching [0-9]*_*), runs
    TWO diffvim pipelines in parallel (8 concurrent via xargs -P):

      1. C pipeline:        compute-cpp → C postprocess → C pace → C animator
                            (via animator/diffvim-pipeline --no-display ...)
      2. Pure-Perl pipeline: compute_builtin.pl → postprocess.pl →
                            pace.pl → animator.pl

    Both pipelines write their final buffer to a snapshot file, the
    MD5 of each snapshot is computed, and those MD5s are compared to
    the MD5 of the expected new file. The script prints a table with
    one row per example showing: example name, new-file MD5, C-pipeline
    MD5, and Perl-pipeline MD5, followed by a summary count of
    OK/bad for each pipeline.

    This verifies that:
      1. The C pipeline produces the correct output (its buffer's MD5
         matches the new file's MD5).
      2. The Perl pipeline produces byte-identical output to the C
         pipeline (so the Perl tools are first-class, not just a
         fallback).

OPTIONS
    -h, --help     Show this help message and exit 0.
                   This script takes no other arguments — it always
                   processes every example under examples/.

EXAMPLES
    verify_md5.sh
        Run MD5 round-trip verification across all examples.

OUTPUT
    A table to stdout, plus per-example MD5 files under
    /tmp/dv_md5_verify/.
HELP
}

set -uo pipefail

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

ROOT=/home/z/my-project/gitanim
OUTDIR=/tmp/dv_md5_verify
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

# -----------------------------------------------------------------------------
# Worker function: runs the C pipeline (compute-cpp → C postprocess → C pace → C animator)
# -----------------------------------------------------------------------------
run_pipe() {
    local d="$1"; local old="$2"; local new="$3"
    local out="$OUTDIR/dv_pipe_${d}.md5"
    local buf="/tmp/dv_buf_${d}_pipe.txt"
    rm -f "$buf"
    ( cd "$ROOT" && timeout -k 5 120 bash -c \
        "animator/diffvim-pipeline --no-display --speed 1000 --snapshot '$buf' '$old' '$new'" \
        >/dev/null 2>&1 )
    if [[ -f "$buf" ]]; then
        md5sum "$buf" | awk '{print $1}' > "$out"
    else
        echo "MISSING" > "$out"
    fi
    rm -f "$buf"
}

# -----------------------------------------------------------------------------
# Worker function: runs the pure-Perl pipeline
# (compute_builtin.pl → postprocess.pl → pace.pl → animator.pl)
# Verifies the Perl toolchain produces byte-identical output to the C pipeline.
# -----------------------------------------------------------------------------
run_perl_pipe() {
    local d="$1"; local old="$2"; local new="$3"
    local out="$OUTDIR/dv_perl_pipe_${d}.md5"
    local buf="/tmp/dv_buf_${d}_perl_pipe.txt"
    rm -f "$buf"
    ( cd "$ROOT" && timeout -k 5 180 bash -c \
        "perl compute/perl/compute_builtin.pl '$old' '$new' /tmp/_perl_raw_$$.txt 2>/dev/null && \
         perl animator/perl/postprocess.pl < /tmp/_perl_raw_$$.txt 2>/dev/null | \
         perl animator/perl/pace.pl 2>/dev/null | \
         perl animator/perl/animator.pl --no-display --speed 1000 --snapshot '$buf' '$old' 2>/dev/null" \
        >/dev/null 2>&1 )
    rm -f /tmp/_perl_raw_$$.txt
    if [[ -f "$buf" ]]; then
        md5sum "$buf" | awk '{print $1}' > "$out"
    else
        echo "MISSING" > "$out"
    fi
    rm -f "$buf"
}

export -f run_pipe run_perl_pipe
export ROOT OUTDIR

# -----------------------------------------------------------------------------
# Build task list and run in parallel via xargs
# -----------------------------------------------------------------------------
> /tmp/dv_tasks.txt
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    news=( "$ROOT/examples/$d"/new.* )
    olds=( "$ROOT/examples/$d"/old.* )
    [[ ${#news[@]} -eq 0 || ${#olds[@]} -eq 0 ]] && continue
    new="${news[0]}"; old="${olds[0]}"
    echo "pipe|$d|$old|$new"          >> /tmp/dv_tasks.txt
    echo "perl_pipe|$d|$old|$new"     >> /tmp/dv_tasks.txt
done

echo "Total tasks: $(wc -l < /tmp/dv_tasks.txt)"
echo "Running in parallel (8 concurrent)..."

# Each line is kind|dir|old|new
cat /tmp/dv_tasks.txt | \
    awk -F'|' '{ printf "%s \"%s\" \"%s\" \"%s\"\n", $1, $2, $3, $4 }' | \
    xargs -P 8 -I {} bash -c 'IFS=" " read -r kind d old new <<< "{}";
case "$kind" in
    pipe)       run_pipe       "$d" "$old" "$new" ;;
    perl_pipe)  run_perl_pipe  "$d" "$old" "$new" ;;
esac'

echo ""
echo "All tasks complete. Collecting results..."

# -----------------------------------------------------------------------------
# Print table
# -----------------------------------------------------------------------------
printf "\n"
printf "Round-trip MD5 verification — all 42 example pairs\n"
printf '%s\n' "$(printf '%.0s=' {1..120})"
printf "%-22s | %-32s | %-32s | %-32s\n" "example" "new-file MD5" \
    "pipeline (C animator)" "pipeline (Perl)"
printf '%s\n' "$(printf '%.0s-' {1..120})"

p_ok=0; p_bad=0; pp_ok=0; pp_bad=0

for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    news=( "$ROOT/examples/$d"/new.* )
    [[ ${#news[@]} -eq 0 ]] && continue
    new="${news[0]}"

    new_md5=$(md5sum "$new" | awk '{print $1}')
    p_md5=$(cat "$OUTDIR/dv_pipe_${d}.md5"      2>/dev/null || echo "MISSING")
    pp_md5=$(cat "$OUTDIR/dv_perl_pipe_${d}.md5" 2>/dev/null || echo "MISSING")

    [[ "$p_md5"  == "$new_md5" ]]  && p_ok=$((p_ok+1))   || p_bad=$((p_bad+1))
    [[ "$pp_md5" == "$new_md5" ]]  && pp_ok=$((pp_ok+1))  || pp_bad=$((pp_bad+1))

    printf "%-22s | %-32s | %-32s | %-32s\n" "$d" "$new_md5" "$p_md5" "$pp_md5"
done

printf '%s\n' "$(printf '%.0s=' {1..120})"
printf "\nSummary:\n"
printf "  diffvim-pipeline (C animator):              %2d OK / %2d bad\n" $p_ok $p_bad
printf "  diffvim-pipeline (Perl):                   %2d OK / %2d bad\n" $pp_ok $pp_bad
echo ""
