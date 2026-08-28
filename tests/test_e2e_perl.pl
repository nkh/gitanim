#!/usr/bin/env perl
# Standalone E2E test for diffvim.pl

use strict;
use warnings;
use Time::HiRes qw(sleep);

my $test_dir = "/tmp/dv_perl_e2e";
system("rm -rf $test_dir && mkdir -p $test_dir");

my $old_content = "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n\n# TODO: implement subtract\n";
my $new_content = "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n\ndef subtract(a, b):\n    return a - b\n";

open my $fh, '>', "$test_dir/old.txt"; print $fh $old_content; close $fh;
open $fh, '>', "$test_dir/new.txt"; print $fh $new_content; close $fh;

my $pass = 0;
my $fail = 0;

for my $parser ('perl') {
    print "=" x 50, "\nTesting parser: $parser\n", "=" x 50, "\n";

    # Set fast config
    $ENV{AD_TICK_MS} = 2;
    $ENV{AD_TYPE_DELAY_MS} = 2;
    $ENV{AD_DELETE_DELAY_MS} = 2;
    $ENV{AD_MOVE_MIN_MS} = 10;
    $ENV{AD_MOVE_MAX_MS} = 50;
    $ENV{AD_HUNK_PAUSE_MS} = 5;

    # Start diffvim.pl in background
    my $pid = fork();
    if ($pid == 0) {
        exec("perl /home/z/my-project/download/diffvim.pl --parser $parser '$test_dir/old.txt' '$test_dir/new.txt' 2>/dev/null");
        exit 1;
    }

    sleep 3;

    # Find the session
    my $sessions = `tmux list-sessions 2>/dev/null`;
    my $session;
    for my $line (split /\n/, $sessions) {
        if ($line =~ /^(diffvim-\d+):/) {
            $session = $1;
            last;
        }
    }

    unless ($session) {
        print "FAIL: No diffvim session found for $parser\n";
        kill 'TERM', $pid;
        waitpid($pid, 0);
        $fail++;
        next;
    }

    # Wait for animation to complete
    my $done = 0;
    for (1..120) {
        my $pane = `tmux capture-pane -t '$session' -p 2>/dev/null`;
        if ($pane =~ /animation complete|animation stopped/) {
            $done = 1;
            last;
        }
        sleep 0.5;
    }

    print "Animation done: $done\n";

    # Write buffer
    my $result_file = "$test_dir/result_$parser.txt";
    system("tmux send-keys -t '$session' Escape");
    sleep 0.3;
    system("tmux send-keys -l -t '$session' ':w! $result_file'");
    system("tmux send-keys -t '$session' Enter");
    sleep 1;

    # Capture pane for debugging
    my $pane = `tmux capture-pane -t '$session' -p 2>/dev/null`;
    print "Pane (last 5 lines):\n";
    for my $l (split /\n/, $pane) { print "  |$l\n" if $l =~ /\S/; }
    print "\n";

    # Quit vim
    system("tmux send-keys -t '$session' ':qa!' Enter");
    sleep 0.5;
    system("tmux kill-session -t '$session' 2>/dev/null");
    kill 'TERM', $pid;
    waitpid($pid, 0);

    # Compare
    my $result = '';
    if (-f $result_file) {
        open my $rfh, '<', $result_file or die;
        local $/;
        $result = <$rfh>;
        close $rfh;
    }

    if ($result eq $new_content) {
        print "RESULT ($parser): MATCH\n\n";
        $pass++;
    } else {
        print "RESULT ($parser): MISMATCH\n";
        print "  expected:\n";
        for my $l (split /\n/, $new_content) { print "    |$l\n"; }
        print "  got:\n";
        for my $l (split /\n/, $result) { print "    |$l\n"; }
        print "\n";
        $fail++;
    }
}

# Cleanup
system("rm -rf $test_dir");

print "Results: $pass passed, $fail failed\n";
exit($fail == 0 ? 0 : 1);
