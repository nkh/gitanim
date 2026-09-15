#!/usr/bin/env perl
# test_property_reversed.pl — Property-based testing in REVERSED direction:
# generate random file pairs (old, new), then run the pipeline as
# new -> old (swap argument order) and verify animate(new, old) == old
# for all inputs. Mirrors tests/test_property.pl but reversed.
#
# This stresses the symmetric property: any valid transformation must be
# reversible through the same pipeline.
use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;
my $iterations = $ENV{AD_PROPERTY_REVERSED_ITERATIONS} // 100;
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

# Run $iterations random test cases in REVERSED direction
for my $i (1..$iterations) {
    my $old = "$tmpdir/old_$i.txt";
    my $new = "$tmpdir/new_$i.txt";
    my $snap = "$tmpdir/snap_$i.txt";

    random_file($old, 5 + int(rand(20)), 30);
    mutate_file($old, $new);

    # REVERSED: pipeline args are new old (swap), target is `old`
    system("$root/pipeline/ad_pipeline --no-display --speed 1000 --snapshot $snap $new $old 2>/dev/null");

    my $md5_snap = `md5sum $snap 2>/dev/null` // '';
    my $md5_target = `md5sum $old` // '';
    $md5_snap =~ s/\s.*//;
    $md5_target =~ s/\s.*//;

    if ($md5_snap eq $md5_target) {
        $pass++;
    } else {
        $fail++;
        print "FAIL: test $i\n";
        print "  start (new): $new\n  target (old): $old\n  snap: $snap\n";

        # Run L1/L2 to find where the divergence begins
        my $timed = "$tmpdir/timed_$i.txt";
        # Re-run pipeline stages individually to get the timed file
        system("$root/bin/ad_compute $new $old $tmpdir/raw_$i.txt 2>/dev/null");
        system("$root/pipeline/ad_postprocess --ad-layer=ad_layer_reorder < $tmpdir/raw_$i.txt > $tmpdir/post_$i.txt 2>/dev/null");
        system("$root/bin/ad_layer_pace < $tmpdir/post_$i.txt > $timed 2>/dev/null");
        my $l1l2 = `$root/scripts/ad_l1l2 $new $old $timed 2>/dev/null` // '';
        if ($l1l2 ne '') {
            print "  L1/L2:\n";
            $l1l2 =~ s/^/    /mg;
            print $l1l2;
        }
    }
}

print "\n=== Reversed property results: $pass passed, $fail failed (out of $iterations) ===\n";
exit($fail == 0 ? 0 : 1);
