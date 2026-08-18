#!/usr/bin/env perl
# run_vim_correctness_fast.pl — Run the SIMPLE-loop engine test (same as
# test_vim_correctness.pl) on every example pair, in parallel.
#
# Uses simple loop (DeleteCharAtCursor / InsertCharAtCursor / AdvanceForKeepChar),
# NOT ProcessCharOp. This is what test_vim_correctness.pl does.

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);

$| = 1;

my $root = "/home/z/my-project/gitanim";
my $engine_test = "/tmp/dv_engine_test.vim";

# --- extract engine ------------------------------------------------------
sub extract_engine {
    open my $fh, '<', "$root/diffvim" or die;
    my $in = 0; my @L;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in=1; next; }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @L, $line if $in;
    }
    close $fh;
    my $c = join('', @L);
    $c =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    $c .= <<'VIM';

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

    open my $ofh, '>', $engine_test or die;
    print $ofh $c;
    close $ofh;
}
extract_engine();

# --- discover example pairs -----------------------------------------------
opendir(my $dh, "$root/examples") or die;
my @dirs = sort grep { -d "$root/examples/$_" && /^\d+_/ } readdir($dh);
closedir $dh;

# --- run in parallel via fork+exec ----------------------------------------
my @tasks;
for my $d (@dirs) {
    my @news = glob("$root/examples/$d/new.*");
    next unless @news;
    my $new = $news[0];
    my @olds = glob("$root/examples/$d/old.*");
    my $old = $olds[0];
    my $out = "/tmp/dv_fc_$d.out";
    unlink $out if -f $out;
    push @tasks, [$d, $old, $new, $out];
}

my $batch = 8;
my %pid2task;
my @queue = @tasks;
my @running;

sub spawn_one {
    my ($t) = @_;
    my ($d, $old, $new, $out) = @$t;
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        # child: use single quotes around the -c args so { and } survive.
        # We can't use single quotes inside the -c arg (would close it),
        # but we don't need to — vim treats the inner single-quote as a
        # string delimiter.
        my @cmd = (
            'timeout', '8', 'vim', '-e', '-s', '-n', '-Nu', 'NONE', '-U', 'NONE',
            '-c', "let g:diffvim_new_file = '$new'",
            '-c', "let g:diffvim = {'output_file': '$out'}",
            '-c', "source $engine_test",
            $old,
        );
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec(@cmd);
        exit(127);
    }
    $pid2task{$pid} = $t;
}

# Spawn initial batch
for (1..$batch) {
    last unless @queue;
    spawn_one(shift @queue);
}

# Wait for completions, spawn more
while (%pid2task) {
    my $pid = wait();
    last if $pid < 0;
    delete $pid2task{$pid};
    if (@queue) {
        spawn_one(shift @queue);
    }
}

# --- collect results ------------------------------------------------------
my %results;
for my $t (@tasks) {
    my ($d, $old, $new, $out) = @$t;
    my $new_md5 = '-';
    my $got_md5 = 'MISSING';
    if (-f $new) {
        open my $fh, '<:raw', $new; my $data = do { local $/; <$fh> }; close $fh;
        $new_md5 = md5_hex($data);
    }
    if (-f $out) {
        open my $fh, '<:raw', $out; my $data = do { local $/; <$fh> }; close $fh;
        $got_md5 = md5_hex($data);
    }
    my $status = ($got_md5 eq $new_md5) ? 'OK' : 'MISMATCH';
    $results{$d} = { new_md5 => $new_md5, got_md5 => $got_md5, status => $status };
}

# --- print table ----------------------------------------------------------
print "\n=== test_vim_correctness (simple loop, primitives only) ===\n";
printf "%-30s %-32s %-32s %s\n", 'example', 'new-file MD5', 'buffer MD5 (saved)', 'status';
print "-" x 100, "\n";
my $ok = 0; my $bad = 0;
for my $d (@dirs) {
    next unless exists $results{$d};
    my $r = $results{$d};
    printf "%-30s %-32s %-32s %s\n", $d, $r->{new_md5}, $r->{got_md5}, $r->{status};
    if ($r->{status} eq 'OK') { $ok++; } else { $bad++; }
}
print "-" x 100, "\n";
printf "\n%d OK, %d MISMATCH out of %d\n", $ok, $bad, $ok + $bad;

# cleanup
for my $t (@tasks) {
    unlink $t->[3];
}
