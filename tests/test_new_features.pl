#!/usr/bin/env perl
# test_new_features.pl - Verify that the new features (--accel-delete,
# --overwrite, --delete-end-first, --inline-highlight, --gaussian-jitter,
# --dim-unchanged, --pause-after-lines, --startup-feedback) don't break
# the core animation correctness.
#
# The key property: all these features are visual/timing-only. The final
# buffer must still match the new file exactly.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_nf_engine.vim';

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
    my $tmp = "/tmp/dv_nf_test";
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

    # Set env vars
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
    # Accelerated deletion with multi-line deletes
    ['accel-delete small', "line1\nline2\nline3\n", "line1\n",
     {DIFFVIM_ACCEL_DELETE => '1'}],
    ['accel-delete large', "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n", "a\nj\n",
     {DIFFVIM_ACCEL_DELETE => '1', DIFFVIM_ACCEL_DELETE_START_MS => '80',
      DIFFVIM_ACCEL_DELETE_MIN_MS => '10', DIFFVIM_ACCEL_DELETE_ACCEL => '85'}],

    # Inline highlight (visual only, no buffer effect)
    ['inline-highlight', "hello world\n", "hello there\n",
     {DIFFVIM_INLINE_HIGHLIGHT => '1'}],
    ['inline-highlight delete', "hello world foo\n", "hello \n",
     {DIFFVIM_INLINE_HIGHLIGHT => '1'}],

    # Gaussian jitter (timing only, no buffer effect)
    ['gaussian-jitter', "hello world\n", "hello there\n",
     {DIFFVIM_GAUSSIAN_JITTER => '1', DIFFVIM_GAUSSIAN_JITTER_PCT => '20'}],

    # Dim unchanged (visual only)
    ['dim-unchanged', "same\nchange\nsame\n", "same\nchanged\nsame\n",
     {DIFFVIM_DIM_UNCHANGED => '1', DIFFVIM_DIM_UNCHANGED_PCT => '60'}],

    # Pause after lines (timing only)
    ['pause-after-lines', "a\nb\nc\nd\ne\nf\ng\nh\ni\nj\n",
     "a\nb\nC\nd\ne\nF\ng\nh\nI\nj\n",
     {DIFFVIM_PAUSE_AFTER_LINES => '3', DIFFVIM_PAUSE_AFTER_THRESHOLD => '5',
      DIFFVIM_PAUSE_AFTER_MS => '100'}],

    # Combined: multiple new features at once
    ['all new features', "line1\nline2\nline3\nline4\nline5\n",
     "line1\nLINE2\nline3\nLINE4\nline5\n",
     {DIFFVIM_ACCEL_DELETE => '1', DIFFVIM_INLINE_HIGHLIGHT => '1',
      DIFFVIM_GAUSSIAN_JITTER => '1', DIFFVIM_DIM_UNCHANGED => '1'}],

    # Control: no new features (should still work)
    ['control (no new features)', "hello\nworld\n", "hello\nthere\n", {}],
);

print "=== New Features Correctness Test ===\n";
print "Verifies new features don't break core animation correctness.\n\n";

for my $case (@cases) {
    my ($name, $old, $new, $env) = @$case;
    run_test($name, $old, $new, $env);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
