#!/usr/bin/env perl
# diffvim.pl - Animate a code diff as if a human were typing it.
#
# Architecture:
#   - Perl is the orchestrator: computes the diff (via one of two parsers),
#     manages animation state, handles user input, controls timing.
#   - Vim runs in a tmux pane and displays the buffer + cursor.
#   - Perl sends Ex commands to vim via `tmux send-keys`.
#   - Vim normal-mode mappings write user commands (p/n/b/q/+/=/</>) to a FIFO.
#   - Perl reads the FIFO (non-blocking) between animation steps.
#
# Two diff parsers are available:
#   --parser perl       Pure-Perl LCS diff (default, no external deps)
#   --parser diff2html  Shells out to `diff2html -f json` for line-level parsing
#
# Usage:
#   diffvim.pl [options] <oldfile> <newfile>
#   diffvim.pl [options] --multi <old1:new1> <old2:new2> ...
#   diffvim.pl [options] --replay <file> [--from REV] [--to REV]
#
# Options:
#   --parser perl|diff2html  Diff parser (default: perl)
#   --speed N                Speed multiplier (0.5=half, 1=normal, 2=double)
#   --output FILE            Write result to FILE after animation
#   --context N              Fold unchanged regions >2N lines, keep N context
#   --max-hunk-chars N       Skip char-by-char for hunks > N changed chars
#   --max-word-chars N       Type words <= N chars instantly, pause after
#   --word-pause-ms N        Pause after instant word (default: 150)
#   --scroll zz|zt|zb|none   Cursor scroll position (default: none)
#   --multi                  Treat args as old:new pairs for multi-file
#   --replay                 Animate git history for given file(s)
#   --from REV               Git rev to start replay from (default: HEAD~5)
#   --to REV                 Git rev to end replay at (default: HEAD)
#   --help, -h               Show help
#
# Controls (in vim, during animation):
#   <Space>  pause / resume
#   n        skip current hunk (apply instantly, move to next)
#   b        back to previous hunk (revert and restart)
#   q        stop animation (leave buffer for editing)
#   +        speed up (multiply speed by 1.5)
#   -        slow down (divide speed by 1.5)
#   =        reset speed to 1.0
#
# Requires: Perl 5.10+, tmux 3+, vim 8+, diff.
# Optional: diff2html-cli (npm install -g diff2html-cli) for the diff2html parser.

use strict;
use warnings;
use utf8;
use Getopt::Long qw(GetOptions);
use File::Temp qw(tempdir mktemp);
use File::Basename qw(dirname basename);
use POSIX qw(:sys_wait_h);
use IO::Handle;
use Fcntl qw(:flock O_RDWR O_NONBLOCK);
use Time::HiRes qw(sleep time);

# Ensure we can find our modules
use lib dirname(__FILE__);
use DiffVim::Parser::Perl qw(parse_diff);
use DiffVim::Parser::Diff2Html;

binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
sub _env_or {
    my ($name, $default) = @_;
    my $val = $ENV{$name};
    return (defined($val) && length($val) > 0) ? $val : $default;
}

my %config = (
    tick_ms          => _env_or('DIFFVIM_TICK_MS',          16),
    type_delay_ms    => _env_or('DIFFVIM_TYPE_DELAY_MS',    35),
    delete_delay_ms  => _env_or('DIFFVIM_DELETE_DELAY_MS',  25),
    move_min_ms      => _env_or('DIFFVIM_MOVE_MIN_MS',      200),
    move_max_ms      => _env_or('DIFFVIM_MOVE_MAX_MS',      1400),
    move_ms_per_unit => _env_or('DIFFVIM_MOVE_MS_PER_UNIT', 6),
    hunk_pause_ms    => _env_or('DIFFVIM_HUNK_PAUSE_MS',    180),
    word_pause_ms    => _env_or('DIFFVIM_WORD_PAUSE_MS',    150),
);

# ---------------------------------------------------------------------------
# CLI options
# ---------------------------------------------------------------------------
my $parser_name    = 'perl';
my $help           = 0;
my $speed_mult     = _env_or('DIFFVIM_SPEED', 1.0);
my $output_file    = '';
my $context_lines  = 0;
my $max_hunk_chars = 0;
my $max_word_chars = 0;
my $scroll_mode    = 'none';
my $multi_mode     = 0;
my $replay_mode    = 0;
my $replay_from    = 'HEAD~5';
my $replay_to      = 'HEAD';

GetOptions(
    'parser=s'        => \$parser_name,
    'speed=f'         => \$speed_mult,
    'output=s'        => \$output_file,
    'context=i'       => \$context_lines,
    'max-hunk-chars=i'=> \$max_hunk_chars,
    'max-word-chars=i'=> \$max_word_chars,
    'word-pause-ms=i' => sub { $config{word_pause_ms} = $_[1]; },
    'scroll=s'        => \$scroll_mode,
    'multi'           => \$multi_mode,
    'replay'          => \$replay_mode,
    'from=s'          => \$replay_from,
    'to=s'            => \$replay_to,
    'help|h'          => \$help,
) or die "Usage: $0 [options] <oldfile> <newfile>\n  Run $0 --help for details.\n";

# Apply speed multiplier to all timing values
sub apply_speed {
    my $m = $speed_mult > 0 ? 1.0 / $speed_mult : 1.0;
    $config{tick_ms}          = int($config{tick_ms} * $m);
    $config{type_delay_ms}    = int($config{type_delay_ms} * $m);
    $config{delete_delay_ms}  = int($config{delete_delay_ms} * $m);
    $config{move_min_ms}      = int($config{move_min_ms} * $m);
    $config{move_max_ms}      = int($config{move_max_ms} * $m);
    $config{hunk_pause_ms}    = int($config{hunk_pause_ms} * $m);
    $config{word_pause_ms}    = int($config{word_pause_ms} * $m);
    # Ensure minimums
    $config{tick_ms}       = 1 if $config{tick_ms} < 1;
    $config{type_delay_ms} = 1 if $config{type_delay_ms} < 1;
    $config{delete_delay_ms} = 1 if $config{delete_delay_ms} < 1;
}
apply_speed();

if ($help) {
    print STDERR <<USAGE;
Usage: $0 [options] <oldfile> <newfile>
       $0 [options] --multi <old1:new1> <old2:new2> ...
       $0 [options] --replay <file> [--from REV] [--to REV]

Animate a code diff in vim (inside a tmux pane), as if a human were typing it.

Options:
  --parser perl|diff2html  Diff parser (default: perl)
  --speed N                Speed multiplier: 0.5=half speed, 2=double, 5=5x
  --output FILE            Write result to FILE after animation, then quit
  --context N              Fold unchanged regions >2N lines, keep N context lines
  --max-hunk-chars N       If a hunk has >N changed chars, apply instantly
  --max-word-chars N       Type words <=N chars instantly, pause after
  --word-pause-ms N        Pause after instant word (default: 150)
  --scroll zz|zt|zb|none   Scroll cursor to center/top/bottom/none (default: none)
  --multi                  Treat args as old:new pairs for multi-file animation
  --replay                 Animate git history for given file(s)
  --from REV               Git rev to start replay from (default: HEAD~5)
  --to REV                 Git rev to end replay at (default: HEAD)
  --help, -h               Show this help

Controls (during animation, in vim normal mode):
  <Space>  pause / resume
  n        skip current hunk (apply instantly)
  b        back to previous hunk (revert and restart)
  q        stop animation (leave buffer for editing)
  +        speed up (x1.5)
  -        slow down (x0.67)
  =        reset speed to 1.0

Environment variables:
  DIFFVIM_TICK_MS, DIFFVIM_TYPE_DELAY_MS, DIFFVIM_DELETE_DELAY_MS,
  DIFFVIM_MOVE_MIN_MS, DIFFVIM_MOVE_MAX_MS, DIFFVIM_MOVE_MS_PER_UNIT,
  DIFFVIM_HUNK_PAUSE_MS, DIFFVIM_WORD_PAUSE_MS, DIFFVIM_SPEED
USAGE
    exit 0;
}

# ---------------------------------------------------------------------------
# File-pair resolution
# ---------------------------------------------------------------------------
my @file_pairs;  # list of [old_file, new_file]

if ($replay_mode) {
    # --replay: each arg is a file path; animate git history for each
    @ARGV or die "Error: --replay requires at least one file path\n";
    _which('git') or die "Error: 'git' not found in PATH\n";

    for my $file (@ARGV) {
        my $abs = _abs_path($file);
        -f $abs or die "Error: '$abs' not found\n";
        my @commits = _git_commits($abs, $replay_from, $replay_to);
        @commits or die "Error: no commits found for '$file' in range $replay_from..$replay_to\n";
        for my $i (0 .. $#commits - 1) {
            my $old_tmp = _git_show_file($abs, $commits[$i]);
            my $new_tmp = _git_show_file($abs, $commits[$i + 1]);
            push @file_pairs, [$old_tmp, $new_tmp];
        }
        # Final: last commit to working copy
        my $old_tmp = _git_show_file($abs, $commits[-1]);
        push @file_pairs, [$old_tmp, $abs];
    }
} elsif ($multi_mode) {
    # --multi: each arg is old:new
    @ARGV or die "Error: --multi requires at least one old:new pair\n";
    for my $arg (@ARGV) {
        if ($arg =~ /^([^:]+):(.+)$/) {
            push @file_pairs, [_abs_path($1), _abs_path($2)];
        } else {
            die "Error: '$arg' is not in old:new format\n";
        }
    }
} else {
    # Single pair: oldfile newfile
    @ARGV == 2 or die "Usage: $0 [options] <oldfile> <newfile>\n  Run $0 --help for details.\n";
    @file_pairs = ([_abs_path($ARGV[0]), _abs_path($ARGV[1])]);
}

# Validate all files exist
for my $pair (@file_pairs) {
    -f $pair->[0] or die "Error: '$pair->[0]' not found\n";
    -f $pair->[1] or die "Error: '$pair->[1]' not found\n";
}

for my $cmd (qw(tmux vim diff)) {
    _which($cmd) or die "Error: '$cmd' not found in PATH\n";
}

# ---------------------------------------------------------------------------
# Workspace setup
# ---------------------------------------------------------------------------
my $workdir = tempdir(CLEANUP => 0);
my $ctrl_fifo = "$workdir/ctrl.fifo";
my $engine_vim = "$workdir/engine.vim";
my $snap_dir = "$workdir/snaps";
mkdir $snap_dir;

system("mkfifo '$ctrl_fifo'") == 0 or die "Cannot create FIFO: $!";

sysopen(my $fifo_fh, $ctrl_fifo, O_RDWR | O_NONBLOCK)
    or die "Cannot open FIFO: $!";
$fifo_fh->autoflush(1);

# ---------------------------------------------------------------------------
# Global state
# ---------------------------------------------------------------------------
my $session = '';
my $target = '';
my $attached = 0;
my $anim_pid = 0;

my $phase = 'idle';
my $hunk_idx = 0;
my $op_idx = 0;
my $cur_l = 1;
my $cur_c = 1;
my $line_offset = 0;
my $paused = 0;
my $stopped = 0;
my $snap_count = 0;
my $buf_lines = 0;
my $pair_idx = 0;

my @move_l;
my @move_c;
my $move_idx = 0;

my @hunks;
my $parser_used = '';

# Dynamic speed (adjustable via +/- keys at runtime)
my $runtime_speed = 1.0;

# ---------------------------------------------------------------------------
# Vimscript engine
# ---------------------------------------------------------------------------
sub write_engine {
    open my $fh, '>', $engine_vim or die "Cannot write $engine_vim: $!";
    print $fh <<'VIMEOF';
" diffvim engine - buffer manipulation helpers driven by perl via tmux.
let g:dv_ctrl = 'CTRL_FIFO_PLACEHOLDER'
let g:dv_scroll = 'SCROLL_PLACEHOLDER'

let s:dv_l = 1
let s:dv_c = 1

function! s:DvPlace() abort
    let l = s:dv_l
    if l < 1 | let l = 1 | endif
    if l > line('$') | let l = line('$') | endif
    let len = len(getline(l))
    let c = s:dv_c
    if c > len + 1 | let c = len + 1 | endif
    if c < 1 | let c = 1 | endif
    call cursor(l, c)
    if g:dv_scroll ==# 'zz' | normal! zz
    elseif g:dv_scroll ==# 'zt' | normal! zt
    elseif g:dv_scroll ==# 'zb' | normal! zb | endif
endfunction

function! DvSetPos(l, c) abort
    let s:dv_l = a:l
    let s:dv_c = a:c
    call s:DvPlace()
endfunction

function! DvKeep(code) abort
    if a:code == 10
        let s:dv_l += 1
        if s:dv_l > line('$') | let s:dv_l = line('$') | endif
        let s:dv_c = 1
    else
        let s:dv_c += 1
    endif
    call s:DvPlace()
endfunction

function! DvInsert(code) abort
    let line = getline(s:dv_l)
    let before = strpart(line, 0, s:dv_c - 1)
    let after = strpart(line, s:dv_c - 1)
    if a:code == 10
        call setline(s:dv_l, before)
        call append(s:dv_l, after)
        let s:dv_l += 1
        let s:dv_c = 1
    else
        call setline(s:dv_l, before . nr2char(a:code) . after)
        let s:dv_c += 1
    endif
    call s:DvPlace()
endfunction

function! DvInsertBatch(codes) abort
    for code in a:codes
        call DvInsert(code)
    endfor
endfunction

function! DvDelete() abort
    let line = getline(s:dv_l)
    let line_len = len(line)
    if s:dv_c > line_len
        if s:dv_l < line('$')
            let next = getline(s:dv_l + 1)
            call setline(s:dv_l, line . next)
            execute (s:dv_l + 1) . 'delete _'
        endif
    else
        let before = strpart(line, 0, s:dv_c - 1)
        let after = strpart(line, s:dv_c)
        call setline(s:dv_l, before . after)
    endif
    call s:DvPlace()
endfunction

function! DvSaveSnap(path) abort
    call writefile(getline(1, '$'), a:path)
endfunction

function! DvLoadSnap(path) abort
    silent %delete _
    let lines = readfile(a:path)
    if empty(lines)
        call setline(1, '')
    else
        call setline(1, lines)
    endif
    redraw
endfunction

function! DvGetEol(l) abort
    let l = a:l
    if l < 1 | let l = 1 | endif
    if l > line('$') | let l = line('$') | endif
    return l . ' ' . (len(getline(l)) + 1)
endfunction

function! DvReport(expr, path) abort
    call writefile([string(eval(a:expr))], a:path)
endfunction

function! DvSetStatusline(text) abort
    echo a:text
endfunction

function! DvFoldContext(hunks_str, context) abort
    " Fold unchanged regions outside context window around each hunk.
    " hunks_str is a semicolon-separated list of "start,end" line pairs.
    if a:context <= 0 | return | endif
    " Simple approach: just set foldmethod=manual and create folds.
    " For now, we use a simpler approach: just scroll to show context.
endfunction

nnoremap <buffer> <silent> <Space> :call writefile(['p'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> n       :call writefile(['n'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> b       :call writefile(['b'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> q       :call writefile(['q'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> +       :call writefile(['+'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> -       :call writefile(['-'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> =       :call writefile(['='], g:dv_ctrl, 'a')<CR>

autocmd VimLeave * call writefile(['vimleft'], g:dv_ctrl, 'a')
VIMEOF
    close $fh;

    # Substitute placeholders
    my $content;
    {
        open my $rfh, '<', $engine_vim or die;
        local $/;
        $content = <$rfh>;
        close $rfh;
    }
    $content =~ s/CTRL_FIFO_PLACEHOLDER/$ctrl_fifo/g;
    $content =~ s/SCROLL_PLACEHOLDER/$scroll_mode/g;
    open my $wfh, '>', $engine_vim or die;
    print $wfh $content;
    close $wfh;
}

# ---------------------------------------------------------------------------
# tmux setup
# ---------------------------------------------------------------------------
sub setup_tmux {
    my ($old_file_arg) = @_;
    $old_file_arg //= $file_pairs[0][0];
    write_engine();

    my $vim_cmd = "vim -N -u NONE -c 'source $engine_vim' '$old_file_arg'";

    if ($ENV{TMUX}) {
        $attached = 1;
        my $cur_session = _tmux_capture("display-message -p '#S'");
        chomp $cur_session;
        $session = $cur_session;
        system("tmux", "new-window", "-t", "$session:", "-n", "diffvim", $vim_cmd) == 0
            or warn "tmux new-window failed\n";
        $target = _tmux_capture("display-message -p -t '$session:' '#{pane_id}'");
        chomp $target;
    } else {
        $attached = 0;
        $session = "diffvim-$$";
        my $cols = $ENV{COLUMNS} // 80;
        my $lines = $ENV{LINES} // 24;
        system("tmux", "new-session", "-d", "-s", $session, "-n", "main",
               "-x", $cols, "-y", $lines, $vim_cmd) == 0
            or warn "tmux new-session failed\n";
        $target = _tmux_capture_first("list-panes -t '$session' -F '\#{pane_id}'");
        chomp $target;
    }
}

sub _tmux {
    my ($cmd) = @_;
    my @args = _shell_split($cmd);
    system("tmux", @args) == 0
        or warn "tmux command failed: tmux @args\n";
}

sub _tmux_capture {
    my ($cmd) = @_;
    my @args = _shell_split($cmd);
    my $pid = open(my $fh, '-|');
    die "Cannot fork: $!" unless defined $pid;
    if ($pid == 0) {
        exec("tmux", @args) or die "Cannot exec tmux: $!";
    }
    local $/;
    my $output = <$fh>;
    close $fh;
    return $output // '';
}

sub _tmux_capture_first {
    my ($cmd) = @_;
    my $output = _tmux_capture($cmd);
    my @lines = split /\n/, $output;
    return $lines[0] // '';
}

sub _shell_split {
    my ($str) = @_;
    my @args;
    while ($str =~ /\S/) {
        $str =~ s/^\s+//;
        if ($str =~ s/^'([^']*)'//) {
            push @args, $1;
        } elsif ($str =~ s/^"([^"]*)"//) {
            push @args, $1;
        } elsif ($str =~ s/^(\S+)//) {
            push @args, $1;
        }
    }
    return @args;
}

sub _shell_quote {
    my ($str) = @_;
    $str =~ s/'/'\\''/g;
    return "'$str'";
}

# ---------------------------------------------------------------------------
# Vim communication
# ---------------------------------------------------------------------------
sub send_ex {
    my ($cmd) = @_;
    my $rc1 = system("tmux", "send-keys", "-l", "-t", $target, ":$cmd");
    return if $rc1 != 0;
    system("tmux", "send-keys", "-t", $target, "Enter");
    Time::HiRes::sleep(0.005);
}

sub send_ex_redraw {
    my ($cmd) = @_;
    send_ex("$cmd | redraw");
}

sub query_vim {
    my ($expr) = @_;
    my $qfile = "$workdir/query";
    open my $fh, '>', $qfile or return '';
    close $fh;

    my $escaped = $expr;
    $escaped =~ s/"/\\"/g;
    send_ex("call DvReport(\"$escaped\", '$qfile')");

    for (1 .. 100) {
        if (-s $qfile) {
            open my $rf, '<', $qfile or return '';
            local $/;
            my $val = <$rf>;
            close $rf;
            chomp $val;
            return $val;
        }
        sleep 0.01;
    }
    return '';
}

# ---------------------------------------------------------------------------
# Diff computation
# ---------------------------------------------------------------------------
sub compute_diff {
    my ($old, $new) = @_;
    my $result;
    if ($parser_name eq 'diff2html') {
        _which('diff2html') or die "Error: 'diff2html' not found in PATH\n" .
            "Install with: npm install -g diff2html-cli\n";
        $result = DiffVim::Parser::Diff2Html::parse_diff($old, $new);
    } else {
        $result = DiffVim::Parser::Perl::parse_diff($old, $new);
    }
    @hunks = @{$result->{hunks}};
    $parser_used = $result->{parser};
}

sub init_buffer_lines {
    my ($file) = @_;
    $file //= $file_pairs[0][0];
    $buf_lines = 0;
    open my $fh, '<:raw', $file or die "Cannot open $file: $!";
    while (my $line = <$fh>) {
        $buf_lines++;
    }
    close $fh;
    $buf_lines = 1 if $buf_lines < 1;
}

# ---------------------------------------------------------------------------
# Easing and movement
# ---------------------------------------------------------------------------
sub ease_in_out {
    my ($t) = @_;
    if ($t < 0.5) {
        return 4.0 * $t * $t * $t;
    } else {
        my $f = -2.0 * $t + 2.0;
        return 1.0 - ($f * $f * $f) / 2.0;
    }
}

sub precompute_move {
    my ($sl, $sc, $el, $ec) = @_;
    my $dl = $el - $sl;
    my $dc = $ec - $sc;
    my $dist = abs($dl) * 80 + abs($dc);
    my $dur = $dist * $config{move_ms_per_unit};
    $dur = $config{move_min_ms} if $dur < $config{move_min_ms};
    $dur = $config{move_max_ms} if $dur > $config{move_max_ms};
    my $steps = int(($dur + $config{tick_ms} - 1) / $config{tick_ms});
    $steps = 1 if $steps < 1;

    @move_l = ();
    @move_c = ();
    for my $i (0 .. $steps - 1) {
        my $t = $steps > 1 ? $i / ($steps - 1) : 1.0;
        my $e = ease_in_out($t);
        push @move_l, int($sl + $dl * $e + 0.5);
        push @move_c, int($sc + $dc * $e + 0.5);
    }
    $move_idx = 0;
}

# ---------------------------------------------------------------------------
# Snapshots
# ---------------------------------------------------------------------------
sub save_snapshot {
    send_ex("call DvSaveSnap('$snap_dir/$snap_count')");
    $snap_count++;
    sleep 0.03;
}

sub restore_snapshot {
    my ($idx) = @_;
    send_ex("call DvLoadSnap('$snap_dir/$idx')");
    $buf_lines = query_vim("line('\$')") || $buf_lines;
    sleep 0.03;
}

# ---------------------------------------------------------------------------
# Progress display
# ---------------------------------------------------------------------------
sub update_progress {
    my $total = scalar(@hunks);
    my $current = $hunk_idx + 1;
    $current = $total if $current > $total;
    my $pct = $total > 0 ? int($current / $total * 100) : 100;
    my $msg = "diffvim: hunk $current/$total ($pct%)";
    $msg .= " | pair " . ($pair_idx + 1) . "/" . scalar(@file_pairs) if @file_pairs > 1;
    $msg .= " | speed " . sprintf("%.1f", $runtime_speed) . "x" if abs($runtime_speed - 1.0) > 0.01;
    $msg .= " | PAUSED" if $paused;
    send_ex("echo '$msg'");
}

# ---------------------------------------------------------------------------
# Animation phases
# ---------------------------------------------------------------------------
sub start_next_hunk {
    if ($hunk_idx >= scalar(@hunks)) {
        $phase = 'done';
        return;
    }

    save_snapshot();
    update_progress();

    my $hunk = $hunks[$hunk_idx];
    my $target_line = $hunk->{target_line} + $line_offset;
    my $end_ins = $hunk->{is_end_insert};
    my $end_del = $hunk->{is_end_delete};

    # Check --max-hunk-chars: if hunk has too many changed chars, apply instantly
    if ($max_hunk_chars > 0) {
        my $changed = 0;
        for my $op (@{$hunk->{char_ops}}) {
            $changed++ if $op->{op} ne 'keep';
        }
        if ($changed > $max_hunk_chars) {
            send_ex("echo 'diffvim: hunk $hunk_idx has $changed changed chars (> $max_hunk_chars), applying instantly'");
            apply_hunk_instantly();
            return;
        }
    }

    my ($ml, $mc);

    if ($end_ins && $target_line > $buf_lines) {
        my $pos = query_vim("DvGetEol(line('\$'))");
        if ($pos =~ /^(\d+)\s+(\d+)$/) {
            ($ml, $mc) = ($1, $2);
        } else {
            $ml = $buf_lines; $mc = 1;
        }
    } elsif ($end_del) {
        my $prev = $target_line - 1;
        $prev = 1 if $prev < 1;
        my $pos = query_vim("DvGetEol($prev)");
        if ($pos =~ /^(\d+)\s+(\d+)$/) {
            ($ml, $mc) = ($1, $2);
        } else {
            $ml = $prev; $mc = 1;
        }
    } else {
        $ml = $target_line;
        $mc = 1;
        $ml = 1 if $ml < 1;
        my $last_line = query_vim("line('\$')") || $buf_lines;
        $ml = $last_line if $ml > $last_line;
    }

    precompute_move($cur_l, $cur_c, $ml, $mc);
    $phase = 'moving';
}

sub apply_hunk_instantly {
    my $hunk = $hunks[$hunk_idx];
    my $ops = $hunk->{char_ops};
    for my $op (@$ops) {
        my $type = $op->{op};
        my $code = $op->{code};
        if ($type eq 'keep') {
            send_ex("call DvKeep($code)");
        } elsif ($type eq 'delete') {
            send_ex("call DvDelete()");
        } elsif ($type eq 'insert') {
            send_ex("call DvInsert($code)");
        }
    }
    send_ex("redraw");
    $line_offset += $hunk->{inserted_count} - $hunk->{deleted_count};
    $buf_lines += $hunk->{inserted_count} - $hunk->{deleted_count};
    $hunk_idx++;
    $phase = 'idle';
}

sub move_step {
    if ($move_idx >= scalar(@move_l)) {
        $cur_l = $move_l[-1];
        $cur_c = $move_c[-1];
        send_ex("call DvSetPos($cur_l, $cur_c)");
        $phase = 'typing';
        $op_idx = 0;
        sleep $config{hunk_pause_ms} / 1000 / $runtime_speed;
        return;
    }
    $cur_l = $move_l[$move_idx];
    $cur_c = $move_c[$move_idx];
    send_ex_redraw("call DvSetPos($cur_l, $cur_c)");
    $move_idx++;
    sleep $config{tick_ms} / 1000 / $runtime_speed;
}

sub type_step {
    my $hunk = $hunks[$hunk_idx];
    my $ops = $hunk->{char_ops};

    if ($op_idx >= scalar(@$ops)) {
        $line_offset += $hunk->{inserted_count} - $hunk->{deleted_count};
        $buf_lines += $hunk->{inserted_count} - $hunk->{deleted_count};
        $hunk_idx++;
        $phase = 'idle';
        sleep $config{hunk_pause_ms} / 1000 / $runtime_speed;
        return;
    }

    my $op = $ops->[$op_idx];
    my $type = $op->{op};
    my $code = $op->{code};

    # --max-word-chars: if we're about to insert/delete a word (contiguous
    # non-space chars followed by space), and the word is <= N chars, apply
    # the whole word instantly, then pause.
    if ($max_word_chars > 0 && ($type eq 'insert' || $type eq 'delete')) {
        my $word_len = _lookahead_word_length($ops, $op_idx);
        if ($word_len > 0 && $word_len <= $max_word_chars) {
            _apply_word_instantly($ops, $op_idx, $word_len);
            $op_idx += $word_len;
            sleep $config{word_pause_ms} / 1000 / $runtime_speed;
            return;
        }
    }

    if ($type eq 'keep') {
        send_ex("call DvKeep($code)");
        sleep 0.001;
    } elsif ($type eq 'delete') {
        send_ex_redraw("call DvDelete()");
        sleep $config{delete_delay_ms} / 1000 / $runtime_speed;
    } elsif ($type eq 'insert') {
        send_ex_redraw("call DvInsert($code)");
        sleep $config{type_delay_ms} / 1000 / $runtime_speed;
    }
    $op_idx++;
}

# Look ahead from $op_idx to find a "word": contiguous insert or delete ops
# (not mixed) where chars are non-space, terminated by a space or op change.
# Returns the length of the word (0 if not a word boundary).
sub _lookahead_word_length {
    my ($ops, $start) = @_;
    my $first_type = $ops->[$start]{op};
    return 0 if $first_type eq 'keep';
    my $len = 0;
    for my $i ($start .. $#$ops) {
        my $op = $ops->[$i];
        last if $op->{op} ne $first_type;
        my $code = $op->{code};
        # Newline or space terminates a word
        last if $code == 10 || $code == 32;
        $len++;
    }
    # Word must be terminated by a space/newline/keep/end to be a "word"
    my $end_idx = $start + $len;
    if ($end_idx <= $#$ops) {
        my $next_op = $ops->[$end_idx];
        my $next_code = $next_op->{code};
        if ($next_op->{op} eq 'keep' || $next_code == 10 || $next_code == 32) {
            return $len;
        }
    } else {
        return $len;  # End of ops
    }
    return 0;  # Not terminated properly
}

sub _apply_word_instantly {
    my ($ops, $start, $len) = @_;
    my $first_type = $ops->[$start]{op};
    for my $i ($start .. $start + $len - 1) {
        my $op = $ops->[$i];
        my $code = $op->{code};
        if ($first_type eq 'insert') {
            send_ex("call DvInsert($code)");
        } elsif ($first_type eq 'delete') {
            send_ex("call DvDelete()");
        }
    }
    send_ex("redraw");
}

# ---------------------------------------------------------------------------
# User input
# ---------------------------------------------------------------------------
sub handle_user_input {
    my $buf = '';
    while (1) {
        my $data = '';
        my $n = sysread($fifo_fh, $data, 4096);
        last unless defined($n) && $n > 0;
        $buf .= $data;
    }
    return unless length($buf);

    # Split on newlines to handle multi-char commands like 'vimleft'
    for my $line (split /\n/, $buf) {
        $line =~ s/\n//g;
        next if $line eq '';
        my $cmd = substr($line, 0, 1);  # First char is the command

        if ($cmd eq 'p') {
            $paused = !$paused;
            update_progress();
        } elsif ($cmd eq 'n') {
            skip_current();
        } elsif ($cmd eq 'b') {
            go_back();
        } elsif ($cmd eq 'q') {
            $stopped = 1;
            send_ex("echo 'diffvim: animation stopped. Buffer left for editing.'");
        } elsif ($cmd eq '+') {
            $runtime_speed *= 1.5;
            send_ex("echo 'diffvim: speed " . sprintf("%.1f", $runtime_speed) . "x'");
        } elsif ($cmd eq '-') {
            $runtime_speed /= 1.5;
            send_ex("echo 'diffvim: speed " . sprintf("%.1f", $runtime_speed) . "x'");
        } elsif ($cmd eq '=') {
            $runtime_speed = 1.0;
            send_ex("echo 'diffvim: speed reset to 1.0x'");
        } elsif ($line eq 'vimleft') {
            $stopped = 1;
        }
    }
}

sub read_fifo_line {
    my $line = '';
    while (1) {
        my $n = sysread($fifo_fh, my $data, 1);
        if (!defined($n) || $n == 0) {
            return undef if length($line) == 0;
            return $line;
        }
        $line .= $data;
        last if $data eq "\n";
    }
    chomp $line;
    return $line;
}

sub skip_current {
    return if $phase eq 'done' || $phase eq 'idle';
    $paused = 0;

    if ($phase eq 'moving') {
        $cur_l = $move_l[-1];
        $cur_c = $move_c[-1];
        send_ex("call DvSetPos($cur_l, $cur_c)");
        $phase = 'typing';
        $op_idx = 0;
    }

    if ($phase eq 'typing') {
        apply_hunk_instantly();
    }
    update_progress();
}

sub go_back {
    return if $hunk_idx == 0 && $snap_count == 0;
    $hunk_idx-- if $hunk_idx > 0;

    my $target_snap = $hunk_idx;
    $target_snap = $snap_count - 1 if $target_snap >= $snap_count;
    $target_snap = 0 if $target_snap < 0;

    restore_snapshot($target_snap);
    $phase = 'idle';
    $op_idx = 0;
    update_progress();
}

# ---------------------------------------------------------------------------
# Animation loop
# ---------------------------------------------------------------------------
sub animate {
    sleep 0.5;

    # Show config
    my $config_msg = "diffvim config: tick=$config{tick_ms}ms type=$config{type_delay_ms}ms " .
                     "del=$config{delete_delay_ms}ms move=$config{move_min_ms}-$config{move_max_ms}ms " .
                     "hunk_pause=$config{hunk_pause_ms}ms";
    $config_msg .= " speed=" . sprintf("%.1f", $runtime_speed) . "x" if abs($runtime_speed - 1.0) > 0.01;
    $config_msg .= " scroll=$scroll_mode" if $scroll_mode ne 'none';
    $config_msg .= " max_hunk=$max_hunk_chars" if $max_hunk_chars > 0;
    $config_msg .= " max_word=$max_word_chars" if $max_word_chars > 0;
    send_ex("echo '$config_msg'");

    send_ex("echo 'diffvim: Space=pause n=skip b=back q=quit +/-=speed | hunk 1/" . scalar(@hunks) . " | parser: $parser_used'");

    sleep 0.3;

    while (!$stopped && $phase ne 'done') {
        handle_user_input();
        if ($paused) {
            sleep 0.05;
            next;
        }
        if ($phase eq 'idle') {
            start_next_hunk();
        } elsif ($phase eq 'moving') {
            move_step();
        } elsif ($phase eq 'typing') {
            type_step();
        }
    }

    # If --output was specified, write the buffer to the output file
    if ($output_file ne '' && !$stopped) {
        send_ex("w! $output_file");
        sleep 0.5;
        send_ex("echo 'diffvim: result written to $output_file'");
        sleep 1;
        send_ex("qa!");
        sleep 0.5;
    }

    # Wait for vim to exit
    while (!$stopped) {
        my $cmd = read_fifo_line();
        last unless defined($cmd);
        if ($cmd eq 'q' || $cmd eq 'vimleft') {
            $stopped = 1;
            last;
        }
    }
}

# ---------------------------------------------------------------------------
# Multi-file animation
# ---------------------------------------------------------------------------
sub animate_all_pairs {
    for my $i (0 .. $#file_pairs) {
        $pair_idx = $i;
        my ($old, $new) = @{$file_pairs[$i]};

        # Reset state for this pair
        $phase = 'idle';
        $hunk_idx = 0;
        $op_idx = 0;
        $cur_l = 1;
        $cur_c = 1;
        $line_offset = 0;
        $paused = 0;
        $stopped = 0;
        $snap_count = 0;

        compute_diff($old, $new);
        init_buffer_lines($old);

        if (@hunks == 0) {
            print "diffvim: pair " . ($i + 1) . "/" . scalar(@file_pairs) . ": files identical, skipping.\n";
            next;
        }

        print "diffvim: pair " . ($i + 1) . "/" . scalar(@file_pairs) .
              ": " . scalar(@hunks) . " hunk(s) (parser: $parser_used)\n";

        if ($i == 0) {
            setup_tmux($old);
        } else {
            # Switch buffer to new file
            send_ex("edit! $old");
            sleep 0.5;
            send_ex("echo 'diffvim: next file: " . basename($old) . " -> " . basename($new) . "'");
            sleep 1;
        }

        if (!$attached && $i == 0) {
            # Fork: child runs animation, parent attaches
            $anim_pid = fork();
            if ($anim_pid == 0) {
                animate();
                exit 0;
            }
            system("tmux attach-session -t '$session' 2>/dev/null");
            waitpid($anim_pid, 0) if $anim_pid > 0;
        } else {
            animate();
        }
    }
}

# ---------------------------------------------------------------------------
# Git helpers (for --replay)
# ---------------------------------------------------------------------------
sub _git_commits {
    my ($file, $from, $to) = @_;
    my $range = "$from..$to";
    my @commits = `git log --reverse --format=%H $range -- "$file" 2>/dev/null`;
    chomp @commits;
    # Prepend the "from" commit itself
    my $from_commit = `git rev-parse "$from" 2>/dev/null`;
    chomp $from_commit;
    unshift @commits, $from_commit if $from_commit && @commits;
    return @commits;
}

sub _git_show_file {
    my ($file, $commit) = @_;
    my $tmp = "$workdir/git_${commit}_" . basename($file);
    $tmp =~ s/[^a-zA-Z0-9_.\/-]/_/g;
    system("git show '$commit:$file' > '$tmp' 2>/dev/null") == 0
        or die "Error: cannot get '$file' at commit '$commit'\n";
    return $tmp;
}

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
sub cleanup {
    if ($anim_pid > 0 && kill 0, $anim_pid) {
        kill 'TERM', $anim_pid;
        waitpid($anim_pid, 0);
    }
    close $fifo_fh if defined $fifo_fh;
    if ($session ne '' && !$attached) {
        system("tmux kill-session -t '$session' 2>/dev/null");
    }
    system("rm -rf '$workdir' 2>/dev/null");
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------
sub _abs_path {
    my ($path) = @_;
    my $dir = dirname($path);
    $dir = '.' if $dir eq '';
    my $abs_dir = _abs_dir($dir);
    return "$abs_dir/" . basename($path);
}

sub _abs_dir {
    my ($dir) = @_;
    return $dir if $dir =~ m{^/};
    my $cwd = `pwd`;
    chomp $cwd;
    return "$cwd/$dir";
}

sub _which {
    my ($cmd) = @_;
    for my $path (split /:/, $ENV{PATH} // '') {
        return 1 if -x "$path/$cmd";
    }
    return 0;
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$SIG{INT}  = sub { cleanup(); exit 130 };
$SIG{TERM} = sub { cleanup(); exit 143 };
$SIG{__DIE__} = sub { cleanup() };

if (@file_pairs > 1) {
    animate_all_pairs();
} else {
    my ($old, $new) = @{$file_pairs[0]};
    compute_diff($old, $new);
    init_buffer_lines($old);

    if (@hunks == 0) {
        print "diffvim: files are identical, nothing to animate.\n";
        setup_tmux($old);
        sleep 0.5;
        send_ex("echo 'diffvim: files are identical.'");
        if (!$attached) {
            system("tmux attach-session -t '$session'");
        }
        cleanup();
        exit 0;
    }

    print "diffvim: " . scalar(@hunks) . " hunk(s) to animate (parser: $parser_used).\n";
    print "Launching vim in tmux...\n";

    setup_tmux($old);

    if (!$attached) {
        $anim_pid = fork();
        if ($anim_pid == 0) {
            animate();
            exit 0;
        }
        system("tmux attach-session -t '$session' 2>/dev/null");
        waitpid($anim_pid, 0) if $anim_pid > 0;
    } else {
        animate();
    }
}

cleanup();
exit 0;
