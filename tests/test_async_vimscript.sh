#!/usr/bin/env bash
# test_async_vimscript.sh — Test the vimscript animator in ASYNC mode
# (with timers, like real ad_vim). This catches bugs that the sync
# test misses.
#
# Usage: bash tests/test_async_vimscript.sh <example_dir>

show_help() {
cat <<'HELP'
NAME
    test_async_vimscript.sh — Test the vimscript animator in ASYNC mode

SYNOPSIS
    test_async_vimscript.sh [-h|--help]
    test_async_vimscript.sh <example_dir>

DESCRIPTION
    Tests the vimscript animator (the engine embedded in the ad_vim
    launcher) in its REAL asynchronous mode — i.e. with timers, exactly
    as it runs inside Vim during a live ad_vim session. This catches
    bugs that the synchronous variant (test_vimscript_animator.sh)
    cannot, such as timer-related state issues.

    Pipeline per example:
      1. Extracts the vimscript engine from the ad_vim launcher.
      2. Runs compute-cpp + postprocess + pace to get the timed ops.
      3. Runs headless Vim (vim -e -s -n) with the engine sourced,
         AD_SPEED=1000000 (delays become ~0ms), and a 60s timeout.
      4. Compares the engine's output buffer to the expected new file.

OPTIONS
    -h, --help        Show this help message and exit 0.
    <example_dir>     Path to an example directory containing old.*
                      and new.* files (e.g. tests/examples/01_small_python).

EXAMPLES
    test_async_vimscript.sh tests/examples/01_small_python
        Run the async test on the small Python example.

    test_async_vimscript.sh /home/z/my-project/gitanim/tests/examples/32_python_classes
        Use an absolute path to the example directory.

EXIT STATUS
    0   PASS — engine output matches the new file exactly.
    1   FAIL — no output produced, or output differs from the new file.
HELP
}

set -uo pipefail
ROOT=/home/z/my-project/gitanim

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

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
"$ROOT/bin/ad_compute" "$OLD" "$NEW" "$RAW" 2>/dev/null
"$ROOT/bin/ad_postprocess" < "$RAW" > "$POST" 2>/dev/null
"$ROOT/bin/ad_layer_pace" < "$POST" > "$TIMED" 2>/dev/null

# Run the REAL vimscript animator (with timers, headless)
# Speed 1000000 makes delays ~0ms, so it finishes fast
AD_TIMED_OPS="$TIMED" \
AD_OUTPUT="$OUT" \
AD_SPEED=1000000 \
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
