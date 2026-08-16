#!/usr/bin/env perl
# test_tool.pl - Test the --tool option for external compute tools.

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

# Test 1: --help mentions --tool
my $help = run_with_timeout("$DIFFVIM -h", 3);
ok('--help shows --tool', $help =~ /--tool/);
ok('--help lists all 4 tools', $help =~ /c.*cpp.*rust.*go/);

# Test 2: All 4 tools are accepted (use --dry-run to avoid launching vim)
for my $tool (qw(c cpp rust go)) {
    my $out = run_with_timeout("$DIFFVIM --tool $tool --dry-run examples/01_small_python/old.py examples/01_small_python/new.py", 5);
    ok("--tool $tool accepted", $out =~ /---/ || $out =~ /dry-run/);
}

# Test 3: Invalid tool is rejected
my $bad = run_with_timeout("$DIFFVIM --tool invalid examples/01_small_python/old.py examples/01_small_python/new.py", 3);
ok('--tool invalid rejected', $bad =~ /invalid --tool value/);
ok('--tool invalid shows valid options', $bad =~ /c.*cpp.*rust.*go/);

# Test 4: --tool works with other options
my $out_combo = run_with_timeout("$DIFFVIM --tool rust --op-order optimize --dry-run examples/01_small_python/old.py examples/01_small_python/new.py", 5);
ok('--tool combines with --op-order', $out_combo =~ /---/ || $out_combo =~ /dry-run/);

# Test 5: --tool works with --delete-pacing
my $out_combo2 = run_with_timeout("$DIFFVIM --tool c --delete-pacing word --dry-run examples/01_small_python/old.py examples/01_small_python/new.py", 5);
ok('--tool combines with --delete-pacing', $out_combo2 =~ /---/ || $out_combo2 =~ /dry-run/);

# Test 6: --tool works with --highlight
my $out_combo3 = run_with_timeout("$DIFFVIM --tool rust --highlight inline --dry-run examples/01_small_python/old.py examples/01_small_python/new.py", 5);
ok('--tool combines with --highlight', $out_combo3 =~ /---/ || $out_combo3 =~ /dry-run/);

# Test 7: --tool works with --preset
my $out_combo4 = run_with_timeout("$DIFFVIM --tool c --preset review --dry-run examples/01_small_python/old.py examples/01_small_python/new.py", 5);
ok('--tool combines with --preset', $out_combo4 =~ /---/ || $out_combo4 =~ /dry-run/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
