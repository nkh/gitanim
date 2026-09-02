#!/usr/bin/env perl
# ad_layer_pace — Insert delays between ops.
#
# Reads post-processed ops from stdin, inserts delay lines between them,
# writes timed ops to stdout.
#
# PACE DOES NOT MODIFY, REORDER, OR ADD ANY OPS.
# It only inserts "delay\t<ms>\t<type>" lines between ops.
#
# Delay types: char, word, hunk, awd_slow, awd_fast, awd_skip
#
# Usage: ad_layer_pace [options] < postprocessed_ops > timed_ops

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $delete_pacing = 'word';
my $delete_speed = 'normal';
my $delete_threshold = 3;
my $insert_pacing = 'char';
my $insert_speed = 'normal';
my $pacing_mode = 'uniform';
my $gaussian_jitter_pct = 20;
my $pause_after_lines = 0;
my $pause_after_threshold = 50;
my $pause_after_ms = 500;
my $accel_delete = 0;
my $accel_delete_start_ms = 80;
my $accel_delete_min_ms = 10;
my $accel_delete_accel = 0.85;
my $block_delete_size = 3;
my $pause_before_delete_ms = 200;
my $pause_after_delete_ms = 200;
my $snapshot_file;
my $help = 0;

# Pacing state for adaptive mode
my $prev_op_type = '';
my $adaptive_run_count = 0;

GetOptions(
    'delete-pacing=s'      => \$delete_pacing,
    'delete-speed=s'        => \$delete_speed,
    'delete-threshold=i'     => \$delete_threshold,
    'insert-pacing=s'       => \$insert_pacing,
    'insert-speed=s'        => \$insert_speed,
    'pacing=s'              => \$pacing_mode,
    'gaussian-jitter-pct=i'  => \$gaussian_jitter_pct,
    'pause-after-lines=i'     => \$pause_after_lines,
    'pause-after-threshold=i'  => \$pause_after_threshold,
    'pause-after-ms=i'         => \$pause_after_ms,
    'accel-delete'             => sub { $accel_delete = 1; },
    'accel-delete-start-ms=i'   => \$accel_delete_start_ms,
    'accel-delete-min-ms=i'      => \$accel_delete_min_ms,
    'accel-delete-accel=f'       => \$accel_delete_accel,
    'block-delete-size=i'        => \$block_delete_size,
    'pause-before-delete-ms=i'   => \$pause_before_delete_ms,
    'pause-after-delete-ms=i'    => \$pause_after_delete_ms,
    'snapshot=s'             => \$snapshot_file,
    'help|h'                 => \$help,
) or die "Usage: $0 [options]\n";

if ($help) {
    print STDERR "Usage: ad_layer_pace [options]\n";
    exit 0;
}

srand(time());

# Apply pacing mode to a delay value. Returns adjusted delay.
sub apply_pacing {
    my ($delay) = @_;
    return 0 if $delay <= 0;

    if ($pacing_mode eq 'review') {
        return $delay * 2;
    }

    if ($pacing_mode eq 'gaussian') {
        my $jitter = int(($delay * $gaussian_jitter_pct) / 100);
        if ($jitter > 0) {
            my $offset = int(rand(2 * $jitter + 1)) - $jitter;
            my $result = $delay + $offset;
            return $result < 1 ? 1 : $result;
        }
        return $delay;
    }

    if ($pacing_mode eq 'adaptive') {
        return int($delay * 0.4) if $adaptive_run_count > 20;
        return int($delay * 0.6) if $adaptive_run_count > 10;
        return int($delay * 0.8) if $adaptive_run_count > 5;
        return $delay;
    }

    # uniform (default): no change
    return $delay;
}

sub track_op_type {
    my ($type) = @_;
    if ($type eq $prev_op_type) {
        $adaptive_run_count++;
    } else {
        $prev_op_type = $type;
        $adaptive_run_count = 0;
    }
}

sub emit_paced_delay {
    my ($ms, $type) = @_;
    my $adjusted = apply_pacing($ms);
    print "delay\t$adjusted\t$type\n";
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

# Read all lines (stop at EOF)
my @lines;
while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq '' || $line =~ /^#/;
    last if $line eq 'EOF';
    push @lines, $line;
}

# Output header
print "# diffvim timed ops v2\n";
print "# delete_pacing $delete_pacing\n";
print "# insert_pacing $insert_pacing\n";

my $i = 0;
my $changed_lines = 0;
while ($i < @lines) {
    my @parts = split /\t/, $lines[$i];
    my $cmd = $parts[0];

    if ($cmd eq 'HUNK' || $cmd eq 'HUNK_END') {
        # Pass through, insert hunk pause between hunks
        print "$lines[$i]\n";
        if ($cmd eq 'HUNK_END' && $i + 1 < @lines) {
            my @next = split /\t/, $lines[$i + 1];
            if ($next[0] eq 'HUNK') {
                emit_paced_delay($hunk_pause, "hunk");
            }
        }
        $i++;
        next;
    }

    if ($cmd eq 'keep') {
        track_op_type("keep");
        # Pass through, insert char delay
        print "$lines[$i]\n";
        emit_paced_delay(1, "char");
        $i++;
    } elsif ($cmd eq 'delete') {
        track_op_type("delete");
        my $code = $parts[3] // 0;
        if ($code == 10) {
            # \n delete — check for multi-line accel delete
            if ($accel_delete) {
                # Collect consecutive \n deletes
                my $start_idx = $i;
                while ($i < @lines) {
                    my @p = split /\t/, $lines[$i];
                    my $c = $p[3] // 0;
                    last if $p[0] ne 'delete' || $c != 10;
                    $i++;
                }
                my $count = $i - $start_idx;
                my $delay = $accel_delete_start_ms;
                for my $k ($start_idx .. $start_idx + $count - 1) {
                    print "$lines[$k]\n";
                    my $remaining = ($start_idx + $count) - $k;
                    if ($remaining <= 3) {
                        my $d = $accel_delete_start_ms * (4 - $remaining) / 3.0;
                        emit_paced_delay(int($d), "accel_delete");
                    } else {
                        emit_paced_delay(int($delay), "accel_delete");
                        $delay *= $accel_delete_accel;
                        $delay = $accel_delete_min_ms if $delay < $accel_delete_min_ms;
                    }
                    $changed_lines++;
                    if ($pause_after_lines > 0 && $changed_lines % $pause_after_lines == 0
                        && scalar(@lines) > $pause_after_threshold) {
                        emit_paced_delay($pause_after_ms, "pause_after");
                    }
                }
            } else {
                # Normal \n delete
                print "$lines[$i]\n";
                emit_paced_delay($delete_delay, "char");
                $changed_lines++;
                if ($pause_after_lines > 0 && $changed_lines % $pause_after_lines == 0
                    && scalar(@lines) > $pause_after_threshold) {
                    emit_paced_delay($pause_after_ms, "pause_after");
                }
                $i++;
            }
        } else {
            # Non-newline delete: handle pacing
            if ($delete_pacing eq 'char') {
                # Block delete: group consecutive char deletes, pause before/after
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
                if ($count > $block_delete_size) {
                    emit_paced_delay($pause_before_delete_ms, "block_start");
                }
                for my $k ($start_idx .. $i - 1) {
                    print "$lines[$k]\n";
                    emit_paced_delay($delete_delay, "char");
                }
                if ($count > $block_delete_size) {
                    emit_paced_delay($pause_after_delete_ms, "block_end");
                }
            } elsif ($delete_pacing eq 'instant') {
                print "$lines[$i]\n";
                emit_paced_delay(1, "char");
                $i++;
            } elsif ($delete_pacing eq 'rapid-eol') {
                # Rapid EOL: delete trailing chars rapidly
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
                if ($count <= $delete_threshold) {
                    for my $k ($start_idx .. $i - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay($delete_delay, "rapid_eol");
                    }
                } else {
                    my $delay = $delete_delay;
                    for my $k ($start_idx .. $i - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay(int($delay), "rapid_eol");
                        $delay *= $awd_accel;
                        $delay = $awd_min_ms if $delay < $awd_min_ms;
                    }
                }
            } elsif ($delete_pacing eq 'rapid-identical') {
                # Rapid identical: delete runs of same char rapidly
                my $start_line = $parts[1] // 0;
                my $start_idx = $i;
                my $start_code = $code;
                while ($i < @lines) {
                    my @p = split /\t/, $lines[$i];
                    my $c = $p[3] // 0;
                    my $l = $p[1] // 0;
                    last if $p[0] ne 'delete' || $c != $start_code || $l != $start_line;
                    $i++;
                }
                my $count = $i - $start_idx;
                if ($count <= $delete_threshold) {
                    for my $k ($start_idx .. $i - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay($delete_delay, "rapid_identical");
                    }
                } else {
                    my $delay = $delete_delay;
                    for my $k ($start_idx .. $i - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay(int($delay), "rapid_identical");
                        $delay *= $awd_accel;
                        $delay = $awd_min_ms if $delay < $awd_min_ms;
                    }
                }
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
                    emit_paced_delay($awd_min_ms, "awd_skip");
                    $j++;
                }
                my $remaining = $i - $j;
                if ($remaining <= $awd_start_chars) {
                    for my $k ($j .. $i - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay($awd_min_ms, "awd_fast");
                    }
                } else {
                    # Phase 2: slow start
                    for my $k ($j .. $j + $awd_start_chars - 1) {
                        print "$lines[$k]\n";
                        emit_paced_delay($awd_start_ms, "awd_slow");
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
                            emit_paced_delay(int($delay), "awd_fast");
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
                            emit_paced_delay($awd_min_ms, "awd_skip");
                        }
                    }
                }
            }
        }
    } elsif ($cmd eq 'insert' || $cmd eq 'overwrite_insert') {
        track_op_type("insert");
        my $code = $parts[3] // 0;
        # Pass through op
        print "$lines[$i]\n";
        # Insert delay based on type
        if ($cmd eq 'overwrite_insert') {
            emit_paced_delay(1, "overwrite");
        } else {
            emit_paced_delay($char_delay, "char");
        }
        if ($code == 10) {
            # \n insert — counts as a changed line
            $changed_lines++;
            if ($pause_after_lines > 0 && $changed_lines % $pause_after_lines == 0
                && scalar(@lines) > $pause_after_threshold) {
                emit_paced_delay($pause_after_ms, "pause_after");
            }
        }
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
