#!/usr/bin/env perl
# test_highlight_word.pl - Verify that --highlight-word produces the same
# buffer content as without it. The highlight is purely visual (matchaddpos)
# and must not affect the char ops applied to the buffer.
#
# This test extracts the engine, runs it synchronously in vim with
# highlight_word on and off, and compares both outputs with the expected
# new file. All three must match.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_hw_engine.vim';

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
    return $content;
}

sub run_test {
    my ($name, $old_text, $new_text, $hw_on) = @_;
    my $tmp = "/tmp/dv_hw_test";
    mkdir $tmp unless -d $tmp;
    my $oldf = "$tmp/old.txt";
    my $newf = "$tmp/new.txt";
    my $outf = "$tmp/out.txt";
    open my $fh, '>', $oldf; print $fh $old_text; close $fh;
    open $fh, '>', $newf; print $fh $new_text; close $fh;
    unlink $outf if -f $outf;

    my $engine = extract_engine();
    $engine .= <<'VIM';

function! s:RunTest() abort
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
        while s:state.op_idx < len(l:ops)
            let l:op = l:ops[s:state.op_idx]
            " Simulate the --highlight-word call (visual only, no buffer effect)
            if g:diffvim.highlight_word && (l:op[0] ==# 'delete' || l:op[0] ==# 'insert')
                let l:run_len = s:LookaheadSameTypeRun(l:ops, s:state.op_idx)
                call s:HighlightCurrentWord(l:op[0], l:run_len)
            endif
            " Simulate rapid EOL delete (same as production)
            if l:op[0] ==# 'delete' && g:diffvim.rapid_eol_delete
                let l:rc = s:LookaheadEOLDelete(l:ops, s:state.op_idx)
                if l:rc >= g:diffvim.rapid_eol_min_chars
                    for l:i in range(l:rc)
                        call s:DeleteCharAtCursor()
                    endfor
                    let s:state.op_idx += l:rc
                    continue
                endif
            endif
            if l:op[0] ==# 'keep'
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
            endif
            let s:state.op_idx += 1
        endwhile
        call s:ClearWordHighlight()
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
    endwhile
    if !empty(g:diffvim.output_file)
        execute 'w! ' . g:diffvim.output_file
    endif
endfunction

call s:RunTest()
qa!
VIM

    open $fh, '>', $engine_file; print $fh $engine; close $fh;

    local $ENV{AD_HIGHLIGHT_WORD} = $hw_on ? '1' : '';
    local $ENV{AD_RAPID_EOL_DELETE} = '1';

    system("vim -e -s -n -Nu NONE -U NONE " .
           "-c \"let g:diffvim_new_file = '$newf'\" " .
           "-c \"let g:diffvim = {'output_file': '$outf'}\" " .
           "-c \"source $engine_file\" " .
           "\"$oldf\" > /dev/null 2>&1");

    my $got = '';
    if (-f $outf) {
        local $/;
        open $fh, '<:raw', $outf; $got = <$fh>; close $fh;
    }
    my $exp = $new_text;
    $got =~ s/\n+$//;
    $exp =~ s/\n+$//;
    if ($got eq $exp) {
        print "PASS: $name (hw=" . ($hw_on ? 'on' : 'off') . ")\n";
        $pass++;
    } else {
        print "FAIL: $name (hw=" . ($hw_on ? 'on' : 'off') . ")\n";
        print "  expected: " . substr($exp, 0, 80) . "\n";
        print "  got:      " . substr($got, 0, 80) . "\n";
        $fail++;
    }
}

my @cases = (
    ['simple word replace',
     "hello world\n",
     "hello there\n"],
    ['multi-word line',
     "the quick brown fox\n",
     "the slow brown fox\n"],
    ['trailing delete (rapid EOL)',
     "print(\"Hello, World!\")\n",
     "print(\"Hi!\")\n"],
    ['multi-line with word changes',
     "def hello_world_function():\n    return \"this is a long trailing string\"\n",
     "def hello_world_function():\n    return \"short\"\n"],
    ['pure insertion',
     "hello\n",
     "hello world\n"],
    ['identical files',
     "same\n",
     "same\n"],
    ['single char change (below min)',
     "abc\n",
     "xbc\n"],
    ['long word replace',
     "function calculate_total_price(items, tax_rate) {\n  return total;\n}\n",
     "function compute_total(items, rate) {\n  return total;\n}\n"],
    ['mixed insert and delete',
     "x = old_value + 1234567890\n",
     "y = new_value + 42\n"],
    ['multiple words on same line',
     "foo bar baz qux\n",
     "foo BAR baz QUUX\n"],
);

print "=== Highlight Word Correctness Test ===\n";
print "Both hw=on and hw=off must produce identical correct output.\n\n";
for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    run_test($name, $old, $new, 1);  # highlight_word ON
    run_test($name, $old, $new, 0);  # highlight_word OFF
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
