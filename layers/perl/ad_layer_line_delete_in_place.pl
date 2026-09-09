#!/usr/bin/env perl
# ad_layer_line_delete_in_place.pl — Delete content BEFORE joining lines.
#
# Perl twin of ad_layer_line_delete_in_place.c.
# Two modes: --mode batch (default) or --mode interleaved.
# See C source for full documentation.

use strict;
use warnings;

my $ldi_mode = 0;  # 0=batch, 1=interleaved

# Parse args
for my $arg (@ARGV) {
    if ($arg eq '--mode' && defined $ARGV[0]) {
        # Handled below
    }
}
for (my $ai = 0; $ai < @ARGV; $ai++) {
    if ($ARGV[$ai] eq '--mode' && $ai + 1 < @ARGV) {
        $ai++;
        $ldi_mode = 1 if $ARGV[$ai] eq 'interleaved';
    } elsif ($ARGV[$ai] eq '--help' || $ARGV[$ai] eq '-h') {
        print STDERR "ad_layer_line_delete_in_place — delete content before joining lines\n\n";
        print STDERR "Usage: ad_layer_line_delete_in_place [--mode batch|interleaved] < ops.tsv\n\n";
        print STDERR "Options:\n";
        print STDERR "  --mode batch        Delete all content first, then join all (default)\n";
        print STDERR "  --mode interleaved  Delete each line then immediately join\n";
        print STDERR "  --help, -h          Show this help\n";
        exit 0;
    }
}

my @work;
while (my $line = <STDIN>) {
    chomp $line;
    push @work, $line;
}

my @out;
my $i = 0;

while ($i < scalar(@work)) {
    my @parts = split "\t", $work[$i];
    next unless defined $parts[0];

    # Pattern: join_lines(L) + delete(content at col 1) + join_lines(L)
    if ($parts[0] eq 'join_lines') {
        # Scan forward for content deletes
        my $ce = $i + 1;
        while ($ce < scalar(@work)) {
            my @cparts = split "\t", $work[$ce];
            last unless defined $cparts[0] && $cparts[0] eq 'delete';
            # Check not a line op
            last if $cparts[0] eq 'join_lines' || $cparts[0] eq 'split_line' || $cparts[0] eq 'keep_line';
            $ce++;
        }

        # Check: trailing join_lines?
        if ($ce > $i + 1 && $ce < scalar(@work)) {
            my @eparts = split "\t", $work[$ce];
            if (defined $eparts[0] && $eparts[0] eq 'join_lines') {
                # Check: content at col 1?
                my @fparts = split "\t", $work[$i + 1];
                my $content_col = defined $fparts[2] ? $fparts[2] : 1;

                if ($content_col == 1) {
                    my $joiner_line = $parts[1];
                    my $content_count = $ce - ($i + 1);

                    if ($ldi_mode == 0) {
                        # Batch mode: emit content at L+1, join at L+1, keep joiner
                        for my $k ($i + 1 .. $ce - 1) {
                            my @dparts = split "\t", $work[$k];
                            $dparts[1] = $joiner_line + 1;
                            push @out, join("\t", @dparts);
                        }
                        my @jparts = split "\t", $work[$ce];
                        $jparts[1] = $joiner_line + 1;
                        push @out, join("\t", @jparts);

                        # Remove content + 2nd join, keep joiner
                        my $removed = $content_count + 1;
                        splice(@work, $i + 1, $removed);
                        next;  # re-iterate
                    } else {
                        # Interleaved mode: pass through
                        push @out, $work[$i];
                        $i++;
                        next;
                    }
                }
            }
        }
    }

    # No match — emit unchanged
    push @out, $work[$i];
    $i++;
}

print "$_\n" for @out;
