#!/usr/bin/env perl
# diffvim-pace — Insert delays between ops.
#
# Reads post-processed ops from stdin, inserts delay lines between them,
# writes timed ops to stdout.
#
# PACE DOES NOT MODIFY, REORDER, OR ADD ANY OPS.
# It only inserts "delay\t<ms>\t<type>" lines between ops.
#
# Delay types: char, word, hunk, awd_slow, awd_fast, awd_skip
#
# Usage: diffvim-pace [options] < postprocessed_ops > timed_ops

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $delete_pacing = 'word';
my $delete_speed = 'normal';
my $delete_threshold = 3;
my $insert_pacing = 'char';
my $insert_speed = 'normal';
my $snapshot_file;
my $help = 0;

GetOptions(
    'delete-pacing=s'  => \$delete_pacing,
    'delete-speed=s'    => \$delete_speed,
    'delete-threshold=i' => \$delete_threshold,
    'insert-pacing=s'   => \$insert_pacing,
    'insert-speed=s'    => \$insert_speed,
    'snapshot=s'        => \$snapshot_file,
    'help|h'            => \$help,
) or die "Usage: $0 [options]\n";

if ($help) {
    print STDERR "Usage: diffvim-pace [options]\n";
    exit 0;
}

# Timing defaults (ms)
my $char_delay = 50;
my $delete_delay = 40;
my $hunk_pause = 250;
my $awd_start_chars = 3;
my $awd_start_ms = 80;
my $awd_min_ms = 15;
my $awd_accel = 0.85;

# Apply speed multipliers
if ($delete_speed eq 'fast') {
    $delete_delay = int($delete_delay / 2);
    $awd_start_ms = int($awd_start_ms / 2);
} elsif ($delete_speed eq 'instant') {
    $delete_delay = 1;
    $awd_start_ms = 1;
    $awd_min_ms = 1;
}
if ($insert_speed eq 'fast') {
    $char_delay = int($char_delay / 2);
} elsif ($insert_speed eq 'slow') {
    $char_delay = int($char_delay * 2);
}

# Helper: convert char code to readable representation
sub char_repr {
    my ($code) = @_;
    return "\\n" if $code == 10;
    return "\\t" if $code == 9;
    return "\\r" if $code == 13;
    return "space" if $code == 32;
    if ($code >= 33 && $code <= 126) {
        return "'" . chr($code) . "'";
    }
    return "$code";
}

# Read all lines
my @lines;
while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq '' || $line =~ /^#/;
    push @lines, $line;
}

# Output header
print "# diffvim timed ops v2\n";
print "# delete_pacing $delete_pacing\n";
print "# insert_pacing $insert_pacing\n";

my $i = 0;
while ($i < @lines) {
    my @parts = split /\t/, $lines[$i];
    my $cmd = $parts[0];

    if ($cmd eq 'HUNK' || $cmd eq 'HUNK_END') {
        # Pass through, insert hunk pause between hunks
        print "$lines[$i]\n";
        if ($cmd eq 'HUNK_END' && $i + 1 < @lines) {
            my @next = split /\t/, $lines[$i + 1];
            if ($next[0] eq 'HUNK') {
                print "delay\t$hunk_pause\thunk\n";
            }
        }
        $i++;
        next;
    }

    if ($cmd eq 'keep') {
        # Pass through, insert char delay
        print "$lines[$i]\n";
        print "delay\t1\tchar\n";
        $i++;
    } elsif ($cmd eq 'delete') {
        my $code = $parts[3] // 0;
        if ($code == 10) {
            # \n delete
            print "$lines[$i]\n";
            print "delay\t$delete_delay\tchar\n";
            $i++;
        } else {
            # Non-newline delete: handle pacing
            if ($delete_pacing eq 'char') {
                print "$lines[$i]\n";
                print "delay\t$delete_delay\tchar\n";
                $i++;
            } elsif ($delete_pacing eq 'instant') {
                print "$lines[$i]\n";
                print "delay\t1\tchar\n";
                $i++;
            } else {
                # AWD: collect consecutive deletes on same line
                my $start_line = $parts[1] // 0;
                my $start_idx = $i;
                while ($i < @lines) {
                    my @p = split /\t/, $lines[$i];
                    my $c = $p[3] // 0;
                    my $l = $p[1] // 0;
                    last if $p[0] ne 'delete' || $c == 10 || $l != $start_line;
                    $i++;
                }
                my $count = $i - $start_idx;

                # AWD phases
                my $j = $start_idx;
                # Phase 1: spaces instantly
                while ($j < $i) {
                    my @p = split /\t/, $lines[$j];
                    my $c = $p[3] // 0;
                    last if $c != 32 && $c != 9;
                    print "$lines[$j]\n";
                    print "delay\t$awd_min_ms\tawd_skip\n";
                    $j++;
                }
                my $remaining = $i - $j;
                if ($remaining <= $awd_start_chars) {
                    for my $k ($j .. $i - 1) {
                        print "$lines[$k]\n";
                        print "delay\t$awd_min_ms\tawd_fast\n";
                    }
                } else {
                    # Phase 2: slow start
                    for my $k ($j .. $j + $awd_start_chars - 1) {
                        print "$lines[$k]\n";
                        print "delay\t$awd_start_ms\tawd_slow\n";
                    }
                    $j += $awd_start_chars;
                    # Phase 3: accelerated
                    my $delay = $awd_start_ms;
                    while ($j < $i) {
                        my $word_len = 0;
                        while ($j + $word_len < $i) {
                            my @p = split /\t/, $lines[$j + $word_len];
                            my $c = $p[3] // 0;
                            last if $c == 32 || $c == 9;
                            $word_len++;
                        }
                        if ($word_len > 0) {
                            for my $k ($j .. $j + $word_len - 1) {
                                print "$lines[$k]\n";
                            }
                            $delay *= $awd_accel;
                            $delay = $awd_min_ms if $delay < $awd_min_ms;
                            print "delay\t" . int($delay) . "\tawd_fast\n";
                            $j += $word_len;
                        }
                        # Skip spaces
                        if ($j < $i) {
                            my $space_start = $j;
                            while ($j < $i) {
                                my @p = split /\t/, $lines[$j];
                                my $c = $p[3] // 0;
                                last if $c != 32 && $c != 9;
                                $j++;
                            }
                            for my $k ($space_start .. $j - 1) {
                                print "$lines[$k]\n";
                            }
                            print "delay\t$awd_min_ms\tawd_skip\n";
                        }
                    }
                }
            }
        }
    } elsif ($cmd eq 'insert') {
        # Pass through, insert char delay
        print "$lines[$i]\n";
        print "delay\t$char_delay\tchar\n";
        $i++;
    } else {
        # Unknown — pass through
        print "$lines[$i]\n";
        $i++;
    }
}

if ($snapshot_file) {
    print "snapshot\t$snapshot_file\n";
}
print "\n";  # blank line at bottom
