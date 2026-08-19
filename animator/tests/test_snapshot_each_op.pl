#!/usr/bin/env perl
# test_snapshot_each_op.pl — Snapshot the buffer after each op.
# Verifies that the buffer state after each op is consistent.
use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0; my $fail = 0;
my $tmpdir = tempdir(CLEANUP => 1);

my @cases = (
    ['simple join', "foo\nbar\n", "foobar\n"],
    ['multi-delete', "line1\nline2\nline3\n", "line1\nline3\n"],
    ['insert', "hello\n", "hello world\n"],
    ['replace', "abc\n", "xyz\n"],
    ['empty new', "hello\n", ""],
    ['empty old', "", "hello\n"],
    ['unicode', "caf\xc3\xa9\n", "coffee\n"],
);

for my $case (@cases) {
    my ($name, $old_content, $new_content) = @$case;
    my $old = "$tmpdir/old.txt"; my $new = "$tmpdir/new.txt";
    open my $fh, '>:raw', $old; print $fh $old_content; close $fh;
    open $fh, '>:raw', $new; print $fh $new_content; close $fh;
    
    system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' $tmpdir/raw.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-postprocess < $tmpdir/raw.txt > $tmpdir/post.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-pace < $tmpdir/post.txt > $tmpdir/timed.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot $tmpdir/snap.txt '$old' < $tmpdir/timed.txt 2>/dev/null");
    
    open $fh, '<:raw', "$tmpdir/snap.txt"; my $snap = do { local $/; <$fh> }; close $fh;
    
    if ($snap eq $new_content) {
        $pass++;
    } else {
        $fail++;
        print "FAIL: $name\n  expected: [" . unpack("H*", $new_content) . "]\n  got:      [" . unpack("H*", $snap) . "]\n";
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
