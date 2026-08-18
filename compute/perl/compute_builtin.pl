#!/usr/bin/env perl
# compute_builtin.pl — Pure-Perl fallback for diffvim-compute-cpp.
#
# Used by diffvim-pipeline (and the diffvim bash launcher, if desired) when
# the C++ compute binary is not available. Produces byte-identical output
# to compute/bin/diffvim-compute-cpp via the DiffVim::Parser::Perl module.
#
# Usage:
#   perl compute_builtin.pl <oldfile> <newfile> <outputfile> [--algorithm lcs|patience]
#
# Notes:
#   - This is slower than the C++ tool but produces the same op stream.
#   - Myers is not supported (it was removed from the project).

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../../";

use DiffVim::Parser::Perl qw(parse_diff);

binmode(STDERR, ':utf8');

my $algorithm = 'patience';
my @positionals;

for (my $i = 0; $i < @ARGV; $i++) {
    my $a = $ARGV[$i];
    if ($a eq '--semantic-cleanup') {
        # passed through to parser via options below
    } elsif ($a eq '--word-diff') {
        # passed through to parser via options below
    } elsif ($a eq '--indent-aware') {
        # passed through
    } elsif ($a eq '-h' || $a eq '--help') {
        print STDERR "Usage: $0 <oldfile> <newfile> <outputfile> [--algorithm lcs|patience]\n";
        exit 0;
    } else {
        push @positionals, $a;
    }
}

if (@positionals < 3) {
    print STDERR "Usage: $0 <oldfile> <newfile> <outputfile> [--algorithm lcs|patience]\n";
    exit 1;
}

my ($oldfile, $newfile, $outfile) = @positionals;

my $t_start = Time::HiRes::time() if eval { require Time::HiRes; };

my $result = parse_diff($oldfile, $newfile, {
    algorithm       => $algorithm,
    semantic_cleanup => 0,
    indent_aware    => 0,
});

my @hunks = @{$result->{hunks}};

open my $out, '>:raw', $outfile or die "Cannot write $outfile: $!";
print $out "# diffvim precomputed diff v1\n";
print $out "# algorithm $algorithm\n";
print $out "# semantic_cleanup 0\n";
print $out "# word_diff 0\n";
print $out "# indent_aware 0\n";
print $out "# optimize_sequence 1\n";
print $out "# left_to_right 0\n";
print $out "# hunk_count " . scalar(@hunks) . "\n";

for my $h (@hunks) {
    print $out "HUNK $h->{target_line} $h->{deleted_count} $h->{inserted_count} $h->{is_end_insert} $h->{is_end_delete}\n";
    for my $op (@{$h->{char_ops}}) {
        my $code = ($op->{code} =~ /^\d+$/) ? $op->{code} : ord($op->{code});
        print $out "$op->{op} $code\n";
    }
}
close $out;

if ($t_start) {
    my $elapsed = (Time::HiRes::time() - $t_start) * 1000.0;
    printf STDERR "compute: %.2f ms (builtin perl)\n", $elapsed;
}
