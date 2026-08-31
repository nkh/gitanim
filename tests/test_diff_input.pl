#!/usr/bin/env perl
# test_diff_input.pl - Test --diff flag (unified diff input)
# Tests that ad_vim.pl can accept a .diff/.patch file or stdin as input.

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

# Create a test diff file
my $diff_content = `diff -u tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>/dev/null`;
open my $fh, '>', '/tmp/dv_test_diff.patch';
print $fh $diff_content;
close $fh;

# Test 1: --diff FILE produces output
my $out = `perl ad_vim.pl --diff /tmp/dv_test_diff.patch --dry-run 2>&1`;
ok('--diff FILE produces dry-run output', $out =~ /Dry run/);
ok('--diff FILE finds the correct hunk', $out =~ /Hunks: 1/);
ok('--diff FILE finds the correct target_line', $out =~ /target_line=2/);

# Test 2: --diff - (stdin)
$out = `cat /tmp/dv_test_diff.patch | perl ad_vim.pl --diff - --dry-run 2>&1`;
ok('--diff - (stdin) produces output', $out =~ /Dry run/);
ok('--diff - (stdin) finds the hunk', $out =~ /Hunks: 1/);

# Test 3: --diff with git-style diff (a/ b/ prefixes)
my $git_diff = `diff -u --label a/tests/examples/01_small_python/old.py --label b/tests/examples/01_small_python/new.py tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>/dev/null`;
open $fh, '>', '/tmp/dv_test_git.patch';
print $fh $git_diff;
close $fh;

$out = `perl ad_vim.pl --diff /tmp/dv_test_git.patch --dry-run 2>&1`;
ok('--diff with git-style a/b prefixes works', $out =~ /Dry run/ && $out =~ /Hunks: 1/);

# Test 4: --diff with invalid file
$out = `perl ad_vim.pl --diff /nonexistent.patch --dry-run 2>&1`;
ok('--diff with missing file errors gracefully', $out =~ /Error|cannot read/i);

# Test 5: --diff with empty diff
open $fh, '>', '/tmp/dv_empty.patch';
print $fh '';
close $fh;
$out = `perl ad_vim.pl --diff /tmp/dv_empty.patch --dry-run 2>&1`;
ok('--diff with empty diff errors gracefully', $out =~ /Error|no file pairs/i);

# Test 6: --help shows --diff
$out = `perl ad_vim.pl --help 2>&1`;
ok('--help shows --diff option', $out =~ /--diff/);

# Cleanup
unlink '/tmp/dv_test_diff.patch', '/tmp/dv_test_git.patch', '/tmp/dv_empty.patch';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
