#!/usr/bin/env perl
# test_roundtrip_verify.pl — Round-trip test that ACTUALLY compares
# the animator's output with the expected new file.
#
# For each test case:
#   1. Compute the diff
#   2. Postprocess
#   3. Pace
#   4. Animate with --no-display --snapshot
#   5. Compare the snapshot file with the new file BYTE FOR BYTE
#
# This catches the \n problem: if the animator pulls lines up,
# the output won't match the new file.

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $compute = "$root/bin/ad_compute";
my $postprocess = "perl $root/layers/perl/postprocess.pl";
my $pace = "perl $root/layers/perl/ad_layer_pace.pl";

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond, $actual, $expected) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else {
        print "FAIL: $name\n";
        $fail++;
        if (defined $actual && defined $expected) {
            my @a = split /\n/, $actual;
            my @e = split /\n/, $expected;
            for my $i (0 .. $#e) {
                last if $i > $#a;
                if ($a[$i] ne $e[$i]) {
                    printf "  Line %d:\n    Expected: '%s'\n    Actual:   '%s'\n", $i+1, $e[$i], $a[$i];
                    last;
                }
            }
            if (@a != @e) {
                printf "  Line count: expected %d, got %d\n", scalar(@e), scalar(@a);
            }
        }
    }
}

# Test cases that specifically test \n handling
my @cases = (
    # Whole-line deletions (the \n problem)
    ['1 line delete',
     "line1\nline2\nline3\n", "line1\nline3\n"],
    ['3 consecutive line deletes',
     "line1\nline2\nline3\nline4\nline5\n", "line1\nline5\n"],
    ['delete first line',
     "line1\nline2\nline3\n", "line2\nline3\n"],
    ['delete last line',
     "line1\nline2\nline3\n", "line1\nline2\n"],

    # Mid-line changes (no \n involved)
    ['simple replace',
     "hello world\n", "hello there\n"],
    ['insert at end',
     "hello\n", "hello world\n"],
    ['delete at end',
     "hello world\n", "hello\n"],
    ['python function replace',
     "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"],

    # Mixed: some lines deleted, some modified
    ['mixed delete and modify',
     "line1\nold line\nline3\nline4\nline5\n",
     "line1\nnew line\nline3\nline5\n"],

    # Empty files
    ['empty old',
     "", "hello\n"],
    ['empty new',
     "hello\n", ""],
    ['identical',
     "hello\n", "hello\n"],

    # Unicode
    ['unicode replace',
     "x = \"caf\xc3\xa9\"\n", "x = \"coffee\"\n"],

    # Indent change
    ['indent change',
     "def foo():\n    x = 1\n    return x\n",
     "def foo():\n        x = 1\n        return x\n"],

    # Multiple hunks
    ['multi-hunk',
     "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n",
     "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n"],
);

my $tmpdir = tempdir(CLEANUP => 1);

for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $rf = "$tmpdir/raw.txt"; my $tf = "$tmpdir/timed.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;

    system("$compute '$of' '$nf' '$rf' 2>/dev/null");
    system("$postprocess --op-order optimize < '$rf' 2>/dev/null | $pace --delete-pacing word 2>/dev/null > '$tf'");

    # Read expected
    open $fh, '<:raw', $nf; my $expected = do { local $/; <$fh> }; close $fh;

    # Test all 2 animators (Go was removed in the refactor — C and Perl remain)
    for my $animator (
        ['Perl', "perl $root/animator/perl/ad.pl"],
        ['C',    "$root/bin/ad"],
    ) {
        my ($lang, $cmd) = @$animator;
        my $out = "$tmpdir/out_$lang.txt";
        system("$cmd --no-display --snapshot '$out' '$of' < '$tf' 2>/dev/null");

        if (!-f $out) {
            ok("$lang: $name (no output)", 0);
            next;
        }

        open $fh, '<:raw', $out; my $actual = do { local $/; <$fh> }; close $fh;
        ok("$lang: $name", $actual eq $expected, $actual, $expected);
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
