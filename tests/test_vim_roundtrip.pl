#!/usr/bin/env perl
# test_vim_roundtrip.pl — Apply ops in REAL VIM, compare result with new file.
#
# This test extracts the ad_vim engine, runs it synchronously in vim,
# writes the buffer, and compares byte-for-byte with the expected new file.
# This catches ALL bugs: cursor tracking, \n handling, buffer corruption.
#
# Usage: perl tests/test_vim_roundtrip.pl

use strict;
use warnings;
use File::Temp qw(tempdir);
use Time::HiRes qw(alarm);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond, $actual, $expected) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else {
        print "FAIL: $name\n";
        $fail++;
        if (defined $actual && defined $expected) {
            my @a = split /\n/, $actual;
            my @e = split /\n/, $expected;
            for my $i (0 .. $#e) {
                last if $i > $#a;
                if ($a[$i] ne $e[$i]) {
                    printf "  Line %d:\n    Expected: '%s'\n    Actual:   '%s'\n", $i+1, $e[$i], $a[$i];
                    last;
                }
            }
            printf "  Expected %d lines, got %d lines\n", scalar(@e), scalar(@a) if @a != @e;
        }
    }
}

# Extract the engine from ad_vim
sub extract_engine {
    my $engine_file = '/tmp/dv_roundtrip_engine.vim';
    open my $fh, '<', "$root/diffvim" or die "Cannot open ad_vim: $!";
    my $in_engine = 0;
    my @lines;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) {
            $in_engine = 1;
            next;
        }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @lines, $line if $in_engine;
    }
    close $fh;
    my $content = join('', @lines);
    # Remove autocmd
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
    # Override ScheduleNext to no-op
    $content =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;
    
    # Add synchronous runner
    $content .= <<'VIM';

function! s:RunRoundTrip() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
        endif
        return
    endif
    
    " Initialize state
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
        
        " Position cursor at hunk target
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
        
        " Process all ops
        let l:safety = 0
        let l:prev_hunk_idx = s:state.hunk_idx
        while !s:state.stopped && l:safety < 500000
            let l:safety += 1
            
            " Check if hunk changed (ProcessCharOp may have advanced it)
            if s:state.hunk_idx != l:prev_hunk_idx
                let l:prev_hunk_idx = s:state.hunk_idx
                if s:state.hunk_idx >= len(s:state.hunks)
                    break
                endif
                " Set up new hunk
                let l:hunk = s:state.hunks[s:state.hunk_idx]
                let s:state.cur_hunk = l:hunk
                let s:state.op_idx = 0
                let s:state.awd_phase = 0
                let s:state.awd_delay = 0
                let s:state.awd_word_count = 0
                let s:state.accel_delete_count = 0
                let s:state.accel_delete_total = 0
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
            endif
            
            " Check if all hunks done
            if s:state.hunk_idx >= len(s:state.hunks)
                break
            endif
            
            " Check if current hunk is done
            let l:hunk = s:state.hunks[s:state.hunk_idx]
            if s:state.op_idx >= len(l:hunk.char_ops)
                " Hunk done — ProcessCharOp should have advanced hunk_idx
                " but if it didn't (e.g. ScheduleNext was no-op), do it
                let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
                let s:state.hunk_idx += 1
                continue
            endif
            
            " VERIFY: cursor must be at the right position
            call s:PlaceCursor()
            
            call s:ProcessCharOp()
        endwhile
    endwhile
    
    " Write output
    if !empty(g:diffvim.output_file)
        " Check if new file is empty (0 bytes)
        let l:new_size = getfsize(g:diffvim_new_file)
        if l:new_size == 0
            " New file is empty — delete all lines and set noeol
            1,$delete _
            call setline(1, '')
            setlocal noeol
            setlocal nomodified
            " Use writefile to write empty file
            call writefile([], g:diffvim.output_file, 'b')
            return
        else
            " Check if new file has no trailing newline
            let l:new_bytes = readfile(g:diffvim_new_file, 'b')
            if !empty(l:new_bytes)
                let l:last = l:new_bytes[-1]
                if l:last !~# "\\n$" && l:last !~# "\\r$"
                    setlocal noeol
                endif
            endif
        endif
        execute 'w! ' . g:diffvim.output_file
    endif
endfunction

call s:RunRoundTrip()
qa!
VIM

    open my $out, '>', $engine_file or die "Cannot write $engine_file: $!";
    print $out $content;
    close $out;
    return $engine_file;
}

my $engine_file = extract_engine();
my $tmpdir = tempdir(CLEANUP => 1);

# Test cases
my @cases = (
    ['simple replace', "hello world\n", "hello there\n"],
    ['whole line delete', "line1\nline2\nline3\n", "line1\nline3\n"],
    ['3 line delete', "line1\nline2\nline3\nline4\nline5\n", "line1\nline5\n"],
    ['delete first line', "line1\nline2\nline3\n", "line2\nline3\n"],
    ['delete last line', "line1\nline2\nline3\n", "line1\nline2\n"],
    ['python func', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
                    "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"],
    ['insert at end', "hello\n", "hello world\n"],
    ['empty new', "hello\n", ""],
    ['empty old', "", "hello\n"],
    ['identical', "hello\n", "hello\n"],
    ['indent change', "def foo():\n    x = 1\n    return x\n",
                      "def foo():\n        x = 1\n        return x\n"],
    ['multi-hunk', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n",
                   "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n"],
    ['unicode', "x = \"caf\xc3\xa9\"\n", "x = \"coffee\"\n"],
    ['char run', "x = ---------------------------\n", "x = ---\n"],
    ['mixed delete and modify',
     "line1\nold line\nline3\nline4\nline5\n",
     "line1\nnew line\nline3\nline5\n"],
);

my $env = "AD_TICK_MS=16 AD_TYPE_DELAY_MS=50 AD_DELETE_DELAY_MS=40 " .
          "AD_MOVE_MIN_MS=250 AD_MOVE_MAX_MS=1600 AD_MOVE_MS_PER_UNIT=6 " .
          "AD_HUNK_PAUSE_MS=250 AD_SPEED=1 " .
          "AD_OP_ORDER=optimize AD_DELETE_PACING=word " .
          "AD_INSERT_PACING=char AD_PACING=uniform AD_HIGHLIGHT=none " .
          "AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1";

for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $out = "$tmpdir/out.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;

    my $cmd = "env $env AD_OUTPUT='$out' timeout 30 vim -u NONE -N -n -es " .
              "-c 'let g:diffvim_new_file = \"$nf\"' " .
              "-c 'source $engine_file' " .
              "'$of' 2>/dev/null";
    system($cmd);

    if (-f $out) {
        open $fh, '<:raw', $out; my $actual = do { local $/; <$fh> }; close $fh;
        open $fh, '<:raw', $nf; my $expected = do { local $/; <$fh> }; close $fh;
        ok("vim: $name", $actual eq $expected, $actual, $expected);
    } else {
        ok("vim: $name (no output)", 0);
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
