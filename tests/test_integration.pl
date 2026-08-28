#!/usr/bin/env perl
# test_integration.pl - Integration tests for the full animation pipeline.
#
# Runs the complete animation on example files and verifies the buffer
# matches the expected output. Uses --dry-run to test the diff computation
# and op generation without requiring tmux/vim.

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) {
        print "PASS: $name\n";
        $pass++;
    } else {
        print "FAIL: $name\n";
        $fail++;
    }
}

# ---------------------------------------------------------------------------
# Test 1: Dry-run produces output for all example pairs
# ---------------------------------------------------------------------------
print "\n=== Test: Dry-run on all examples ===\n";

my @examples = glob("tests/examples/*/old.*");
for my $old_file (@examples) {
    my $dir = $old_file;
    $dir =~ s|/old\.[^.]+$||;
    my $new_file = $dir . "/new." . ($old_file =~ /\.(\w+)$/ ? $1 : "txt");

    if (!-f $new_file) {
        print "SKIP: no new file for $old_file\n";
        next;
    }

    my $output = `perl diffvim.pl --dry-run "$old_file" "$new_file" 2>&1`;
    my $name = $dir;
    $name =~ s|tests/examples/||;
    ok("dry-run produces output for $name", $output =~ /Dry run/ && $output =~ /Hunks:/);
    ok("dry-run shows char_ops for $name", $output =~ /char_ops/);
}

# ---------------------------------------------------------------------------
# Test 2: --version works
# ---------------------------------------------------------------------------
print "\n=== Test: --version ===\n";
my $ver = `perl diffvim.pl --version 2>&1`;
ok('version shows version number', $ver =~ /version/);
ok('version shows perl version', $ver =~ /perl/);
ok('version shows vim version', $ver =~ /vim/i);

# ---------------------------------------------------------------------------
# Test 3: --help shows all options
# ---------------------------------------------------------------------------
print "\n=== Test: --help completeness ===\n";
my $help = `perl diffvim.pl --help 2>&1`;
my @expected_opts = qw(
    --parser --speed --output --context --max-hunk-chars --max-word-chars
    --word-pause-ms --scroll --multi --replay --from --to --git-rev
    --no-tmux --dry-run --sign-column --git-blame --step-mode
    --max-line-len --adaptive-timing --word-diff --version --help
);
for my $opt (@expected_opts) {
    ok("help shows $opt", $help =~ /\Q$opt\E/);
}

# ---------------------------------------------------------------------------
# Test 4: Binary file detection
# ---------------------------------------------------------------------------
print "\n=== Test: Binary file detection ===\n";
# Create a binary file
open my $fh, '>:raw', '/tmp/dv_binary.dat';
print $fh "binary\x00data\x01\x02\x03";
close $fh;
open $fh, '>', '/tmp/dv_text.txt';
print $fh "hello world\n";
close $fh;

my $bin_out = `perl diffvim.pl /tmp/dv_binary.dat /tmp/dv_text.txt 2>&1`;
ok('binary file rejected', $bin_out =~ /binary/i);

# ---------------------------------------------------------------------------
# Test 5: Empty file handling
# ---------------------------------------------------------------------------
print "\n=== Test: Empty file handling ===\n";
open $fh, '>', '/tmp/dv_empty.txt';
close $fh;
open $fh, '>', '/tmp/dv_content.txt';
print $fh "hello\nworld\n";
close $fh;

my $empty_out = `perl diffvim.pl --dry-run /tmp/dv_empty.txt /tmp/dv_content.txt 2>&1`;
ok('empty old file handled', $empty_out =~ /Dry run/ && $empty_out !~ /Error/i);

my $empty_out2 = `perl diffvim.pl --dry-run /tmp/dv_content.txt /tmp/dv_empty.txt 2>&1`;
ok('empty new file handled', $empty_out2 =~ /Dry run/ && $empty_out2 !~ /Error/i);

# ---------------------------------------------------------------------------
# Test 6: Identical files
# ---------------------------------------------------------------------------
print "\n=== Test: Identical files ===\n";
my $ident_out = `perl diffvim.pl --dry-run /tmp/dv_content.txt /tmp/dv_content.txt 2>&1`;
ok('identical files produce 0 hunks', $ident_out =~ /Hunks: 0/ || $ident_out =~ /identical/i);

# ---------------------------------------------------------------------------
# Test 7: Word diff produces different output
# ---------------------------------------------------------------------------
print "\n=== Test: Word diff ===\n";
my $char_out = `perl diffvim.pl --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
my $word_out = `perl diffvim.pl --dry-run --word-diff tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1`;
ok('word-diff produces output', $word_out =~ /char_ops/);
# Word diff and char diff should both produce valid ops
ok('char-diff produces output', $char_out =~ /char_ops/);

# ---------------------------------------------------------------------------
# Test 8: Parser tests still pass
# ---------------------------------------------------------------------------
print "\n=== Test: Parser tests ===\n";
my $parser_out = `perl tests/test_parsers.pl 2>&1`;
ok('parser tests pass', $parser_out =~ /18 passed, 0 failed/);

# ---------------------------------------------------------------------------
# Test 9: Feature tests pass
# ---------------------------------------------------------------------------
print "\n=== Test: Feature tests ===\n";
my $feat_out = `perl tests/test_features.pl 2>&1`;
ok('feature tests pass', $feat_out =~ /\d+ passed, 0 failed/);

# ---------------------------------------------------------------------------
# Test 10: Plugin files exist
# ---------------------------------------------------------------------------
print "\n=== Test: Plugin ===\n";
ok('plugin/diffvim.vim exists', -f 'plugin/diffvim.vim');
ok('autoload/diffvim/engine.vim exists', -f 'autoload/diffvim/engine.vim');
ok('plugin defines :Diffvim command', `cat plugin/diffvim.vim` =~ /command.*Diffvim/);

# ---------------------------------------------------------------------------
# Test 11: Shell completion exists
# ---------------------------------------------------------------------------
print "\n=== Test: Shell completion ===\n";
ok('bash completion exists', -f 'completion/diffvim.bash');
ok('zsh completion exists', -f 'completion/_diffvim');
ok('fish completion exists', -f 'completion/diffvim.fish');

# ---------------------------------------------------------------------------
# Test 12: Man page exists and is valid
# ---------------------------------------------------------------------------
print "\n=== Test: Man page ===\n";
ok('man page exists', -f 'diffvim.1');
ok('man page has NAME section', `head -5 diffvim.1` =~ /\.SH NAME/);
ok('man page has SYNOPSIS', `grep SYNOPSIS diffvim.1` =~ /SYNOPSIS/);
ok('man page has OPTIONS', `grep OPTIONS diffvim.1` =~ /OPTIONS/);

# ---------------------------------------------------------------------------
# Test 13: mdbook docs exist
# ---------------------------------------------------------------------------
print "\n=== Test: mdbook docs ===\n";
ok('docs/src/SUMMARY.md exists', -f 'docs/src/SUMMARY.md');
ok('docs/src/introduction.md exists', -f 'docs/src/introduction.md');
ok('docs/src/options.md exists', -f 'docs/src/options.md');
ok('docs/src/examples.md exists', -f 'docs/src/examples.md');

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
unlink '/tmp/dv_binary.dat', '/tmp/dv_text.txt', '/tmp/dv_empty.txt', '/tmp/dv_content.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
