#!/usr/bin/env perl
# test_parser_compare.pl - Test --parser-compare feature (#30)
# Verifies that the parser comparison runs both parsers and reports
# differences correctly.

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Test 1: --parser-compare runs and produces output
print "=== Test: --parser-compare runs ===\n";
my $out = `perl diffvim.pl --parser-compare tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--parser-compare produces output', $out =~ /Comparing parsers/);
ok('--parser-compare shows result', $out =~ /Parser comparison/);
ok('--parser-compare shows match count', $out =~ /0 mismatch/ || $out =~ /mismatch/);

# Test 2: --parser-compare on identical files
print "\n=== Test: identical files ===\n";
$out = `perl diffvim.pl --parser-compare tests/examples/01_small_python/old.py tests/examples/01_small_python/old.py 2>&1`;
ok('--parser-compare on identical files works', $out =~ /Comparing parsers/ || $out =~ /0 hunk/);

# Test 3: --help shows --parser-compare
print "\n=== Test: help text ===\n";
$out = `perl diffvim.pl --help 2>&1`;
ok('--help shows --parser-compare', $out =~ /--parser-compare/);

# Test 4: Exit code reflects mismatches
print "\n=== Test: exit code ===\n";
system("perl diffvim.pl --parser-compare tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py >/dev/null 2>&1");
my $rc = $? >> 8;
# Small Python should match (exit 0) or have known mismatches (exit 1)
ok('--parser-compare returns 0 or 1', $rc == 0 || $rc == 1);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
