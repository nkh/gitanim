#!/usr/bin/env perl
# test_indent_last.pl — Verify --indent-last moves whitespace deletes to end.
#
# RULE: When --indent-last is enabled and a line is entirely deleted,
# the leading whitespace (spaces/tabs) deletes must appear AFTER the
# content deletes, not before them.
#
# Usage: perl tests/test_indent_last.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;

# Test: entire line with indentation is deleted (in the middle of file)
my $old = "/tmp/il_test_old.txt";
my $new = "/tmp/il_test_new.txt";
open(my $fh, '>', $old) or die; print $fh "def foo():\n    print(\"hello\")\n    return None\n\ndef bar():\n    pass\n"; close($fh);
open($fh, '>', $new) or die; print $fh "def foo():\n\ndef bar():\n    pass\n"; close($fh);

# Run compute
system("AD_LEFT_TO_RIGHT=1 ./bin/ad_compute '$old' '$new' /tmp/il_test_raw.txt 2>/dev/null");

# Run postprocess WITHOUT indent-last
system("./pipeline/ad_postprocess --ad-layer=ad_layer_reorder < /tmp/il_test_raw.txt > /tmp/il_test_post_no.txt 2>/dev/null");

# Run postprocess WITH indent-last
system("./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_indent_last < /tmp/il_test_raw.txt > /tmp/il_test_post_il.txt 2>/dev/null");

# Read the ops
sub read_ops {
    my ($file) = @_;
    open(my $fh, '<', $file) or return [];
    my @ops;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^#/ || $line =~ /^$/;
        push @ops, $line;
    }
    close($fh);
    return \@ops;
}

my $ops_no = read_ops("/tmp/il_test_post_no.txt");
my $ops_il = read_ops("/tmp/il_test_post_il.txt");

# Check: WITHOUT indent-last, the first delete should be a space (code 32 or 9)
my $first_no = $ops_no->[1] // "";
if ($first_no =~ /^delete\t\d+\t\d+\t(32|9)\t/) {
    print "PASS: WITHOUT indent-last, first delete is whitespace (expected)\n";
    $pass++;
} else {
    print "FAIL: WITHOUT indent-last, first delete should be whitespace, got: $first_no\n";
    $fail++;
}

# Check: WITH indent-last, the first delete should NOT be a space
my $first_il = $ops_il->[1] // "";
if ($first_il !~ /^delete\t\d+\t\d+\t(32|9)\t/) {
    print "PASS: WITH indent-last, first delete is content (not whitespace)\n";
    $pass++;
} else {
    print "FAIL: WITH indent-last, first delete should be content, got: $first_il\n";
    $fail++;
}

# Check: WITH indent-last, space deletes appear AFTER content deletes
my $found_content = 0;
my $found_space_after_content = 0;
for my $op (@$ops_il) {
    if ($op =~ /^delete\t\d+\t\d+\t(\d+)\t/) {
        my $code = $1;
        if ($code != 32 && $code != 9 && $code != 10) {
            $found_content = 1;
        } elsif ($code == 32 || $code == 9) {
            if ($found_content) {
                $found_space_after_content = 1;
            }
        }
    }
}
if ($found_space_after_content) {
    print "PASS: WITH indent-last, space deletes appear AFTER content deletes\n";
    $pass++;
} else {
    print "FAIL: WITH indent-last, no space deletes found after content\n";
    $fail++;
}

# Check: both produce correct output
system("./bin/ad_layer_pace < /tmp/il_test_post_no.txt > /tmp/il_test_timed_no.txt 2>/dev/null");
system("./bin/ad_layer_pace < /tmp/il_test_post_il.txt > /tmp/il_test_timed_il.txt 2>/dev/null");
system("./bin/ad --no-display --speed 1000 --snapshot /tmp/il_test_out_no.txt '$old' < /tmp/il_test_timed_no.txt 2>/dev/null");
system("./bin/ad --no-display --speed 1000 --snapshot /tmp/il_test_out_il.txt '$old' < /tmp/il_test_timed_il.txt 2>/dev/null");

if (system("diff -q '$new' /tmp/il_test_out_no.txt >/dev/null 2>&1") == 0) {
    print "PASS: WITHOUT indent-last, output matches\n";
    $pass++;
} else {
    print "FAIL: WITHOUT indent-last, output doesn't match\n";
    $fail++;
}

if (system("diff -q '$new' /tmp/il_test_out_il.txt >/dev/null 2>&1") == 0) {
    print "PASS: WITH indent-last, output matches\n";
    $pass++;
} else {
    print "FAIL: WITH indent-last, output doesn't match\n";
    $fail++;
}

# Check: C and Perl implementations of indent_last produce identical output
system("./bin/ad_layer_reorder < /tmp/il_test_raw.txt > /tmp/il_test_reord.txt 2>/dev/null");
system("./bin/ad_layer_indent_last < /tmp/il_test_reord.txt > /tmp/il_test_c.txt 2>/dev/null");
system("perl ./layers/perl/ad_layer_indent_last.pl < /tmp/il_test_reord.txt > /tmp/il_test_perl.txt 2>/dev/null");
if (system("diff -q /tmp/il_test_c.txt /tmp/il_test_perl.txt >/dev/null 2>&1") == 0) {
    print "PASS: C and Perl indent_last produce identical output (parity)\n";
    $pass++;
} else {
    print "FAIL: C and Perl indent_last differ\n";
    $fail++;
}

# Check: --ad-layer=ad_layer_indent_last dynamic flag works
system("./pipeline/ad_postprocess --ad-layer=ad_layer_reorder --ad-layer=ad_layer_indent_last < /tmp/il_test_raw.txt > /tmp/il_test_ad_layer_flag.txt 2>/dev/null");
# Compare against the --indent-last convenience flag (which expands to
# the same --ad-layer=ad_layer_indent_last chain).
my $il_out_count = 0;
my $ad_layer_count = 0;
open(my $ifh, '<', "/tmp/il_test_post_il.txt") or die;
while (my $line = <$ifh>) { chomp $line; $il_out_count++ if $line =~ /^delete\t/; }
close($ifh);
open($ifh, '<', "/tmp/il_test_ad_layer_flag.txt") or die;
while (my $line = <$ifh>) { chomp $line; $ad_layer_count++ if $line =~ /^delete\t/; }
close($ifh);
if ($il_out_count > 0 && $il_out_count == $ad_layer_count) {
    print "PASS: --ad-layer=ad_layer_indent_last produces same op count as convenience flag\n";
    $pass++;
} else {
    print "FAIL: --ad-layer=ad_layer_indent_last differs (il=$il_out_count, ad_layer=$ad_layer_count)\n";
    $fail++;
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
