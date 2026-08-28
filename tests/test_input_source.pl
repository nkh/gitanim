#!/usr/bin/env perl
# test_input_source.pl - Test the input source options.
#
# Verifies that --from, --to, --auto-precompute, --compute-tool are
# removed from the bash diffvim, and that --git-rev still works.

use strict;
use warnings;
use Time::HiRes qw(alarm);

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

sub run_with_timeout {
    my ($cmd, $timeout) = @_;
    $timeout //= 5;
    my $output = '';
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $timeout;
        $output = `$cmd 2>&1`;
        alarm 0;
    };
    if ($@ && $@ eq "timeout\n") {
        return "<TIMEOUT>";
    }
    return $output;
}

my $DIFFVIM = './diffvim';

# Test 1: --help no longer mentions --from, --to, --auto-precompute, --compute-tool
my $help = run_with_timeout("$DIFFVIM -h", 3);
ok('--help does NOT show --from', $help !~ /--from /);
ok('--help does NOT show --to ', $help !~ /--to /);
ok('--help does NOT show --auto-precompute', $help !~ /--auto-precompute/);
ok('--help does NOT show --compute-tool', $help !~ /--compute-tool/);

# Test 2: --from is rejected as unknown option
my $out_from = run_with_timeout("$DIFFVIM --from HEAD~3 tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py", 3);
ok('--from rejected as unknown', $out_from =~ /Unknown option: --from/);

# Test 3: --to is rejected as unknown option
my $out_to = run_with_timeout("$DIFFVIM --to HEAD tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py", 3);
ok('--to rejected as unknown', $out_to =~ /Unknown option: --to/);

# Test 4: --auto-precompute is rejected as unknown option
my $out_ap = run_with_timeout("$DIFFVIM --auto-precompute tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py", 3);
ok('--auto-precompute rejected as unknown', $out_ap =~ /Unknown option: --auto-precompute/);

# Test 5: --compute-tool is rejected as unknown option
my $out_ct = run_with_timeout("$DIFFVIM --compute-tool c tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py", 3);
ok('--compute-tool rejected as unknown', $out_ct =~ /Unknown option: --compute-tool/);

# Test 6: --git-rev is parsed (not "Unknown option")
# Use --dry-run to avoid actually running git
my $out_gr = run_with_timeout("$DIFFVIM --git-rev HEAD~1..HEAD --dry-run tests/tests/examples/01_small_python/old.py", 5);
ok('--git-rev is accepted (not "Unknown option")', $out_gr !~ /Unknown option: --git-rev/);

# Test 7: --replay is parsed (not "Unknown option")
my $out_replay = run_with_timeout("$DIFFVIM --replay --dry-run tests/tests/examples/01_small_python/old.py", 5);
ok('--replay is accepted (not "Unknown option")', $out_replay !~ /Unknown option: --replay/);

# Test 8: --precomputed still works (kept)
my $out_pc = run_with_timeout("$DIFFVIM --precomputed /tmp/nonexistent.diff --dry-run tests/tests/examples/01_small_python/old.py tests/tests/examples/01_small_python/new.py", 3);
ok('--precomputed is accepted (not "Unknown option")', $out_pc !~ /Unknown option: --precomputed/);

# Test 9: --multi still works (kept)
my $out_multi = run_with_timeout("$DIFFVIM --multi --dry-run tests/tests/examples/01_small_python/old.py:tests/tests/examples/01_small_python/new.py", 3);
ok('--multi is accepted', $out_multi =~ /---/ || $out_multi !~ /Unknown option/);

# Test 10: Short options -r and -R still work
my $out_r = run_with_timeout("$DIFFVIM -r --dry-run tests/tests/examples/01_small_python/old.py", 5);
ok('-r is accepted (not "Unknown option")', $out_r !~ /Unknown option: -r/);

my $out_R = run_with_timeout("$DIFFVIM -R HEAD~1..HEAD --dry-run tests/tests/examples/01_small_python/old.py", 5);
ok('-R is accepted (not "Unknown option")', $out_R !~ /Unknown option: -R/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
