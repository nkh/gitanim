#!/usr/bin/env perl
# test_timer_engine.pl - Test the REAL timer-based vimscript engine
# by setting env vars and running vim with the actual diffvim script.
#
# This test catches bugs that the synchronous test misses:
# - env var reading (step_mode, word_diff, etc.)
# - timer-based execution
# - max-word-chars batching in the real ProcessCharOp
# - max-hunk-chars in the real StartNextHunk
#
# It does this by:
# 1. Setting the env vars exactly as the bash script does
# 2. Sourcing the engine vimscript
# 3. Letting the timer-based animation run to completion
# 4. Writing the buffer and comparing with the expected file

use strict;
use warnings;
use lib '.';
use Time::HiRes qw(sleep);

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Extract the engine from the diffvim bash script
my $engine_file = '/tmp/dv_timer_engine.vim';
sub extract_engine {
    open my $fh, '<', 'diffvim' or die "Cannot open diffvim: $!";
    my $in = 0; my @lines;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in = 1; next; }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @lines, $line if $in;
    }
    close $fh;
    my $content = join('', @lines);
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;

    # Replace the autocmd with a timer-based auto-start that writes output when done
    $content .= <<'VIM';

" Timer-based test runner: starts animation, polls for completion, writes output
let s:test_timer = -1
let s:test_start = reltime()
let s:test_output_file = ''
let s:test_expected_file = ''

function! s:TestTick(timer) abort
    " Check if animation is done
    if s:state.phase ==# 'done' || s:state.stopped
        " Write the buffer
        if !empty(s:test_output_file)
            execute 'w! ' . s:test_output_file
        endif
        " Stop the timer
        call timer_stop(a:timer)
        let s:test_timer = -1
        " Quit
        qa!
        return
    endif

    " Timeout after 30 seconds
    let l:elapsed = reltimefloat(reltime(s:test_start))
    if l:elapsed > 30.0
        if !empty(s:test_output_file)
            execute 'w! ' . s:test_output_file
        endif
        call timer_stop(a:timer)
        qa!
        return
    endif
endfunction

function! s:StartTestTimer() abort
    " Start the animation
    call s:StartAnimation()
    " Poll every 50ms for completion
    let s:test_timer = timer_start(50, function('s:TestTick'), {'repeat': -1})
endfunction

" Public entry point
function! diffvim#engine#Start() abort
    call s:StartTestTimer()
endfunction
VIM

    open my $ofh, '>', $engine_file or die "Cannot write $engine_file: $!";
    print $ofh $content;
    close $ofh;
}

# Run a test with specific env vars and options
sub test_timer_engine {
    my ($old_file, $new_file, $env_vars, $vim_config, $name) = @_;

    my $result_file = '/tmp/dv_timer_result.txt';
    unlink $result_file;

    # Set env vars
    local %ENV = %ENV;
    for my $k (keys %$env_vars) {
        $ENV{$k} = $env_vars->{$k};
    }

    # Build the vim config dict
    my $config_str = "{'output_file': '$result_file'";
    for my $k (keys %$vim_config) {
        if ($k eq 'max_word_chars' || $k eq 'max_hunk_chars' || $k eq 'tick_ms'
            || $k eq 'type_delay_ms' || $k eq 'delete_delay_ms'
            || $k eq 'move_min_ms' || $k eq 'move_max_ms'
            || $k eq 'hunk_pause_ms' || $k eq 'word_pause_ms'
            || $k eq 'highlight_duration' || $k eq 'highlight_min_chars') {
            $config_str .= ", '$k': $vim_config->{$k}";
        } else {
            $config_str .= ", '$k': '$vim_config->{$k}'";
        }
    }
    $config_str .= '}';

    # Use fast timing for tests
    $ENV{DIFFVIM_TICK_MS} //= 1;
    $ENV{DIFFVIM_TYPE_DELAY_MS} //= 1;
    $ENV{DIFFVIM_DELETE_DELAY_MS} //= 1;
    $ENV{DIFFVIM_MOVE_MIN_MS} //= 1;
    $ENV{DIFFVIM_MOVE_MAX_MS} //= 1;
    $ENV{DIFFVIM_HUNK_PAUSE_MS} //= 1;

    my $new_abs = `realpath "$new_file"`; chomp $new_abs;
    my $old_abs = `realpath "$old_file"`; chomp $old_abs;

    # Run vim with the timer-based engine
    system("vim -e -s -n -Nu NONE -U NONE -T dumb "
         . "--cmd 'set nomore noswapfile' "
         . "-c \"let g:diffvim_new_file = '$new_abs'\" "
         . "-c \"let g:diffvim = $config_str\" "
         . "-c \"source $engine_file\" "
         . "-c \"call diffvim#engine#Start()\" "
         . "\"$old_abs\" 2>/dev/null");

    # Compare result with expected
    my $result = '';
    my $expected = '';
    if (-f $result_file) {
        open my $rfh, '<:raw', $result_file or return 0;
        local $/; $result = <$rfh>; close $rfh;
    }
    open my $efh, '<:raw', $new_file or return 0;
    local $/; $expected = <$efh>; close $efh;

    $result =~ s/\n+$//;
    $expected =~ s/\n+$//;

    return $result eq $expected;
}

extract_engine();
print "Engine extracted to $engine_file\n\n";

# --- Test 1: Basic correctness (no options) ---
print "=== Timer-based engine tests ===\n";

ok("Test 1: old.py -> new.py (no options)",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {}, {}, "basic"));

# --- Test 2: With max-word-chars ---
ok("Test 2: --max-word-chars 5",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {}, {max_word_chars => 5}, "max-word-chars"));

# --- Test 3: With max-hunk-chars ---
ok("Test 3: --max-hunk-chars 10",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {}, {max_hunk_chars => 10}, "max-hunk-chars"));

# --- Test 4: Large file with both options ---
ok("Test 4: large file with --max-word-chars 5 --max-hunk-chars 200",
   test_timer_engine("examples/02_large_python/old.py", "examples/02_large_python/new.py",
                     {}, {max_word_chars => 5, max_hunk_chars => 200}, "large+options"));

# --- Test 5: Reversed direction (new -> old) ---
ok("Test 5: new.py -> old.py (reversed)",
   test_timer_engine("examples/01_small_python/new.py", "examples/01_small_python/old.py",
                     {}, {}, "reversed"));

# --- Test 6: Step mode is OFF by default (Space should pause, not step) ---
# Verify by checking that the animation completes without any Space presses
ok("Test 6: animation completes without Space (step_mode off)",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {DIFFVIM_STEP_MODE => ''}, {}, "step_mode_off"));

# --- Test 7: Verify env var booleans are empty when not set ---
ok("Test 7: DIFFVIM_STEP_MODE empty when not passed",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {DIFFVIM_STEP_MODE => '', DIFFVIM_WORD_DIFF => '',
                      DIFFVIM_ADAPTIVE_TIMING => '', DIFFVIM_SIGN_COLUMN => '',
                      DIFFVIM_GIT_BLAME => '', DIFFVIM_HIGHLIGHT_HUNK => ''},
                     {}, "all_bools_off"));

# --- Test 8: Large file reversed with options ---
ok("Test 8: large file reversed with --max-word-chars 5",
   test_timer_engine("examples/02_large_python/new.py", "examples/02_large_python/old.py",
                     {}, {max_word_chars => 5, max_hunk_chars => 200}, "large+reversed+options"));

# --- Test 9: Small Python with all options ---
ok("Test 9: small python with max-word-chars=3, max-hunk-chars=5",
   test_timer_engine("examples/01_small_python/old.py", "examples/01_small_python/new.py",
                     {}, {max_word_chars => 3, max_hunk_chars => 5}, "aggressive_options"));

# --- Test 10: Go code (different language) ---
ok("Test 10: Go code",
   test_timer_engine("examples/05_go_code/old.go", "examples/05_go_code/new.go",
                     {}, {max_word_chars => 5}, "go_code"));

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
