#!/usr/bin/env perl
# test_delete_pacing.pl - Test the --delete-pacing unified selector.
#
# --delete-pacing replaces:
#   --rapid-eol-delete / --no-rapid-eol-delete
#   --rapid-identical-chars
#   --accel-delete
#   --adaptive-word-delete
#
# Also tests --delete-speed and --delete-threshold.

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

# Test 1: --help mentions --delete-pacing
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --delete-pacing', $help =~ /--delete-pacing/);
ok('--help lists all 6 modes', $help =~ /char.*rapid-eol.*rapid-identical.*accel.*word.*instant/s);
ok('--help shows --delete-speed', $help =~ /--delete-speed/);
ok('--help shows --delete-threshold', $help =~ /--delete-threshold/);

# Test 2: All 6 modes are accepted
for my $mode (qw(char rapid-eol rapid-identical accel word instant)) {
    my $out = `$DIFFVIM --delete-pacing $mode --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--delete-pacing $mode accepted", $out =~ /---/);
}

# Test 3: Invalid mode is rejected
my $bad = `$DIFFVIM --delete-pacing invalid tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-pacing invalid rejected', $bad =~ /invalid --delete-pacing value/);

# Test 4: All 4 speeds are accepted
for my $speed (qw(slow normal fast instant)) {
    my $out = `$DIFFVIM --delete-speed $speed --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--delete-speed $speed accepted", $out =~ /---/);
}

# Test 5: Invalid speed is rejected
my $bad_speed = `$DIFFVIM --delete-speed invalid tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-speed invalid rejected', $bad_speed =~ /invalid --delete-speed value/);

# Test 6: --delete-threshold accepts a number
my $out_thr = `$DIFFVIM --delete-threshold 5 --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-threshold accepted', $out_thr =~ /---/);

# Test 7: Old flags are rejected (removed)
my $out_old_reol = `$DIFFVIM --rapid-eol-delete tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--rapid-eol-delete rejected', $out_old_reol =~ /Unknown option: --rapid-eol-delete/);

my $out_old_accel = `$DIFFVIM --accel-delete tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--accel-delete rejected', $out_old_accel =~ /Unknown option: --accel-delete/);

my $out_old_awd = `$DIFFVIM --adaptive-word-delete tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--adaptive-word-delete rejected', $out_old_awd =~ /Unknown option: --adaptive-word-delete/);

my $out_old_ric = `$DIFFVIM --rapid-identical-chars tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--rapid-identical-chars rejected', $out_old_ric =~ /Unknown option: --rapid-identical-chars/);

# Test 8: Env vars work
$ENV{AD_DELETE_PACING} = 'word';
my $out_env = `$DIFFVIM --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('AD_DELETE_PACING env var works', $out_env =~ /---/);
delete $ENV{AD_DELETE_PACING};

$ENV{AD_DELETE_SPEED} = 'fast';
my $out_env_sp = `$DIFFVIM --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('AD_DELETE_SPEED env var works', $out_env_sp =~ /---/);
delete $ENV{AD_DELETE_SPEED};

# Test 9: --delete-pacing combines with --op-order
my $out_combo = `$DIFFVIM --delete-pacing word --op-order end-first-smart --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-pacing combines with --op-order', $out_combo =~ /---/);

# Test 10: --delete-pacing instant + --delete-speed fast combine
my $out_combo2 = `$DIFFVIM --delete-pacing instant --delete-speed fast --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-pacing instant + --delete-speed fast combine', $out_combo2 =~ /---/);

# Test 11: --delete-pacing char disables rapid-eol (verify via correctness)
# Run the correctness test on multiple examples to make sure output is still correct
for my $ex (qw(01_small_python 02_large_python 08_rust_code)) {
    my $old = `ls tests/examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls tests/examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    my $out = `$DIFFVIM --delete-pacing char --dry-run $old $new 2>&1`;
    ok("--delete-pacing char produces diff for $ex", $out =~ /---/);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
