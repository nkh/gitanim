#!/usr/bin/env perl
# test_overwrite_deletefirst.pl - Verify --overwrite and --delete-end-first
# produce correct output. These transform char_ops but the final buffer
# must still match the new file.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_od_engine.vim';

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
    my ($name, $old_text, $new_text, $env) = @_;
    $env //= {};
    my $tmp = "/tmp/dv_od_test";
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
            if l:op[0] ==# 'keep'
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
            elseif l:op[0] ==# 'pause_end_first'
                " Just a delay, no buffer change
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

    for my $key (keys %$env) {
        $ENV{$key} = $env->{$key};
    }

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
        print "PASS: $name\n";
        $pass++;
    } else {
        print "FAIL: $name\n";
        print "  expected: " . substr($exp, 0, 80) . "\n";
        print "  got:      " . substr($got, 0, 80) . "\n";
        $fail++;
    }
}

my @cases = (
    # Overwrite mode: word replace (same length)
    ['overwrite same length', "hello world\n", "hello there\n",
     {AD_OVERWRITE_MODE => '1'}],
    # Overwrite mode: replacement shorter
    ['overwrite shorter', "hello world\n", "hello hi\n",
     {AD_OVERWRITE_MODE => '1'}],
    # Overwrite mode: replacement longer
    ['overwrite longer', "hello hi\n", "hello world\n",
     {AD_OVERWRITE_MODE => '1'}],
    # Overwrite mode: multi-word
    ['overwrite multi-word', "foo bar baz\n", "fox bat boz\n",
     {AD_OVERWRITE_MODE => '1'}],

    # Delete-end-first
    ['delete-end-first', "print(\"hello world\")\n", "print(\"hi\")\n",
     {AD_DELETE_END_FIRST => '1'}],
    ['delete-end-first with insert', "x = old_value\n", "y = new_value extra\n",
     {AD_DELETE_END_FIRST => '1'}],

    # Combined overwrite + delete-end-first
    ['overwrite + delete-end-first', "print(\"hello world\")\n", "print(\"hi\")\n",
     {AD_OVERWRITE_MODE => '1', AD_DELETE_END_FIRST => '1'}],

    # Control
    ['control', "hello\n", "there\n", {}],
);

print "=== Overwrite + Delete-End-First Test ===\n\n";

for my $case (@cases) {
    my ($name, $old, $new, $env) = @$case;
    run_test($name, $old, $new, $env);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
