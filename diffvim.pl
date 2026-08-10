#!/usr/bin/env perl
# diffvim.pl - Animate a code diff as if a human were typing it.
#
# Architecture:
#   - Perl is the orchestrator: computes the diff (via one of two parsers),
#     manages animation state, handles user input, controls timing.
#   - Vim runs in a tmux pane and displays the buffer + cursor.
#   - Perl sends Ex commands to vim via `tmux send-keys`.
#   - Vim normal-mode mappings write user commands (p/n/b/q) to a FIFO.
#   - Perl reads the FIFO (non-blocking) between animation steps.
#
# Two diff parsers are available:
#   --parser perl       Pure-Perl LCS diff (default, no external deps)
#   --parser diff2html  Shells out to `diff2html -f json` for line-level parsing
#
# Usage: diffvim.pl [--parser perl|diff2html] <oldfile> <newfile>
#
# Controls (in vim, during animation):
#   <Space>  pause / resume
#   n        skip current hunk (apply instantly, move to next)
#   b        back to previous hunk (revert and restart)
#   q        stop animation (leave buffer for editing)
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
my %config = (
    tick_ms        => $ENV{DIFFVIM_TICK_MS}        // 16,
    type_delay_ms  => $ENV{DIFFVIM_TYPE_DELAY_MS}  // 35,
    delete_delay_ms=> $ENV{DIFFVIM_DELETE_DELAY_MS}// 25,
    move_min_ms    => $ENV{DIFFVIM_MOVE_MIN_MS}    // 200,
    move_max_ms    => $ENV{DIFFVIM_MOVE_MAX_MS}    // 1400,
    move_ms_per_unit => $ENV{DIFFVIM_MOVE_MS_PER_UNIT} // 6,
    hunk_pause_ms  => $ENV{DIFFVIM_HUNK_PAUSE_MS}  // 180,
);

my $parser_name = 'perl';
my $help = 0;

GetOptions(
    'parser=s' => \$parser_name,
    'help|h'   => \$help,
) or die "Usage: $0 [--parser perl|diff2html] <oldfile> <newfile>\n";

if ($help || @ARGV != 2) {
    print STDERR <<USAGE;
Usage: $0 [--parser perl|diff2html] <oldfile> <newfile>

Opens <oldfile> in vim (inside a tmux pane) and animates the diff
transforming it into <newfile>.

Options:
  --parser perl       Use pure-Perl LCS diff parser (default)
  --parser diff2html  Use diff2html CLI for line-level parsing

Controls (during animation, in vim normal mode):
  <Space>  pause / resume
  n        skip current hunk
  b        back to previous hunk
  q        stop animation

Environment variables for tuning:
  DIFFVIM_TICK_MS         Animation frame interval (default: 16)
  DIFFVIM_TYPE_DELAY_MS   Delay between typed chars (default: 35)
  DIFFVIM_DELETE_DELAY_MS Delay between deleted chars (default: 25)
  DIFFVIM_MOVE_MIN_MS     Minimum cursor glide duration (default: 200)
  DIFFVIM_MOVE_MAX_MS     Maximum cursor glide duration (default: 1400)
  DIFFVIM_MOVE_MS_PER_UNIT  Ms per unit of distance (default: 6)
  DIFFVIM_HUNK_PAUSE_MS   Pause between hunks (default: 180)
USAGE
    exit($help ? 0 : 1);
}

my ($old_file, $new_file) = @ARGV;

# Resolve absolute paths
$old_file = _abs_path($old_file);
$new_file = _abs_path($new_file);

-f $old_file or die "Error: '$old_file' not found\n";
-f $new_file or die "Error: '$new_file' not found\n";

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

# Create the FIFO for user input
system("mkfifo '$ctrl_fifo'") == 0 or die "Cannot create FIFO: $!";

# Open FIFO read+write (non-blocking, stays open)
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

# Animation state
my $phase = 'idle';     # idle | moving | typing | done
my $hunk_idx = 0;
my $op_idx = 0;
my $cur_l = 1;
my $cur_c = 1;
my $line_offset = 0;
my $paused = 0;
my $stopped = 0;
my $snap_count = 0;
my $buf_lines = 0;

my @move_l;
my @move_c;
my $move_idx = 0;

my @hunks;
my $parser_used = '';

# ---------------------------------------------------------------------------
# Vimscript engine
# ---------------------------------------------------------------------------
sub write_engine {
    open my $fh, '>', $engine_vim or die "Cannot write $engine_vim: $!";
    print $fh <<'VIMEOF';
" diffvim engine - buffer manipulation helpers driven by perl via tmux.
let g:dv_ctrl = 'CTRL_FIFO_PLACEHOLDER'

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

nnoremap <buffer> <silent> <Space> :call writefile(['p'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> n       :call writefile(['n'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> b       :call writefile(['b'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> q       :call writefile(['q'], g:dv_ctrl, 'a')<CR>

autocmd VimLeave * call writefile(['vimleft'], g:dv_ctrl, 'a')
VIMEOF
    close $fh;

    # Substitute the FIFO path
    my $content;
    {
        open my $rfh, '<', $engine_vim or die;
        local $/;
        $content = <$rfh>;
        close $rfh;
    }
    $content =~ s/CTRL_FIFO_PLACEHOLDER/$ctrl_fifo/g;
    open my $wfh, '>', $engine_vim or die;
    print $wfh $content;
    close $wfh;
}

# ---------------------------------------------------------------------------
# tmux setup
# ---------------------------------------------------------------------------
sub setup_tmux {
    write_engine();

    my $vim_cmd = "vim -N -u NONE -c 'source $engine_vim' '$old_file'";

    if ($ENV{TMUX}) {
        # Inside tmux: create a new window
        $attached = 1;
        my $cur_session = _tmux_capture("display-message -p '#S'");
        chomp $cur_session;
        $session = $cur_session;
        system("tmux", "new-window", "-t", "$session:", "-n", "diffvim", $vim_cmd) == 0
            or warn "tmux new-window failed\n";
        $target = _tmux_capture("display-message -p -t '$session:' '#{pane_id}'");
        chomp $target;
    } else {
        # Outside tmux: create a new detached session
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
    # Use list form of system() to avoid shell quoting issues.
    # $cmd is a string like "send-keys -t 'target' Enter"; we split it
    # into arguments for tmux.  This is safe because tmux arguments don't
    # contain spaces (paths are passed separately via send_ex).
    my @args = _shell_split($cmd);
    system("tmux", @args) == 0
        or warn "tmux command failed: tmux @args\n";
}

sub _tmux_capture {
    my ($cmd) = @_;
    my @args = _shell_split($cmd);
    # Use open with list form to capture output
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

# Like _tmux_capture but returns only the first line (replaces | head -1).
sub _tmux_capture_first {
    my ($cmd) = @_;
    my $output = _tmux_capture($cmd);
    my @lines = split /\n/, $output;
    return $lines[0] // '';
}

# Simple shell-like splitting: splits on whitespace, respects single and
# double quotes.  This is sufficient for tmux commands (no complex escaping).
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

# Shell-quote a string so it survives system() intact.
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
    # Use list form of system() to avoid shell quoting issues.
    # The Ex command is sent literally via send-keys -l, then Enter separately.
    my $rc1 = system("tmux", "send-keys", "-l", "-t", $target, ":$cmd");
    return if $rc1 != 0;
    system("tmux", "send-keys", "-t", $target, "Enter");
    # Small delay to let vim process the command before the next one arrives.
    # Without this, tmux can queue keys faster than vim processes them,
    # causing Ex command text to leak into normal mode.
    Time::HiRes::sleep(0.005);
}

sub send_ex_redraw {
    my ($cmd) = @_;
    # Combine the command and redraw into a single Ex line using | separator.
    # This avoids race conditions where :redraw text is interpreted as
    # normal-mode keystrokes if vim hasn't finished the previous command.
    send_ex("$cmd | redraw");
}

sub query_vim {
    my ($expr) = @_;
    my $qfile = "$workdir/query";
    open my $fh, '>', $qfile or return '';
    close $fh;

    # Use double quotes in vim for the expression to handle single quotes
    my $escaped = $expr;
    $escaped =~ s/"/\\"/g;
    send_ex("call DvReport(\"$escaped\", '$qfile')");

    # Wait for vim to write the result
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
    if ($parser_name eq 'diff2html') {
        _which('diff2html') or die "Error: 'diff2html' not found in PATH\n" .
            "Install with: npm install -g diff2html-cli\n";
        my $result = DiffVim::Parser::Diff2Html::parse_diff($old_file, $new_file);
        @hunks = @{$result->{hunks}};
        $parser_used = $result->{parser};
    } else {
        my $result = DiffVim::Parser::Perl::parse_diff($old_file, $new_file);
        @hunks = @{$result->{hunks}};
        $parser_used = $result->{parser};
    }
}

sub init_buffer_lines {
    $buf_lines = 0;
    open my $fh, '<:raw', $old_file or die "Cannot open $old_file: $!";
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
# Animation phases
# ---------------------------------------------------------------------------
sub start_next_hunk {
    if ($hunk_idx >= scalar(@hunks)) {
        $phase = 'done';
        # send_ex("echo 'diffvim: animation complete (" . scalar(@hunks) . " hunk(s) applied)'");
        return;
    }

    save_snapshot();

    my $hunk = $hunks[$hunk_idx];
    my $target_line = $hunk->{target_line} + $line_offset;
    my $end_ins = $hunk->{is_end_insert};
    my $end_del = $hunk->{is_end_delete};

    my ($ml, $mc);

    if ($end_ins && $target_line > $buf_lines) {
        my $pos = query_vim("DvGetEol(line('\$'))");
        if ($pos =~ /^(\d+)\s+(\d+)$/) {
            ($ml, $mc) = ($1, $2);
        } else {
            $ml = $buf_lines;
            $mc = 1;
        }
    } elsif ($end_del) {
        my $prev = $target_line - 1;
        $prev = 1 if $prev < 1;
        my $pos = query_vim("DvGetEol($prev)");
        if ($pos =~ /^(\d+)\s+(\d+)$/) {
            ($ml, $mc) = ($1, $2);
        } else {
            $ml = $prev;
            $mc = 1;
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

sub move_step {
    if ($move_idx >= scalar(@move_l)) {
        $cur_l = $move_l[-1];
        $cur_c = $move_c[-1];
        send_ex("call DvSetPos($cur_l, $cur_c)");
        $phase = 'typing';
        $op_idx = 0;
        sleep $config{hunk_pause_ms} / 1000;
        return;
    }
    $cur_l = $move_l[$move_idx];
    $cur_c = $move_c[$move_idx];
    send_ex_redraw("call DvSetPos($cur_l, $cur_c)");
    $move_idx++;
    sleep $config{tick_ms} / 1000;
}

sub type_step {
    my $hunk = $hunks[$hunk_idx];
    my $ops = $hunk->{char_ops};

    if ($op_idx >= scalar(@$ops)) {
        $line_offset += $hunk->{inserted_count} - $hunk->{deleted_count};
        $buf_lines += $hunk->{inserted_count} - $hunk->{deleted_count};
        $hunk_idx++;
        $phase = 'idle';
        sleep $config{hunk_pause_ms} / 1000;
        return;
    }

    my $op = $ops->[$op_idx];
    my $type = $op->{op};
    my $code = $op->{code};

    if ($type eq 'keep') {
        send_ex("call DvKeep($code)");
        sleep 0.001;
    } elsif ($type eq 'delete') {
        send_ex_redraw("call DvDelete()");
        sleep $config{delete_delay_ms} / 1000;
    } elsif ($type eq 'insert') {
        send_ex_redraw("call DvInsert($code)");
        sleep $config{type_delay_ms} / 1000;
    }
    $op_idx++;
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

    for my $cmd (split //, $buf) {
        # Each command is a single character possibly followed by \n
        next if $cmd eq "\n";
        if ($cmd eq 'p') {
            $paused = !$paused;
            if ($paused) {
                send_ex("echo 'diffvim: PAUSED (Space=resume n=skip b=back q=quit)'");
            } else {
                send_ex("echo 'diffvim: resumed'");
            }
        } elsif ($cmd eq 'n') {
            skip_current();
        } elsif ($cmd eq 'b') {
            go_back();
        } elsif ($cmd eq 'q') {
            $stopped = 1;
            send_ex("echo 'diffvim: animation stopped. Buffer left for editing.'");
        } elsif ($cmd eq 'vimleft') {
            $stopped = 1;
        }
    }
}

# Wait for a complete command line from the FIFO.
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
        my $hunk = $hunks[$hunk_idx];
        my $ops = $hunk->{char_ops};
        for my $i ($op_idx .. $#$ops) {
            my $op = $ops->[$i];
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
    send_ex("echo 'diffvim: skipped to hunk " . ($hunk_idx + 1) . "/" . scalar(@hunks) . "'");
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
    send_ex("echo 'diffvim: back to hunk " . ($hunk_idx + 1) . "/" . scalar(@hunks) . "'");
}

# ---------------------------------------------------------------------------
# Animation loop
# ---------------------------------------------------------------------------
sub animate {
    # Wait for vim to be ready
    sleep 0.5;

    send_ex("echo 'diffvim: Space=pause n=skip b=back q=quit | hunk 1/" . scalar(@hunks) . " | parser: $parser_used'");

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
    # Clean temp dir
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
$SIG{INT} = sub { cleanup(); exit 130 };
$SIG{TERM} = sub { cleanup(); exit 143 };
$SIG{__DIE__} = sub { cleanup() };

compute_diff();
init_buffer_lines();

if (@hunks == 0) {
    print "diffvim: files are identical, nothing to animate.\n";
    setup_tmux();
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

setup_tmux();

# Run animation in foreground (we'll attach to tmux which blocks)
if (!$attached) {
    # Fork: child runs animation, parent attaches to tmux
    $anim_pid = fork();
    if ($anim_pid == 0) {
        # Child: run animation
        animate();
        exit 0;
    }
    # Parent: attach to tmux (blocks until user detaches or vim exits)
    system("tmux attach-session -t '$session' 2>/dev/null");
    # After detach, wait for animation child
    waitpid($anim_pid, 0) if $anim_pid > 0;
} else {
    # Inside tmux: animation runs in foreground, new window is focused
    animate();
}

cleanup();
exit 0;
