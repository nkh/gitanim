#!/usr/bin/env perl
# ad_layer_line_delete_in_place.pl — Delete content BEFORE joining lines.
#
# Perl twin of ad_layer_line_delete_in_place.c.
# See the C source for full documentation.
#
# Pattern: join_lines(L) + delete(content at L, col 1) + join_lines(L)
# Reorder: delete(content at L+1) + join_lines(L+1) + [joiner stays]
#
# Only matches when content deletes are at col 1 (full line deletion).
# Partial content at col > 1 is left unchanged.
#
# Build: None (Perl script)
# Usage:  ad_layer_line_delete_in_place < ops.tsv > processed.tsv

use strict;
use warnings;

my @ops;
while (my $line = <STDIN>) {
    chomp $line;
    push @ops, $line;
}

my @work = @ops;
my @out;
my $i = 0;

while ($i < scalar(@work)) {
    my @parts = split "\t", $work[$i];

    # Pattern: join_lines(L) + delete(content, col 1) + join_lines(L)
    if ($parts[0] eq 'join_lines') {
        # Scan forward for content deletes
        my $ce = $i + 1;
        while ($ce < scalar(@work)) {
            my @cparts = split "\t", $work[$ce];
            last unless $cparts[0] eq 'delete' && defined $cparts[3] && $cparts[3] != 10;
            $ce++;
        }

        # Check: trailing join_lines?
        if ($ce > $i + 1 && $ce < scalar(@work)) {
            my @eparts = split "\t", $work[$ce];
            if ($eparts[0] eq 'join_lines') {
                # Check: content at col 1?
                my @fparts = split "\t", $work[$i + 1];
                my $content_col = $fparts[2] // 1;

                if ($content_col == 1) {
                    # Full line deletion — reorder
                    my $joiner_line = $parts[1];

                    # Emit content deletes at line+1
                    for my $k ($i + 1 .. $ce - 1) {
                        my @dparts = split "\t", $work[$k];
                        $dparts[1] = $joiner_line + 1;
                        push @out, join("\t", @dparts);
                    }
                    # Emit second join_lines at line+1
                    my @jparts = split "\t", $work[$ce];
                    $jparts[1] = $joiner_line + 1;
                    push @out, join("\t", @jparts);

                    # Remove content + 2nd join from work, keep joiner
                    my $removed = ($ce - ($i + 1)) + 1;
                    splice(@work, $i + 1, $removed);
                    next;  # re-iterate at joiner
                }
            }
        }
    }

    # No match — emit unchanged
    push @out, $work[$i];
    $i++;
}

print "$_\n" for @out;
