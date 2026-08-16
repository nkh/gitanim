#!/usr/bin/env perl
# test_pacing.pl - Test the --pacing unified timing selector.
#
# --pacing replaces:
#   --adaptive / --adaptive-timing
#   --gaussian-jitter
#   --pause-after-lines / --pause-after-threshold

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

# Test 1: --help mentions --pacing
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --pacing', $help =~ /--pacing/);
ok('--help lists all 4 modes', $help =~ /uniform.*adaptive.*gaussian.*review/s);

# Test 2: All 4 modes are accepted
for my $mode (qw(uniform adaptive gaussian review)) {
    my $out = `$DIFFVIM --pacing $mode --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
    ok("--pacing $mode accepted", $out =~ /---/);
}

# Test 3: Invalid mode is rejected
my $bad = `$DIFFVIM --pacing invalid examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--pacing invalid rejected', $bad =~ /invalid --pacing value/);

# Test 4: Old flags still work (backwards compat)
my $out_old_adapt = `$DIFFVIM --adaptive --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--adaptive still works', $out_old_adapt =~ /---/);

my $out_old_at = `$DIFFVIM --adaptive-timing --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--adaptive-timing still works', $out_old_at =~ /---/);

my $out_old_gj = `$DIFFVIM --gaussian-jitter --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--gaussian-jitter still works', $out_old_gj =~ /---/);

my $out_old_pal = `$DIFFVIM --pause-after-lines 5 --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--pause-after-lines still works', $out_old_pal =~ /---/);

# Test 5: Env var works
$ENV{DIFFVIM_PACING} = 'adaptive';
my $out_env = `$DIFFVIM --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('DIFFVIM_PACING env var works', $out_env =~ /---/);
delete $ENV{DIFFVIM_PACING};

# Test 6: --pacing combines with --delete-pacing and --insert-pacing
my $out_combo = `$DIFFVIM --pacing review --delete-pacing word --insert-pacing word --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--pacing combines with --delete-pacing and --insert-pacing', $out_combo =~ /---/);

# Test 7: --pacing combines with --op-order
my $out_combo2 = `$DIFFVIM --pacing adaptive --op-order end-first-smart --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--pacing combines with --op-order', $out_combo2 =~ /---/);

# Test 8: --pacing gaussian + --pacing adaptive (last one wins via env)
# Actually, --pacing can only be set once. Test that it works with --speed
my $out_combo3 = `$DIFFVIM --pacing gaussian --speed 2 --dry-run examples/01_small_python/old.py examples/01_small_python/new.py 2>&1`;
ok('--pacing gaussian combines with --speed', $out_combo3 =~ /---/);

# Test 9: All 4 pacings produce correct output on multiple examples
for my $ex (qw(01_small_python 02_large_python 08_rust_code)) {
    my $old = `ls examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    for my $mode (qw(uniform adaptive gaussian review)) {
        my $out = `$DIFFVIM --pacing $mode --dry-run $old $new 2>&1`;
        ok("--pacing $mode produces diff for $ex", $out =~ /---/);
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
