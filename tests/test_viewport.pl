#!/usr/bin/env perl
# test_viewport.pl - Test the --scroll + --context viewport options.
#
# --fold-unchanged is now an alias for --context 0.

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

# Test 1: --help mentions --context and --scroll
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --context', $help =~ /--context/);
ok('--help shows --scroll', $help =~ /--scroll/);
ok('--help does NOT show --fold-unchanged', $help !~ /--fold-unchanged/);

# Test 2: --context accepts various values
for my $n (0, 1, 3, 5, 10) {
    my $out = `$DIFFVIM --context $n --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--context $n accepted", $out =~ /---/);
}

# Test 3: -c short option works
my $out_short = `$DIFFVIM -c 3 --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('-c 3 works', $out_short =~ /---/);

# Test 4: --scroll accepts all 4 values
for my $mode (qw(zz zt zb none)) {
    my $out = `$DIFFVIM --scroll $mode --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--scroll $mode accepted", $out =~ /---/);
}

# Test 5: --fold-unchanged is rejected (removed, use --context 0)
my $out_fu = `$DIFFVIM --fold-unchanged tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--fold-unchanged rejected', $out_fu =~ /Unknown option: --fold-unchanged/);

# Test 6: -f short option is rejected (removed)
my $out_f = `$DIFFVIM -f tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('-f rejected', $out_f =~ /Unknown option: -f/);

# Test 7: --context 0 works (replaces --fold-unchanged)
my $out_c0 = `$DIFFVIM --context 0 --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--context 0 works', $out_c0 =~ /---/);

# Test 8: Env vars work
$ENV{AD_CONTEXT} = '3';
my $out_env = `$DIFFVIM --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('AD_CONTEXT env var works', $out_env =~ /---/);
delete $ENV{AD_CONTEXT};

# Test 9: --context combines with --scroll
my $out_combo = `$DIFFVIM --context 3 --scroll zz --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--context combines with --scroll', $out_combo =~ /---/);

# Test 10: --context combines with all the new unified options
my $out_combo2 = `$DIFFVIM --context 3 --op-order end-first-smart --delete-pacing word --insert-pacing word --pacing review --highlight hunk --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--context combines with all unified options', $out_combo2 =~ /---/);

# Test 11: Correctness on multiple examples with --context 0
for my $ex (qw(01_small_python 02_large_python 06_typescript)) {
    my $old = `ls tests/examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls tests/examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    my $out = `$DIFFVIM --context 0 --dry-run $old $new 2>&1`;
    ok("--context 0 produces diff for $ex", $out =~ /---/);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
