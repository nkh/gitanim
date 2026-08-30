#!/usr/bin/env perl
# compute_builtin.pl — Pure-Perl fallback for ad_compute.
#
# Used by ad_pipeline (and the diffvim bash launcher, if desired) when
# the C++ compute binary is not available. Produces v2 TSV output that is
# byte-identical to bin/ad_compute via the DiffVim::Parser::Perl
# module.
#
# v2 TSV output format (tab-separated, 1-indexed line/col):
#   # diffvim raw diff v2
#   # algorithm <patience|lcs>
#   # hunk_count <N>
#   HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>
#   keep\t<line>\t<col>\t<code>\t<char_repr>
#   delete\t<line>\t<col>\t<code>\t<char_repr>
#   insert\t<line>\t<col>\t<code>\t<char_repr>
#   HUNK_END
#   (blank line at end)
#
# Usage:
#   perl compute_builtin.pl <oldfile> <newfile> <outputfile> [--algorithm lcs|patience]
#
# Notes:
#   - This is slower than the C++ tool but produces the same op stream.
#   - Myers is not supported (it was removed from the project).
#   - Positions (line, col) are computed by walking the diff buffer the
#     same way the C++ tool does — the postprocessor will recompute
#     them anyway, but the raw op stream includes them for traceability.

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../../";

use DiffVim::Parser::Perl qw(parse_diff);

binmode(STDERR, ':utf8');

my $algorithm = 'patience';
my $do_semantic = 0;
my $do_word_diff = 0;
my @positionals;

for (my $i = 0; $i < @ARGV; $i++) {
    my $a = $ARGV[$i];
    if ($a eq '--semantic-cleanup') {
        $do_semantic = 1;
    } elsif ($a eq '--word-diff') {
        $do_word_diff = 1;
    } elsif ($a eq '-h' || $a eq '--help') {
        print STDERR "Usage: $0 <oldfile> <newfile> <outputfile> [options]\n";
        print STDERR "Options: --semantic-cleanup --word-diff\n";
        exit 0;
    } else {
        push @positionals, $a;
    }
}

if (@positionals < 3) {
    print STDERR "Usage: $0 <oldfile> <newfile> <outputfile> [options]\n";
    exit 1;
}

my ($oldfile, $newfile, $outfile) = @positionals;

my $t_start = Time::HiRes::time() if eval { require Time::HiRes; };

my $result = parse_diff($oldfile, $newfile, {
    algorithm       => $algorithm,
    semantic_cleanup => $do_semantic,
    word_diff       => $do_word_diff,
});

my @hunks = @{$result->{hunks}};

# Convert char code to readable representation, matching the C++ tool.
sub char_repr {
    my ($code) = @_;
    return "\\n"  if $code == 10;
    return "\\t"  if $code == 9;
    return "\\r"  if $code == 13;
    return "space" if $code == 32;
    if ($code >= 33 && $code <= 126) {
        return "'" . chr($code) . "'";
    }
    return "$code";
}

open my $out, '>:raw', $outfile or die "Cannot write $outfile: $!";
print $out "# diffvim raw diff v2\n";
print $out "# algorithm $algorithm\n";
print $out "# semantic_cleanup $do_semantic\n";
print $out "# word_diff $do_word_diff\n";
print $out "# optimize_sequence 1\n";

print $out "# hunk_count " . scalar(@hunks) . "\n";

for my $h (@hunks) {
    print $out "HUNK\t$h->{target_line}\t$h->{deleted_count}\t$h->{inserted_count}\t$h->{is_end_insert}\t$h->{is_end_delete}\n";


    # Walk the ops and compute (line, col) for each op, mirroring the
    # C++ compute tool: cursor starts at (target, 1). keep/insert
    # advance col; delete stays at same col. Any op with code 10
    # (newline — keep, delete, or insert) advances line, resets col.
    my $cur_line = $h->{target_line};
    my $cur_col = 1;

    my @ops = @{$h->{char_ops}};

    for my $op (@ops) {
        my $code = ($op->{code} =~ /^\d+$/) ? $op->{code} : ord($op->{code});
        my $type = $op->{op};   # keep | delete | insert

        printf $out "%s\t%d\t%d\t%d\t%s\n", $type, $cur_line, $cur_col, $code, char_repr($code);

        if ($code == 10) {
            $cur_line++;
            $cur_col = 1;
        } else {
            if ($type eq 'keep' || $type eq 'insert') {
                $cur_col++;
            }
            # delete: cursor col unchanged (next char shifts into this col).
        }
    }
    print $out "HUNK_END\n";
}
print $out "\n";  # blank line at bottom
close $out;

if ($t_start) {
    my $elapsed = (Time::HiRes::time() - $t_start) * 1000.0;
    printf STDERR "compute: %.2f ms (builtin perl)\n", $elapsed;
}
