#!/usr/bin/env perl
# test_ghost_line.pl — Test the ghost-line visual problem.
#
# The ghost-line problem: when delete \n joins two lines, the next
# line's content visually jumps up onto the current line. The fix
# lives in the POSTPROCESSOR: it reorders the next line's content
# deletes to target (line+1, 1) BEFORE the \n delete, so by the time
# the \n delete runs the next line is empty and the join is a no-op.
#
# The animator's delete_char(\n) just does a standard "join with next"
# — no special empty-line handling. This test verifies the pipeline
# (compute → postprocess → pace → animator) produces the correct
# final buffer state in all the ghost-line scenarios.
#
# Usage: perl test_ghost_line.pl

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond, $got, $expected) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else {
        print "FAIL: $name\n";
        if (defined $got && defined $expected) {
            print "  Expected: [$expected]\n";
            print "  Got:      [$got]\n";
        }
        $fail++;
    }
}

# ── Test 1: Simple join (foo\nbar → foobar) ──────────────────────
# The core ghost-line case.
#
# The postprocess ghost-line fix reorders the ops so the next line's
# content is deleted before the \n is removed. The animator just does
# a standard join — by the time it sees the \n delete, the joined-in
# content is already empty.
print "=== Test 1: Simple join (foo\\nbar → foobar) ===\n";

my $tmpdir = tempdir(CLEANUP => 1);
my $old = "$tmpdir/old.txt";
my $new = "$tmpdir/new.txt";

# Write test files
open my $fh, '>:raw', $old; print $fh "foo\nbar\n"; close $fh;
open $fh, '>:raw', $new; print $fh "foobar\n"; close $fh;

# Run the pipeline
system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");

# Check final output
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/out.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; my $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', $new; my $expected = do { local $/; <$fh> }; close $fh;

ok('simple join: final output correct', $actual eq $expected, $actual, $expected);

# Check the timed ops — verify there IS a delete \n op (v2 format)
open $fh, '<', "$tmpdir/timed.txt"; my @timed = <$fh>; close $fh;
my $has_newline_delete = grep { /^delete\t\d+\t\d+\t10\t/ } @timed;
ok('simple join: has delete-\\n op (v2 format)', $has_newline_delete);

# ── Test 2: Multi-line delete (line1\nline2\nline3 → line1\nline3) ──
# Two lines deleted (line2 removed entirely).
print "\n=== Test 2: Multi-line delete (remove line2) ===\n";

open $fh, '>:raw', $old; print $fh "line1\nline2\nline3\n"; close $fh;
open $fh, '>:raw', $new; print $fh "line1\nline3\n"; close $fh;

system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/out.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', $new; $expected = do { local $/; <$fh> }; close $fh;

ok('multi-line delete: final output correct', $actual eq $expected, $actual, $expected);

# ── Test 3: Mid-line replace with join ────────────────────────────
# Old: "hello world\nfoo"  New: "hello foo"
# keep "hello ", delete "world", delete \n, keep "foo"
print "\n=== Test 3: Mid-line replace with join ===\n";

open $fh, '>:raw', $old; print $fh "hello world\nfoo\n"; close $fh;
open $fh, '>:raw', $new; print $fh "hello foo\n"; close $fh;

system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/out.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', $new; $expected = do { local $/; <$fh> }; close $fh;

ok('mid-line replace with join: final output correct', $actual eq $expected, $actual, $expected);

# ── Test 4: Pure deletion (all content + all \n) ───────────────────
# Old: "abc\n"  New: "" (empty)
print "\n=== Test 4: Pure deletion (all content) ===\n";

open $fh, '>:raw', $old; print $fh "abc\n"; close $fh;
open $fh, '>:raw', $new; print $fh ""; close $fh;

system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/out.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', $new; $expected = do { local $/; <$fh> }; close $fh;

ok('pure deletion: final output correct', $actual eq $expected, $actual, $expected);

# ── Test 5: Insert + delete + \n delete mix ───────────────────────
# Old: "foo\nbar\n"  New: "foox\nbar\n"
# keep foo, insert x, keep \n, keep bar
# No ghost-line issue here (no \n delete), but verify correctness.
print "\n=== Test 5: Insert (no ghost-line) ===\n";

open $fh, '>:raw', $old; print $fh "foo\nbar\n"; close $fh;
open $fh, '>:raw', $new; print $fh "foox\nbar\n"; close $fh;

system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/out.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', $new; $expected = do { local $/; <$fh> }; close $fh;

ok('insert (no ghost-line): final output correct', $actual eq $expected, $actual, $expected);

# ── Test 6: Example 07 (large text prose with many joins) ─────────
# This is the main ghost-line test case from the project.
print "\n=== Test 6: Example 07 (text prose, many joins) ===\n";

system("$root/animator/diffvim-pipeline --no-display --speed 1000 --snapshot $tmpdir/out.txt $root/examples/07_text_prose/old.txt $root/examples/07_text_prose/new.txt 2>/dev/null");
open $fh, '<:raw', "$tmpdir/out.txt"; $actual = do { local $/; <$fh> }; close $fh;
open $fh, '<:raw', "$root/examples/07_text_prose/new.txt"; $expected = do { local $/; <$fh> }; close $fh;

ok('example 07: final output correct', $actual eq $expected);

# ── Test 7: Sanity check — all previous tests passed ──────────────
# The postprocess ghost-line fix is in place: the postprocess reorders
# content deletes to target (line+1, 1) before the \n delete, so by the
# time the animator's delete_char(\n) runs the joined-in content is
# already empty and the join is a no-op (visually: no jump).
print "\n=== Test 7: Sanity check — all previous tests passed ===\n";
ok('ghost-line: all final outputs correct (fix in postprocess)', $pass > 0 && $fail == 0);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
