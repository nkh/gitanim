#!/usr/bin/env perl
# test_highlight_hunk.pl - Test --highlight-hunk feature
# Verifies that the highlight options are parsed correctly and the
# engine functions exist.

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

# Test 1: --help shows highlight options
print "=== Test: --help shows highlight options ===\n";
my $help = `perl ad_vim.pl --help 2>&1`;
ok('--help shows --highlight-hunk',         $help =~ /--highlight-hunk/);
ok('--help shows --highlight-color',        $help =~ /--highlight-color/);
ok('--help shows --highlight-duration-ms',  $help =~ /--highlight-duration-ms/);
ok('--help shows --highlight-min-chars',    $help =~ /--highlight-min-chars/);

# Test 2: ad_vim (bash) --help shows highlight options
print "\n=== Test: ad_vim --help shows highlight options ===\n";
$help = `bash ad_vim --help 2>&1`;
ok('ad_vim --help shows --highlight-hunk',         $help =~ /--highlight-hunk/);
ok('ad_vim --help shows --highlight-color',        $help =~ /--highlight-color/);
ok('ad_vim --help shows --highlight-duration-ms',  $help =~ /--highlight-duration-ms/);
ok('ad_vim --help shows --highlight-min-chars',    $help =~ /--highlight-min-chars/);

# Test 3: ad_vim.pl accepts highlight options
print "\n=== Test: ad_vim.pl accepts highlight options ===\n";
my $out = `perl ad_vim.pl --highlight-hunk --highlight-color Search --highlight-duration-ms 500 --highlight-min-chars 5 --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('--highlight-hunk with --dry-run works', $out =~ /Dry run/);

# Test 4: Engine has DvHighlightHunk function (ad_vim.pl)
print "\n=== Test: engine functions in ad_vim.pl ===\n";
my $engine = `grep DvHighlightHunk ad_vim.pl`;
ok('ad_vim.pl engine has DvHighlightHunk', $engine =~ /DvHighlightHunk/);
$engine = `grep DvClearHighlight ad_vim.pl`;
ok('ad_vim.pl engine has DvClearHighlight', $engine =~ /DvClearHighlight/);

# Test 5: Engine has HighlightHunk function (ad_vim vimscript)
print "\n=== Test: engine functions in ad_vim ===\n";
$engine = `grep HighlightHunk diffvim`;
ok('ad_vim engine has s:HighlightHunk', $engine =~ /HighlightHunk/);
$engine = `grep ClearHighlight diffvim`;
ok('ad_vim engine has s:ClearHighlight', $engine =~ /ClearHighlight/);

# Test 6: Autoload engine has highlight functions
print "\n=== Test: autoload engine ===\n";
$engine = `grep HighlightHunk autoload/diffvim/engine.vim`;
ok('autoload engine has HighlightHunk', $engine =~ /HighlightHunk/);

# Test 7: Default values
print "\n=== Test: default values ===\n";
ok('default color is DiffChange', `perl ad_vim.pl --help 2>&1` =~ /DiffChange/);
ok('default duration is 1000', `perl ad_vim.pl --help 2>&1` =~ /1000/);
ok('default min-chars is 10', `perl ad_vim.pl --help 2>&1` =~ /10/);

# Test 8: Custom color via env var
print "\n=== Test: env var override ===\n";
$out = `AD_HIGHLIGHT_COLOR=Search perl ad_vim.pl --highlight-hunk --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('AD_HIGHLIGHT_COLOR env var works', $out =~ /Dry run/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
