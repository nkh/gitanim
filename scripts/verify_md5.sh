#!/usr/bin/env bash
# verify_md5.sh — Round-trip MD5 verification using xargs -P for parallelism.
#
# For each example pair, runs three tests in parallel batches:
#   - simple-loop test (test_vim_correctness.pl style: DeleteCharAtCursor/InsertCharAtCursor)
#   - ProcessCharOp test (test_vim_roundtrip.pl style: full engine)
#   - diffvim-pipeline (C animator)
#
# Outputs MD5 of saved buffer for each, compares with MD5 of new file.

set -uo pipefail

ROOT=/home/z/my-project/gitanim
ENG_SIMPLE=/tmp/dv_eng_simple.vim
ENG_RT=/tmp/dv_eng_rt.vim
OUTDIR=/tmp/dv_md5_verify
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

# -----------------------------------------------------------------------------
# Extract engines from diffvim (vimscript heredoc between two markers)
# -----------------------------------------------------------------------------
perl -e '
my ($out, $mode) = @ARGV;
open my $fh, "<", "/home/z/my-project/gitanim/diffvim" or die;
my $in = 0; my @L;
while (my $line = <$fh>) {
    if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in=1; next; }
    if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
    push @L, $line if $in;
}
close $fh;
my $c = join("", @L);
$c =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
if ($mode eq "simple") {
    $c .= <<'"'"'VIM'"'"';

function! s:RunTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file) | execute "w! " . g:diffvim.output_file | endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = "idle"
    let s:state.stopped = 0
    let s:state.paused = 0
    let s:cur_l = line(".")
    let s:cur_c = col(".")
    while s:state.hunk_idx < len(s:state.hunks)
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let s:state.op_idx = 0
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line("$")
            let s:cur_l = line("$")
            let s:cur_c = len(getline(line("$"))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line("$") | let l:prev = line("$") | endif
            let s:cur_l = l:prev
            let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line
            let s:cur_c = 1
        endif
        call s:PlaceCursor()
        let l:ops = l:hunk.char_ops
        for l:op in l:ops
            if l:op[0] ==# "keep"
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# "delete"
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# "insert"
                call s:InsertCharAtCursor(l:op[1])
            endif
        endfor
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
    endwhile
    if !empty(g:diffvim.output_file)
        let l:bytes = readfile(g:diffvim_new_file, "b")
        if !empty(l:bytes)
            let l:last = l:bytes[-1]
            if l:last !~# "\\n$" && l:last !~# "\\r$"
                setlocal noeol
            endif
        endif
        execute "w! " . g:diffvim.output_file
    endif
endfunction
call s:RunTest()
qa!
VIM
}
elsif ($mode eq "rt") {
    $c =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;
    $c .= <<'"'"'VIM'"'"';

function! s:RunRoundTrip() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file) | execute "w! " . g:diffvim.output_file | endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = "typing"
    let s:state.stopped = 0
    let s:state.paused = 0
    let s:state.runtime_speed = 1.0
    let s:state.op_idx = 0
    let s:state.awd_phase = 0
    let s:state.awd_delay = 0
    let s:state.awd_word_count = 0
    let s:state.accel_delete_count = 0
    let s:state.accel_delete_total = 0
    let s:state.accel_delete_delay = 0
    let s:state.word_accel_total = 0
    let s:state.word_accel_idx = 0
    let s:state.word_accel_base_delay = 0
    let s:state.adaptive_delay = 0
    let s:state.adaptive_lines_done = 0
    let s:state.pause_after_count = 0
    let s:state.inline_highlights = []
    let s:state.inline_run_type = ""
    let s:state.inline_run_start_line = 0
    let s:state.inline_run_start_col = 0
    let s:state.inline_run_len = 0
    let s:state.inline_run_match_id = -1
    let s:state.inline_run_timer = -1
    let s:state.smart_highlight_id = -1
    let s:cur_l = 1
    let s:cur_c = 1
    while s:state.hunk_idx < len(s:state.hunks) && !s:state.stopped
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let s:state.op_idx = 0
        let s:state.awd_phase = 0
        let s:state.awd_delay = 0
        let s:state.awd_word_count = 0
        let s:state.accel_delete_count = 0
        let s:state.accel_delete_total = 0
        let s:state.word_accel_total = 0
        let s:state.word_accel_idx = 0
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line("$")
            let s:cur_l = line("$")
            let s:cur_c = len(getline(line("$"))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line("$") | let l:prev = line("$") | endif
            let s:cur_l = l:prev
            let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line
            let s:cur_c = 1
        endif
        call s:PlaceCursor()
        let l:safety = 0
        let l:prev_hunk_idx = s:state.hunk_idx
        while !s:state.stopped && l:safety < 50000
            let l:safety += 1
            if s:state.hunk_idx != l:prev_hunk_idx
                let l:prev_hunk_idx = s:state.hunk_idx
                if s:state.hunk_idx >= len(s:state.hunks) | break | endif
                let l:hunk = s:state.hunks[s:state.hunk_idx]
                let s:state.cur_hunk = l:hunk
                let s:state.op_idx = 0
                let s:state.awd_phase = 0
                let s:state.awd_delay = 0
                let s:state.awd_word_count = 0
                let s:state.accel_delete_count = 0
                let s:state.accel_delete_total = 0
                let s:state.word_accel_total = 0
                let s:state.word_accel_idx = 0
                let l:target_line = l:hunk.target_line_old + s:state.line_offset
                if l:hunk.is_end_insert && l:target_line > line("$")
                    let s:cur_l = line("$")
                    let s:cur_c = len(getline(line("$"))) + 1
                elseif l:hunk.is_end_delete
                    let l:prev = l:target_line - 1
                    if l:prev < 1 | let l:prev = 1 | endif
                    if l:prev > line("$") | let l:prev = line("$") | endif
                    let s:cur_l = l:prev
                    let s:cur_c = len(getline(l:prev)) + 1
                else
                    let s:cur_l = l:target_line
                    let s:cur_c = 1
                endif
                call s:PlaceCursor()
            endif
            if s:state.hunk_idx >= len(s:state.hunks) | break | endif
            let l:hunk = s:state.hunks[s:state.hunk_idx]
            if s:state.op_idx >= len(l:hunk.char_ops)
                let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
                let s:state.hunk_idx += 1
                continue
            endif
            call s:PlaceCursor()
            call s:ProcessCharOp()
        endwhile
    endwhile
    if !empty(g:diffvim.output_file)
        let l:new_size = getfsize(g:diffvim_new_file)
        if l:new_size == 0
            1,$delete _
            call setline(1, "")
            setlocal noeol
            setlocal nomodified
            call writefile([], g:diffvim.output_file, "b")
            return
        else
            let l:new_bytes = readfile(g:diffvim_new_file, "b")
            if !empty(l:new_bytes)
                let l:last = l:new_bytes[-1]
                if l:last !~# "\\n$" && l:last !~# "\\r$"
                    setlocal noeol
                endif
            endif
        endif
        execute "w! " . g:diffvim.output_file
    endif
endfunction
call s:RunRoundTrip()
qa!
VIM
}
open my $ofh, ">", $out or die;
print $ofh $c;
close $ofh;
' "$ENG_SIMPLE" simple

perl -e '
my ($out, $mode) = @ARGV;
open my $fh, "<", "/home/z/my-project/gitanim/diffvim" or die;
my $in = 0; my @L;
while (my $line = <$fh>) {
    if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in=1; next; }
    if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
    push @L, $line if $in;
}
close $fh;
my $c = join("", @L);
$c =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
$c =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;
$c .= <<'"'"'VIM'"'"';

function! s:RunRoundTrip() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file) | execute "w! " . g:diffvim.output_file | endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = "typing"
    let s:state.stopped = 0
    let s:state.paused = 0
    let s:state.runtime_speed = 1.0
    let s:state.op_idx = 0
    let s:state.awd_phase = 0
    let s:state.awd_delay = 0
    let s:state.awd_word_count = 0
    let s:state.accel_delete_count = 0
    let s:state.accel_delete_total = 0
    let s:state.accel_delete_delay = 0
    let s:state.word_accel_total = 0
    let s:state.word_accel_idx = 0
    let s:state.word_accel_base_delay = 0
    let s:state.adaptive_delay = 0
    let s:state.adaptive_lines_done = 0
    let s:state.pause_after_count = 0
    let s:state.inline_highlights = []
    let s:state.inline_run_type = ""
    let s:state.inline_run_start_line = 0
    let s:state.inline_run_start_col = 0
    let s:state.inline_run_len = 0
    let s:state.inline_run_match_id = -1
    let s:state.inline_run_timer = -1
    let s:state.smart_highlight_id = -1
    let s:cur_l = 1
    let s:cur_c = 1
    while s:state.hunk_idx < len(s:state.hunks) && !s:state.stopped
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let s:state.op_idx = 0
        let s:state.awd_phase = 0
        let s:state.awd_delay = 0
        let s:state.awd_word_count = 0
        let s:state.accel_delete_count = 0
        let s:state.accel_delete_total = 0
        let s:state.word_accel_total = 0
        let s:state.word_accel_idx = 0
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line("$")
            let s:cur_l = line("$")
            let s:cur_c = len(getline(line("$"))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line("$") | let l:prev = line("$") | endif
            let s:cur_l = l:prev
            let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line
            let s:cur_c = 1
        endif
        call s:PlaceCursor()
        let l:safety = 0
        let l:prev_hunk_idx = s:state.hunk_idx
        while !s:state.stopped && l:safety < 50000
            let l:safety += 1
            if s:state.hunk_idx != l:prev_hunk_idx
                let l:prev_hunk_idx = s:state.hunk_idx
                if s:state.hunk_idx >= len(s:state.hunks) | break | endif
                let l:hunk = s:state.hunks[s:state.hunk_idx]
                let s:state.cur_hunk = l:hunk
                let s:state.op_idx = 0
                let s:state.awd_phase = 0
                let s:state.awd_delay = 0
                let s:state.awd_word_count = 0
                let s:state.accel_delete_count = 0
                let s:state.accel_delete_total = 0
                let s:state.word_accel_total = 0
                let s:state.word_accel_idx = 0
                let l:target_line = l:hunk.target_line_old + s:state.line_offset
                if l:hunk.is_end_insert && l:target_line > line("$")
                    let s:cur_l = line("$")
                    let s:cur_c = len(getline(line("$"))) + 1
                elseif l:hunk.is_end_delete
                    let l:prev = l:target_line - 1
                    if l:prev < 1 | let l:prev = 1 | endif
                    if l:prev > line("$") | let l:prev = line("$") | endif
                    let s:cur_l = l:prev
                    let s:cur_c = len(getline(l:prev)) + 1
                else
                    let s:cur_l = l:target_line
                    let s:cur_c = 1
                endif
                call s:PlaceCursor()
            endif
            if s:state.hunk_idx >= len(s:state.hunks) | break | endif
            let l:hunk = s:state.hunks[s:state.hunk_idx]
            if s:state.op_idx >= len(l:hunk.char_ops)
                let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
                let s:state.hunk_idx += 1
                continue
            endif
            call s:PlaceCursor()
            call s:ProcessCharOp()
        endwhile
    endwhile
    if !empty(g:diffvim.output_file)
        let l:new_size = getfsize(g:diffvim_new_file)
        if l:new_size == 0
            1,$delete _
            call setline(1, "")
            setlocal noeol
            setlocal nomodified
            call writefile([], g:diffvim.output_file, "b")
            return
        else
            let l:new_bytes = readfile(g:diffvim_new_file, "b")
            if !empty(l:new_bytes)
                let l:last = l:new_bytes[-1]
                if l:last !~# "\\n$" && l:last !~# "\\r$"
                    setlocal noeol
                endif
            endif
        endif
        execute "w! " . g:diffvim.output_file
    endif
endfunction
call s:RunRoundTrip()
qa!
VIM
open my $ofh, ">", $out or die;
print $ofh $c;
close $ofh;
' "$ENG_RT" rt

# -----------------------------------------------------------------------------
# Worker function: runs one test, writes MD5 to a file
# -----------------------------------------------------------------------------
run_simple() {
    local d="$1"; local old="$2"; local new="$3"
    local out="$OUTDIR/dv_simple_${d}.md5"
    local buf="/tmp/dv_buf_${d}_simple.txt"
    rm -f "$buf"
    timeout -k 5 30 vim -e -s -n -Nu NONE -U NONE \
        -c "let g:diffvim_new_file = '$new'" \
        -c "let g:diffvim = {'output_file': '$buf'}" \
        -c "source $ENG_SIMPLE" \
        "$old" </dev/null >/dev/null 2>&1
    if [[ -f "$buf" ]]; then
        md5sum "$buf" | awk '{print $1}' > "$out"
    else
        echo "MISSING" > "$out"
    fi
    rm -f "$buf"
}

run_rt() {
    local d="$1"; local old="$2"; local new="$3"
    local out="$OUTDIR/dv_rt_${d}.md5"
    local buf="/tmp/dv_buf_${d}_rt.txt"
    rm -f "$buf"
    DIFFVIM_OUTPUT="$buf" \
    DIFFVIM_TICK_MS=16 DIFFVIM_TYPE_DELAY_MS=50 DIFFVIM_DELETE_DELAY_MS=40 \
    DIFFVIM_OP_ORDER=optimize DIFFVIM_DELETE_PACING=word \
    DIFFVIM_INSERT_PACING=char DIFFVIM_PACING=uniform DIFFVIM_HIGHLIGHT=none \
    timeout -k 5 30 vim -u NONE -N -n -es \
        -c "let g:diffvim_new_file = '$new'" \
        -c "source $ENG_RT" \
        "$old" </dev/null >/dev/null 2>&1
    if [[ -f "$buf" ]]; then
        md5sum "$buf" | awk '{print $1}' > "$out"
    else
        echo "MISSING" > "$out"
    fi
    rm -f "$buf"
}

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

export -f run_simple run_rt run_pipe
export ROOT ENG_SIMPLE ENG_RT OUTDIR

# -----------------------------------------------------------------------------
# Build task list and run in parallel via xargs
# -----------------------------------------------------------------------------
> /tmp/dv_tasks.txt
for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    news=( "$ROOT/examples/$d"/new.* )
    olds=( "$ROOT/examples/$d"/old.* )
    [[ ${#news[@]} -eq 0 || ${#olds[@]} -eq 0 ]] && continue
    new="${news[0]}"; old="${olds[0]}"
    echo "simple|$d|$old|$new" >> /tmp/dv_tasks.txt
    echo "rt|$d|$old|$new"    >> /tmp/dv_tasks.txt
    echo "pipe|$d|$old|$new"  >> /tmp/dv_tasks.txt
done

echo "Total tasks: $(wc -l < /tmp/dv_tasks.txt)"
echo "Running in parallel (8 concurrent)..."

# Each line is kind|dir|old|new
# Use awk to convert to a function call, then xargs -P 8 to run them.
cat /tmp/dv_tasks.txt | \
    awk -F'|' '{ printf "%s \"%s\" \"%s\" \"%s\"\n", $1, $2, $3, $4 }' | \
    xargs -P 8 -I {} bash -c 'IFS=" " read -r kind d old new <<< "{}";
case "$kind" in
    simple) run_simple "$d" "$old" "$new" ;;
    rt)     run_rt     "$d" "$old" "$new" ;;
    pipe)   run_pipe   "$d" "$old" "$new" ;;
esac'

echo ""
echo "All tasks complete. Collecting results..."

# -----------------------------------------------------------------------------
# Print table
# -----------------------------------------------------------------------------
printf "\n"
printf "Round-trip MD5 verification — all 42 example pairs\n"
printf '%s\n' "$(printf '%.0s=' {1..150})"
printf "%-22s | %-32s | %-32s | %-32s | %-32s\n" "example" "new-file MD5" \
    "diffvim (simple loop)" "diffvim (ProcessCharOp)" "pipeline (C animator)"
printf '%s\n' "$(printf '%.0s-' {1..150})"

s_ok=0; s_bad=0; r_ok=0; r_bad=0; p_ok=0; p_bad=0

for d in $(ls "$ROOT/examples" | grep '^[0-9]*_' | sort); do
    news=( "$ROOT/examples/$d"/new.* )
    [[ ${#news[@]} -eq 0 ]] && continue
    new="${news[0]}"

    new_md5=$(md5sum "$new" | awk '{print $1}')
    s_md5=$(cat "$OUTDIR/dv_simple_${d}.md5" 2>/dev/null || echo "MISSING")
    r_md5=$(cat "$OUTDIR/dv_rt_${d}.md5"     2>/dev/null || echo "MISSING")
    p_md5=$(cat "$OUTDIR/dv_pipe_${d}.md5"   2>/dev/null || echo "MISSING")

    [[ "$s_md5" == "$new_md5" ]] && s_ok=$((s_ok+1)) || s_bad=$((s_bad+1))
    [[ "$r_md5" == "$new_md5" ]] && r_ok=$((r_ok+1)) || r_bad=$((r_bad+1))
    [[ "$p_md5" == "$new_md5" ]] && p_ok=$((p_ok+1)) || p_bad=$((p_bad+1))

    printf "%-22s | %-32s | %-32s | %-32s | %-32s\n" "$d" "$new_md5" "$s_md5" "$r_md5" "$p_md5"
done

printf '%s\n' "$(printf '%.0s=' {1..150})"
printf "\nSummary:\n"
printf "  diffvim (simple loop / primitives only):    %2d OK / %2d bad\n" $s_ok $s_bad
printf "  diffvim (ProcessCharOp / full engine):      %2d OK / %2d bad\n" $r_ok $r_bad
printf "  diffvim-pipeline (C animator):              %2d OK / %2d bad\n" $p_ok $p_bad
echo ""
