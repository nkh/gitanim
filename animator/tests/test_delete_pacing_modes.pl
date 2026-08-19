#!/usr/bin/env perl
# test_delete_pacing_modes.pl — Test all delete-pacing modes produce correct output.
use strict;
use warnings;

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

my @modes = qw(char rapid-eol rapid-identical accel word instant);

for my $mode (@modes) {
    my $old = "$root/examples/01_small_python/old.py";
    my $new = "$root/examples/01_small_python/new.py";
    
    system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/raw.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-postprocess < /tmp/raw.txt > /tmp/post.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-pace --delete-pacing $mode < /tmp/post.txt > /tmp/timed.txt 2>/dev/null");
    system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/snap.txt '$old' < /tmp/timed.txt 2>/dev/null");
    
    my $snap_md5 = `md5sum /tmp/snap.txt`;
    my $new_md5 = `md5sum '$new'`;
    $snap_md5 =~ s/\s.*//;
    $new_md5 =~ s/\s.*//;
    
    if ($snap_md5 eq $new_md5) {
        $pass++;
        print "PASS: delete-pacing $mode\n";
    } else {
        $fail++;
        print "FAIL: delete-pacing $mode\n";
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
