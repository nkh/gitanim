#!/usr/bin/env perl
# test_awd_correctness.pl - Test that ProcessAdaptiveWordDelete produces
# correct output (all deleted chars are actually removed from the buffer).
#
# This test creates specific file pairs that trigger AWD and verifies
# the animation result matches the expected new file.
#
# Bug being tested: Phase 0 of ProcessAdaptiveWordDelete used to skip
# whitespace delete ops by calling AdvanceForKeepChar (which just moves
# the cursor) instead of DeleteCharAtCursor. This left whitespace in
# the buffer, producing incorrect output.

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

my $engine_test = '/tmp/dv_awd_test.vim';

sub extract_engine {
    open my $fh, '<', 'diffvim' or die "Cannot open diffvim: $!";
    my $in_engine = 0;
    my @lines;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) {
            $in_engine = 1;
            next;
        }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) {
            last;
        }
        push @lines, $line if $in_engine;
    }
    close $fh;

    my $content = join('', @lines);
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    # Override ScheduleNext to be a no-op
    $content =~ s/function! s:ScheduleNext\([^)]*\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in synchronous test mode\nendfunction/ms;

    # Add synchronous test runner that calls ProcessCharOp in a loop.
    # ProcessCharOp takes NO arguments — it reads from s:state.cur_hunk.
    $content .= <<'VIM';

function! s:RunAWDTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
        endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'typing'
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
    let s:state.inline_run_type = ''
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
        if l:hunk.is_end_insert && l:target_line > line('$')
            let s:cur_l = line('$')
            let s:cur_c = len(getline(line('$'))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line('$') | let l:prev = line('$') | endif
            let s:cur_l = l:prev
            let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line
            let s:cur_c = 1
        endif
        call s:PlaceCursor()

        " Process all ops by calling ProcessCharOp in a loop
        let l:safety = 0
        while s:state.hunk_idx == len(s:state.hunks) ? 0 :
              \ s:state.op_idx < len(s:state.hunks[s:state.hunk_idx].char_ops)
              \ && !s:state.stopped && l:safety < 50000
            let l:safety += 1
            " Check if hunk changed (ProcessCharOp advanced to next hunk)
            if s:state.hunk_idx >= len(s:state.hunks)
                break
            endif
            let l:cur_hunk = s:state.hunks[s:state.hunk_idx]
            if s:state.op_idx >= len(l:cur_hunk.char_ops)
                " ProcessCharOp will detect this and advance hunk_idx
                call s:ProcessCharOp()
                " If hunk_idx didn't change, we're stuck — break
                if s:state.hunk_idx >= len(s:state.hunks)
                    break
                endif
                let l:cur_hunk = s:state.hunks[s:state.hunk_idx]
                if s:state.op_idx >= len(l:cur_hunk.char_ops)
                    " Still stuck — manually advance
                    let s:state.hunk_idx += 1
                    break
                endif
            else
                call s:ProcessCharOp()
            endif
        endwhile

        if s:state.hunk_idx < len(s:state.hunks)
            let s:state.line_offset += (s:state.hunks[s:state.hunk_idx].inserted_count - s:state.hunks[s:state.hunk_idx].deleted_count)
        endif
        let s:state.hunk_idx += 1
    endwhile

    if !empty(g:diffvim.output_file)
        let l:new_no_eol = 0
        let l:bytes = readfile(g:diffvim_new_file, 'b')
        if !empty(l:bytes)
            let l:last = l:bytes[-1]
            if l:last !~# "\n$" && l:last !~# "\r$"
                setlocal noeol
            endif
        endif
        execute 'w! ' . g:diffvim.output_file
    endif
endfunction

call s:RunAWDTest()
qa!
VIM

    return $content;
}

my $engine = extract_engine();
open my $out, '>', $engine_test or die "Cannot write $engine_test: $!";
print $out $engine;
close $out;

# Test with AWD enabled (the default --delete-pacing word setting)
my @test_cases = (
    ['01_small_python', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['02_large_python', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['03_json_config', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['04_shell_script', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['05_go_code', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['06_typescript', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['08_rust_code', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['09_c_code', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['13_java', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['16_ruby', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    ['26_markdown', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1'],
    # Also test without AWD (char-by-char) to verify baseline
    ['01_small_python', 'AD_ADAPTIVE_WORD_DELETE=0 AD_RAPID_EOL_DELETE=0'],
    ['02_large_python', 'AD_ADAPTIVE_WORD_DELETE=0 AD_RAPID_EOL_DELETE=0'],
);

for my $tc (@test_cases) {
    my ($dir, $env) = @$tc;
    my $old_file = `ls tests/tests/examples/$dir/old.* 2>/dev/null | head -1`; chomp $old_file;
    my $new_file = `ls tests/tests/examples/$dir/new.* 2>/dev/null | head -1`; chomp $new_file;
    next unless $old_file && $new_file && -f $old_file && -f $new_file;

    my $output_file = "/tmp/dv_awd_out.txt";
    unlink $output_file;

    my $cmd = "env $env vim -u NONE -N -n -es " .
              "-c 'let g:diffvim_new_file = \"$new_file\"' " .
              "-c 'let g:diffvim.output_file = \"$output_file\"' " .
              "-c 'source $engine_test' " .
              "'$old_file' 2>/dev/null";
    system($cmd);

    if (-f $output_file) {
        my $expected = `cat "$new_file"`;
        my $actual = `cat "$output_file"`;
        if ($expected eq $actual) {
            print "PASS: $dir [$env]\n";
            $pass++;
        } else {
            print "FAIL: $dir [$env]\n";
            # Show first difference
            my @exp_lines = split /\n/, $expected;
            my @act_lines = split /\n/, $actual;
            for my $i (0 .. $#exp_lines) {
                if ($i > $#act_lines) {
                    print "  Line " . ($i+1) . ": expected '$exp_lines[$i]' but got nothing\n";
                    last;
                }
                if ($exp_lines[$i] ne $act_lines[$i]) {
                    print "  Line " . ($i+1) . ":\n";
                    print "    Expected: '$exp_lines[$i]'\n";
                    print "    Actual:   '$act_lines[$i]'\n";
                    last;
                }
            }
            $fail++;
        }
    } else {
        print "FAIL: $dir [$env] (no output file produced)\n";
        $fail++;
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
