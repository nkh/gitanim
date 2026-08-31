#!/usr/bin/env perl
# verify_md5.pl — Round-trip MD5 verification of ad_vim AND ad_pipeline
#                  on every example pair under tests/examples/.
#
# For each (old, new) pair:
#   1. compute md5 of the new file
#   2. run ad_vim synchronously (extracted engine, like test_vim_roundtrip.pl),
#      capture md5 of saved buffer (--output FILE)
#   3. run ad_pipeline --no-display --snapshot FILE,
#      capture md5 of snapshot
#   4. print a table
#
# Usage: perl tests/verify_md5.pl

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Basename qw(basename dirname);
use Digest::MD5 qw(md5_hex);

$| = 1;           # autoflush stdout
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $root     = "/home/z/my-project/gitanim";
my $outdir   = "$root/verify_out";
my $engine   = "$outdir/engine.vim";
my $tmpdir   = tempdir(CLEANUP => 1);

mkdir $outdir unless -d $outdir;

# --- extract the vimscript engine from ad_vim (same approach as
#     tests/test_vim_roundtrip.pl) ----------------------------------------
sub extract_engine {
    open my $fh, '<', "$root/diffvim" or die "open ad_vim: $!";
    my $in = 0; my @L;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in=1; next; }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @L, $line if $in;
    }
    close $fh;
    my $c = join('', @L);
    # drop autocmd
    $c =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
    # ScheduleNext → no-op (synchronous)
    $c =~ s/function! s:ScheduleNext\(delay_ms\) abort.*?^endfunction/function! s:ScheduleNext(delay_ms) abort\n    " No-op in sync test mode\nendfunction/ms;

    # Append a synchronous runner identical to test_vim_roundtrip.pl
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

    open my $out, '>', $engine or die "write $engine: $!";
    print $out $c;
    close $out;
}
extract_engine();

# --- helpers ---------------------------------------------------------------
sub md5_file {
    my ($f) = @_;
    return 'MISSING' unless -f $f;
    open my $fh, '<:raw', $f or return "ERR:$!";
    my $data = do { local $/; <$fh> };
    close $fh;
    return Digest::MD5::md5_hex($data);
}

sub run_cmd {
    my ($cmd) = @_;
    # Use system() instead of backticks — backticks can be killed by signals
    # if the child process panics or dumps core.
    my $rc = system("$cmd");
    if ($rc == -1) { return -1; }
    if ($rc & 127) { return $rc; }   # signal
    return $rc >> 8;                  # exit code
}

# --- discover example pairs -----------------------------------------------
opendir(my $dh, "$root/examples") or die "opendir: $!";
my @dirs = sort grep { -d "$root/tests/examples/$_" && /^\d+_/ } readdir($dh);
closedir $dh;

my @rows;   # each: [name, new_md5, dv_md5, dv_status, pipe_md5, pipe_status, pipe_err]

my $env = "AD_TICK_MS=16 AD_TYPE_DELAY_MS=50 AD_DELETE_DELAY_MS=40 " .
          "AD_MOVE_MIN_MS=250 AD_MOVE_MAX_MS=1600 AD_MOVE_MS_PER_UNIT=6 " .
          "AD_HUNK_PAUSE_MS=250 AD_SPEED=1 " .
          "AD_OP_ORDER=optimize AD_DELETE_PACING=word " .
          "AD_INSERT_PACING=char AD_PACING=uniform AD_HIGHLIGHT=none " .
          "AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1";

for my $d (@dirs) {
    my $old = "$root/tests/examples/$d/old.py";
    # find the new.* file
    my @new_candidates = glob("$root/tests/examples/$d/new.*");
    unless (@new_candidates) {
        push @rows, [$d, 'NO_NEW', '-', '-', '-', '-', ''];
        next;
    }
    my $new = $new_candidates[0];
    # also need old.* matching same extension
    my @old_candidates = glob("$root/tests/examples/$d/old.*");
    $old = $old_candidates[0] if @old_candidates;

    my $new_md5 = md5_file($new);

    # --- ad_vim run ------------------------------------------------------
    my $dv_out = "$tmpdir/dv_$d.out";
    unlink $dv_out if -f $dv_out;
    my $cmd = "env $env AD_OUTPUT='$dv_out' timeout 8 vim -u NONE -N -n -es " .
              "-c 'let g:diffvim_new_file = \"$new\"' " .
              "-c 'source $engine' " .
              "'$old' >/dev/null 2>&1";
    my $rc = run_cmd($cmd);
    my $dv_md5     = md5_file($dv_out);
    my $dv_status  = ($dv_md5 eq $new_md5) ? 'OK' : 'MISMATCH';

    # --- ad_pipeline run --------------------------------------------
    my $pipe_out = "$tmpdir/pipe_$d.out";
    unlink $pipe_out if -f $pipe_out;
    my $pcmd = "cd $root && animator/ad_pipeline --no-display --snapshot '$pipe_out' '$old' '$new' >/dev/null 2>&1";
    my $prc = run_cmd($pcmd);
    my $pipe_md5    = md5_file($pipe_out);
    my $pipe_status = ($pipe_md5 eq $new_md5) ? 'OK' : 'MISMATCH';
    my $pipe_err    = ($prc != 0) ? "rc=$prc" : '';

    # Flush progress to stdout so we can see what's running
    printf "PROGRESS %-28s new=%s dv=%s(%s) pipe=%s(%s %s)\n",
        $d, substr($new_md5,0,8), substr($dv_md5,0,8), $dv_status,
        substr($pipe_md5,0,8), $pipe_status, $pipe_err;

    push @rows, [$d, $new_md5, $dv_md5, $dv_status, $pipe_md5, $pipe_status, $pipe_err];
}

# --- print table -----------------------------------------------------------
print "\n";
print "Round-trip MD5 verification on every example pair\n";
print "=" x 110, "\n";
printf "%-28s | %-32s | %-32s | %-32s | %-10s | %-10s\n",
       'example', 'new-file MD5', 'ad_vim buffer MD5', 'pipeline snapshot MD5', 'dv', 'pipe';
print "-" x 110, "\n";
for my $r (@rows) {
    my ($name, $nm, $dm, $ds, $pm, $ps, $pe) = @$r;
    printf "%-28s | %-32s | %-32s | %-32s | %-10s | %-10s\n",
        $name, $nm, $dm, $pm, $ds, $ps . ($pe ? "/$pe" : '');
}
print "=" x 110, "\n";

# --- summary ---------------------------------------------------------------
my $total = scalar @rows;
my $dv_ok    = grep { $_->[3] eq 'OK' } @rows;
my $pipe_ok  = grep { $_->[5] eq 'OK' } @rows;
printf "\nad_vim:        %d/%d match\n",        $dv_ok,   $total;
printf "ad_pipeline: %d/%d match\n", $pipe_ok, $total;

# list mismatches
my @dv_bad = grep { $_->[3] ne 'OK' } @rows;
my @pp_bad = grep { $_->[5] ne 'OK' } @rows;
if (@dv_bad) {
    print "\nad_vim mismatches:\n";
    for my $r (@dv_bad) {
        printf "  %-28s new=%s buffer=%s\n", $r->[0], $r->[1], $r->[2];
    }
}
if (@pp_bad) {
    print "\nad_pipeline mismatches:\n";
    for my $r (@pp_bad) {
        printf "  %-28s new=%s snap=%s (%s)\n", $r->[0], $r->[1], $r->[4], $r->[6] || $r->[5];
    }
}
print "\n";
