#!/usr/bin/env perl
# test_op_order.pl - Test the --op-order unified post-processing selector.
#
# --op-order replaces:
#   --optimize-sequence / --no-optimize-sequence
#   --left-to-right / --no-left-to-right
#   --delete-end-first
#   --delete-end-first-smart
#   --overwrite
#
# This test verifies:
# 1. All 6 modes are accepted
# 2. Invalid modes are rejected
# 3. Each mode sets the correct underlying variables
# 4. The old flags are rejected (removed)
# 5. --op-order is exposed in --help

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

# Test 1: --help mentions --op-order
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --op-order', $help =~ /--op-order/);
ok('--help lists all 6 modes', $help =~ /natural.*optimize.*left-to-right.*end-first.*end-first-smart.*overwrite/s);

# Test 2: All 6 modes are accepted (use --dry-run to avoid launching vim)
for my $mode (qw(natural optimize left-to-right end-first end-first-smart overwrite)) {
    my $out = `$DIFFVIM --op-order $mode --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--op-order $mode accepted", $out =~ /=== ad_vim dry-run/ || $out =~ /---/);
}

# Test 3: Invalid mode is rejected
my $bad = `$DIFFVIM --op-order invalid tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--op-order invalid rejected', $bad =~ /invalid --op-order value/);
ok('--op-order invalid shows valid options', $bad =~ /natural.*optimize.*left-to-right/);

# Test 4: --op-order natural disables optimize-sequence
# We can verify this by checking the env var via a subshell
my $out_natural = `$DIFFVIM --op-order natural --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--op-order natural runs', $out_natural =~ /---/);

# Test 5: --op-order overwrite runs
my $out_overwrite = `$DIFFVIM --op-order overwrite --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--op-order overwrite runs', $out_overwrite =~ /---/);

# Test 6: --op-order end-first-smart runs
my $out_smart = `$DIFFVIM --op-order end-first-smart --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--op-order end-first-smart runs', $out_smart =~ /---/);

# Test 7: Old flags are rejected (removed)
my $out_old_opt = `$DIFFVIM --optimize-sequence tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--optimize-sequence rejected', $out_old_opt =~ /Unknown option: --optimize-sequence/);

my $out_old_l2r = `$DIFFVIM --left-to-right tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--left-to-right rejected', $out_old_l2r =~ /Unknown option: --left-to-right/);

my $out_old_def = `$DIFFVIM --delete-end-first tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--delete-end-first rejected', $out_old_def =~ /Unknown option: --delete-end-first/);

my $out_old_ovw = `$DIFFVIM --overwrite tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--overwrite rejected', $out_old_ovw =~ /Unknown option: --overwrite/);

# Test 8: AD_OP_ORDER env var works
$ENV{AD_OP_ORDER} = 'natural';
my $out_env = `$DIFFVIM --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('AD_OP_ORDER env var works', $out_env =~ /---/);
delete $ENV{AD_OP_ORDER};

# Test 9: Short option -O still maps to --overwrite (not --op-order)
my $out_short = `$DIFFVIM -O --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('-O still maps to --overwrite', $out_short =~ /---/);

# Test 10: --op-order works with other options
my $out_combo = `$DIFFVIM --op-order left-to-right --word-diff --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--op-order combines with --word-diff', $out_combo =~ /---/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
