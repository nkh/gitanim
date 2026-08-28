#!/usr/bin/env perl
# test_highlight.pl - Test the --highlight unified selector.
#
# --highlight replaces:
#   --highlight-word
#   --highlight-hunk
#   --highlight-inline

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

# Test 1: --help mentions --highlight
my $help = `$DIFFVIM -h 2>&1`;
ok('--help shows --highlight', $help =~ /--highlight MODE/);
ok('--help lists all 4 modes', $help =~ /none.*inline.*word.*hunk/s);

# Test 2: All 4 modes are accepted
for my $mode (qw(none inline word hunk)) {
    my $out = `$DIFFVIM --highlight $mode --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
    ok("--highlight $mode accepted", $out =~ /---/);
}

# Test 3: Invalid mode is rejected
my $bad = `$DIFFVIM --highlight invalid tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight invalid rejected', $bad =~ /invalid --highlight value/);

# Test 4: Old flags are rejected (removed)
my $out_old_hw = `$DIFFVIM --highlight-word tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight-word rejected', $out_old_hw =~ /Unknown option: --highlight-word/);

my $out_old_hh = `$DIFFVIM --highlight-hunk tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight-hunk rejected', $out_old_hh =~ /Unknown option: --highlight-hunk/);

my $out_old_hi = `$DIFFVIM --highlight-inline tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight-inline rejected', $out_old_hi =~ /Unknown option: --highlight-inline/);

# Test 5: Short options -W, -H, -I are rejected (removed)
my $out_short_w = `$DIFFVIM -W tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('-W rejected', $out_short_w =~ /Unknown option: -W/);

my $out_short_h = `$DIFFVIM -H tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('-H rejected', $out_short_h =~ /Unknown option: -H/);

my $out_short_i = `$DIFFVIM -I tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('-I rejected', $out_short_i =~ /Unknown option: -I/);

# Test 6: Env var works
$ENV{AD_HIGHLIGHT} = 'word';
my $out_env = `$DIFFVIM --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('AD_HIGHLIGHT env var works', $out_env =~ /---/);
delete $ENV{AD_HIGHLIGHT};

# Test 7: --highlight combines with --pacing
my $out_combo = `$DIFFVIM --highlight inline --pacing gaussian --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight combines with --pacing', $out_combo =~ /---/);

# Test 8: --highlight combines with --op-order and --delete-pacing
my $out_combo2 = `$DIFFVIM --highlight hunk --op-order end-first-smart --delete-pacing word --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight combines with --op-order and --delete-pacing', $out_combo2 =~ /---/);

# Test 9: --highlight combines with --dim-unchanged and --sign-column
my $out_combo3 = `$DIFFVIM --highlight word --dim-unchanged --sign-column --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight combines with --dim-unchanged and --sign-column', $out_combo3 =~ /---/);

# Test 10: All 4 highlight modes produce correct output on multiple examples
for my $ex (qw(01_small_python 02_large_python 06_typescript)) {
    my $old = `ls tests/tests/examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls tests/tests/examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    for my $mode (qw(none inline word hunk)) {
        my $out = `$DIFFVIM --highlight $mode --dry-run $old $new 2>&1`;
        ok("--highlight $mode produces diff for $ex", $out =~ /---/);
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
