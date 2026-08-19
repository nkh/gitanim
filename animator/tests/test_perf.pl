#!/usr/bin/env perl
# test_perf.pl — Track timing for each example and alert on regressions.
use strict;
use warnings;
use Time::HiRes qw(time);

my $root = "/home/z/my-project/gitanim";
my $threshold = 5.0;  # seconds — alert if any example takes longer

my @times;
opendir(my $dh, "$root/examples") or die $!;
my @dirs = grep { /^\d+_/ && -d "$root/examples/$_" } readdir($dh);
closedir($dh);

my $max_time = 0;
my $max_name = "";

for my $dir (sort @dirs) {
    my @olds = glob("$root/examples/$dir/old.*");
    my @news = glob("$root/examples/$dir/new.*");
    next unless @olds && @news;
    
    my $t0 = time();
    system("$root/animator/diffvim-pipeline --no-display --speed 1000 --snapshot /tmp/perf_snap.txt '$olds[0]' '$news[0]' 2>/dev/null");
    my $elapsed = time() - $t0;
    
    push @times, [$dir, $elapsed];
    if ($elapsed > $max_time) {
        $max_time = $elapsed;
        $max_name = $dir;
    }
    
    if ($elapsed > $threshold) {
        print "SLOW: $dir took ${elapsed}s\n";
    }
}

print "\nTiming summary:\n";
for my $t (sort { $b->[1] <=> $a->[1] } @times) {
    printf "  %-25s %6.3fs\n", $t->[0], $t->[1];
}
printf "\nSlowest: %s (%.3fs)\n", $max_name, $max_time;
exit(0);
