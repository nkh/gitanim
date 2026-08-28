#!/usr/bin/env perl
# test_benchmark.pl - Benchmark suite (#83)
# Measures animation speed, diff computation time, and memory usage
# across different file sizes and diff complexities.
#
# Usage: perl tests/test_benchmark.pl

use strict;
use warnings;
use lib '.';
use Time::HiRes qw(time);
use DiffVim::Parser::Perl qw(parse_diff);

my $results_file = '/tmp/diffvim-benchmark-results.txt';
open my $rfh, '>', $results_file or die "Cannot write $results_file: $!";
my $original_stdout = \*STDOUT;
*STDOUT = $rfh;

print "=" x 70, "\n";
print "diffvim Benchmark Suite\n";
print "=" x 70, "\n\n";

# Benchmark function
sub benchmark {
    my ($name, $old_file, $new_file, $options) = @_;
    $options //= {};
    my $label = $name;
    $label .= " ($options->{algorithm})" if $options->{algorithm};
    $label .= " (word-diff)" if $options->{word_diff};
    $label .= " (semantic-cleanup)" if $options->{semantic_cleanup};

    # Measure file sizes
    my $old_size = -s $old_file // 0;
    my $new_size = -s $new_file // 0;
    my $old_lines = 0;
    my $new_lines = 0;
    open my $fh, '<', $old_file; $old_lines++ while <$fh>; close $fh;
    open $fh, '<', $new_file; $new_lines++ while <$fh>; close $fh;

    # Measure diff computation time
    my $t0 = time();
    my $result = parse_diff($old_file, $new_file, $options);
    my $t1 = time();
    my $compute_ms = int(($t1 - $t0) * 1000);

    # Count hunks and ops
    my $hunk_count = scalar(@{$result->{hunks}});
    my $total_ops = 0;
    my $changed_ops = 0;
    for my $h (@{$result->{hunks}}) {
        $total_ops += scalar(@{$h->{char_ops}});
        for my $op (@{$h->{char_ops}}) {
            $changed_ops++ if $op->{op} ne 'keep';
        }
    }

    # Estimate animation time (sum of all delays)
    my $type_delay = 35;   # ms per typed char
    my $delete_delay = 25; # ms per deleted char
    my $hunk_pause = 180;  # ms between hunks
    my $move_min = 200;    # ms min move
    my $estimated_anim_ms = $changed_ops * ($type_delay + $delete_delay) / 2 + $hunk_count * ($hunk_pause + $move_min);

    # Memory usage (approximate)
    my $mem = 0;
    # The LCS DP table for char diff is roughly (len(old_text) * len(new_text)) integers
    for my $h (@{$result->{hunks}}) {
        my $old_len = length($h->{old_text});
        my $new_len = length($h->{new_text});
        $mem += $old_len * $new_len * 8;  # 8 bytes per int (approximate)
    }

    printf "%-40s  %5d/%-5d lines  %5d/%-5d bytes  %3d hunks  %5d ops  %5d changed  %6d ms compute  %6.1f s est. anim  %6d KB DP mem\n",
        $label, $old_lines, $new_lines, $old_size, $new_size,
        $hunk_count, $total_ops, $changed_ops, $compute_ms,
        $estimated_anim_ms / 1000, $mem / 1024;

    return {
        name        => $name,
        compute_ms  => $compute_ms,
        hunk_count  => $hunk_count,
        total_ops   => $total_ops,
        changed_ops => $changed_ops,
        est_anim_s  => $estimated_anim_ms / 1000,
        mem_kb      => int($mem / 1024),
    };
}

# --- Run benchmarks on all example files ---
print "Benchmark Results:\n";
print "-" x 120, "\n";
printf "%-40s  %6s  %6s  %5s  %6s  %6s  %8s  %10s  %10s\n",
    "Test", "Lines", "Bytes", "Hunks", "Ops", "Changed", "Compute", "Est. Anim", "DP Mem";
print "-" x 120, "\n";

my @all_results;
for my $dir (sort glob("tests/tests/examples/*/")) {
    my @old_files = glob("$dir/old.*");
    for my $old (@old_files) {
        my $ext = $old =~ /\.(\w+)$/ ? $1 : 'txt';
        (my $new = $old) =~ s/old\.\w+$/new.$ext/;
        next unless -f $new;
        my $name = $dir;
        $name =~ s|tests/tests/examples/||;
        $name =~ s|/$||;

        # Default LCS
        my $r = benchmark($name, $old, $new, {});
        push @all_results, $r;

        # Myers (falls back to LCS but still benchmark)
        $r = benchmark($name, $old, $new, { algorithm => 'myers' });
        push @all_results, $r;

        # Patience
        $r = benchmark($name, $old, $new, { algorithm => 'patience' });
        push @all_results, $r;

        # Word diff
        $r = benchmark($name, $old, $new, { word_diff => 1 });
        push @all_results, $r;

        # Semantic cleanup
        $r = benchmark($name, $old, $new, { semantic_cleanup => 1 });
        push @all_results, $r;
    }
}

print "\n";

# --- Summary statistics ---
print "=" x 70, "\n";
print "Summary Statistics:\n";
print "=" x 70, "\n\n";

my @compute_times = map { $_->{compute_ms} } @all_results;
my @hunk_counts = map { $_->{hunk_count} } @all_results;
my @op_counts = map { $_->{total_ops} } @all_results;

my $min_compute = [sort { $a <=> $b } @compute_times]->[0];
my $max_compute = [sort { $a <=> $b } @compute_times]->[-1];
my $avg_compute = int(0 + ($min_compute + $max_compute) / 2);

printf "Diff computation time:  min=%dms  max=%dms  avg=%dms\n",
    $min_compute, $max_compute, $avg_compute;

printf "Total benchmarks run:   %d\n", scalar(@all_results);
printf "Total test files:       %d\n", scalar(@all_results) / 5;  # 5 variants per file

print "\nBenchmark results written to $results_file\n";

*STDOUT = $original_stdout;

# Print summary to stdout
print "Benchmark complete. Results written to $results_file\n";
my $min_c = [sort { $a <=> $b } @compute_times]->[0];
my $max_c = [sort { $a <=> $b } @compute_times]->[-1];
print "Summary: " . scalar(@all_results) . " benchmarks, compute time range ${min_c}ms-${max_c}ms\n";
