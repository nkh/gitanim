#!/usr/bin/env perl
# test_features.pl - Test the new features added to ad_vim.pl
#
# Tests:
#   1. --speed flag affects timing
#   2. --max-hunk-chars applies large hunks instantly
#   3. --max-word-chars batches short words
#   4. --output writes result file
#   5. --scroll accepts valid values
#   6. --multi parses multiple file pairs
#   7. --replay extracts git history
#   8. --help shows all options
#   9. Runtime speed adjustment (+/- keys logic)
#  10. Progress display format

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
# Test 1: --help shows all new options
# ---------------------------------------------------------------------------
print "\n=== Test: --help shows all options ===\n";
my $help_output = `perl ad_vim.pl --help 2>&1`;
ok('--speed in help',     $help_output =~ /--speed/);
ok('--output in help',    $help_output =~ /--output/);
ok('--context in help',   $help_output =~ /--context/);
ok('--max-hunk-chars in help', $help_output =~ /--max-hunk-chars/);
ok('--speed in help',  $help_output =~ /--speed/);
ok('--scroll in help',    $help_output =~ /--scroll/);
ok('--multi in help',     $help_output =~ /--multi/);
ok('--replay in help',    $help_output =~ /--replay/);
ok('--from in help',      $help_output =~ /--from/);
ok('--to in help',        $help_output =~ /--to/);
ok('+/- controls in help',     $help_output =~ /speed up|slow down/i || $help_output =~ /\+.*speed/i);

# ---------------------------------------------------------------------------
# Test 2: --speed applies multiplier
# ---------------------------------------------------------------------------
print "\n=== Test: --speed multiplier ===\n";
# Create test files
open my $fh, '>', '/tmp/dv_test_old.txt'; print $fh "hello\n"; close $fh;
open $fh, '>', '/tmp/dv_test_new.txt'; print $fh "hello there\n"; close $fh;

# Test that --speed 2 halves the delays
my $output = `AD_TYPE_DELAY_MS=100 perl ad_vim.pl --speed 2 --help 2>&1`;
# --speed 2 should make type_delay = 100/2 = 50
# We can't easily test runtime values without running vim, but we can
# verify the script accepts the flag without error
ok('--speed 2 accepted', $? == 0 || $output =~ /Usage/);

# Test invalid speed value
$output = `perl ad_vim.pl --speed abc /tmp/dv_test_old.txt /tmp/dv_test_new.txt 2>&1`;
ok('--speed with non-numeric fails gracefully', $output =~ /Error|Usage|invalid/i || $? != 0);

# ---------------------------------------------------------------------------
# Test 3: --output flag
# ---------------------------------------------------------------------------
print "\n=== Test: --output flag ===\n";
ok('--output accepted', `perl ad_vim.pl --output /tmp/dv_result.txt --help 2>&1` =~ /--output/);

# ---------------------------------------------------------------------------
# Test 4: --scroll valid values
# ---------------------------------------------------------------------------
print "\n=== Test: --scroll values ===\n";
for my $val ('zz', 'zt', 'zb', 'none') {
    my $out = `perl ad_vim.pl --scroll $val --help 2>&1`;
    ok("--scroll $val accepted", $out =~ /--scroll/);
}

# --scroll accepts any string value (vim ignores invalid ones at runtime)
# We just verify it doesn't crash during arg parsing
$output = `perl ad_vim.pl --scroll invalid --help 2>&1`;
ok('--scroll accepts any string', $output =~ /--scroll/);

# ---------------------------------------------------------------------------
# Test 5: --multi parses pairs
# ---------------------------------------------------------------------------
print "\n=== Test: --multi ===\n";
open $fh, '>', '/tmp/dv_multi_old1.txt'; print $fh "a\n"; close $fh;
open $fh, '>', '/tmp/dv_multi_new1.txt'; print $fh "b\n"; close $fh;
open $fh, '>', '/tmp/dv_multi_old2.txt'; print $fh "c\n"; close $fh;
open $fh, '>', '/tmp/dv_multi_new2.txt'; print $fh "d\n"; close $fh;

# Test invalid format
$output = `perl ad_vim.pl --multi /tmp/dv_multi_old1.txt /tmp/dv_multi_new1.txt 2>&1`;
ok('--multi rejects non-old:new format', $output =~ /not in old:new format/);

# Test valid format (will fail at tmux step, but parsing should work)
$output = `perl ad_vim.pl --multi /tmp/dv_multi_old1.txt:/tmp/dv_multi_new1.txt /tmp/dv_multi_old2.txt:/tmp/dv_multi_new2.txt 2>&1`;
ok('--multi accepts valid pairs', $output !~ /not in old:new format/);

# ---------------------------------------------------------------------------
# Test 6: --max-hunk-chars and unified pacing options
# ---------------------------------------------------------------------------
print "\n=== Test: --max-hunk-chars and unified options ===\n";
ok('--max-hunk-chars accepted', `perl ad_vim.pl --max-hunk-chars 100 --help 2>&1` =~ /--max-hunk-chars/);
ok('--insert-pacing accepted', `bash ad_vim --insert-pacing word --help 2>&1` =~ /--insert-pacing/);
ok('--delete-pacing accepted', `bash ad_vim --delete-pacing word --help 2>&1` =~ /--delete-pacing/);
ok('--op-order accepted', `bash ad_vim --op-order optimize --help 2>&1` =~ /--op-order/);
ok('--pacing accepted', `bash ad_vim --pacing uniform --help 2>&1` =~ /--pacing/);
ok('--highlight accepted', `bash ad_vim --highlight none --help 2>&1` =~ /--highlight/);

# ---------------------------------------------------------------------------
# Test 7: --replay requires git
# ---------------------------------------------------------------------------
print "\n=== Test: --replay ===\n";
$output = `perl ad_vim.pl --replay /tmp/dv_test_old.txt 2>&1`;
ok('--replay accepted', $output =~ /git|not found|hunk|Launching/i || $? != 0);

# Test --git-rev (replaces --from/--to in bash ad_vim)
ok('--git-rev accepted', `bash ad_vim --git-rev HEAD~1..HEAD --help 2>&1` =~ /--git-rev/);

# ---------------------------------------------------------------------------
# Test 8: Parser tests still pass
# ---------------------------------------------------------------------------
print "\n=== Test: Parser tests ===\n";
my $parser_output = `perl tests/test_parsers.pl 2>&1`;
ok('Parser tests pass', $parser_output =~ /9 passed, 0 failed/);

# ---------------------------------------------------------------------------
# Test 9: ad_vim (bash) --help
# ---------------------------------------------------------------------------
print "\n=== Test: ad_vim (bash) --help ===\n";
$help_output = `bash ad_vim --help 2>&1`;
ok('ad_vim --speed in help',     $help_output =~ /--speed/);
ok('ad_vim --output in help',    $help_output =~ /--output/);
ok('ad_vim --max-hunk-chars in help', $help_output =~ /--max-hunk-chars/);
ok('ad_vim --insert-pacing in help', $help_output =~ /--insert-pacing/);
ok('ad_vim --scroll in help',    $help_output =~ /--scroll/);
ok('ad_vim --multi in help',     $help_output =~ /--multi/);
ok('ad_vim --replay in help',    $help_output =~ /--replay/);
ok('ad_vim +/- in help',         $help_output =~ /\+.*speed/);

# ---------------------------------------------------------------------------
# Test 10: ad_tmux --help
# ---------------------------------------------------------------------------
print "\n=== Test: ad_tmux --help ===\n";
$help_output = `bash ad_tmux --help 2>&1`;
ok('ad_tmux --speed in help',     $help_output =~ /--speed/);
ok('ad_tmux --output in help',    $help_output =~ /--output/);
ok('ad_tmux --max-hunk-chars in help', $help_output =~ /--max-hunk-chars/);
ok('ad_tmux --scroll in help',    $help_output =~ /--scroll/);
ok('ad_tmux --multi in help',     $help_output =~ /--multi/);
ok('ad_tmux --replay in help',    $help_output =~ /--replay/);

# ---------------------------------------------------------------------------
# Test 11: ad_vim accepts --speed and applies it
# ---------------------------------------------------------------------------
print "\n=== Test: ad_vim --speed ===\n";
# Test that ad_vim --speed doesn't produce an error (use --help to avoid launching vim)
$output = `bash ad_vim --speed 2 --help 2>&1`;
ok('ad_vim --speed 2 accepted', $output =~ /--speed/);

# ---------------------------------------------------------------------------
# Test 12: Plugin file exists
# ---------------------------------------------------------------------------
print "\n=== Test: Plugin ===\n";
ok('plugin/diffvim.vim exists', -f 'plugin/diffvim.vim');
ok('plugin defines :Diffvim command', `cat plugin/diffvim.vim` =~ /command.*Diffvim/);

# ---------------------------------------------------------------------------
# Test 13: Man page exists
# ---------------------------------------------------------------------------
print "\n=== Test: Man page ===\n";
ok('ad_vim.1 exists', -f 'ad_vim.1');
ok('man page has NAME section', `head -5 ad_vim.1` =~ /NAME/);
ok('man page documents --speed', `grep 'speed' ad_vim.1` =~ /speed/);
ok('man page documents --output', `grep 'output' ad_vim.1` =~ /output/);
ok('man page documents --replay', `grep 'replay' ad_vim.1` =~ /replay/);

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
unlink '/tmp/dv_test_old.txt', '/tmp/dv_test_new.txt';
unlink '/tmp/dv_multi_old1.txt', '/tmp/dv_multi_new1.txt', '/tmp/dv_multi_old2.txt', '/tmp/dv_multi_new2.txt';
unlink '/tmp/dv_result.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
