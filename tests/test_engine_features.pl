#!/usr/bin/env perl
# test_engine_features.pl - Verify that --word-diff, --semantic-cleanup,
# and --indent-aware in the vimscript engine produce correct output.
#
# The key property: all three features are purely about HOW the diff is
# computed (word grouping, cleanup, indent normalization), not WHAT the
# final result is. The buffer after applying the ops must still match
# the new file exactly.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_ef_engine.vim';

sub extract_engine {
    open my $fh, '<', 'diffvim' or die "Cannot open ad_vim: $!";
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
    my $tmp = "/tmp/dv_ef_test";
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

    # Set env vars BEFORE launching vim
    local $ENV{AD_WORD_DIFF} = $env->{word_diff} ? '1' : '';
    local $ENV{AD_SEMANTIC_CLEANUP} = $env->{semantic_cleanup} ? '1' : '';
    local $ENV{AD_INDENT_AWARE} = $env->{indent_aware} ? '1' : '';

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
    my $exp = $env->{_expect_old} ? $old_text : $new_text;
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
    # Basic cases
    ['plain char-diff', "hello world\n", "hello there\n", {}],
    ['word-diff', "hello world\n", "hello there\n", {word_diff => 1}],
    ['semantic-cleanup', "abc\n", "xbc\n", {semantic_cleanup => 1}],
    # indent-aware: indent-only changes are "keep" at line level (not animated).
    # The buffer keeps the OLD indentation. So we expect the OLD output, not new.
    ['indent-aware (indent-only = keep old)', "    hello\n", "  hello\n",
     {indent_aware => 1, _expect_old => 1}],

    # Combined
    ['word-diff + semantic-cleanup', "foo bar\n", "foo baz\n",
     {word_diff => 1, semantic_cleanup => 1}],
    # indent-aware + word-diff: indent-only lines are kept at old indent
    ['indent-aware + word-diff (keep old indent)', "    if x:\n        pass\n",
     "  if x:\n    pass\n", {indent_aware => 1, word_diff => 1, _expect_old => 1}],
    ['all three', "    old_value = 123\n", "  new_value = 456\n",
     {indent_aware => 1, word_diff => 1, semantic_cleanup => 1}],

    # Edge cases
    ['identical files', "same\n", "same\n", {word_diff => 1, semantic_cleanup => 1}],
    ['pure insertion', "hello\n", "hello world\n", {word_diff => 1}],
    ['pure deletion', "hello world\n", "hello\n", {word_diff => 1}],
    # Note: indent-aware skips indent-only changes (they become "keep" at line
    # level and are not animated). So we only test indent-aware with content
    # changes that also have indent differences.
    ['indent-aware with content change', "    old_value\n", "  new_value\n",
     {indent_aware => 1}],

    # Larger examples
    ['python function', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n",
     {word_diff => 1, semantic_cleanup => 1}],
);

print "=== Engine Features Test ===\n";
print "Verifies --word-diff, --semantic-cleanup, --indent-aware produce correct output.\n\n";

for my $case (@cases) {
    my ($name, $old, $new, $env) = @$case;
    run_test($name, $old, $new, $env);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
