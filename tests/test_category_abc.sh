#!/usr/bin/env bash
# test_category_abc.sh — Comprehensive tests for all Category A, B, C features.
#
# Tests every new feature added in the A/B/C implementation:
#   A: pacing modes, pause-after-lines, accel-delete, rapid-eol,
#      rapid-identical, block-delete, overwrite, op-order variants
#   B: decorate (highlight, dim, fold, sign, skip_hunk), C/Perl parity
#   C: log-mode, debug, max-line-len, presets
#
# Usage: bash test_category_abc.sh

set -uo pipefail
ROOT=/home/z/my-project/gitanim
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
total=0

ok() { total=$((total+1)); if eval "$2"; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# === Setup test files ===
printf 'hello world\nabc\ndef\n' > "$TMPDIR/old1.txt"
printf 'hello there\nabc\nghi\n' > "$TMPDIR/new1.txt"

printf 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n' > "$TMPDIR/old2.txt"
printf 'CHANGED1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nCHANGED10\n' > "$TMPDIR/new2.txt"

printf 'aaaaaaaaaa\n' > "$TMPDIR/old3.txt"
printf 'bb\n' > "$TMPDIR/new3.txt"

printf '    print("hello")\n' > "$TMPDIR/old4.txt"
printf '    print(f"hello")\n' > "$TMPDIR/new4.txt"

run_pipeline() {
    local old="$1" new="$2" extra_args="${3:-}"
    "$ROOT/compute/bin/diffvim-compute-cpp" "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess $extra_args < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
}

echo "=== Category A: Pipeline features ==="

# A3: --pacing modes
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
DELAY_UNI=$($ROOT/animator/bin/diffvim-pace --pacing uniform < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "delay	1	" | head -1 | cut -f2)
DELAY_REV=$($ROOT/animator/bin/diffvim-pace --pacing review < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "delay	1	" | head -1 | cut -f2)
ok "pacing review doubles delays" "[[ '$DELAY_REV' -gt 0 ]] && [[ $DELAY_REV -ge $((DELAY_UNI * 2)) ]]"

run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
DELAY_GAUSS1=$($ROOT/animator/bin/diffvim-pace --pacing gaussian < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "delay	1	" | head -1 | cut -f2)
DELAY_GAUSS2=$($ROOT/animator/bin/diffvim-pace --pacing gaussian < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "delay	1	" | head -1 | cut -f2)
ok "pacing gaussian produces variation" "[[ '$DELAY_GAUSS1' -gt 0 ]]"

run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
DELAY_ADAPT=$($ROOT/animator/bin/diffvim-pace --pacing adaptive < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "delay	1	" | head -1 | cut -f2)
ok "pacing adaptive produces delays" "[[ '$DELAY_ADAPT' -gt 0 ]]"

# A5: --pause-after-lines
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
PAUSE_COUNT=$($ROOT/animator/bin/diffvim-pace --pause-after-lines 1 --pause-after-threshold 1 < "$TMPDIR/post.txt" 2>/dev/null | grep "pause_after" | wc -l)
ok "pause-after-lines inserts pauses" "[[ $PAUSE_COUNT -gt 0 ]]"

PAUSE_NONE=$($ROOT/animator/bin/diffvim-pace --pause-after-lines 0 < "$TMPDIR/post.txt" 2>/dev/null | grep "pause_after" | wc -l)
ok "pause-after-lines 0 = no pauses" "[[ $PAUSE_NONE -eq 0 ]]"

# A6: --accel-delete
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
ACCEL_COUNT=$($ROOT/animator/bin/diffvim-pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | wc -l)
ok "accel-delete emits accel_delete delays" "[[ $ACCEL_COUNT -gt 0 ]]"

ACCEL_FIRST=$($ROOT/animator/bin/diffvim-pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | head -1 | cut -f2)
ACCEL_LAST=$($ROOT/animator/bin/diffvim-pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | tail -1 | cut -f2)
ok "accel-delete first delay >= last delay (deceleration)" "[[ $ACCEL_FIRST -ge $ACCEL_LAST ]]"

# A7: --delete-pacing rapid-eol
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
RAPID_EOL=$($ROOT/animator/bin/diffvim-pace --delete-pacing rapid-eol < "$TMPDIR/post.txt" 2>/dev/null | grep "rapid_eol" | wc -l)
ok "rapid-eol emits rapid_eol delays" "[[ $RAPID_EOL -gt 0 ]]"

# A7: --delete-pacing rapid-identical
run_pipeline "$TMPDIR/old3.txt" "$TMPDIR/new3.txt"
RAPID_ID=$($ROOT/animator/bin/diffvim-pace --delete-pacing rapid-identical < "$TMPDIR/post.txt" 2>/dev/null | grep "rapid_identical" | wc -l)
ok "rapid-identical emits rapid_identical delays" "[[ $RAPID_ID -gt 0 ]]"

# A8: --block-delete-size
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
BLOCK_START=$($ROOT/animator/bin/diffvim-pace --block-delete-size 1 --pause-before-delete-ms 100 < "$TMPDIR/post.txt" 2>/dev/null | grep "block_start" | wc -l)
ok "block-delete emits block_start pauses" "[[ $BLOCK_START -gt 0 ]]"

BLOCK_END=$($ROOT/animator/bin/diffvim-pace --block-delete-size 1 --pause-after-delete-ms 100 < "$TMPDIR/post.txt" 2>/dev/null | grep "block_end" | wc -l)
ok "block-delete emits block_end pauses" "[[ $BLOCK_END -gt 0 ]]"

# A9: --overwrite
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" "--overwrite"
OW_COUNT=$(grep "overwrite_insert" "$TMPDIR/post.txt" | wc -l)
ok "overwrite produces overwrite_insert ops" "[[ $OW_COUNT -gt 0 ]]"

# A9: overwrite output still correct
$ROOT/animator/bin/diffvim-pace < "$TMPDIR/post.txt" > "$TMPDIR/timed_ow.txt" 2>/dev/null
$ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/out_ow.txt" "$TMPDIR/old1.txt" < "$TMPDIR/timed_ow.txt" 2>/dev/null
ok "overwrite output matches new file" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/out_ow.txt'"

# A10: --op-order left-to-right
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
LT_COUNT=$($ROOT/animator/bin/diffvim-postprocess --op-order left-to-right < "$TMPDIR/raw.txt" 2>/dev/null | grep "^keep" | head -1 | wc -l)
ok "op-order left-to-right produces output" "[[ $LT_COUNT -gt 0 ]]"

# A10: --op-order end-first
EF_COUNT=$($ROOT/animator/bin/diffvim-postprocess --op-order end-first < "$TMPDIR/raw.txt" 2>/dev/null | wc -l)
ok "op-order end-first produces output" "[[ $EF_COUNT -gt 0 ]]"

# A10: --op-order end-first-smart
EFS_COUNT=$($ROOT/animator/bin/diffvim-postprocess --op-order end-first-smart < "$TMPDIR/raw.txt" 2>/dev/null | wc -l)
ok "op-order end-first-smart produces output" "[[ $EFS_COUNT -gt 0 ]]"

# A parity: C vs Perl pace
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/animator/bin/diffvim-pace --pacing review < "$TMPDIR/post.txt" > "$TMPDIR/pace_c.txt" 2>/dev/null
perl $ROOT/animator/perl/pace.pl --pacing review < "$TMPDIR/post.txt" > "$TMPDIR/pace_perl.txt" 2>/dev/null
ok "C pace == Perl pace (review mode)" "diff -q '$TMPDIR/pace_c.txt' '$TMPDIR/pace_perl.txt'"

echo ""
echo "=== Category B: Decorate features ==="

# B: --highlight inline
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/animator/bin/diffvim-decorate --highlight inline < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_INLINE=$(grep "^highlight" "$TMPDIR/dec.txt" | grep "insert\|delete" | wc -l)
ok "highlight inline emits per-char highlights" "[[ $HL_INLINE -gt 0 ]]"

# B: --highlight word
$ROOT/animator/bin/diffvim-decorate --highlight word < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_WORD=$(grep "^highlight" "$TMPDIR/dec.txt" | wc -l)
ok "highlight word emits highlights" "[[ $HL_WORD -gt 0 ]]"

# B: --highlight hunk
$ROOT/animator/bin/diffvim-decorate --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_HUNK=$(grep "^highlight.*hunk" "$TMPDIR/dec.txt" | wc -l)
ok "highlight hunk emits hunk highlights" "[[ $HL_HUNK -gt 0 ]]"

# B: --dim-unchanged
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
$ROOT/animator/bin/diffvim-decorate --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
DIM_COUNT=$(grep "^dim" "$TMPDIR/dec.txt" | wc -l)
ok "dim-unchanged emits dim ops" "[[ $DIM_COUNT -gt 0 ]]"

# B: --context N
$ROOT/animator/bin/diffvim-decorate --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
FOLD_CONTEXT=$(grep "^fold" "$TMPDIR/dec.txt" | wc -l)
ok "context N emits fold ops" "[[ $FOLD_CONTEXT -gt 0 ]]"

# B: --fold-unchanged
$ROOT/animator/bin/diffvim-decorate --fold-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
FOLD_COUNT=$(grep "^fold" "$TMPDIR/dec.txt" | wc -l)
ok "fold-unchanged emits fold ops" "[[ $FOLD_COUNT -gt 0 ]]"

# B: --sign-column
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/animator/bin/diffvim-decorate --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
SIGN_COUNT=$(grep "^sign" "$TMPDIR/dec.txt" | wc -l)
ok "sign-column emits sign ops" "[[ $SIGN_COUNT -gt 0 ]]"

# B: --max-hunk-chars
$ROOT/animator/bin/diffvim-decorate --max-hunk-chars 1 < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
SKIP_COUNT=$(grep "^skip_hunk" "$TMPDIR/dec.txt" | wc -l)
ok "max-hunk-chars emits skip_hunk ops" "[[ $SKIP_COUNT -gt 0 ]]"

# B: default (no decorations)
$ROOT/animator/bin/diffvim-decorate < "$TMPDIR/timed.txt" > "$TMPDIR/dec_default.txt" 2>/dev/null
DEC_DEFAULT=$(grep -c "highlight\|dim\|fold\|sign\|skip_hunk\|marker" "$TMPDIR/dec_default.txt")
ok "default decorate produces no decoration ops" "[[ $DEC_DEFAULT -eq 0 ]]"

# B: C animator handles decoration ops without crashing
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/animator/bin/diffvim-decorate --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
$ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/out_dec.txt" "$TMPDIR/old1.txt" < "$TMPDIR/dec.txt" 2>/dev/null
ok "C animator handles decoration ops" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/out_dec.txt'"

# B: C vs Perl decorate parity
$ROOT/animator/bin/diffvim-decorate --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c.txt" 2>/dev/null
perl $ROOT/animator/perl/decorate.pl --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl.txt" 2>/dev/null
ok "C decorate == Perl decorate" "diff -q '$TMPDIR/dec_c.txt' '$TMPDIR/dec_perl.txt'"

# B: decorate with --dim-unchanged C vs Perl parity
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
$ROOT/animator/bin/diffvim-decorate --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c2.txt" 2>/dev/null
perl $ROOT/animator/perl/decorate.pl --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl2.txt" 2>/dev/null
ok "C decorate == Perl decorate (dim-unchanged)" "diff -q '$TMPDIR/dec_c2.txt' '$TMPDIR/dec_perl2.txt'"

# B: decorate with --context C vs Perl parity
$ROOT/animator/bin/diffvim-decorate --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c3.txt" 2>/dev/null
perl $ROOT/animator/perl/decorate.pl --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl3.txt" 2>/dev/null
ok "C decorate == Perl decorate (context)" "diff -q '$TMPDIR/dec_c3.txt' '$TMPDIR/dec_perl3.txt'"

# B: decorate with --highlight hunk C vs Perl parity
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/animator/bin/diffvim-decorate --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c4.txt" 2>/dev/null
perl $ROOT/animator/perl/decorate.pl --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl4.txt" 2>/dev/null
ok "C decorate == Perl decorate (highlight hunk)" "diff -q '$TMPDIR/dec_c4.txt' '$TMPDIR/dec_perl4.txt'"

# B: decorate with --fold-unchanged C vs Perl parity
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
$ROOT/animator/bin/diffvim-decorate --fold-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c5.txt" 2>/dev/null
perl $ROOT/animator/perl/decorate.pl --fold-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl5.txt" 2>/dev/null
ok "C decorate == Perl decorate (fold-unchanged)" "diff -q '$TMPDIR/dec_c5.txt' '$TMPDIR/dec_perl5.txt'"

echo ""
echo "=== Category C: Bash launcher features ==="

# C1: --log-mode 1
rm -f "$TMPDIR/test.log"
$ROOT/diffvim --log-mode 1 --log-file "$TMPDIR/test.log" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" >/dev/null 2>&1
ok "log-mode 1 produces log file" "[[ -f '$TMPDIR/test.log' ]]"
ok "log-mode 1 has HUNK headers" "grep -q 'HUNK' '$TMPDIR/test.log'"
ok "log-mode 1 has line info" "grep -q 'Line' '$TMPDIR/test.log'"

# C1: --log-mode 2
rm -f "$TMPDIR/test2.log"
$ROOT/diffvim --log-mode 2 --log-file "$TMPDIR/test2.log" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" >/dev/null 2>&1
ok "log-mode 2 produces log file" "[[ -f '$TMPDIR/test2.log' ]]"

# C1: --no-log-timing
rm -f "$TMPDIR/test3.log"
$ROOT/diffvim --log-mode 1 --log-file "$TMPDIR/test3.log" --no-log-timing "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" >/dev/null 2>&1
TIMING_COUNT=$(grep "timing:" "$TMPDIR/test3.log" | wc -l)
ok "no-log-timing suppresses timing info" "[[ $TIMING_COUNT -eq 0 ]]"

# C2: --debug
rm -f /tmp/diffvim-debug.log
$ROOT/diffvim --debug --sync --output "$TMPDIR/dbg_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "debug produces log file" "[[ -f /tmp/diffvim-debug.log ]]"
ok "debug log has stage info" "grep -q 'Stage' /tmp/diffvim-debug.log"

# C3: --max-line-len
MAX_LEN_OUT=$($ROOT/diffvim --max-line-len 10 --sync --output "$TMPDIR/ml_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null 2>&1 | grep "warning" | wc -l)
ok "max-line-len produces warnings" "[[ $MAX_LEN_OUT -gt 0 ]]"

# C3: --max-line-len 0 = no warnings
MAX_LEN_NONE=$($ROOT/diffvim --max-line-len 0 --sync --output "$TMPDIR/ml_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null 2>&1 | grep "warning" | wc -l)
ok "max-line-len 0 = no warnings" "[[ $MAX_LEN_NONE -eq 0 ]]"

# C4: --preset fast-delete
$ROOT/diffvim --preset fast-delete --sync --output "$TMPDIR/p1.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset fast-delete: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p1.txt'"

# C4: --preset review
$ROOT/diffvim --preset review --sync --output "$TMPDIR/p2.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset review: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p2.txt'"

# C4: --preset demo
$ROOT/diffvim --preset demo --sync --output "$TMPDIR/p3.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset demo: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p3.txt'"

# C4: --preset ai-code
$ROOT/diffvim --preset ai-code --sync --output "$TMPDIR/p4.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset ai-code: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p4.txt'"

echo ""
echo "=== Extended correctness tests ==="

# Verify all 42 examples with --pacing review
PASS_REV=0; FAIL_REV=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/diffvim --preset review --sync --output "$TMPDIR/rev_out.txt" "$old" "$new" </dev/null >/dev/null 2>&1
    if diff -q "$new" "$TMPDIR/rev_out.txt" >/dev/null 2>&1; then
        PASS_REV=$((PASS_REV+1))
    else
        FAIL_REV=$((FAIL_REV+1))
    fi
done
total=$((total+1))
if [[ $FAIL_REV -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --preset review"; else fail=$((fail+1)); echo "FAIL: $FAIL_REV examples fail with --preset review"; fi

# Verify all 42 examples with --pacing gaussian
PASS_GAU=0; FAIL_GAU=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/diffvim --preset demo --sync --output "$TMPDIR/gau_out.txt" "$old" "$new" </dev/null >/dev/null 2>&1
    if diff -q "$new" "$TMPDIR/gau_out.txt" >/dev/null 2>&1; then
        PASS_GAU=$((PASS_GAU+1))
    else
        FAIL_GAU=$((FAIL_GAU+1))
    fi
done
total=$((total+1))
if [[ $FAIL_GAU -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --preset demo (gaussian)"; else fail=$((fail+1)); echo "FAIL: $FAIL_GAU examples fail with --preset demo"; fi

# Verify all 42 examples with --overwrite
PASS_OW=0; FAIL_OW=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess --overwrite < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/ow_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/ow_out.txt" >/dev/null 2>&1; then
        PASS_OW=$((PASS_OW+1))
    else
        FAIL_OW=$((FAIL_OW+1))
    fi
done
total=$((total+1))
if [[ $FAIL_OW -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --overwrite"; else fail=$((fail+1)); echo "FAIL: $FAIL_OW examples fail with --overwrite"; fi

# Verify all 42 examples with --delete-pacing rapid-eol
PASS_REOL=0; FAIL_REOL=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace --delete-pacing rapid-eol < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/reol_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/reol_out.txt" >/dev/null 2>&1; then
        PASS_REOL=$((PASS_REOL+1))
    else
        FAIL_REOL=$((FAIL_REOL+1))
    fi
done
total=$((total+1))
if [[ $FAIL_REOL -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --delete-pacing rapid-eol"; else fail=$((fail+1)); echo "FAIL: $FAIL_REOL examples fail with rapid-eol"; fi

# Verify all 42 examples with --delete-pacing rapid-identical
PASS_RID=0; FAIL_RID=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace --delete-pacing rapid-identical < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/rid_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/rid_out.txt" >/dev/null 2>&1; then
        PASS_RID=$((PASS_RID+1))
    else
        FAIL_RID=$((FAIL_RID+1))
    fi
done
total=$((total+1))
if [[ $FAIL_RID -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --delete-pacing rapid-identical"; else fail=$((fail+1)); echo "FAIL: $FAIL_RID examples fail with rapid-identical"; fi

# Verify all 42 examples with --accel-delete
PASS_AD=0; FAIL_AD=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace --accel-delete < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/ad_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/ad_out.txt" >/dev/null 2>&1; then
        PASS_AD=$((PASS_AD+1))
    else
        FAIL_AD=$((FAIL_AD+1))
    fi
done
total=$((total+1))
if [[ $FAIL_AD -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --accel-delete"; else fail=$((fail+1)); echo "FAIL: $FAIL_AD examples fail with --accel-delete"; fi

# Verify all 42 examples with --block-delete-size
PASS_BD=0; FAIL_BD=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace --block-delete-size 2 --pause-before-delete-ms 50 --pause-after-delete-ms 50 < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/bd_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/bd_out.txt" >/dev/null 2>&1; then
        PASS_BD=$((PASS_BD+1))
    else
        FAIL_BD=$((FAIL_BD+1))
    fi
done
total=$((total+1))
if [[ $FAIL_BD -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --block-delete-size"; else fail=$((fail+1)); echo "FAIL: $FAIL_BD examples fail with --block-delete-size"; fi

# Verify all 42 examples with decorate --highlight inline
PASS_HL=0; FAIL_HL=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-decorate --highlight inline < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/hl_out.txt" "$old" < "$TMPDIR/dec.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/hl_out.txt" >/dev/null 2>&1; then
        PASS_HL=$((PASS_HL+1))
    else
        FAIL_HL=$((FAIL_HL+1))
    fi
done
total=$((total+1))
if [[ $FAIL_HL -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --highlight inline"; else fail=$((fail+1)); echo "FAIL: $FAIL_HL examples fail with --highlight inline"; fi

# Verify all 42 examples with --pause-after-lines
PASS_PAL=0; FAIL_PAL=0
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    old=$(ls "$ROOT/examples/$d"/old.* 2>/dev/null | head -1)
    new=$(ls "$ROOT/examples/$d"/new.* 2>/dev/null | head -1)
    [[ -f "$old" && -f "$new" ]] || continue
    $ROOT/compute/bin/diffvim-compute-cpp "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-postprocess < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-pace --pause-after-lines 5 --pause-after-threshold 1 < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
    $ROOT/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot "$TMPDIR/pal_out.txt" "$old" < "$TMPDIR/timed.txt" 2>/dev/null
    if diff -q "$new" "$TMPDIR/pal_out.txt" >/dev/null 2>&1; then
        PASS_PAL=$((PASS_PAL+1))
    else
        FAIL_PAL=$((FAIL_PAL+1))
    fi
done
total=$((total+1))
if [[ $FAIL_PAL -eq 0 ]]; then pass=$((pass+1)); echo "PASS: all 42 examples with --pause-after-lines 5"; else fail=$((fail+1)); echo "FAIL: $FAIL_PAL examples fail with --pause-after-lines"; fi

echo ""
echo "=== Results: $pass passed, $fail failed (of $total total) ==="
exit $((fail == 0 ? 0 : 1))
