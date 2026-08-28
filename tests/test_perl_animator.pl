#!/usr/bin/env perl
# test_perl_animator.pl — Test all 42 examples with the Perl animator.
use strict;
use warnings;

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

opendir(my $dh, "$root/examples") or die "Cannot open examples: $!";
my @dirs = grep { /^\d+_/ && -d "$root/examples/$_" } readdir($dh);
closedir($dh);

for my $dir (sort @dirs) {
    my @olds = glob("$root/examples/$dir/old.*");
    my @news = glob("$root/examples/$dir/new.*");
    next unless @olds && @news;
    my $old = $olds[0];
    my $new = $news[0];
    
    my $tmp = "/tmp/perl_anim_test.txt";
    unlink $tmp;
    
    system("$root/compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/raw.txt 2>/dev/null");
    system("perl $root/animator/perl/postprocess.pl < /tmp/raw.txt > /tmp/post.txt 2>/dev/null");
    system("perl $root/animator/perl/pace.pl < /tmp/post.txt > /tmp/timed.txt 2>/dev/null");
    system("perl $root/animator/perl/animator.pl --no-display --speed 1000 --snapshot $tmp '$old' < /tmp/timed.txt 2>/dev/null");
    
    my $snap_md5 = `md5sum $tmp 2>/dev/null`;
    my $new_md5 = `md5sum '$new'`;
    $snap_md5 =~ s/\s.*//;
    $new_md5 =~ s/\s.*//;
    
    if ($snap_md5 eq $new_md5) {
        $pass++;
    } else {
        $fail++;
        print "FAIL: $dir\n";
    }
}

print "\n=== Perl animator: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
