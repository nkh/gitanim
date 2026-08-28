#!/usr/bin/env perl
# test_vim_engine.pl - Test the REAL ProcessCharOp animation engine,
# including AWD (adaptive word delete), rapid-eol, and all pacing logic.
#
# Unlike test_vim_correctness.pl which bypasses ProcessCharOp, this test
# calls ProcessCharOp in a loop (simulating timer callbacks) to verify
# that the animation engine produces correct output with all the pacing
# options enabled.

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

my $engine_test = '/tmp/dv_engine_test2.vim';

# Extract the engine from the diffvim bash script
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
    # Remove the autocmd block
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    # Override ScheduleNext to be a no-op (we call ProcessCharOp in a loop)
    $content =~ s/function! s:ScheduleNext\([^)]*\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in synchronous test mode\nendfunction/ms;

    # Add synchronous test runner that calls ProcessCharOp in a loop
    $content .= <<'VIM';

function! s:RunEngineTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
        endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'idle'
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

    while s:state.hunk_idx < len(s:state.hunks)
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

        " Process all ops in this hunk by calling ProcessCharOp in a loop
        let l:safety = 0
        while s:state.op_idx < len(l:hunk.char_ops) && !s:state.stopped && l:safety < 100000
            let l:safety += 1
            call s:ProcessCharOp(l:hunk)
        endwhile

        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
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

call s:RunEngineTest()
qa!
VIM

    return $content;
}

my $engine = extract_engine();
open my $out, '>', $engine_test or die "Cannot write $engine_test: $!";
print $out $engine;
close $out;

# Test with various delete-pacing modes
my @test_cases = (
    # [label, env_vars, example_dir]
    ['default (word pacing)', '', 'tests/examples/01_small_python'],
    ['word pacing explicit', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/01_small_python'],
    ['rapid-eol pacing', 'AD_ADAPTIVE_WORD_DELETE=0 AD_RAPID_EOL_DELETE=1', 'tests/examples/01_small_python'],
    ['char pacing', 'AD_ADAPTIVE_WORD_DELETE=0 AD_RAPID_EOL_DELETE=0', 'tests/examples/01_small_python'],
    ['word pacing + large python', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/02_large_python'],
    ['word pacing + rust', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/08_rust_code'],
    ['word pacing + typescript', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/06_typescript'],
    ['word pacing + go', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/05_go_code'],
    ['word pacing + c', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/09_c_code'],
    ['word pacing + shell', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/04_shell_script'],
    ['word pacing + json', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/03_json_config'],
    ['word pacing + yaml', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/10_yaml_config'],
    ['word pacing + java', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/13_java'],
    ['word pacing + ruby', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/16_ruby'],
    ['word pacing + markdown', 'AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1', 'tests/examples/26_markdown'],
);

for my $tc (@test_cases) {
    my ($label, $env, $dir) = @$tc;
    my $old_file = `ls $dir/old.* 2>/dev/null | head -1`; chomp $old_file;
    my $new_file = `ls $dir/new.* 2>/dev/null | head -1`; chomp $new_file;
    next unless $old_file && $new_file && -f $old_file && -f $new_file;

    my $output_file = "/tmp/dv_engine_test_output.txt";
    unlink $output_file;

    # Run vim with the engine, setting env vars
    my $cmd = "env $env vim -es -c 'let g:diffvim_new_file = \"$new_file\"' " .
              "-c 'let g:diffvim.output_file = \"$output_file\"' " .
              "-c 'source $engine_test' " .
              "-c 'qa!' " .
              "'$old_file' 2>/dev/null";
    system($cmd);

    # Compare output with expected
    if (-f $output_file) {
        my $expected = `cat "$new_file"`;
        my $actual = `cat "$output_file"`;
        if ($expected eq $actual) {
            print "PASS: $label\n";
            $pass++;
        } else {
            print "FAIL: $label\n";
            print "  Expected: " . substr($expected, 0, 200) . "\n";
            print "  Actual:   " . substr($actual, 0, 200) . "\n";
            $fail++;
        }
    } else {
        print "FAIL: $label (no output file)\n";
        $fail++;
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
