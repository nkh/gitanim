#!/usr/bin/env perl
#
# Text::LogAnalyzer - Procedural-style log file analyzer.
# Reads a log file, extracts statistics, and writes a summary report.
# Uses manual file handling with no error checking.

use strict;
use warnings;

our $VERSION = '0.01';

my %LEVELS = (
    'DEBUG'   => 0,
    'INFO'    => 1,
    'WARN'    => 2,
    'ERROR'   => 3,
    'CRITICAL' => 4,
);

my @COLUMNS = qw(timestamp level pid message);

sub read_log_file {
    my ($path) = @_;
    my @lines;
    open(my $fh, '<', $path);
    while (my $line = <$fh>) {
        chomp $line;
        push @lines, $line;
    }
    close($fh);
    return @lines;
}

sub parse_line {
    my ($line) = @_;
    # Expected format: 2024-01-15T10:23:45Z [INFO] [12345] Hello world
    if ($line =~ /^(\S+)\s+\[(\w+)\]\s+\[(\d+)\]\s+(.*)$/) {
        return {
            timestamp => $1,
            level     => $2,
            pid       => $3,
            message   => $4,
        };
    }
    return undef;
}

sub filter_by_level {
    my ($entries, $min_level) = @_;
    my @result;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $lvl = $LEVELS{$entry->{level}};
        if (!defined $lvl) { next; }
        if ($lvl >= $min_level) {
            push @result, $entry;
        }
    }
    return \@result;
}

sub group_by_pid {
    my ($entries) = @_;
    my %groups;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        push @{$groups{$entry->{pid}}}, $entry;
    }
    return \%groups;
}

sub count_by_level {
    my ($entries) = @_;
    my %counts;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        $counts{$entry->{level}}++;
    }
    return \%counts;
}

sub find_error_patterns {
    my ($entries) = @_;
    my @errors;
    my $current;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        if ($entry->{level} eq 'ERROR' || $entry->{level} eq 'CRITICAL') {
            if ($current && $current->{pid} eq $entry->{pid}) {
                push @{$current->{related}}, $entry;
            } else {
                if ($current) {
                    push @errors, $current;
                }
                $current = {
                    timestamp => $entry->{timestamp},
                    pid       => $entry->{pid},
                    message   => $entry->{message},
                    related   => [],
                };
            }
        } else {
            if ($current) {
                push @errors, $current;
                $current = undef;
            }
        }
    }
    if ($current) {
        push @errors, $current;
    }
    return \@errors;
}

sub extract_timestamp_range {
    my ($entries) = @_;
    my $min;
    my $max;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $ts = $entry->{timestamp};
        if (!defined $min || $ts lt $min) {
            $min = $ts;
        }
        if (!defined $max || $ts gt $max) {
            $max = $ts;
        }
    }
    return ($min, $max);
}

sub write_summary_report {
    my ($entries, $output_path) = @_;
    my $counts = count_by_level($entries);
    my ($min_ts, $max_ts) = extract_timestamp_range($entries);
    my $errors = find_error_patterns($entries);
    my $groups = group_by_pid($entries);

    open(my $fh, '>', $output_path);
    print $fh "=== Log Analysis Summary ===\n";
    print $fh "Time range: $min_ts to $max_ts\n";
    print $fh "Total entries: ", scalar(@$entries), "\n";
    print $fh "\nBy level:\n";
    for my $level (sort keys %$counts) {
        print $fh "  $level: $counts->{$level}\n";
    }
    print $fh "\nUnique PIDs: ", scalar(keys %$groups), "\n";
    print $fh "\nError patterns (", scalar(@$errors), "):\n";
    for my $err (@$errors) {
        print $fh "  [$err->{timestamp}] PID $err->{pid}: $err->{message}\n";
        for my $rel (@{$err->{related}}) {
            print $fh "    + [$rel->{timestamp}] $rel->{message}\n";
        }
    }
    close($fh);
}

sub write_csv_report {
    my ($entries, $output_path) = @_;
    open(my $fh, '>', $output_path);
    print $fh join(',', @COLUMNS), "\n";
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $msg = $entry->{message};
        $msg =~ s/"/""/g;
        print $fh "$entry->{timestamp},$entry->{level},$entry->{pid},\"$msg\"\n";
    }
    close($fh);
}

sub merge_log_files {
    my ($paths) = @_;
    my @all_entries;
    for my $path (@$paths) {
        my @lines = read_log_file($path);
        for my $line (@lines) {
            my $entry = parse_line($line);
            if ($entry) {
                push @all_entries, $entry;
            }
        }
    }
    @all_entries = sort { $a->{timestamp} cmp $b->{timestamp} } @all_entries;
    return \@all_entries;
}

sub deduplicate_entries {
    my ($entries) = @_;
    my %seen;
    my @unique;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $key = "$entry->{timestamp}:$entry->{pid}:$entry->{message}";
        if (!$seen{$key}) {
            $seen{$key} = 1;
            push @unique, $entry;
        }
    }
    return \@unique;
}

sub extract_context {
    my ($entries, $index, $before, $after) = @_;
    my @context;
    my $start = $index - $before;
    if ($start < 0) { $start = 0; }
    my $end = $index + $after;
    if ($end > $#$entries) { $end = $#$entries; }
    for my $i ($start .. $end) {
        push @context, $entries->[$i];
    }
    return \@context;
}

sub top_messages {
    my ($entries, $n) = @_;
    my %counts;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        $counts{$entry->{message}}++;
    }
    my @sorted = sort { $counts{$b} <=> $counts{$a} } keys %counts;
    my @top;
    for my $i (0 .. $n - 1) {
        if ($i > $#sorted) { last; }
        push @top, { message => $sorted[$i], count => $counts{$sorted[$i]} };
    }
    return \@top;
}

sub compute_percentiles {
    my ($entries, $percentiles) = @_;
    my @latencies;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        if ($entry->{message} =~ /latency=(\d+(?:\.\d+)?)/) {
            push @latencies, $1 + 0;
        }
    }
    @latencies = sort { $a <=> $b } @latencies;
    my %result;
    my $n = scalar(@latencies);
    if ($n == 0) {
        for my $p (@$percentiles) {
            $result{$p} = undef;
        }
        return \%result;
    }
    for my $p (@$percentiles) {
        my $idx = int(($p / 100) * ($n - 1));
        $result{$p} = $latencies[$idx];
    }
    return \%result;
}

sub rolling_average {
    my ($entries, $window) = @_;
    my @result;
    my @window_buf;
    my $sum = 0;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $value;
        if ($entry->{message} =~ /latency=(\d+(?:\.\d+)?)/) {
            $value = $1 + 0;
        } else {
            next;
        }
        push @window_buf, $value;
        $sum += $value;
        if (scalar(@window_buf) > $window) {
            $sum -= shift @window_buf;
        }
        my $avg = $sum / scalar(@window_buf);
        push @result, {
            timestamp => $entry->{timestamp},
            pid       => $entry->{pid},
            average   => $avg,
            count     => scalar(@window_buf),
        };
    }
    return \@result;
}

sub bucket_by_hour {
    my ($entries) = @_;
    my %buckets;
    for my $entry (@$entries) {
        if (!defined $entry) { next; }
        my $ts = $entry->{timestamp};
        if ($ts =~ /^(\d{4}-\d{2}-\d{2}T\d{2}):/) {
            $buckets{$1}++;
        }
    }
    return \%buckets;
}

sub detect_bursts {
    my ($entries, $threshold) = @_;
    $threshold //= 50;
    my $buckets = bucket_by_hour($entries);
    my @bursts;
    for my $hour (sort keys %$buckets) {
        if ($buckets->{$hour} >= $threshold) {
            push @bursts, { hour => $hour, count => $buckets->{$hour} };
        }
    }
    return \@bursts;
}

sub correlate_pids {
    my ($entries) = @_;
    my $groups = group_by_pid($entries);
    my @correlations;
    my @pids = sort { $a <=> $b } keys %$groups;
    for my $i (0 .. $#pids - 1) {
        my $pid_a = $pids[$i];
        my $pid_b = $pids[$i + 1];
        my $entries_a = $groups->{$pid_a};
        my $entries_b = $groups->{$pid_b};
        my $a_count = scalar(@$entries_a);
        my $b_count = scalar(@$entries_b);
        if ($a_count > 0 && $b_count > 0) {
            my $time_gap = $entries_b->[0]{timestamp}
                         cmp $entries_a->[-1]{timestamp};
            push @correlations, {
                pid_a    => $pid_a,
                pid_b    => $pid_b,
                a_count  => $a_count,
                b_count  => $b_count,
                time_gap => $time_gap,
            };
        }
    }
    return \@correlations;
}

sub analyze {
    my ($input_path, $summary_path, $csv_path) = @_;
    my @lines = read_log_file($input_path);
    my @entries;
    for my $line (@lines) {
        my $entry = parse_line($line);
        if ($entry) {
            push @entries, $entry;
        }
    }
    my $filtered = filter_by_level(\@entries, $LEVELS{'WARN'});
    my $deduped = deduplicate_entries($filtered);
    write_summary_report($deduped, $summary_path);
    write_csv_report($deduped, $csv_path);
    return {
        total      => scalar(@entries),
        filtered   => scalar(@$filtered),
        deduped    => scalar(@$deduped),
        summary    => $summary_path,
        csv        => $csv_path,
    };
}

1;

__END__

=head1 NAME

Text::LogAnalyzer - Procedural log file analyzer

=head1 SYNOPSIS

  use Text::LogAnalyzer;
  my $result = analyze('app.log', 'summary.txt', 'entries.csv');

=cut
