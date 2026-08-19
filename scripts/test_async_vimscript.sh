#!/usr/bin/env bash
# test_async_vimscript.sh — Test the vimscript animator in ASYNC mode
# (with timers, like real diffvim). This catches bugs that the sync
# test misses.
#
# Usage: bash scripts/test_async_vimscript.sh <example_dir>

set -uo pipefail
ROOT=/home/z/my-project/gitanim

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <example_dir>"
    exit 1
fi

EXAMPLE="$1"
OLD=$(ls "$EXAMPLE"/old.* 2>/dev/null | head -1)
NEW=$(ls "$EXAMPLE"/new.* 2>/dev/null | head -1)
[[ -f "$OLD" && -f "$NEW" ]] || { echo "Example not found: $EXAMPLE"; exit 1; }

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Extract the engine
ENG="$TMPDIR/engine.vim"
perl -e '
    open my $fh, "<", "/home/z/my-project/gitanim/diffvim" or die;
    my $in = 0; my @L;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in=1; next; }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @L, $line if $in;
    }
    close $fh;
    open my $ofh, ">", $ARGV[0] or die;
    print $ofh join("", @L);
    close $ofh;
' "$ENG"

# Run the pipeline to get the timed ops
RAW="$TMPDIR/raw.txt"
POST="$TMPDIR/post.txt"
TIMED="$TMPDIR/timed.txt"
OUT="$TMPDIR/out.txt"
"$ROOT/compute/bin/diffvim-compute-cpp" "$OLD" "$NEW" "$RAW" 2>/dev/null
"$ROOT/animator/bin/diffvim-postprocess" < "$RAW" > "$POST" 2>/dev/null
"$ROOT/animator/bin/diffvim-pace" < "$POST" > "$TIMED" 2>/dev/null

# Run the REAL vimscript animator (with timers, headless)
# Speed 1000000 makes delays ~0ms, so it finishes fast
DIFFVIM_TIMED_OPS="$TIMED" \
DIFFVIM_OUTPUT="$OUT" \
DIFFVIM_SPEED=1000000 \
timeout -k 5 60 vim -e -s -n -Nu NONE -U NONE \
    -c "let g:diffvim_new_file = '$NEW'" \
    -c "source $ENG" \
    "$OLD" </dev/null >/dev/null 2>&1

if [[ ! -f "$OUT" ]]; then
    echo "FAIL: no output file produced"
    exit 1
fi

if diff -q "$NEW" "$OUT" >/dev/null 2>&1; then
    echo "PASS: $EXAMPLE"
    exit 0
else
    echo "FAIL: $EXAMPLE"
    echo "  Differences (first 20 lines):"
    diff "$NEW" "$OUT" | head -20 | sed 's/^/  /'
    exit 1
fi
