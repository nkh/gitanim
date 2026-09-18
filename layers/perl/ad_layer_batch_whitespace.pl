#!/usr/bin/env perl
# ad_layer_batch_whitespace.pl — Batch consecutive insert ops.
#
# Perl twin of ad_layer_batch_whitespace.c.
# Replaces runs of consecutive insert ops (at the same line, advancing
# col by 1 each) with a single batch_insert op:
#   batch_insert\t<line>\t<col>\t<code1>,<code2>,...
#
# Phase 2 generalization: previously only whitespace inserts (space=32,
# tab=9) were batched. Now ANY consecutive insert run is batched —
# whitespace, letters, digits, punctuation, anything. (Mirrors the C
# version.)

use strict;
use warnings;

# Parse args
for (my $ai = 0; $ai < @ARGV; $ai++) {
    if ($ARGV[$ai] eq '--help' || $ARGV[$ai] eq '-h') {
        print STDERR "ad_layer_batch_whitespace — batch consecutive insert ops\n\n";
        print STDERR "Usage: ad_layer_batch_whitespace < ops.tsv\n\n";
        print STDERR "Replaces runs of consecutive insert ops (at the same\n";
        print STDERR "line, advancing col by 1 each) with a single batch_insert\n";
        print STDERR "op: batch_insert\\t<line>\\t<col>\\t<code1>,<code2>,...\n\n";
        print STDERR "Any consecutive insert run is batched — whitespace, letters,\n";
        print STDERR "digits, punctuation, anything. (Phase 2 generalization:\n";
        print STDERR "previously only space=32 and tab=9 were batched.)\n";
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
            # Detect start of a consecutive insert run (any code).
            if ($hunk_ops[$i] =~ /^insert\t(\d+)\t(\d+)\t(\d+)/) {
                my $line_num = $1;
                my $col = $2;

                # Scan forward for consecutive inserts at the same line,
                # advancing col by 1 each (any code — Phase 2 generalization).
                my $start = $i;
                my $expected_col = $col;
                my $run_ln = $line_num;
                while ($i < scalar @hunk_ops
                       && $hunk_ops[$i] =~ /^insert\t(\d+)\t(\d+)\t(\d+)/
                       && $1 == $run_ln
                       && $2 == $expected_col) {
                    $expected_col++;
                    $i++;
                }
                my $count = $i - $start;

                if ($count >= 2) {
                    # Batch the run: emit a single batch_insert op.
                    my @codes;
                    for (my $k = $start; $k < $i; $k++) {
                        if ($hunk_ops[$k] =~ /^insert\t\d+\t\d+\t(\d+)/) {
                            push @codes, $1;
                        }
                    }
                    print "batch_insert\t$line_num\t$col\t" . join(',', @codes) . "\n";
                    next;
                }
                # Single insert — rewind and emit as-is.
                $i = $start;
            }

            # Pass through unchanged (including unknown op types:
            # delete_line, batch_insert, delay, etc.)
            print "$hunk_ops[$i]\n";
            $i++;
        }
        print "HUNK_END\n";
        @hunk_ops = ();
        next;
    }

    # Non-hunk lines that should be passed through
    if (!$in_hunk) {
        print "$line\n";
        next;
    }

    # Collect op within hunk
    push @hunk_ops, $line;
}
