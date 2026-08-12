#!/usr/bin/env perl
# test_rapid_eol.pl - Verify --rapid-eol-delete produces the same buffer
# content as --no-rapid-eol-delete. Both modes must reconstruct the new file
# exactly. This test extracts the engine and runs it synchronously in vim.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_rapid_engine.vim';

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
    # Remove the autocmd block — we call RunTest manually inside the script
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
    return $content;
}

sub run_test {
    my ($name, $old_text, $new_text, $rapid_on) = @_;
    my $tmp = "/tmp/dv_rapid_test";
    mkdir $tmp unless -d $tmp;
    my $oldf = "$tmp/old.txt";
    my $newf = "$tmp/new.txt";
    my $outf = "$tmp/out.txt";
    open my $fh, '>', $oldf; print $fh $old_text; close $fh;
    open $fh, '>', $newf; print $fh $new_text; close $fh;
    unlink $outf if -f $outf;

    my $engine = extract_engine();
    # Append a synchronous test runner that uses the rapid-eol-delete logic
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
            " Apply rapid-eol-delete logic same as ProcessCharOp
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

    # Set env var BEFORE launching vim — the config dict reads $DIFFVIM_RAPID_EOL_DELETE
    # at source time.
    local $ENV{DIFFVIM_RAPID_EOL_DELETE} = $rapid_on ? '1' : '';

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
    # Normalize trailing newlines for comparison
    my $exp = $new_text;
    $got =~ s/\n+$//;
    $exp =~ s/\n+$//;
    if ($got eq $exp) {
        print "PASS: $name (rapid=" . ($rapid_on ? 'on' : 'off') . ")\n";
        $pass++;
    } else {
        print "FAIL: $name (rapid=" . ($rapid_on ? 'on' : 'off') . ")\n";
        print "  expected: " . substr($exp, 0, 80) . "\n";
        print "  got:      " . substr($got, 0, 80) . "\n";
        $fail++;
    }
}

# Test cases — each run with rapid ON and OFF, both must produce correct output
my @cases = (
    ['trailing line delete',
     "print(\"Hello, World!\")\n",
     "print(\"Hi!\")\n"],
    ['multi-line trailing delete',
     "def hello():\n    print(\"Hello, World!\")\n    x = 12345678901234567890\n    return x\n",
     "def hello():\n    print(\"Hi!\")\n    y = 42\n    return y\n"],
    ['short trailing delete (below min)',
     "abc\n",
     "ab\n"],
    ['mid-line delete (not EOL)',
     "hello world foo\n",
     "hello foo\n"],
    ['delete entire line including newline',
     "line1\nline2\nline3\n",
     "line1\nline3\n"],
    ['delete multiple lines',
     "a\nb\nc\nd\ne\n",
     "a\ne\n"],
    ['pure insertion (no delete)',
     "hello\n",
     "hello world\n"],
    ['identical files',
     "same\n",
     "same\n"],
    ['long trailing delete',
     "x = abcdefghijklmnopqrstuvwxyz\n",
     "x = abc\n"],
    ['mixed mid-line and trailing',
     "function foo(arg1, arg2, arg3) {\n  return arg1 + arg2 + arg3;\n}\n",
     "function foo(a, b) {\n  return a + b;\n}\n"],
);

print "=== Rapid EOL Delete Correctness Test ===\n";
print "Both rapid=on and rapid=off must produce identical correct output.\n\n";
for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    run_test($name, $old, $new, 1);  # rapid ON
    run_test($name, $old, $new, 0);  # rapid OFF
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
