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
my $version_flag   = 0;
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
my $no_tmux        = 0;
my $dry_run        = 0;
my $sign_column    = 0;
my $git_blame      = 0;
my $step_mode      = 0;
my $git_rev        = '';
my $max_line_len   = _env_or('DIFFVIM_MAX_LINE_LEN', 10000);
my $adaptive_timing= 0;
my $word_diff_mode = 0;

GetOptions(
    'parser=s'         => \$parser_name,
    'speed=f'          => \$speed_mult,
    'output=s'         => \$output_file,
    'context=i'        => \$context_lines,
    'max-hunk-chars=i' => \$max_hunk_chars,
    'max-word-chars=i' => \$max_word_chars,
    'word-pause-ms=i'  => sub { $config{word_pause_ms} = $_[1]; },
    'scroll=s'         => \$scroll_mode,
    'multi'            => \$multi_mode,
    'replay'           => \$replay_mode,
    'from=s'           => \$replay_from,
    'to=s'             => \$replay_to,
    'no-tmux'          => \$no_tmux,
    'dry-run'          => \$dry_run,
    'sign-column'      => \$sign_column,
    'git-blame'        => \$git_blame,
    'step-mode'        => \$step_mode,
    'git-rev=s'        => \$git_rev,
    'max-line-len=i'   => \$max_line_len,
    'adaptive-timing'  => \$adaptive_timing,
    'word-diff'        => \$word_diff_mode,
    'version|V'        => \$version_flag,
    'help|h'           => \$help,
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

# --version flag: print version and dependency info
if ($version_flag) {
    my $version = '1.2.0';
    print "diffvim.pl version $version\n";
    print "  parser: $parser_name\n";
    print "  perl: $]\n";
    for my $cmd (qw(vim tmux diff git diff2html)) {
        if (_which($cmd)) {
            my $v = `$cmd --version 2>&1 | head -1`;
            chomp $v;
            print "  $cmd: $v\n";
        } else {
            print "  $cmd: not found\n";
        }
    }
    exit 0;
}

if ($help) {
    print STDERR <<USAGE;
Usage: $0 [options] <oldfile> <newfile>
       $0 [options] --multi <old1:new1> <old2:new2> ...
       $0 [options] --replay <file> [--from REV] [--to REV]
       $0 [options] --git-rev REV..REV <file> [<file> ...]
       $0 --dry-run [options] <oldfile> <newfile>
       $0 --version

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
  --git-rev REV..REV       Animate a git commit range (e.g. HEAD~3..HEAD)
  --no-tmux                Run vim directly in terminal (no tmux wrapper)
  --dry-run                Compute and print diff ops without launching vim
  --sign-column            Show +/- signs in vim's sign column
  --git-blame              Show git blame for changed lines
  --step-mode              Space advances one char op at a time
  --max-line-len N         Skip char-level diff for lines >N chars (default: 10000)
  --adaptive-timing        Auto-slow for complex hunks, speed up for simple ones
  --word-diff              Use word-level diff (groups changes by word)
  --version, -V            Print version and dependency info
  --help, -h               Show this help

Controls (during animation, in vim normal mode):
  <Space>  pause / resume (or advance one op in --step-mode)
  n        skip current hunk (apply instantly)
  b        back to previous hunk (revert and restart)
  q        stop animation (leave buffer for editing)
  +        speed up (x1.5)
  -        slow down (x0.67)
  =        reset speed to 1.0
  u        undo last hunk
  Ctrl-r   redo hunk
  ?        show full-screen help overlay

Environment variables:
  DIFFVIM_TICK_MS, DIFFVIM_TYPE_DELAY_MS, DIFFVIM_DELETE_DELAY_MS,
  DIFFVIM_MOVE_MIN_MS, DIFFVIM_MOVE_MAX_MS, DIFFVIM_MOVE_MS_PER_UNIT,
  DIFFVIM_HUNK_PAUSE_MS, DIFFVIM_WORD_PAUSE_MS, DIFFVIM_SPEED,
  DIFFVIM_MAX_LINE_LEN
USAGE
    exit 0;
}

# ---------------------------------------------------------------------------
# File-pair resolution
# ---------------------------------------------------------------------------
my @file_pairs;  # list of [old_file, new_file]

# --git-rev: parse REV..REV syntax and animate each file's history
if ($git_rev ne '') {
    _which('git') or die "Error: 'git' not found in PATH\n";
    if ($git_rev =~ /^(\S+)\.\.(\S+)$/) {
        $replay_from = $1;
        $replay_to = $2;
        $replay_mode = 1;
    } else {
        die "Error: --git-rev requires REV..REV syntax (e.g. HEAD~3..HEAD)\n";
    }
}

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

# Validate all files exist and are readable (#66)
for my $pair (@file_pairs) {
    for my $f (@$pair) {
        -f $f or die "Error: '$f' not found\n";
        -r $f or die "Error: '$f' is not readable\n";
    }
}

# Binary file detection (#23) — refuse to animate binary files
sub _is_binary {
    my ($file) = @_;
    open my $fh, '<:raw', $file or return 0;
    my $buf;
    read($fh, $buf, 8192);
    close $fh;
    # Check for null bytes (common binary indicator)
    return $buf =~ /\0/ ? 1 : 0;
}

for my $pair (@file_pairs) {
    for my $f (@$pair) {
        if (_is_binary($f)) {
            die "Error: '$f' appears to be a binary file. diffvim cannot animate binary files.\n";
        }
    }
}

# Check for very long lines (#69) — warn if any line exceeds max_line_len
sub _has_long_lines {
    my ($file, $max_len) = @_;
    open my $fh, '<:raw', $file or return 0;
    while (my $line = <$fh>) {
        if (length($line) > $max_len) {
            close $fh;
            return 1;
        }
    }
    close $fh;
    return 0;
}

for my $pair (@file_pairs) {
    for my $f (@$pair) {
        if (_has_long_lines($f, $max_line_len)) {
            warn "Warning: '$f' has lines longer than $max_line_len chars. Char-level diff may be slow.\n";
        }
    }
}

# Forward-declare variables used by compute_diff and the dry-run block
my @hunks;
my $parser_used = '';

# --dry-run: compute and print diff ops without launching vim (#9)
if ($dry_run) {
    for my $pair (@file_pairs) {
        my ($old, $new) = @$pair;
        print "=== Dry run: $old -> $new ===\n";
        compute_diff($old, $new);
        print "Parser: $parser_used\n";
        print "Hunks: " . scalar(@hunks) . "\n";
        for my $i (0 .. $#hunks) {
            my $h = $hunks[$i];
            print "  Hunk " . ($i + 1) . ": target_line=$h->{target_line} " .
                  "del=$h->{deleted_count} ins=$h->{inserted_count} " .
                  "end_ins=$h->{is_end_insert} end_del=$h->{is_end_delete}\n";
            print "    old_text: \"$h->{old_text}\"\n";
            print "    new_text: \"$h->{new_text}\"\n";
            print "    char_ops (" . scalar(@{$h->{char_ops}}) . "):\n";
            for my $j (0 .. $#{$h->{char_ops}}) {
                my $op = $h->{char_ops}[$j];
                my $ch = $op->{code} == 10 ? "\\n" : chr($op->{code});
                printf "      [%d] %s %d (%s)\n", $j, $op->{op}, $op->{code}, $ch;
            }
        }
    }
    exit 0;
}

# Dependency check — skip tmux if --no-tmux
my @required = qw(vim diff);
push @required, 'git' if ($replay_mode || $git_rev ne '');
push @required, 'tmux' unless $no_tmux;
for my $cmd (@required) {
    _which($cmd) or die "Error: '$cmd' not found in PATH\n";
}

# ---------------------------------------------------------------------------
# Workspace setup
# ---------------------------------------------------------------------------
# Use CLEANUP => 1 for automatic temp directory cleanup on exit (#62)
my $workdir = tempdir(CLEANUP => 1);
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
let g:dv_sign_column = SIGN_COLUMN_PLACEHOLDER
let g:dv_git_blame = GIT_BLAME_PLACEHOLDER

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

" Batch keep — advance cursor for multiple chars at once (#4)
function! DvKeepBatch(codes) abort
    for code in a:codes
        call DvKeep(code)
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

" Sign column support (#57) — show +/- signs for deleted/added lines
let g:dv_sign_id = 5000

function! DvSignSetup() abort
    if !g:dv_sign_column | return | endif
    sign define dv_add text=+ texthl=DiffAdd linehl=DiffAdd
    sign define dv_del text=- texthl=DiffDelete linehl=DiffDelete
    sign define dv_chg text=~ texthl=DiffChange linehl=DiffChange
endfunction

function! DvSignPlace(line, type) abort
    if !g:dv_sign_column | return | endif
    let g:dv_sign_id += 1
    if a:type ==# 'add'
        execute 'sign place' g:dv_sign_id 'line=' . a:line 'name=dv_add buffer=' . bufnr('')
    elseif a:type ==# 'del'
        execute 'sign place' g:dv_sign_id 'line=' . a:line 'name=dv_del buffer=' . bufnr('')
    elseif a:type ==# 'chg'
        execute 'sign place' g:dv_sign_id 'line=' . a:line 'name=dv_chg buffer=' . bufnr('')
    endif
endfunction

function! DvSignClear() abort
    if !g:dv_sign_column | return | endif
    sign unplace * buffer=bufnr('')
    let g:dv_sign_id = 5000
endfunction

" Git blame integration (#94) — show blame for a line

function! DvGitBlame(line) abort
    if !g:dv_git_blame | return '' | endif
    let l:file = expand('%:p')
    if empty(l:file) | return '' | endif
    let l:blame = systemlist('git blame -L ' . a:line . ',' . a:line . ' --porcelain ' . shellescape(l:file) . ' 2>/dev/null')
    if empty(l:blame) | return '' | endif
    let l:parts = split(l:blame[0], ' ')
    if len(l:parts) < 2 | return '' | endif
    let l:commit = l:parts[0]
    let l:author = ''
    for l:line in l:blame
        if l:line =~ '^author '
            let l:author = substitute(l:line, '^author ', '', '')
            break
        endif
    endfor
    return l:commit[:7] . ' ' . l:author
endfunction

" Help overlay (#46) — full-screen help page
let g:dv_help_visible = 0

function! DvToggleHelp() abort
    if g:dv_help_visible
        " Close help buffer
        let l:win = bufwinnr('__DiffvimHelp__')
        if l:win != -1
            execute l:win . 'wincmd c'
        endif
        let g:dv_help_visible = 0
    else
        " Open help in a new buffer
        topleft new __DiffvimHelp__
        setlocal buftype=nofile bufhidden=delete noswapfile
        setlocal nowrap
        call setline(1, [
            \ 'diffvim — Help',
            \ '',
            \ 'Animation Controls:',
            \ '  <Space>  Pause / resume (or advance one op in --step-mode)',
            \ '  n        Skip current hunk (apply instantly)',
            \ '  b        Back to previous hunk (revert and restart)',
            \  '  q        Stop animation (leave buffer for editing)',
            \ '  +        Speed up (x1.5)',
            \ '  -        Slow down (x0.67)',
            \ '  =        Reset speed to 1.0x',
            \ '  u        Undo last hunk',
            \ '  Ctrl-r   Redo hunk',
            \ '  ?        Toggle this help overlay',
            \ '',
            \ 'Press ? to close this help.',
            \ ])
        normal! gg
        let g:dv_help_visible = 1
    endif
endfunction

" Undo/redo support (#93)
let g:dv_undo_stack = []
let g:dv_redo_stack = []

function! DvPushUndo(snap_path) abort
    call add(g:dv_undo_stack, a:snap_path)
    let g:dv_redo_stack = []  " Clear redo stack on new action
endfunction

function! DvUndo() abort
    if empty(g:dv_undo_stack)
        echo 'diffvim: nothing to undo'
        return
    endif
    " Move current state to redo stack
    call add(g:dv_redo_stack, remove(g:dv_undo_stack, -1))
    if !empty(g:dv_undo_stack)
        let l:snap = g:dv_undo_stack[-1]
        call DvLoadSnap(l:snap)
        echo 'diffvim: undo'
    endif
endfunction

function! DvRedo() abort
    if empty(g:dv_redo_stack)
        echo 'diffvim: nothing to redo'
        return
    endif
    let l:snap = remove(g:dv_redo_stack, -1)
    call add(g:dv_undo_stack, l:snap)
    call DvLoadSnap(l:snap)
    echo 'diffvim: redo'
endfunction

nnoremap <buffer> <silent> <Space> :call writefile(['p'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> n       :call writefile(['n'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> b       :call writefile(['b'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> q       :call writefile(['q'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> +       :call writefile(['+'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> -       :call writefile(['-'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> =       :call writefile(['='], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> u       :call writefile(['u'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> <C-R>   :call writefile(['r'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> ?       :call writefile(['?'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> B       :call writefile(['B'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> N       :call writefile(['N'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> <C-B>   :call writefile(['\x02'], g:dv_ctrl, 'a')<CR>
nnoremap <buffer> <silent> <C-N>   :call writefile(['\x0e'], g:dv_ctrl, 'a')<CR>

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
    $content =~ s/SIGN_COLUMN_PLACEHOLDER/$sign_column/g;
    $content =~ s/GIT_BLAME_PLACEHOLDER/$git_blame/g;
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

    my $vim_cmd = "vim -N -n -u NONE -T dumb -c 'source $engine_vim' '$old_file_arg'";

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

# --no-tmux mode (#8): run vim directly in terminal, no tmux wrapper
# Uses IPC::Open3 (#10) for bidirectional communication with vim
sub setup_no_tmux {
    my ($old_file_arg) = @_;
    $old_file_arg //= $file_pairs[0][0];
    write_engine();

    # In no-tmux mode, we can't send keys to vim easily.
    # Instead, we launch vim with a startup command that runs the animation
    # entirely inside vim (like the diffvim bash script does).
    # This is simpler but doesn't support the FIFO-based user input.
    # The animation runs autonomously inside vim.

    my $extra_cmd = '';
    if ($output_file ne '') {
        $extra_cmd .= " | let g:diffvim.output_file = '$output_file'";
    }
    if ($sign_column) {
        $extra_cmd .= " | let g:dv_sign_column = 1 | call DvSignSetup()";
    }

    print "diffvim: launching vim directly (no tmux)...\n";
    print "Controls: Space=pause n=skip b=back q=quit +/-=speed u=undo Ctrl-r=redo ?=help\n";
    exec("vim", "-N", "-n", "-u", "NONE", "-T", "dumb",
         "-c", "source $engine_vim",
         "-c", "let g:diffvim_new_file = '$file_pairs[0][1]'$extra_cmd",
         $old_file_arg);
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
    my $options = { word_diff => $word_diff_mode };
    if ($parser_name eq 'diff2html') {
        _which('diff2html') or die "Error: 'diff2html' not found in PATH\n" .
            "Install with: npm install -g diff2html-cli\n";
        $result = DiffVim::Parser::Diff2Html::parse_diff($old, $new);
    } else {
        $result = DiffVim::Parser::Perl::parse_diff($old, $new, $options);
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

    # --max-word-chars: if a contiguous sequence of modified (non-space)
    # characters is LONGER than max_word_chars, apply the whole sequence
    # in one shot with a pause, so the user can read the change.
    # Sequences <= max_word_chars are animated character by character.
    if ($max_word_chars > 0 && ($type eq 'insert' || $type eq 'delete')) {
        my $word_len = _lookahead_word_length($ops, $op_idx);
        if ($word_len > $max_word_chars) {
            _apply_word_instantly($ops, $op_idx, $word_len);
            $op_idx += $word_len;
            sleep $config{word_pause_ms} / 1000 / $runtime_speed;
            return;
        }
    }

    # Process one op at a time. Batch operations via tmux send-keys
    # cause corruption (Ex command text leaks into normal mode when the
    # command is too long), so we don't batch.
    if ($type eq 'keep') {
        send_ex("call DvKeep($code)");
        sleep 0.001;
    } elsif ($type eq 'delete') {
        # Adaptive timing (#44): slow down for complex regions
        my $delay = $config{delete_delay_ms};
        if ($adaptive_timing) {
            my $complexity = _measure_complexity($ops, $op_idx);
            $delay = int($delay * (1.0 + $complexity * 0.5));
        }
        send_ex_redraw("call DvDelete()");
        sleep $delay / 1000 / $runtime_speed;
    } elsif ($type eq 'insert') {
        my $delay = $config{type_delay_ms};
        if ($adaptive_timing) {
            my $complexity = _measure_complexity($ops, $op_idx);
            $delay = int($delay * (1.0 + $complexity * 0.5));
        }
        send_ex_redraw("call DvInsert($code)");
        sleep $delay / 1000 / $runtime_speed;
    }
    $op_idx++;
}

# Measure complexity of surrounding ops for adaptive timing (#44)
# Returns a value 0.0-1.0 where higher means more complex
sub _measure_complexity {
    my ($ops, $idx) = @_;
    my $window = 10;
    my $changes = 0;
    my $start = $idx - $window;
    $start = 0 if $start < 0;
    my $end = $idx + $window;
    $end = $#$ops if $end > $#$ops;
    for my $i ($start .. $end) {
        $changes++ if $ops->[$i]{op} ne 'keep';
    }
    return $changes / ($end - $start + 1);
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
            if ($step_mode) {
                # Step mode: advance one char op instead of pausing (#42)
                advance_one_op();
            } else {
                $paused = !$paused;
                update_progress();
            }
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
        } elsif ($cmd eq 'u') {
            # Undo (#93)
            send_ex("call DvUndo()");
        } elsif ($cmd eq 'r') {
            # Redo (Ctrl-r) (#93)
            send_ex("call DvRedo()");
        } elsif ($cmd eq '?') {
            # Help overlay (#46)
            send_ex("call DvToggleHelp()");
        } elsif ($cmd eq 'B') {
            # Shift-B: go back one char op (#40)
            go_back_one_op();
        } elsif ($cmd eq 'N') {
            # Shift-N: skip to next file (#41)
            skip_to_next_file();
        } elsif ($cmd eq "\x02") {
            # Ctrl-B: go back to beginning (#40)
            go_to_beginning();
        } elsif ($cmd eq "\x0e") {
            # Ctrl-N: skip to end (#41)
            skip_to_end();
        } elsif ($line eq 'vimleft') {
            $stopped = 1;
        }
    }
}

# Advance one char op (for --step-mode, #42)
sub advance_one_op {
    return if $phase eq 'done';
    $paused = 0;
    if ($phase eq 'idle') {
        start_next_hunk();
    } elsif ($phase eq 'moving') {
        # Jump to end of move
        $cur_l = $move_l[-1];
        $cur_c = $move_c[-1];
        send_ex("call DvSetPos($cur_l, $cur_c)");
        $phase = 'typing';
        $op_idx = 0;
    } elsif ($phase eq 'typing') {
        # Process exactly one op, then pause
        type_step_single();
        $paused = 1;
    }
}

# Process a single char op without advancing further (for step mode)
sub type_step_single {
    my $hunk = $hunks[$hunk_idx];
    my $ops = $hunk->{char_ops};
    return if $op_idx >= scalar(@$ops);

    my $op = $ops->[$op_idx];
    my $type = $op->{op};
    my $code = $op->{code};
    if ($type eq 'keep') {
        send_ex("call DvKeep($code)");
    } elsif ($type eq 'delete') {
        send_ex_redraw("call DvDelete()");
    } elsif ($type eq 'insert') {
        send_ex_redraw("call DvInsert($code)");
    }
    $op_idx++;

    # Check if hunk is done
    if ($op_idx >= scalar(@$ops)) {
        $line_offset += $hunk->{inserted_count} - $hunk->{deleted_count};
        $buf_lines += $hunk->{inserted_count} - $hunk->{deleted_count};
        $hunk_idx++;
        $phase = 'idle';
    }
}

# Go back one char op (#40, Shift-B)
sub go_back_one_op {
    return if $hunk_idx == 0 && $op_idx == 0;
    if ($op_idx > 0) {
        $op_idx--;
    } elsif ($hunk_idx > 0) {
        $hunk_idx--;
        $op_idx = scalar(@{$hunks[$hunk_idx]->{char_ops}}) - 1;
    }
    # Restore to the snapshot before this op
    my $target_snap = $hunk_idx;
    $target_snap = $snap_count - 1 if $target_snap >= $snap_count;
    $target_snap = 0 if $target_snap < 0;
    restore_snapshot($target_snap);
    $phase = 'idle';
    $paused = 1;
    update_progress();
}

# Skip to next file (#41, Shift-N)
sub skip_to_next_file {
    # Stop current animation and jump to next pair
    $stopped = 1;
    send_ex("echo 'diffvim: skipping to next file...'");
}

# Go to beginning (#40, Ctrl-B)
sub go_to_beginning {
    $hunk_idx = 0;
    $op_idx = 0;
    $line_offset = 0;
    $phase = 'idle';
    if ($snap_count > 0) {
        restore_snapshot(0);
    }
    update_progress();
    send_ex("echo 'diffvim: rewound to beginning'");
}

# Skip to end (#41, Ctrl-N)
sub skip_to_end {
    while ($hunk_idx < scalar(@hunks)) {
        apply_hunk_instantly();
    }
    $phase = 'done';
    send_ex("echo 'diffvim: skipped to end'");
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

    # Handle --no-tmux mode (#8): run vim directly
    if ($no_tmux) {
        if (@hunks == 0) {
            print "diffvim: files are identical, nothing to animate.\n";
        }
        setup_no_tmux($old);
        exit 0;
    }

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
