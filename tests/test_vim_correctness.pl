#!/usr/bin/env perl
# test_vim_correctness.pl - Apply the diff in ACTUAL VIM, save the buffer,
# and compare with the expected new file. This catches bugs that Perl-only
# tests miss (e.g. UTF-8 cursor tracking, vim buffer manipulation issues).
#
# This test extracts the engine from the diffvim script, runs it
# synchronously in vim (no timers), writes the result, and compares.
#
# Usage: perl tests/test_vim_correctness.pl

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

# Path to the extracted engine test file
my $engine_test = '/tmp/dv_engine_test.vim';

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

    # Remove the autocmd block (we call StartAnimation manually)
    my $content = join('', @lines);
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    # Add synchronous test runner
    $content .= <<'VIM';

function! s:RunTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        " No hunks — files are identical, just write the buffer as-is
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
    let s:cur_l = line('.')
    let s:cur_c = col('.')
    while s:state.hunk_idx < len(s:state.hunks)
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let s:state.op_idx = 0
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
        let l:ops = l:hunk.char_ops
        for l:op in l:ops
            if l:op[0] ==# 'keep'
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
            endif
        endfor
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
    endwhile
    if !empty(g:diffvim.output_file)
        " Preserve trailing newline status of the new file
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

call s:RunTest()
qa!
VIM

    open my $ofh, '>', $engine_test or die "Cannot write $engine_test: $!";
    print $ofh $content;
    close $ofh;
}

# Run vim with the engine on a file pair and compare the result
sub test_pair {
    my ($old_file, $new_file, $name) = @_;
    my $result_file = '/tmp/dv_vim_result.txt';
    unlink $result_file;

    my $new_abs = `realpath "$new_file"`;
    chomp $new_abs;

    my $old_abs = `realpath "$old_file"`;
    chomp $old_abs;

    system("vim -e -s -n -Nu NONE -U NONE " .
           "-c \"let g:diffvim_new_file = '$new_abs'\" " .
           "-c \"let g:diffvim = {'output_file': '$result_file'}\" " .
           "-c \"source $engine_test\" " .
           "\"$old_abs\" 2>/dev/null");

    # Compare result with expected (strip trailing newline for comparison
    # since vim may add one)
    my $result = '';
    my $expected = '';
    if (-f $result_file) {
        open my $rfh, '<:raw', $result_file or die;
        local $/;
        $result = <$rfh>;
        close $rfh;
    }
    open my $efh, '<:raw', $new_file or die;
    local $/;
    $expected = <$efh>;
    close $efh;

    # Normalize trailing newlines
    $result =~ s/\n+$//;
    $expected =~ s/\n+$//;

    if ($result eq $expected) {
        print "PASS: $name\n";
        $pass++;
    } else {
        print "FAIL: $name\n";
        # Show first difference
        my @r = split /\n/, $result;
        my @e = split /\n/, $expected;
        my $max = @r > @e ? @r : @e;
        for my $i (0 .. $max - 1) {
            my $r = $i < @r ? $r[$i] : '<missing>';
            my $e = $i < @e ? $e[$i] : '<missing>';
            if ($r ne $e) {
                print "  Line " . ($i + 1) . ":\n";
                print "    expected: $e\n";
                print "    got:      $r\n";
                last;
            }
        }
        $fail++;
    }
}

# Extract the engine
extract_engine();
print "Engine extracted to $engine_test\n\n";

# Test all example pairs
print "=== Vim correctness tests ===\n";
for my $dir (sort glob("tests/tests/examples/*/")) {
    my @old_files = glob("$dir/old.*");
    for my $old (@old_files) {
        my $ext = $old =~ /\.(\w+)$/ ? $1 : 'txt';
        (my $new = $old) =~ s/old\.\w+$/new.$ext/;
        if (-f $new) {
            my $name = $dir;
            $name =~ s|tests/tests/examples/||;
            $name =~ s|/$||;
            test_pair($old, $new, $name);
        }
    }
}

# Test 'a' and 'b' files
test_pair("a", "b", "a -> b") if -f "a" && -f "b";
test_pair("A", "B", "A -> B") if -f "A" && -f "B";

# Edge cases
print "\n=== Edge cases ===\n";

# Empty old file
open my $fh, '>', '/tmp/dv_empty.txt'; close $fh;
open $fh, '>', '/tmp/dv_content.txt'; print $fh "hello\nworld\n"; close $fh;
test_pair('/tmp/dv_empty.txt', '/tmp/dv_content.txt', 'empty old file');

# Identical files
test_pair('/tmp/dv_content.txt', '/tmp/dv_content.txt', 'identical files');

# Single character
open $fh, '>', '/tmp/dv_a.txt'; print $fh "a"; close $fh;
open $fh, '>', '/tmp/dv_b.txt'; print $fh "b"; close $fh;
test_pair('/tmp/dv_a.txt', '/tmp/dv_b.txt', 'single char');

# Multi-byte UTF-8 (em-dash)
open $fh, '>:raw', '/tmp/dv_utf8_old.txt'; print $fh "hello — world\n"; close $fh;
open $fh, '>:raw', '/tmp/dv_utf8_new.txt'; print $fh "hello — there world\n"; close $fh;
test_pair('/tmp/dv_utf8_old.txt', '/tmp/dv_utf8_new.txt', 'UTF-8 em-dash');

# Copyright symbol
open $fh, '>:raw', '/tmp/dv_copy_old.txt'; print $fh "Copyright 2026\n"; close $fh;
open $fh, '>:raw', '/tmp/dv_copy_new.txt'; print $fh "Copyright © 2026\n"; close $fh;
test_pair('/tmp/dv_copy_old.txt', '/tmp/dv_copy_new.txt', 'UTF-8 copyright');

# Cleanup
unlink '/tmp/dv_empty.txt', '/tmp/dv_content.txt', '/tmp/dv_a.txt', '/tmp/dv_b.txt';
unlink '/tmp/dv_utf8_old.txt', '/tmp/dv_utf8_new.txt';
unlink '/tmp/dv_copy_old.txt', '/tmp/dv_copy_new.txt';
unlink '/tmp/dv_vim_result.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
