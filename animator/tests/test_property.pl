#!/usr/bin/env perl
# test_property.pl — Property-based testing: generate random file pairs
# and verify that animate(old, new) == new for all inputs.
use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;
my $tmpdir = tempdir(CLEANUP => 1);

sub random_file {
    my ($path, $nlines, $maxlen) = @_;
    open my $fh, '>:raw', $path or die $!;
    for my $i (1..$nlines) {
        my $len = 1 + int(rand($maxlen));
        my $line = '';
        $line .= chr(32 + int(rand(94))) for 1..$len;  # printable ASCII
        print $fh $line, "\n";
    }
    close $fh;
}

sub mutate_file {
    my ($old, $new) = @_;
    open my $fh, '<:raw', $old or die $!;
    my @lines = <$fh>;
    close $fh;
    chomp @lines;
    
    # Apply random mutations
    my $n_mutations = 1 + int(rand(5));
    for (1..$n_mutations) {
        my $op = int(rand(4));
        if ($op == 0 && @lines > 0) {
            # Delete a line
            splice(@lines, int(rand(@lines)), 1);
        } elsif ($op == 1) {
            # Insert a line
            my $idx = int(rand(@lines + 1));
            my $len = 1 + int(rand(20));
            my $line = '';
            $line .= chr(32 + int(rand(94))) for 1..$len;
            splice(@lines, $idx, 0, $line);
        } elsif ($op == 2 && @lines > 0) {
            # Modify a line
            my $idx = int(rand(@lines));
            my $len = 1 + int(rand(20));
            my $line = '';
            $line .= chr(32 + int(rand(94))) for 1..$len;
            $lines[$idx] = $line;
        } elsif ($op == 3 && @lines > 0) {
            # Swap two lines
            my $i = int(rand(@lines));
            my $j = int(rand(@lines));
            @lines[$i,$j] = @lines[$j,$i];
        }
    }
    
    open $fh, '>:raw', $new or die $!;
    print $fh "$_\n" for @lines;
    close $fh;
}

# Run 50 random test cases
for my $i (1..50) {
    my $old = "$tmpdir/old_$i.txt";
    my $new = "$tmpdir/new_$i.txt";
    my $snap = "$tmpdir/snap_$i.txt";
    
    random_file($old, 5 + int(rand(20)), 30);
    mutate_file($old, $new);
    
    system("$root/animator/diffvim-pipeline --no-display --speed 1000 --snapshot $snap $old $new 2>/dev/null");
    
    my $md5_snap = `md5sum $snap 2>/dev/null` // '';
    my $md5_new = `md5sum $new` // '';
    $md5_snap =~ s/\s.*//;
    $md5_new =~ s/\s.*//;
    
    if ($md5_snap eq $md5_new) {
        $pass++;
    } else {
        $fail++;
        print "FAIL: test $i\n";
        print "  old: $old\n  new: $new\n  snap: $snap\n";
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
