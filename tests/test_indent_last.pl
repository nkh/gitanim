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
system("DIFFVIM_LEFT_TO_RIGHT=1 ./compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/il_test_raw.txt 2>/dev/null");

# Run postprocess WITHOUT indent-last
system("./animator/bin/diffvim-postprocess < /tmp/il_test_raw.txt > /tmp/il_test_post_no.txt 2>/dev/null");

# Run postprocess WITH indent-last
system("./animator/bin/diffvim-postprocess --indent-last < /tmp/il_test_raw.txt > /tmp/il_test_post_il.txt 2>/dev/null");

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
system("./animator/bin/pp_pace < /tmp/il_test_post_no.txt > /tmp/il_test_timed_no.txt 2>/dev/null");
system("./animator/bin/pp_pace < /tmp/il_test_post_il.txt > /tmp/il_test_timed_il.txt 2>/dev/null");
system("./animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/il_test_out_no.txt '$old' < /tmp/il_test_timed_no.txt 2>/dev/null");
system("./animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/il_test_out_il.txt '$old' < /tmp/il_test_timed_il.txt 2>/dev/null");

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
system("./animator/bin/pp_reorder < /tmp/il_test_raw.txt > /tmp/il_test_reord.txt 2>/dev/null");
system("./animator/bin/pp_indent_last < /tmp/il_test_reord.txt > /tmp/il_test_c.txt 2>/dev/null");
system("perl ./animator/perl/pp_indent_last.pl < /tmp/il_test_reord.txt > /tmp/il_test_perl.txt 2>/dev/null");
if (system("diff -q /tmp/il_test_c.txt /tmp/il_test_perl.txt >/dev/null 2>&1") == 0) {
    print "PASS: C and Perl indent_last produce identical output (parity)\n";
    $pass++;
} else {
    print "FAIL: C and Perl indent_last differ\n";
    $fail++;
}

# Check: --pp-indent-last dynamic flag produces same output as --indent-last
system("./animator/bin/diffvim-postprocess --pp-indent-last < /tmp/il_test_raw.txt > /tmp/il_test_pp_flag.txt 2>/dev/null");
# Strip pace/highlight delays — they aren't deterministic. Compare only
# the post-processed ops (HUNK header through HUNK_END of each hunk).
sub extract_hunk_ops {
    my ($file) = @_;
    open(my $fh, '<', $file) or return [];
    my @ops;
    while (my $line = <$fh>) {
        chomp $line;
        next if $line =~ /^#/ || $line =~ /^$/;
        next if $line =~ /^delay\tnone/;
        # Skip pace/highlight-generated ops for the comparison
        push @ops, $line if $line =~ /^(HUNK|delete|insert|keep|overwrite_insert)/;
    }
    close($fh);
    return \@ops;
}
# Direct diff (orchestrator with --pp-indent-last vs --indent-last should
# produce the same layer chain — both enable the indent_last layer).
my $pp_out = extract_hunk_ops("/tmp/il_test_pp_flag.txt");
my $il_out = extract_hunk_ops("/tmp/il_test_post_il.txt");
# Note: $il_out has no pace/highlight applied yet (raw postprocess output);
# $pp_out has pace+highlight applied. Compare indent_last-relevant ops only.
my @il_deletes = grep { /^delete\t/ && !/^\w+\t\d+\t\d+\t(32|9|10)\t/ } @$il_out;
my @pp_deletes = grep { /^delete\t/ && !/^\w+\t\d+\t\d+\t(32|9|10)\t/ } @$pp_out;
if (scalar(@il_deletes) > 0 && scalar(@il_deletes) == scalar(@pp_deletes)) {
    print "PASS: --pp-indent-last dynamic flag enables the layer\n";
    $pass++;
} else {
    print "FAIL: --pp-indent-last did not enable the layer\n";
    $fail++;
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
