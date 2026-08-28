#!/usr/bin/env bash
# test_category_abc.sh — Comprehensive tests for all Category A, B, C features.

set -uo pipefail
ROOT=/home/z/my-project/gitanim
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0; fail=0; total=0
ok() { total=$((total+1)); if eval "$2"; then pass=$((pass+1)); echo "PASS: $1"; else fail=$((fail+1)); echo "FAIL: $1"; fi; }

# === Test files ===
printf 'hello world\nabc\ndef\n' > "$TMPDIR/old1.txt"
printf 'hello there\nabc\nghi\n' > "$TMPDIR/new1.txt"

printf 'line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\n' > "$TMPDIR/old2.txt"
printf 'CHANGED1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nCHANGED10\n' > "$TMPDIR/new2.txt"

# File with whole-line deletions (needed for \n ops)
printf 'line1\nline2\nline3\nline4\nline5\n' > "$TMPDIR/old3.txt"
printf 'line1\nline5\n' > "$TMPDIR/new3.txt"

printf 'aaaaaaaaaa\n' > "$TMPDIR/old4.txt"
printf 'bb\n' > "$TMPDIR/new4.txt"

run_pipeline() {
    local old="$1" new="$2" extra="${3:-}"
    "$ROOT/bin/ad_compute" "$old" "$new" "$TMPDIR/raw.txt" 2>/dev/null
    $ROOT/bin/ad_postprocess $extra < "$TMPDIR/raw.txt" > "$TMPDIR/post.txt" 2>/dev/null
    $ROOT/bin/ad_layer_pace < "$TMPDIR/post.txt" > "$TMPDIR/timed.txt" 2>/dev/null
}

echo "=== Category A: Pipeline features ==="

# A3: --pacing review (max delay should be >= uniform)
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
DELAY_UNI=$($ROOT/bin/ad_layer_pace --pacing uniform < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | cut -f2 | sort -n | tail -1)
DELAY_REV=$($ROOT/bin/ad_layer_pace --pacing review < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | cut -f2 | sort -n | tail -1)
ok "pacing review doubles delays" "[[ -n '$DELAY_UNI' ]] && [[ -n '$DELAY_REV' ]] && [[ $DELAY_REV -ge $DELAY_UNI ]]"

DELAY_GAUSS=$($ROOT/bin/ad_layer_pace --pacing gaussian < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "^delay      1       " | head -1 | cut -f2)
ok "pacing gaussian produces delays" "[[ -n '$DELAY_GAUSS' ]]"

DELAY_ADAPT=$($ROOT/bin/ad_layer_pace --pacing adaptive < "$TMPDIR/post.txt" 2>/dev/null | grep "^delay" | grep -v "^delay      1       " | head -1 | cut -f2)
ok "pacing adaptive produces delays" "[[ -n '$DELAY_ADAPT' ]]"

# A5: --pause-after-lines (needs file with \n deletes)
run_pipeline "$TMPDIR/old3.txt" "$TMPDIR/new3.txt"
PAUSE_COUNT=$($ROOT/bin/ad_layer_pace --pause-after-lines 1 --pause-after-threshold 1 < "$TMPDIR/post.txt" 2>/dev/null | grep "pause_after" | wc -l)
ok "pause-after-lines inserts pauses" "[[ $PAUSE_COUNT -gt 0 ]]"

PAUSE_NONE=$($ROOT/bin/ad_layer_pace --pause-after-lines 0 < "$TMPDIR/post.txt" 2>/dev/null | grep "pause_after" | wc -l)
ok "pause-after-lines 0 = no pauses" "[[ $PAUSE_NONE -eq 0 ]]"

# A6: --accel-delete (needs file with \n deletes)
ACCEL_COUNT=$($ROOT/bin/ad_layer_pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | wc -l)
ok "accel-delete emits accel_delete delays" "[[ $ACCEL_COUNT -gt 0 ]]"

# A6: verify first delay >= last (deceleration)
ACCEL_FIRST=$($ROOT/bin/ad_layer_pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | head -1 | cut -f2)
ACCEL_LAST=$($ROOT/bin/ad_layer_pace --accel-delete < "$TMPDIR/post.txt" 2>/dev/null | grep "accel_delete" | tail -1 | cut -f2)
ok "accel-delete first delay >= last delay" "[[ $ACCEL_FIRST -ge $ACCEL_LAST ]]"

# A7: --delete-pacing rapid-eol
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
RAPID_EOL=$($ROOT/bin/ad_layer_pace --delete-pacing rapid-eol < "$TMPDIR/post.txt" 2>/dev/null | grep "rapid_eol" | wc -l)
ok "rapid-eol emits rapid_eol delays" "[[ $RAPID_EOL -gt 0 ]]"

# A7: --delete-pacing rapid-identical
run_pipeline "$TMPDIR/old4.txt" "$TMPDIR/new4.txt"
RAPID_ID=$($ROOT/bin/ad_layer_pace --delete-pacing rapid-identical < "$TMPDIR/post.txt" 2>/dev/null | grep "rapid_identical" | wc -l)
ok "rapid-identical emits rapid_identical delays" "[[ $RAPID_ID -gt 0 ]]"

# A8: --block-delete-size (needs char delete-pacing + enough deletes)
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
BLOCK_START=$($ROOT/bin/ad_layer_pace --delete-pacing char --block-delete-size 1 --pause-before-delete-ms 100 < "$TMPDIR/post.txt" 2>/dev/null | grep "block_start" | wc -l)
ok "block-delete emits block_start pauses" "[[ $BLOCK_START -gt 0 ]]"

BLOCK_END=$($ROOT/bin/ad_layer_pace --delete-pacing char --block-delete-size 1 --pause-after-delete-ms 100 < "$TMPDIR/post.txt" 2>/dev/null | grep "block_end" | wc -l)
ok "block-delete emits block_end pauses" "[[ $BLOCK_END -gt 0 ]]"

# A9: --overwrite — test via pipeline directly (launcher passes it to postprocess)
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" "--overwrite"
OW_COUNT=$(grep "overwrite_insert" "$TMPDIR/post.txt" | wc -l)
ok "overwrite produces overwrite_insert ops" "[[ $OW_COUNT -gt 0 ]]"

# A9: overwrite output correctness
$ROOT/bin/ad_layer_pace < "$TMPDIR/post.txt" > "$TMPDIR/timed_ow.txt" 2>/dev/null
$ROOT/bin/ad --no-display --speed 1000 --snapshot "$TMPDIR/out_ow.txt" "$TMPDIR/old1.txt" < "$TMPDIR/timed_ow.txt" 2>/dev/null
ok "overwrite output matches new file" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/out_ow.txt'"

# A10: --op-order variants
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
LT_COUNT=$($ROOT/bin/ad_postprocess --op-order left-to-right < "$TMPDIR/raw.txt" 2>/dev/null | wc -l)
ok "op-order left-to-right produces output" "[[ $LT_COUNT -gt 0 ]]"

EF_COUNT=$($ROOT/bin/ad_postprocess --op-order end-first < "$TMPDIR/raw.txt" 2>/dev/null | wc -l)
ok "op-order end-first produces output" "[[ $EF_COUNT -gt 0 ]]"

EFS_COUNT=$($ROOT/bin/ad_postprocess --op-order end-first-smart < "$TMPDIR/raw.txt" 2>/dev/null | wc -l)
ok "op-order end-first-smart produces output" "[[ $EFS_COUNT -gt 0 ]]"

# A parity: C vs Perl pace
$ROOT/bin/ad_layer_pace --pacing review < "$TMPDIR/post.txt" > "$TMPDIR/pace_c.txt" 2>/dev/null
perl $ROOT/layers/perl/ad_layer_pace.pl --pacing review < "$TMPDIR/post.txt" > "$TMPDIR/pace_perl.txt" 2>/dev/null
ok "C pace == Perl pace (review mode)" "diff -q '$TMPDIR/pace_c.txt' '$TMPDIR/pace_perl.txt'"

echo ""
echo "=== Category B: Decorate features ==="

# B: --highlight inline
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/bin/ad_layer_highlight --highlight inline < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_INLINE=$(grep "^highlight" "$TMPDIR/dec.txt" | grep "insert\|delete" | wc -l)
ok "highlight inline emits per-char highlights" "[[ $HL_INLINE -gt 0 ]]"

# B: --highlight word
$ROOT/bin/ad_layer_highlight --highlight word < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_WORD=$(grep "^highlight" "$TMPDIR/dec.txt" | wc -l)
ok "highlight word emits highlights" "[[ $HL_WORD -gt 0 ]]"

# B: --highlight hunk
$ROOT/bin/ad_layer_highlight --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
HL_HUNK=$(grep "^highlight.*hunk" "$TMPDIR/dec.txt" | wc -l)
ok "highlight hunk emits hunk highlights" "[[ $HL_HUNK -gt 0 ]]"

# B: --dim-unchanged (needs multi-hunk file)
run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
$ROOT/bin/ad_layer_highlight --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
DIM_COUNT=$(grep -P "^dim\t" "$TMPDIR/dec.txt" | wc -l)
ok "dim-unchanged emits dim ops" "[[ $DIM_COUNT -gt 0 ]]"

# B: --context N
$ROOT/bin/ad_layer_highlight --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
FOLD_CONTEXT=$(grep -P "^fold\t" "$TMPDIR/dec.txt" | wc -l)
ok "context N emits fold ops" "[[ $FOLD_CONTEXT -gt 0 ]]"

# B: --fold-unchanged
$ROOT/bin/ad_layer_highlight --fold-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
FOLD_COUNT=$(grep -P "^fold\t" "$TMPDIR/dec.txt" | wc -l)
ok "fold-unchanged emits fold ops" "[[ $FOLD_COUNT -gt 0 ]]"

# B: --sign-column
run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/bin/ad_layer_highlight --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
SIGN_COUNT=$(grep -P "^sign\t" "$TMPDIR/dec.txt" | wc -l)
ok "sign-column emits sign ops" "[[ $SIGN_COUNT -gt 0 ]]"

# B: --max-hunk-chars
$ROOT/bin/ad_layer_highlight --max-hunk-chars 1 < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
SKIP_COUNT=$(grep "^skip_hunk" "$TMPDIR/dec.txt" | wc -l)
ok "max-hunk-chars emits skip_hunk ops" "[[ $SKIP_COUNT -gt 0 ]]"

# B: default (no decorations) — only check ops, not header lines
$ROOT/bin/ad_layer_highlight < "$TMPDIR/timed.txt" > "$TMPDIR/dec_default.txt" 2>/dev/null
DEC_DEFAULT=$(grep -E "^(highlight|dim  |fold   |sign   |skip_hunk|marker       )" "$TMPDIR/dec_default.txt" | wc -l)
ok "default decorate produces no decoration ops" "[[ $DEC_DEFAULT -eq 0 ]]"

# B: C animator handles decoration ops
$ROOT/bin/ad_layer_highlight --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec.txt" 2>/dev/null
$ROOT/bin/ad --no-display --speed 1000 --snapshot "$TMPDIR/out_dec.txt" "$TMPDIR/old1.txt" < "$TMPDIR/dec.txt" 2>/dev/null
ok "C animator handles decoration ops" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/out_dec.txt'"

# B: C vs Perl decorate parity (4 tests)
$ROOT/bin/ad_layer_highlight --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c.txt" 2>/dev/null
perl $ROOT/layers/perl/ad_layer_highlight.pl --highlight inline --sign-column < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl.txt" 2>/dev/null
ok "C decorate == Perl decorate (highlight+sign)" "diff -q '$TMPDIR/dec_c.txt' '$TMPDIR/dec_perl.txt'"

run_pipeline "$TMPDIR/old2.txt" "$TMPDIR/new2.txt"
$ROOT/bin/ad_layer_highlight --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c2.txt" 2>/dev/null
perl $ROOT/layers/perl/ad_layer_highlight.pl --dim-unchanged < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl2.txt" 2>/dev/null
ok "C decorate == Perl decorate (dim-unchanged)" "diff -q '$TMPDIR/dec_c2.txt' '$TMPDIR/dec_perl2.txt'"

$ROOT/bin/ad_layer_highlight --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c3.txt" 2>/dev/null
perl $ROOT/layers/perl/ad_layer_highlight.pl --context 2 < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl3.txt" 2>/dev/null
ok "C decorate == Perl decorate (context)" "diff -q '$TMPDIR/dec_c3.txt' '$TMPDIR/dec_perl3.txt'"

run_pipeline "$TMPDIR/old1.txt" "$TMPDIR/new1.txt"
$ROOT/bin/ad_layer_highlight --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec_c4.txt" 2>/dev/null
perl $ROOT/layers/perl/ad_layer_highlight.pl --highlight hunk < "$TMPDIR/timed.txt" > "$TMPDIR/dec_perl4.txt" 2>/dev/null
ok "C decorate == Perl decorate (highlight hunk)" "diff -q '$TMPDIR/dec_c4.txt' '$TMPDIR/dec_perl4.txt'"

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

# C1: --no-log-timing — fix: check the "# timing:" header
rm -f "$TMPDIR/test3.log"
$ROOT/diffvim --log-mode 1 --log-file "$TMPDIR/test3.log" --no-log-timing "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" >/dev/null 2>&1
TIMING_COUNT=$(grep "^# timing:" "$TMPDIR/test3.log" | wc -l)
ok "no-log-timing suppresses timing header" "[[ $TIMING_COUNT -eq 0 ]]"

# C2: --debug
rm -f /tmp/diffvim-debug.log
$ROOT/diffvim --debug --sync --output "$TMPDIR/dbg_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "debug produces log file" "[[ -f /tmp/diffvim-debug.log ]]"
ok "debug log has stage info" "grep -q 'Stage' /tmp/diffvim-debug.log"

# C3: --max-line-len
MAX_LEN_OUT=$($ROOT/diffvim --max-line-len 10 --sync --output "$TMPDIR/ml_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null 2>&1 | grep "warning" | wc -l)
ok "max-line-len produces warnings" "[[ $MAX_LEN_OUT -gt 0 ]]"

MAX_LEN_NONE=$($ROOT/diffvim --max-line-len 0 --sync --output "$TMPDIR/ml_out.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null 2>&1 | grep "warning" | wc -l)
ok "max-line-len 0 = no warnings" "[[ $MAX_LEN_NONE -eq 0 ]]"

# C4: presets
$ROOT/diffvim --preset fast-delete --sync --output "$TMPDIR/p1.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset fast-delete: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p1.txt'"

$ROOT/diffvim --preset review --sync --output "$TMPDIR/p2.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset review: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p2.txt'"

$ROOT/diffvim --preset demo --sync --output "$TMPDIR/p3.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset demo: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p3.txt'"

$ROOT/diffvim --preset ai-code --sync --output "$TMPDIR/p4.txt" "$TMPDIR/old1.txt" "$TMPDIR/new1.txt" </dev/null >/dev/null 2>&1
ok "preset ai-code: correct output" "diff -q '$TMPDIR/new1.txt' '$TMPDIR/p4.txt'"

echo ""
echo "=== Results: $pass passed, $fail failed (of $total total) ==="
exit $((fail == 0 ? 0 : 1))
