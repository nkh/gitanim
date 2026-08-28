#!/usr/bin/env bash
# test_vimscript_animator.sh — Test the vimscript animator (timed-op-stream reader)
# in headless mode by extracting the engine, patching it to be synchronous
# (no timers), and running it against pre-computed timed op streams.
#
# This complements verify_md5.sh, which tests the C and Perl pipelines.
# Together they cover all three animator implementations (C, Perl, vimscript).
#
# Usage: bash test_vimscript_animator.sh [example_dir]
#   With no argument, tests all examples.

show_help() {
cat <<'HELP'
NAME
    test_vimscript_animator.sh — Synchronous headless test of the vimscript animator

SYNOPSIS
    test_vimscript_animator.sh [-h|--help]
    test_vimscript_animator.sh [example_dir]

DESCRIPTION
    Tests the vimscript animator (the engine embedded in the diffvim
    launcher) by extracting it, patching s:StartTimedAnimation to run
    synchronously (no timers), and running it headless (vim -e -s -n)
    against pre-computed timed op streams produced by the C pipeline.
    The final buffer is written out and compared byte-for-byte with
    the expected new file.

    This complements verify_md5.sh, which tests the C and Perl
    pipelines. Together they cover all three animator implementations
    (C, Perl, vimscript). The async variant is
    test_async_vimscript.sh.

OPTIONS
    -h, --help        Show this help message and exit 0.
    <example_dir>     Optional. Path to a single example directory
                      containing old.* and new.* files. If omitted,
                      every example under tests/tests/examples/ matching [0-9]*_*
                      is tested.

EXAMPLES
    test_vimscript_animator.sh
        Test the vimscript animator against ALL examples.

    test_vimscript_animator.sh tests/tests/examples/01_small_python
        Test only the small Python example.

    test_vimscript_animator.sh 32_python_classes
        The "tests/tests/examples/" prefix may be omitted.

EXIT STATUS
    0   All tested examples PASSED.
    1   At least one example FAILED.
HELP
}

set -uo pipefail
ROOT=/home/z/my-project/gitanim
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Handle -h/--help
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

# --- Extract the vimscript engine from the diffvim launcher ---
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

# --- Patch the engine: replace s:StartTimedAnimation with a synchronous
#     version that doesn't use timers. ---
perl -i -pe '
    if (/^let s:timed_timer = timer_start\(.*$/) {
        $_ = "";  # remove this line
    }
' "$ENG"

# Replace s:StartTimedAnimation with a synchronous version
perl -i -0pe '
    s/function! s:StartTimedAnimation\(\) abort.*?^endfunction//ms;
' "$ENG"

cat >> "$ENG" <<'VIM'

" Synchronous test runner — processes all ops without using timers.
" This is patched in by test_vimscript_animator.sh for headless testing.
function! s:StartTimedAnimation() abort
    call s:LoadTimedOps()
    if empty(s:timed_ops)
        echoerr 'diffvim: timed op stream is empty'
        return
    endif
    let s:timed_speed = 1000000.0  " super fast — delays become ~0ms
    while 1
        let l:delay = s:TimedProcessBatch()
        if l:delay == -1
            break
        endif
    endwhile
    " Write the final buffer to g:diffvim.output_file (re-uses the
    " real helper, which handles the empty-buffer case correctly).
    call s:TimedWriteOutput()
endfunction
call s:StartTimedAnimation()
qa!
VIM

# --- Test runner ---
pass=0
fail=0
total=0

if [[ $# -ge 1 ]]; then
    examples=("$1")
else
    examples=( $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort) )
fi

for d in "${examples[@]}"; do
    # Strip any "tests/tests/examples/" prefix the caller might have passed
    d="${d#tests/tests/examples/}"
    # Find example directory
    if [[ -d "$ROOT/tests/tests/examples/$d" ]]; then
        dirpath="$ROOT/tests/tests/examples/$d"
    elif [[ -d "$d" ]]; then
        dirpath="$d"
    else
        continue
    fi
    old=$(ls "$dirpath"/old.* 2>/dev/null | head -1)
    new=$(ls "$dirpath"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    total=$((total + 1))

    # Pre-compute timed ops using the C pipeline
    raw="$TMPDIR/raw.txt"
    post="$TMPDIR/post.txt"
    timed="$TMPDIR/timed.txt"
    out="$TMPDIR/out.txt"
    rm -f "$out"

    "$ROOT/bin/ad_compute" "$old" "$new" "$raw" 2>/dev/null
    "$ROOT/bin/ad_postprocess" < "$raw" > "$post" 2>/dev/null
    "$ROOT/bin/ad_layer_pace" < "$post" > "$timed" 2>/dev/null

    # Run vim headless with the patched engine
    AD_TIMED_OPS="$timed" \
    AD_OUTPUT="$out" \
    AD_SPEED=1000000 \
    timeout -k 5 60 vim -e -s -n -Nu NONE -U NONE \
        -c "let g:diffvim_new_file = '$new'" \
        -c "source $ENG" \
        "$old" </dev/null >/dev/null 2>&1

    if [[ -f "$out" ]] && diff -q "$new" "$out" >/dev/null 2>&1; then
        pass=$((pass + 1))
        echo "PASS: $d"
    else
        fail=$((fail + 1))
        echo "FAIL: $d"
        if [[ ! -f "$out" ]]; then
            echo "  (no output file produced)"
        else
            diff "$new" "$out" | head -3
        fi
    fi
done

echo ""
echo "=== Results: $pass passed, $fail failed (of $total total) ==="
exit $((fail == 0 ? 0 : 1))
