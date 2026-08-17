#!/usr/bin/env perl
# test_synchronous_engine.pl — Exercise the real ProcessCharOp animation engine
# in synchronous mode (no timers, no terminal).
#
# This test extracts the vimscript engine from the diffvim script, overrides
# ScheduleNext to be a no-op, and calls ProcessCharOp in a loop. This tests
# the actual animation logic including AWD, rapid-EOL, and \n handling.
#
# What it tests:
#   1. The engine produces correct final buffer content
#   2. The \n delete (DeleteNewlineAtCursor) works correctly
#   3. AWD (adaptive word delete) processes ops correctly
#   4. The engine handles interleaved keep/delete/insert ops

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Extract the vimscript engine from the diffvim bash script
sub extract_engine {
    my $engine_file = '/tmp/dv_sync_engine.vim';
    open my $fh, '<', "$root/diffvim" or die "Cannot open diffvim: $!";
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

    # Remove the autocmd block (we call StartAnimation manually)
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    # Override ScheduleNext to be a no-op (synchronous mode)
    $content =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;

    # Add synchronous test runner
    $content .= <<'VIM';

function! s:RunSyncTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        echo "No hunks"
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

    let l:hunk = s:state.hunks[0]
    let s:state.cur_hunk = l:hunk
    let s:state.op_idx = 0
    let l:target_line = l:hunk.target_line_old + s:state.line_offset
    let s:cur_l = l:target_line
    let s:cur_c = 1
    call s:PlaceCursor()

    " Process all ops by calling ProcessCharOp in a loop.
    " ProcessCharOp detects end-of-hunk and calls StartNextHunk,
    " which in turn calls ScheduleNext (our no-op). So we need to
    " detect when the hunk index changed and reposition.
    let l:safety = 0
    let l:prev_hunk_idx = -1
    while l:safety < 100000
        let l:safety += 1

        " Check if we're past all hunks
        if s:state.hunk_idx >= len(s:state.hunks)
            break
        endif

        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk

        " If starting a new hunk, set up cursor position
        if s:state.hunk_idx != l:prev_hunk_idx
            let l:prev_hunk_idx = s:state.hunk_idx
            let s:state.op_idx = 0
            let s:state.awd_phase = 0
            let s:state.awd_delay = 0
            let s:state.awd_word_count = 0
            let s:state.accel_delete_count = 0
            let s:state.accel_delete_total = 0
            let l:target_line = l:hunk.target_line_old + s:state.line_offset
            let s:cur_l = l:target_line
            let s:cur_c = 1
            call s:PlaceCursor()
        endif

        " Check if current hunk is done
        if s:state.op_idx >= len(l:hunk.char_ops)
            " Hunk done — advance to next
            let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
            let s:state.hunk_idx += 1
            continue
        endif

        " Update cur_hunk in case ProcessCharOp changed hunk_idx
        let s:state.cur_hunk = l:hunk

        call s:ProcessCharOp()

        " After ProcessCharOp, if it detected end-of-hunk and incremented
        " hunk_idx, we need to update cur_hunk for the next iteration
        if s:state.hunk_idx < len(s:state.hunks)
            let s:state.cur_hunk = s:state.hunks[s:state.hunk_idx]
        endif
    endwhile

    " Write buffer to output file
    if !empty(g:diffvim.output_file)
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

call s:RunSyncTest()
qa!
VIM

    open my $out, '>', $engine_file or die "Cannot write $engine_file: $!";
    print $out $content;
    close $out;

    return $engine_file;
}

my $engine_file = extract_engine();

# Test cases: [name, old_content, new_content, env_vars]
my @cases = (
    ['simple replace', "hello world\n", "hello there\n", ''],
    ['whole line delete', "line1\nline2\nline3\n", "line1\nline3\n", ''],
    ['multi-line delete', "line1\nline2\nline3\nline4\nline5\n", "line1\nline5\n", ''],
    ['python function', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n", ''],
    ['with AWD', "    print(\"Hello, \" + name)\n", "    print(f\"Hello, {name}!\")\n",
     'DIFFVIM_ADAPTIVE_WORD_DELETE=1 DIFFVIM_RAPID_EOL_DELETE=1'],
    ['with rapid-eol', "    print(\"Hello, \" + name)\n", "    print(f\"Hello, {name}!\")\n",
     'DIFFVIM_ADAPTIVE_WORD_DELETE=0 DIFFVIM_RAPID_EOL_DELETE=1'],
    ['char-by-char (no AWD)', "    print(\"Hello, \" + name)\n", "    print(f\"Hello, {name}!\")\n",
     'DIFFVIM_ADAPTIVE_WORD_DELETE=0 DIFFVIM_RAPID_EOL_DELETE=0'],
    ['multi-hunk', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n", ''],
    ['indent change', "def foo():\n    x = 1\n    return x\n",
     "def foo():\n        x = 1\n        return x\n", ''],
    ['insert at end', "hello\n", "hello world\n", ''],
);

my $tmpdir = tempdir(CLEANUP => 1);

for my $case (@cases) {
    my ($name, $old, $new, $env) = @$case;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $out = "$tmpdir/out.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;

    # Run vim with the synchronous engine
    # Set required env vars for the config dict
    my $cmd = "env $env " .
              "DIFFVIM_TICK_MS=16 DIFFVIM_TYPE_DELAY_MS=50 DIFFVIM_DELETE_DELAY_MS=40 " .
              "DIFFVIM_MOVE_MIN_MS=250 DIFFVIM_MOVE_MAX_MS=1600 DIFFVIM_MOVE_MS_PER_UNIT=6 " .
              "DIFFVIM_HUNK_PAUSE_MS=250 DIFFVIM_SPEED=1 " .
              "DIFFVIM_OP_ORDER=optimize DIFFVIM_DELETE_PACING=word " .
              "DIFFVIM_INSERT_PACING=char DIFFVIM_PACING=uniform DIFFVIM_HIGHLIGHT=none " .
              "vim -u NONE -N -n -es " .
              "-c 'let g:diffvim_new_file = \"$nf\"' " .
              "-c 'let g:diffvim.output_file = \"$out\"' " .
              "-c 'source $engine_file' " .
              "'$of' 2>/dev/null";
    system("timeout 10 $cmd");

    if (-f $out) {
        open $fh, '<:raw', $out; my $actual = do { local $/; <$fh> }; close $fh;
        open $fh, '<:raw', $nf; my $expected = do { local $/; <$fh> }; close $fh;

        if ($actual eq $expected) {
            ok("engine: $name", 1);
        } else {
            ok("engine: $name", 0);
            # Show difference
            my @exp = split /\n/, $expected;
            my @act = split /\n/, $actual;
            for my $i (0 .. $#exp) {
                last if $i > $#act;
                if ($exp[$i] ne $act[$i]) {
                    print "  Line " . ($i+1) . ":\n    Expected: '$exp[$i]'\n    Actual:   '$act[$i]'\n";
                    last;
                }
            }
        }
    } else {
        ok("engine: $name (no output)", 0);
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
