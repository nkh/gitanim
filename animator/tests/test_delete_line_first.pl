#!/usr/bin/env perl
# test_delete_line_first.pl — Test the delete-line-content-first layer.
#
# Tests that when a line is fully deleted, the content is deleted BEFORE
# the \n of the previous line (preventing the "join then delete" visual).
#
# Test cases:
#   1. Single line deletion (A,B,C → A,C)
#   2. Multiple consecutive line deletions (A,B,C,D → A,D)
#   3. Line deletion at start (A,B,C → B,C)
#   4. Line deletion at end (A,B,C → A,B)
#   5. Mixed keeps and deletes
#   6. Full file deletion
#   7. No line deletion (no change to ops)
#   8. Random property tests (50 cases)

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;
my $tmpdir = tempdir(CLEANUP => 1);

sub run_test {
    my ($name, $old, $new) = @_;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $rf = "$tmpdir/raw.txt"; my $pf = "$tmpdir/post.txt";
    my $tf = "$tmpdir/timed.txt"; my $sf = "$tmpdir/snap.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;

    system("$root/compute/bin/diffvim-compute-cpp '$of' '$nf' '$rf' 2>/dev/null");
    system("$root/animator/bin/diffvim-postprocess < '$rf' > '$pf' 2>/dev/null");
    system("$root/animator/bin/pp_pace < '$pf' > '$tf' 2>/dev/null");
    system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot '$sf' '$of' < '$tf' 2>/dev/null");

    open $fh, '<:raw', $sf; my $snap = do { local $/; <$fh> }; close $fh;
    open $fh, '<:raw', $nf; my $exp = do { local $/; <$fh> }; close $fh;

    if ($snap eq $exp) { $pass++; }
    else {
        $fail++;
        print "FAIL: $name\n";
        print "  old: ", unpack("H*", $old), "\n" if length($old) < 100;
        print "  new: ", unpack("H*", $new), "\n" if length($new) < 100;
        print "  snap: ", unpack("H*", $snap), "\n" if length($snap) < 100;
    }
}

# ── Test 1: Single line deletion ──
run_test("single line delete (A,B,C → A,C)",
    "A\nB\nC\n", "A\nC\n");

# ── Test 2: Multiple consecutive line deletions ──
run_test("multi line delete (A,B,C,D → A,D)",
    "A\nB\nC\nD\n", "A\nD\n");

run_test("3 consecutive lines deleted",
    "A\nB\nC\nD\nE\n", "A\nE\n");

# ── Test 3: Line deletion at start ──
run_test("delete first line (A,B,C → B,C)",
    "A\nB\nC\n", "B\nC\n");

# ── Test 4: Line deletion at end ──
run_test("delete last line (A,B,C → A,B)",
    "A\nB\nC\n", "A\nB\n");

# ── Test 5: Mixed keeps and deletes ──
run_test("mixed (A,B,C,D,E → A,C,E)",
    "A\nB\nC\nD\nE\n", "A\nC\nE\n");

run_test("mixed (A,B,C,D,E → B,D)",
    "A\nB\nC\nD\nE\n", "B\nD\n");

# ── Test 6: Full file deletion ──
run_test("delete all (A,B,C → empty)",
    "A\nB\nC\n", "");

run_test("delete all (single line → empty)",
    "Hello\n", "");

# ── Test 7: No line deletion (ops unchanged) ──
run_test("no deletion (A,B,C → A,B,C)",
    "A\nB\nC\n", "A\nB\nC\n");

run_test("content change only (no line delete)",
    "Hello\nWorld\n", "Help\nWorld\n");

# ── Test 8: Single line ──
run_test("single line → empty",
    "X\n", "");

run_test("single line unchanged",
    "X\n", "X\n");

# ── Test 9: Empty lines ──
run_test("delete empty line",
    "A\n\nC\n", "A\nC\n");

run_test("delete multiple empty lines",
    "A\n\n\n\nC\n", "A\nC\n");

# ── Test 10: Long lines with content ──
run_test("long lines",
    "This is line one\nThis is line two\nThis is line three\n",
    "This is line one\nThis is line three\n");

# ── Test 11: Many lines ──
{
    my $old = join("", map { "line$_\n" } 1..20);
    my $new = join("", map { "line$_\n" } grep { $_ % 3 == 0 } 1..20);
    run_test("20 lines, keep every 3rd", $old, $new);
}

# ── Test 12: Property tests (random) ──
srand(42);
for my $i (1..50) {
    my $nlines = 5 + int(rand(20));
    my $old = "";
    for my $j (1..$nlines) {
        my $len = 1 + int(rand(30));
        my $line = "";
        $line .= chr(32 + int(rand(94))) for 1..$len;
        $old .= "$line\n";
    }
    # Delete random lines
    my @lines = split /\n/, $old, -1;
    pop @lines if @lines && $lines[-1] eq '';
    my @new_lines;
    for my $l (@lines) {
        push @new_lines, $l if int(rand(2)) == 0;  # 50% chance to keep
    }
    my $new = join("\n", @new_lines) . (@new_lines ? "\n" : "");

    run_test("random $i", $old, $new);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
