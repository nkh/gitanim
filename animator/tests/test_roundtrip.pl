#!/usr/bin/env perl
# test_animator_roundtrip.pl - Round-trip test for the animator pipeline.
#
# For each test case: compute → postprocess → pace → animate (no-display)
# Verify the animator's output matches the expected new file.
#
# This tests the entire pipeline WITHOUT a terminal.

use strict;
use warnings;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use lib "$Bin/../perl";

my $root = "$Bin/../..";
my $compute = "$root/compute/bin/diffvim-compute-cpp";
my $postprocess = "$root/animator/perl/postprocess.pl";
my $pace = "$root/animator/perl/pace.pl";
my $animator = "$root/animator/bin/diffvim-animator-c";

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Test cases: [name, old_content, new_content]
my @cases = (
    ['simple insert',
     "hello\n", "hello world\n"],
    ['simple delete',
     "hello world\n", "hello\n"],
    ['mid-line replace',
     "    print(\"Hello, \" + name)\n", "    print(f\"Hello, {name}!\")\n"],
    ['whole line delete',
     "line1\nline2\nline3\n", "line1\nline3\n"],
    ['whole line insert',
     "line1\nline3\n", "line1\nline2\nline3\n"],
    ['multi-line delete',
     "line1\nline2\nline3\nline4\nline5\n", "line1\nline5\n"],
    ['multi-line insert',
     "line1\nline5\n", "line1\nline2\nline3\nline4\nline5\n"],
    ['identical files',
     "hello\n", "hello\n"],
    ['empty old file',
     "", "hello\n"],
    ['empty new file',
     "hello\n", ""],
    ['python function',
     "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"],
    ['indent change',
     "def foo():\n    x = 1\n    return x\n",
     "def foo():\n        x = 1\n        return x\n"],
    ['unicode',
     "x = \"café\"\n", "x = \"coffee\"\n"],
    ['multiple hunks',
     "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n"],
    ['identical char run',
     "x = ---------------------------\n", "x = ---\n"],
);

my $tmpdir = tempdir(CLEANUP => 1);

for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    my $old_file = "$tmpdir/old.txt";
    my $new_file = "$tmpdir/new.txt";
    my $raw_file = "$tmpdir/raw.txt";
    my $timed_file = "$tmpdir/timed.txt";
    my $out_file = "$tmpdir/out.txt";

    open my $fh, '>', $old_file; binmode $fh, ':utf8'; print $fh $old; close $fh;
    open $fh, '>', $new_file; binmode $fh, ':utf8'; print $fh $new; close $fh;

    # Run the pipeline
    system("$compute '$old_file' '$new_file' '$raw_file' 2>/dev/null");
    system("perl $postprocess --op-order optimize < '$raw_file' 2>/dev/null | perl $pace --delete-pacing word 2>/dev/null > '$timed_file'");
    system("$animator --no-display --snapshot '$out_file' '$old_file' < '$timed_file' 2>/dev/null");

    # Compare output with expected
    if (!-f $out_file) {
        ok($name, 0);
        next;
    }

    open $fh, '<', $out_file; binmode $fh, ':utf8'; my $actual = do { local $/; <$fh> }; close $fh;
    open $fh, '<', $new_file; binmode $fh, ':utf8'; my $expected = do { local $/; <$fh> }; close $fh;

    ok($name, $actual eq $expected);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
