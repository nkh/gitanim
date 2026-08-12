#!/usr/bin/env perl
#
# Text::LogAnalyzer - Object-oriented log file analyzer with proper error
# handling, streaming I/O, and an embedded test suite (run with --test).
#
# Uses Moose for OO, Try::Tiny for exception handling, and namespace::autoclean
# to keep the namespace tidy.

package Text::LogAnalyzer;

use Moose;
use namespace::autoclean;
use Try::Tiny;
use Carp qw(croak);
use Scalar::Util qw(looks_like_number);

our $VERSION = '1.00';

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

my %LEVELS = (
    DEBUG    => 0,
    INFO     => 1,
    WARN     => 2,
    ERROR    => 3,
    CRITICAL => 4,
);

my @COLUMNS = qw(timestamp level pid message);

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------

package Text::LogAnalyzer::Exception;
use Moose;
has message => (is => 'ro', isa => 'Str', required => 1);
has file    => (is => 'ro', isa => 'Maybe[Str]', default => undef);
has line    => (is => 'ro', isa => 'Maybe[Int]',  default => undef);
__PACKAGE__->meta->make_immutable;

package Text::LogAnalyzer::IOError;
use Moose;
extends 'Text::LogAnalyzer::Exception';
has operation => (is => 'ro', isa => 'Str', required => 1);
__PACKAGE__->meta->make_immutable;

package Text::LogAnalyzer::ParseError;
use Moose;
extends 'Text::LogAnalyzer::Exception';
has raw_line => (is => 'ro', isa => 'Str', required => 1);
__PACKAGE__->meta->make_immutable;

package Text::LogAnalyzer;

# ---------------------------------------------------------------------------
# Attributes
# ---------------------------------------------------------------------------

has min_level => (
    is      => 'ro',
    isa     => 'Str',
    default => 'WARN',
    trigger => sub {
        my ($self, $val) = @_;
        croak "Unknown log level: $val" unless exists $LEVELS{uc $val};
    },
);

has strict_mode => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has keep_unparseable => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1,
);

has deduplicate => (
    is      => 'ro',
    isa     => 'Bool',
    default => 0,
);

has encoding => (
    is      => 'ro',
    isa     => 'Str',
    default => 'UTF-8',
);

# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------

sub BUILDARGS {
    my ($class, %args) = @_;
    $args{min_level} = uc($args{min_level}) if exists $args{min_level};
    return \%args;
}

# ---------------------------------------------------------------------------
# Public methods
# ---------------------------------------------------------------------------

sub level_value {
    my ($self, $level) = @_;
    return $LEVELS{uc $level};
}

sub read_log_file {
    my ($self, $path) = @_;
    croak "path is required" unless defined $path;
    my @lines;
    try {
        open(my $fh, "<:encoding(" . $self->encoding . ")", $path)
            or die "open failed: $!";
        while (my $line = <$fh>) {
            chomp $line;
            push @lines, $line;
        }
        close($fh) or die "close failed: $!";
    } catch {
        Text::LogAnalyzer::IOError->throw(
            message   => "Failed to read $path: $_",
            operation => 'read',
            file      => $path,
        );
    };
    return @lines;
}

sub parse_line {
    my ($self, $line) = @_;
    return undef unless defined $line;
    # Expected: 2024-01-15T10:23:45Z [INFO] [12345] Hello world
    if ($line =~ /^(\S+)\s+\[(\w+)\]\s+\[(\d+)\]\s+(.*)$/) {
        my ($ts, $level, $pid, $msg) = ($1, $2, $3, $4);
        unless (exists $LEVELS{uc $level}) {
            if ($self->strict_mode) {
                Text::LogAnalyzer::ParseError->throw(
                    message  => "Unknown log level: $level",
                    raw_line => $line,
                );
            }
            return undef;
        }
        return {
            timestamp => $ts,
            level     => uc $level,
            pid       => int($pid),
            message   => $msg,
        };
    }
    if ($self->strict_mode) {
        Text::LogAnalyzer::ParseError->throw(
            message  => "Malformed log line",
            raw_line => $line,
        );
    }
    return undef;
}

sub parse_lines {
    my ($self, $lines) = @_;
    my @entries;
    for my $line (@$lines) {
        my $entry = $self->parse_line($line);
        if ($entry) {
            push @entries, $entry;
        } elsif ($self->keep_unparseable) {
            push @entries, { timestamp => '', level => 'UNKNOWN',
                             pid => 0, message => $line };
        }
    }
    return \@entries;
}

sub filter_by_level {
    my ($self, $entries) = @_;
    my $threshold = $LEVELS{$self->min_level};
    return [ grep { defined $_ && $LEVELS{$_->{level}} >= $threshold } @$entries ];
}

sub group_by_pid {
    my ($self, $entries) = @_;
    my %groups;
    for my $entry (@$entries) {
        next unless defined $entry;
        push @{$groups{$entry->{pid}}}, $entry;
    }
    return \%groups;
}

sub count_by_level {
    my ($self, $entries) = @_;
    my %counts;
    for my $entry (@$entries) {
        next unless defined $entry;
        $counts{$entry->{level}}++;
    }
    return \%counts;
}

sub find_error_patterns {
    my ($self, $entries) = @_;
    my @errors;
    my $current;
    for my $entry (@$entries) {
        next unless defined $entry;
        my $is_error = $entry->{level} eq 'ERROR' || $entry->{level} eq 'CRITICAL';
        if ($is_error) {
            if ($current && $current->{pid} == $entry->{pid}) {
                push @{$current->{related}}, $entry;
            } else {
                if ($current) { push @errors, $current; }
                $current = {
                    timestamp => $entry->{timestamp},
                    pid       => $entry->{pid},
                    message   => $entry->{message},
                    related   => [],
                };
            }
        } else {
            if ($current) { push @errors, $current; $current = undef; }
        }
    }
    if ($current) { push @errors, $current; }
    return \@errors;
}

sub extract_timestamp_range {
    my ($self, $entries) = @_;
    my ($min, $max);
    for my $entry (@$entries) {
        next unless defined $entry && length $entry->{timestamp};
        my $ts = $entry->{timestamp};
        $min = $ts if !defined $min || $ts lt $min;
        $max = $ts if !defined $max || $ts gt $max;
    }
    return ($min, $max);
}

sub deduplicate_entries {
    my ($self, $entries) = @_;
    return $entries unless $self->deduplicate;
    my %seen;
    my @unique;
    for my $entry (@$entries) {
        next unless defined $entry;
        my $key = "$entry->{timestamp}:$entry->{pid}:$entry->{message}";
        unless ($seen{$key}++) {
            push @unique, $entry;
        }
    }
    return \@unique;
}

sub extract_context {
    my ($self, $entries, $index, $before, $after) = @_;
    $before //= 3;
    $after  //= 3;
    croak "index out of range" unless $index >= 0 && $index <= $#$entries;
    my $start = $index - $before; $start = 0 if $start < 0;
    my $end   = $index + $after;  $end = $#$entries if $end > $#$entries;
    return [ @{$entries}[$start .. $end] ];
}

sub top_messages {
    my ($self, $entries, $n) = @_;
    $n //= 10;
    croak "n must be a positive integer"
        unless looks_like_number($n) && $n > 0 && $n == int($n);
    my %counts;
    for my $entry (@$entries) {
        next unless defined $entry;
        $counts{$entry->{message}}++;
    }
    my @sorted = sort { $counts{$b} <=> $counts{$a} } keys %counts;
    my @top;
    for my $i (0 .. $n - 1) {
        last if $i > $#sorted;
        push @top, { message => $sorted[$i], count => $counts{$sorted[$i]} };
    }
    return \@top;
}

sub write_summary_report {
    my ($self, $entries, $output_path) = @_;
    my $counts = $self->count_by_level($entries);
    my ($min_ts, $max_ts) = $self->extract_timestamp_range($entries);
    my $errors = $self->find_error_patterns($entries);
    my $groups = $self->group_by_pid($entries);
    try {
        open(my $fh, '>', $output_path) or die "open failed: $!";
        print $fh "=== Log Analysis Summary ===\n";
        print $fh "Time range: ", ($min_ts // 'n/a'), " to ", ($max_ts // 'n/a'), "\n";
        print $fh "Total entries: ", scalar(@$entries), "\n\n";
        print $fh "By level:\n";
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
        close($fh) or die "close failed: $!";
    } catch {
        Text::LogAnalyzer::IOError->throw(
            message   => "Failed to write $output_path: $_",
            operation => 'write',
            file      => $output_path,
        );
    };
    return $output_path;
}

sub write_csv_report {
    my ($self, $entries, $output_path) = @_;
    try {
        open(my $fh, '>', $output_path) or die "open failed: $!";
        print $fh join(',', @COLUMNS), "\n";
        for my $entry (@$entries) {
            next unless defined $entry;
            my $msg = $entry->{message} // '';
            $msg =~ s/"/""/g;
            print $fh join(',',
                $entry->{timestamp} // '',
                $entry->{level} // '',
                $entry->{pid} // 0,
                qq{"$msg"},
            ), "\n";
        }
        close($fh) or die "close failed: $!";
    } catch {
        Text::LogAnalyzer::IOError->throw(
            message   => "Failed to write $output_path: $_",
            operation => 'write',
            file      => $output_path,
        );
    };
    return $output_path;
}

sub merge_log_files {
    my ($self, $paths) = @_;
    croak "paths must be an arrayref" unless ref $paths eq 'ARRAY';
    my @all;
    for my $path (@$paths) {
        my @lines = $self->read_log_file($path);
        my $entries = $self->parse_lines(\@lines);
        push @all, @$entries;
    }
    @all = sort { ($a->{timestamp} // '') cmp ($b->{timestamp} // '') } @all;
    return \@all;
}

sub analyze {
    my ($self, $input_path, $summary_path, $csv_path) = @_;
    my @lines = $self->read_log_file($input_path);
    my $entries = $self->parse_lines(\@lines);
    my $filtered = $self->filter_by_level($entries);
    my $deduped  = $self->deduplicate_entries($filtered);
    $self->write_summary_report($deduped, $summary_path);
    $self->write_csv_report($deduped, $csv_path);
    return {
        total    => scalar(@$entries),
        filtered => scalar(@$filtered),
        deduped  => scalar(@$deduped),
        summary  => $summary_path,
        csv      => $csv_path,
    };
}

__PACKAGE__->meta->make_immutable;

# ---------------------------------------------------------------------------
# Test suite — run with `perl LogAnalyzer.pm --test`
# ---------------------------------------------------------------------------

package main;

sub _run_tests {
    require Test::More;
    Test::More->import(qw(plan ok is is_deeply like));
    my $analyzer = Text::LogAnalyzer->new(min_level => 'WARN');

    my $entry = $analyzer->parse_line(
        '2024-01-15T10:23:45Z [INFO] [12345] Hello world'
    );
    ok($entry, 'parse_line returns a hashref');
    is($entry->{level}, 'INFO', 'level parsed correctly');
    is($entry->{pid}, 12345, 'pid parsed as integer');

    my $bad = $analyzer->parse_line('garbage');
    ok(!defined $bad, 'unparseable line returns undef in non-strict mode');

    my $strict = Text::LogAnalyzer->new(min_level => 'WARN', strict_mode => 1);
    my $threw = 0;
    try {
        $strict->parse_line('garbage');
    } catch {
        $threw = 1;
    };
    ok($threw, 'strict mode throws ParseError on malformed input');

    my $entries = [
        { timestamp => '2024-01-01T00:00:00Z', level => 'INFO',  pid => 1, message => 'a' },
        { timestamp => '2024-01-01T00:00:01Z', level => 'WARN',  pid => 1, message => 'b' },
        { timestamp => '2024-01-01T00:00:02Z', level => 'ERROR', pid => 2, message => 'c' },
        { timestamp => '2024-01-01T00:00:03Z', level => 'ERROR', pid => 2, message => 'd' },
    ];
    my $filtered = $analyzer->filter_by_level($entries);
    is(scalar(@$filtered), 3, 'filter_by_level keeps WARN and above');

    my $counts = $analyzer->count_by_level($entries);
    is($counts->{ERROR}, 2, 'count_by_level counts errors');

    my $errors = $analyzer->find_error_patterns($entries);
    is(scalar(@$errors), 1, 'adjacent errors are grouped');
    is(scalar(@{$errors->[0]{related}}), 1, 'related error captured');

    my ($min, $max) = $analyzer->extract_timestamp_range($entries);
    is($min, '2024-01-01T00:00:00Z', 'min timestamp correct');
    is($max, '2024-01-01T00:00:03Z', 'max timestamp correct');

    my $ctx = $analyzer->extract_context($entries, 2, 1, 1);
    is(scalar(@$ctx), 3, 'extract_context returns surrounding lines');

    my $top = $analyzer->top_messages($entries, 5);
    is(scalar(@$top), 4, 'top_messages returns up to n entries');

    done_testing();
}

sub main {
    if (@ARGV && $ARGV[0] eq '--test') {
        _run_tests();
        return 0;
    }
    if (@ARGV < 3) {
        print STDERR "Usage: $0 <input.log> <summary.txt> <entries.csv>\n";
        print STDERR "       $0 --test\n";
        return 1;
    }
    my $analyzer = Text::LogAnalyzer->new(min_level => 'WARN', deduplicate => 1);
    my $result = $analyzer->analyze($ARGV[0], $ARGV[1], $ARGV[2]);
    print "Analyzed: $result->{total} total, $result->{filtered} filtered, ",
          "$result->{deduped} after dedup\n";
    return 0;
}

exit main() unless caller();

1;

__END__

=head1 NAME

Text::LogAnalyzer - OO log file analyzer with proper error handling

=head1 SYNOPSIS

  use Text::LogAnalyzer;
  my $analyzer = Text::LogAnalyzer->new(
      min_level    => 'WARN',
      deduplicate  => 1,
      strict_mode  => 0,
  );
  my $result = $analyzer->analyze('app.log', 'summary.txt', 'entries.csv');

=head1 DESCRIPTION

Refactored version of the procedural log analyzer. Provides:
=over 4
=item * Moose-based OO interface with immutable instances
=item * Proper exception classes for I/O and parse errors
=item * Configurable strict/lenient parsing modes
=item * Built-in test suite (run with --test)
=back

=cut
