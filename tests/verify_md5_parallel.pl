#!/usr/bin/env perl
# verify_md5_parallel.pl — Round-trip MD5 verification of:
#   1. new file (expected)
#   2. diffvim saved buffer — simple-loop test (test_vim_correctness.pl style)
#   3. diffvim saved buffer — ProcessCharOp test (test_vim_roundtrip.pl style)
#   4. ad_pipeline snapshot
#
# All run in parallel via fork+exec. Total runtime ~30s for all 42 examples.

use strict;
use warnings;
use Digest::MD5 qw(md5_hex);

$| = 1;

my $root = "/home/z/my-project/gitanim";

# --- extract engines ------------------------------------------------------
my $engine_simple   = "/tmp/dv_eng_simple.vim";   # test_vim_correctness.pl style
my $engine_roundtrip = "/tmp/dv_eng_roundtrip.vim"; # test_vim_roundtrip.pl style

sub extract_engine_simple {
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

    open my $ofh, '>', $engine_simple or die;
    print $ofh $c;
    close $ofh;
}

sub extract_engine_roundtrip {
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
    $c =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;

    $c .= <<'VIM';

function! s:RunRoundTrip() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
        endif
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

        let l:safety = 0
        let l:prev_hunk_idx = s:state.hunk_idx
        while !s:state.stopped && l:safety < 50000
            let l:safety += 1

            if s:state.hunk_idx != l:prev_hunk_idx
                let l:prev_hunk_idx = s:state.hunk_idx
                if s:state.hunk_idx >= len(s:state.hunks)
                    break
                endif
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
            endif

            if s:state.hunk_idx >= len(s:state.hunks)
                break
            endif

            let l:hunk = s:state.hunks[s:state.hunk_idx]
            if s:state.op_idx >= len(l:hunk.char_ops)
                let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
                let s:state.hunk_idx += 1
                continue
            endif

            call s:PlaceCursor()
            call s:ProcessCharOp()
        endwhile
    endwhile

    if !empty(g:diffvim.output_file)
        let l:new_size = getfsize(g:diffvim_new_file)
        if l:new_size == 0
            1,$delete _
            call setline(1, '')
            setlocal noeol
            setlocal nomodified
            call writefile([], g:diffvim.output_file, 'b')
            return
        else
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

    open my $ofh, '>', $engine_roundtrip or die;
    print $ofh $c;
    close $ofh;
}

extract_engine_simple();
extract_engine_roundtrip();

# --- discover example pairs -----------------------------------------------
opendir(my $dh, "$root/examples") or die;
my @dirs = sort grep { -d "$root/tests/examples/$_" && /^\d+_/ } readdir($dh);
closedir $dh;

# Build task list: (example_dir, test_kind, old, new, out_file)
my @tasks;
my $taskid = 0;
for my $d (@dirs) {
    my @news = glob("$root/tests/examples/$d/new.*");
    next unless @news;
    my $new = $news[0];
    my @olds = glob("$root/tests/examples/$d/old.*");
    my $old = $olds[0];

    push @tasks, {
        id => $taskid++, dir => $d, kind => 'simple',
        old => $old, new => $new,
        out => "/tmp/dv_p_simple_$d.out",
    };
    push @tasks, {
        id => $taskid++, dir => $d, kind => 'roundtrip',
        old => $old, new => $new,
        out => "/tmp/dv_p_rt_$d.out",
    };
    push @tasks, {
        id => $taskid++, dir => $d, kind => 'pipeline',
        old => $old, new => $new,
        out => "/tmp/dv_p_pipe_$d.out",
    };
}

# --- run in parallel ------------------------------------------------------
my $batch = 8;  # 8 concurrent (lower to avoid system overload)
my %pid2task;

sub spawn {
    my ($t) = @_;
    my $pid = fork();
    die "fork: $!" unless defined $pid;
    if ($pid == 0) {
        my @cmd;
        if ($t->{kind} eq 'simple') {
            @cmd = ('timeout', '12', 'vim', '-e', '-s', '-n', '-Nu', 'NONE', '-U', 'NONE',
                    '-c', "let g:diffvim_new_file = '$t->{new}'",
                    '-c', "let g:diffvim = {'output_file': '$t->{out}'}",
                    '-c', "source $engine_simple",
                    $t->{old});
        } elsif ($t->{kind} eq 'roundtrip') {
            $ENV{AD_OUTPUT} = $t->{out};
            $ENV{AD_TICK_MS} = 16;
            $ENV{AD_TYPE_DELAY_MS} = 50;
            $ENV{AD_DELETE_DELAY_MS} = 40;
            $ENV{AD_OP_ORDER} = 'optimize';
            $ENV{AD_DELETE_PACING} = 'word';
            $ENV{AD_INSERT_PACING} = 'char';
            $ENV{AD_PACING} = 'uniform';
            $ENV{AD_HIGHLIGHT} = 'none';
            @cmd = ('timeout', '12', 'vim', '-u', 'NONE', '-N', '-n', '-es',
                    '-c', "let g:diffvim_new_file = '$t->{new}'",
                    '-c', "source $engine_roundtrip",
                    $t->{old});
        } else {
            @cmd = ('timeout', '12', 'bash', '-c',
                    "cd $root && animator/ad_pipeline --no-display --snapshot '$t->{out}' '$t->{old}' '$t->{new}'");
        }
        open(STDOUT, '>', '/dev/null');
        open(STDERR, '>', '/dev/null');
        exec(@cmd);
        exit(127);
    }
    $pid2task{$pid} = $t;
    print STDERR "  spawned pid=$pid for $t->{dir} ($t->{kind})\n" if $ENV{DEBUG};
}

my @queue = @tasks;
for (1..$batch) {
    last unless @queue;
    spawn(shift @queue);
}

# Use non-blocking waitpid so we can detect zombies
my $idle_count = 0;
while (%pid2task) {
    my $pid = waitpid(-1, 0);
    last if $pid < 0;
    if (exists $pid2task{$pid}) {
        delete $pid2task{$pid};
    }
    if (@queue) {
        spawn(shift @queue);
    }
}

# --- collect results ------------------------------------------------------
sub md5_file {
    my ($f) = @_;
    return 'MISSING' unless -f $f;
    open my $fh, '<:raw', $f or return 'ERR';
    my $d = do { local $/; <$fh> };
    close $fh;
    return md5_hex($d);
}

my %results;  # dir -> { new, simple, roundtrip, pipeline }
for my $t (@tasks) {
    my $d = $t->{dir};
    $results{$d} //= {};
    $results{$d}{new}       //= md5_file($t->{new});
    $results{$d}{$t->{kind}} = md5_file($t->{out});
    unlink $t->{out};
}

# --- print table ----------------------------------------------------------
print "\n";
print "Round-trip MD5 verification — all 42 example pairs\n";
print "=" x 130, "\n";
printf "%-22s | %-32s | %-32s | %-32s | %-32s\n",
       'example', 'new-file MD5',
       'diffvim (simple loop)', 'diffvim (ProcessCharOp)', 'ad_pipeline';
print "-" x 130, "\n";
my ($s_ok, $s_bad, $r_ok, $r_bad, $p_ok, $p_bad) = (0,0,0,0,0,0);
for my $d (@dirs) {
    next unless exists $results{$d};
    my $r = $results{$d};
    my $s_st = ($r->{simple}    eq $r->{new}) ? 'OK ' : 'BAD';
    my $r_st = ($r->{roundtrip} eq $r->{new}) ? 'OK ' : 'BAD';
    my $p_st = ($r->{pipeline}  eq $r->{new}) ? 'OK ' : 'BAD';
    $s_ok++ if $s_st eq 'OK '; $s_bad++ if $s_st ne 'OK ';
    $r_ok++ if $r_st eq 'OK '; $r_bad++ if $r_st ne 'OK ';
    $p_ok++ if $p_st eq 'OK '; $p_bad++ if $p_st ne 'OK ';
    printf "%-22s | %-32s | %-32s | %-32s | %-32s\n",
        $d, $r->{new}, $r->{simple}, $r->{roundtrip}, $r->{pipeline};
}
print "=" x 130, "\n";
printf "\nSummary:\n";
printf "  diffvim (simple loop / primitives only):    %2d OK / %2d bad\n", $s_ok, $s_bad;
printf "  diffvim (ProcessCharOp / full engine):      %2d OK / %2d bad\n", $r_ok, $r_bad;
printf "  ad_pipeline (Go animator):             %2d OK / %2d bad\n", $p_ok, $p_bad;
print "\n";
