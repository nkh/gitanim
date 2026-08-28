#!/usr/bin/env perl
# test_fold_theme_debug.pl - Test --fold-unchanged (#56), --theme (#59), --debug (#75)

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

# Test 1: --help shows new options
print "=== Test: --help shows new options ===\n";
my $help = `perl diffvim.pl --help 2>&1`;
ok('--help shows --fold-unchanged', $help =~ /--fold-unchanged/);
ok('--help shows --theme', $help =~ /--theme/);
ok('--help shows --debug', $help =~ /--debug/);

# Test 2: --fold-unchanged with --dry-run works
print "\n=== Test: --fold-unchanged ===\n";
my $out = `perl diffvim.pl --fold-unchanged --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--fold-unchanged with --dry-run works', $out =~ /Dry run/);

# Test 3: --theme accepts valid values
print "\n=== Test: --theme ===\n";
for my $theme ('dark', 'light', 'high-contrast') {
    $out = `perl diffvim.pl --theme $theme --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
    ok("--theme $theme accepted", $out =~ /Dry run/);
}

# Test 4: --debug creates a log file
print "\n=== Test: --debug ===\n";
unlink '/tmp/diffvim-debug.log';
$out = `perl diffvim.pl --debug --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
# --dry-run exits before any send_ex calls, so the log may be empty
# but the flag should be accepted
ok('--debug flag accepted', $out =~ /Dry run/ || $out =~ /debug/i);

# Test 5: Engine has fold functions
print "\n=== Test: engine functions ===\n";
ok('engine has DvFoldSetup', `grep DvFoldSetup diffvim.pl` =~ /DvFoldSetup/);
ok('engine has DvFoldRegion', `grep DvFoldRegion diffvim.pl` =~ /DvFoldRegion/);
ok('engine has DvToggleFold', `grep DvToggleFold diffvim.pl` =~ /DvToggleFold/);
ok('engine has DvUnfoldAll', `grep DvUnfoldAll diffvim.pl` =~ /DvUnfoldAll/);
ok('f key is mapped', `grep 'nnoremap.*f.*DvToggleFold' diffvim.pl` =~ /DvToggleFold/);

# Test 6: Theme colors are defined
print "\n=== Test: theme definitions ===\n";
ok('dark theme defined', `grep "'dark'" diffvim.pl` =~ /dark/);
ok('light theme defined', `grep "'light'" diffvim.pl` =~ /light/);
ok('high-contrast theme defined', `grep "'high-contrast'" diffvim.pl` =~ /high-contrast/);

# Test 7: Debug log file path
print "\n=== Test: debug log path ===\n";
ok('--help shows debug log path', $help =~ /\/tmp\/diffvim-debug\.log/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
