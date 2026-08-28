#!/usr/bin/env perl
# test_all_animators.pl — Round-trip test for all three animator implementations.
# For each test case: compute → postprocess → pace → animate (no-display)
# Verify each animator's output matches the expected new file.

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $compute = "$root/bin/ad_compute";
my $postprocess_perl = "$root/pipeline/ad_postprocess --ad-layer=ad_layer_reorder";
my $pace_perl = "perl $root/layers/perl/ad_layer_pace.pl";
my $animator_perl = "perl $root/animator/perl/ad.pl";
my $animator_c = "$root/bin/ad";

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

my @cases = (
    ['simple insert',     "hello\n", "hello world\n"],
    ['simple delete',     "hello world\n", "hello\n"],
    ['mid-line replace',  "    print(\"Hello, \" + name)\n", "    print(f\"Hello, {name}!\")\n"],
    ['whole line delete', "line1\nline2\nline3\n", "line1\nline3\n"],
    ['whole line insert', "line1\nline3\n", "line1\nline2\nline3\n"],
    ['multi-line delete', "line1\nline2\nline3\nline4\nline5\n", "line1\nline5\n"],
    ['multi-line insert', "line1\nline5\n", "line1\nline2\nline3\nline4\nline5\n"],
    ['identical',         "hello\n", "hello\n"],
    ['empty old',         "", "hello\n"],
    ['empty new',         "hello\n", ""],
    ['python func',       "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
                          "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"],
    ['indent change',     "def foo():\n    x = 1\n    return x\n",
                          "def foo():\n        x = 1\n        return x\n"],
    ['unicode',           "x = \"caf\xc3\xa9\"\n", "x = \"coffee\"\n"],
    ['multi-hunk',        "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n",
                          "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n"],
    ['char run',          "x = ---------------------------\n", "x = ---\n"],
);

my $tmpdir = tempdir(CLEANUP => 1);

for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $rf = "$tmpdir/raw.txt"; my $pf = "$tmpdir/post.txt";
    my $tf = "$tmpdir/timed.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;

    system("$compute '$of' '$nf' '$rf' 2>/dev/null");
    system("$postprocess_perl --op-order optimize < '$rf' 2>/dev/null > '$pf'");
    system("$pace_perl --delete-pacing word < '$pf' 2>/dev/null > '$tf'");

    open $fh, '<:raw', $nf; my $expected = do { local $/; <$fh> }; close $fh;

    # Test Perl animator
    my $perl_out = "$tmpdir/perl_out.txt";
    system("$animator_perl --no-display --snapshot '$perl_out' '$of' < '$tf' 2>/dev/null");
    open $fh, '<:raw', $perl_out; my $perl_actual = do { local $/; <$fh> }; close $fh;
    ok("Perl: $name", $perl_actual eq $expected);

    # Test C animator
    my $c_out = "$tmpdir/c_out.txt";
    system("$animator_c --no-display --snapshot '$c_out' '$of' < '$tf' 2>/dev/null");
    open $fh, '<:raw', $c_out; my $c_actual = do { local $/; <$fh> }; close $fh;
    ok("C: $name", $c_actual eq $expected);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
