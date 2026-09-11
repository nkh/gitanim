#!/usr/bin/env perl
# ad_layer_batch_whitespace.pl — Batch consecutive whitespace insert ops.
#
# Perl twin of ad_layer_batch_whitespace.c.
# Replaces runs of consecutive whitespace inserts (tab=9, space=32)
# with a single batch_insert op: batch_insert\t<L>\t<C>\t<code1>,<code2>,...
#
# Only batches WHITESPACE chars. Other chars are left as individual
# insert ops.

use strict;
use warnings;

my $WS_TAB   = 9;
my $WS_SPACE = 32;

sub is_whitespace {
    my ($code) = @_;
    return $code == $WS_TAB || $code == $WS_SPACE;
}

# Parse args
for (my $ai = 0; $ai < @ARGV; $ai++) {
    if ($ARGV[$ai] eq '--help' || $ARGV[$ai] eq '-h') {
        print STDERR "ad_layer_batch_whitespace — batch whitespace insert ops\n\n";
        print STDERR "Usage: ad_layer_batch_whitespace < ops.tsv\n\n";
        print STDERR "Replaces runs of consecutive whitespace inserts (tab=9,\n";
        print STDERR "space=32) with a single batch_insert op.\n";
        exit 0;
    }
}

# Read all lines
my @lines = <STDIN>;
my $in_hunk = 0;
my @hunk_ops = ();

for my $line (@lines) {
    chomp $line;

    # Pass through comments and blank lines
    if ($line =~ /^#/ || $line eq '') {
        print "$line\n";
        next;
    }

    # HUNK header
    if ($line =~ /^HUNK\t/) {
        $in_hunk = 1;
        @hunk_ops = ();
        print "$line\n";
        next;
    }

    # HUNK_END — process collected ops
    if ($line =~ /^HUNK_END/) {
        $in_hunk = 0;
        # Process the hunk's ops
        my $i = 0;
        while ($i < scalar @hunk_ops) {
            # Check for insert + whitespace
            if ($hunk_ops[$i] =~ /^insert\t(\d+)\t(\d+)\t(\d+)/) {
                my $line_num = $1;
                my $col = $2;
                my $code = $3;

                if (is_whitespace($code)) {
                    # Scan forward for consecutive whitespace inserts
                    my $start = $i;
                    my $expected_col = $col;
                    while ($i < scalar @hunk_ops
                           && $hunk_ops[$i] =~ /^insert\t(\d+)\t(\d+)\t(\d+)/
                           && $1 == $line_num
                           && $2 == $expected_col
                           && is_whitespace($3)) {
                        $expected_col++;
                        $i++;
                    }
                    my $count = $i - $start;

                    if ($count >= 2) {
                        # Build comma-separated codes
                        my @codes;
                        for (my $k = $start; $k < $i; $k++) {
                            if ($hunk_ops[$k] =~ /^insert\t\d+\t\d+\t(\d+)/) {
                                push @codes, $1;
                            }
                        }
                        print "batch_insert\t$line_num\t$col\t" . join(',', @codes) . "\n";
                        next;
                    }
                    # Single whitespace — rewind and emit as-is
                    $i = $start;
                }
            }

            # Pass through unchanged
            # Also pass through unknown op types (delete_line, batch_insert, etc.)
            print "$hunk_ops[$i]\n";
            $i++;
        }
        print "HUNK_END\n";
        @hunk_ops = ();
        next;
    }

    # Non-hunk lines that should be passed through
    # (delay, snapshot, highlight, dim, fold, sign, marker, etc.)
    if (!$in_hunk) {
        print "$line\n";
        next;
    }

    # Collect op within hunk
    push @hunk_ops, $line;
}
