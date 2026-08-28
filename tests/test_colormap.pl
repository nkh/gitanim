#!/usr/bin/env perl
# test_colormap.pl — Verify the C animator renders correctly with colormaps.
use strict;
use warnings;

my $root = "/home/z/my-project/gitanim";
my $pass = 0; my $fail = 0;

# Test 1: With colormap-old
my $old = "$root/examples/01_small_python/old.py";
my $new = "$root/examples/01_small_python/new.py";
system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < /tmp/raw.txt > /tmp/post.txt 2>/dev/null");
system("$root/animator/bin/pp_pace < /tmp/post.txt > /tmp/timed.txt 2>/dev/null");

# Generate colormap
system("perl $root/animator/perl/colorize.pl --backend vim '$old' /tmp/old.cm 2>/dev/null");

# Test WITH colormap
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/snap_cm.txt --colormap-old /tmp/old.cm '$old' < /tmp/timed.txt 2>/dev/null");
my $snap_md5 = `md5sum /tmp/snap_cm.txt 2>/dev/null`;
my $new_md5 = `md5sum '$new'`;
$snap_md5 =~ s/\s.*//; $new_md5 =~ s/\s.*//;
$pass++ if $snap_md5 eq $new_md5;
$fail++ unless $snap_md5 eq $new_md5;
print ($snap_md5 eq $new_md5 ? "PASS" : "FAIL", ": colormap-old renders correctly\n");

# Test WITHOUT colormap (should also work)
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/snap_nocm.txt '$old' < /tmp/timed.txt 2>/dev/null");
$snap_md5 = `md5sum /tmp/snap_nocm.txt 2>/dev/null`;
$pass++ if $snap_md5 eq $new_md5;
$fail++ unless $snap_md5 eq $new_md5;
print ($snap_md5 eq $new_md5 ? "PASS" : "FAIL", ": no-colormap renders correctly\n");

# Test 2: Colormap with larger file
$old = "$root/examples/32_python_classes/old.py";
$new = "$root/examples/32_python_classes/new.py";
system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/raw.txt 2>/dev/null");
system("$root/animator/bin/diffvim-postprocess < /tmp/raw.txt > /tmp/post.txt 2>/dev/null");
system("$root/animator/bin/pp_pace < /tmp/post.txt > /tmp/timed.txt 2>/dev/null");
system("perl $root/animator/perl/colorize.pl --backend vim '$old' /tmp/old.cm 2>/dev/null");
system("$root/animator/bin/diffvim-animator-c --no-display --speed 1000 --snapshot /tmp/snap_cm.txt --colormap-old /tmp/old.cm '$old' < /tmp/timed.txt 2>/dev/null");
$snap_md5 = `md5sum /tmp/snap_cm.txt 2>/dev/null`;
$new_md5 = `md5sum '$new'`;
$snap_md5 =~ s/\s.*//; $new_md5 =~ s/\s.*//;
$pass++ if $snap_md5 eq $new_md5;
$fail++ unless $snap_md5 eq $new_md5;
print ($snap_md5 eq $new_md5 ? "PASS" : "FAIL", ": colormap with larger file\n");

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
