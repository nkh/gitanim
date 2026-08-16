#!/usr/bin/env perl
# test_insert_pacing.pl - Test the --insert-pacing unified selector.
#
# --insert-pacing replaces:
#   --max-word-chars (type short words instantly)
#   --word-accel (accelerate char-by-char inserts)
#
# Also tests --insert-speed.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

my $DIFFVIM = './diffvim';

# Test 1: --help mentions --insert-pacing
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --insert-pacing', $help =~ /--insert-pacing/);
ok('--help lists all 3 modes', $help =~ /char.*word.*accel/s);
ok('--help shows --insert-speed', $help =~ /--insert-speed/);

# Test 2: All 3 modes are accepted
for my $mode (qw(char word accel)) {
    my $out = `$DIFFVIM --insert-pacing $mode --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
    ok("--insert-pacing $mode accepted", $out =~ /---/);
}

# Test 3: Invalid mode is rejected
my $bad = `$DIFFVIM --insert-pacing invalid examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-pacing invalid rejected', $bad =~ /invalid --insert-pacing value/);

# Test 4: All 3 speeds are accepted
for my $speed (qw(slow normal fast)) {
    my $out = `$DIFFVIM --insert-speed $speed --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
    ok("--insert-speed $speed accepted", $out =~ /---/);
}

# Test 5: Invalid speed is rejected
my $bad_speed = `$DIFFVIM --insert-speed invalid examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-speed invalid rejected', $bad_speed =~ /invalid --insert-speed value/);

# Test 6: Old flags are rejected (removed)
my $out_old_mwc = `$DIFFVIM --max-word-chars 5 examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--max-word-chars rejected', $out_old_mwc =~ /Unknown option: --max-word-chars/);

my $out_old_wpm = `$DIFFVIM --word-pause-ms 200 examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--word-pause-ms rejected', $out_old_wpm =~ /Unknown option: --word-pause-ms/);

my $out_old_wa = `$DIFFVIM --word-accel examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--word-accel rejected', $out_old_wa =~ /Unknown option: --word-accel/);

# Test 7: Env vars work
$ENV{DIFFVIM_INSERT_PACING} = 'word';
my $out_env = `$DIFFVIM --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('DIFFVIM_INSERT_PACING env var works', $out_env =~ /---/);
delete $ENV{DIFFVIM_INSERT_PACING};

$ENV{DIFFVIM_INSERT_SPEED} = 'fast';
my $out_env_sp = `$DIFFVIM --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('DIFFVIM_INSERT_SPEED env var works', $out_env_sp =~ /---/);
delete $ENV{DIFFVIM_INSERT_SPEED};

# Test 8: --insert-pacing combines with --delete-pacing
my $out_combo = `$DIFFVIM --insert-pacing word --delete-pacing word --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-pacing combines with --delete-pacing', $out_combo =~ /---/);

# Test 9: --insert-pacing combines with --op-order
my $out_combo2 = `$DIFFVIM --insert-pacing accel --op-order left-to-right --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-pacing combines with --op-order', $out_combo2 =~ /---/);

# Test 10: --insert-pacing accel + --delete-pacing accel combine
my $out_combo3 = `$DIFFVIM --insert-pacing accel --delete-pacing accel --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-pacing accel + --delete-pacing accel combine', $out_combo3 =~ /---/);

# Test 11: --insert-pacing word + --max-word-chars 3 (explicit override)
my $out_override = `$DIFFVIM --insert-pacing word --max-word-chars 3 --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--insert-pacing word + --max-word-chars 3 (override) works', $out_override =~ /---/);

# Test 12: Correctness on multiple examples
for my $ex (qw(01_small_python 02_large_python 06_typescript)) {
    my $old = `ls examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    my $out = `$DIFFVIM --insert-pacing word --dry-run $old $new 2>&1`;
    ok("--insert-pacing word produces diff for $ex", $out =~ /---/);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
