package DiffVim::Parser::Perl;
# Pure-Perl diff parser. Computes line-level and char-level diffs using
# the classic LCS dynamic-programming algorithm. No external dependencies
# beyond Perl core (uses Algorithm::Diff if available, falls back to a
# built-in LCS implementation).

use strict;
use warnings;
use utf8;

use Exporter qw(import);
our @EXPORT_OK = qw(parse_diff);

# Try to use Algorithm::Diff for better performance; fall back to built-in.
my $HAVE_ALG_DIFF;
BEGIN {
    eval {
        require Algorithm::Diff;
        Algorithm::Diff->import(qw(LCS diff traverse_sequences));
        $HAVE_ALG_DIFF = 1;
    };
    $HAVE_ALG_DIFF //= 0;
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# parse_diff($old_file, $new_file)
# Returns a hash:
#   {
#     hunks => [
#       {
#         target_line  => N,     # 1-indexed line in OLD where the hunk starts
#         char_ops     => [      # ordered list of char-level ops
#           { op => 'keep',   code => N },
#           { op => 'delete', code => N },
#           { op => 'insert', code => N },
#           ...
#         ],
#         deleted_count => N,    # number of old lines deleted
#         inserted_count => N,   # number of new lines inserted
#         is_end_insert  => 0|1, # pure insertion at EOF
#         is_end_delete  => 0|1, # pure deletion at EOF
#         old_text       => str, # joined deleted lines (for debugging)
#         new_text       => str, # joined inserted lines (for debugging)
#       },
#       ...
#     ],
#     parser => 'perl',
#   }
sub parse_diff {
    my ($old_file, $new_file) = @_;

    my $old_lines = _read_lines($old_file);
    my $new_lines = _read_lines($new_file);

    my $line_ops = _line_diff($old_lines, $new_lines);

    # Group line-level ops into hunks (consecutive non-keep ops).
    my @hunks;
    my @cur_old;
    my @cur_new;
    my $cur_target = 1;
    my $has_hunk = 0;
    my $old_pos = 0;  # 0-indexed position in old_lines

    for my $entry (@$line_ops) {
        my ($op, $old_idx, $new_idx) = @$entry;
        if ($op eq 'keep') {
            if ($has_hunk) {
                push @hunks, _flush_hunk(\@cur_old, \@cur_new,
                    $cur_target, scalar(@$old_lines));
                @cur_old = ();
                @cur_new = ();
                $has_hunk = 0;
            }
            $old_pos = $old_idx + 1;
        } elsif ($op eq 'delete') {
            $has_hunk or $cur_target = $old_pos + 1, $has_hunk = 1;
            push @cur_old, $old_lines->[$old_idx];
            $old_pos = $old_idx + 1;
        } elsif ($op eq 'insert') {
            $has_hunk or $cur_target = $old_pos + 1, $has_hunk = 1;
            push @cur_new, $new_lines->[$new_idx];
        }
    }
    if ($has_hunk) {
        push @hunks, _flush_hunk(\@cur_old, \@cur_new,
            $cur_target, scalar(@$old_lines));
    }

    return { hunks => \@hunks, parser => 'perl' };
}

# ---------------------------------------------------------------------------
# Line-level diff (LCS)
# ---------------------------------------------------------------------------

sub _line_diff {
    my ($a, $b) = @_;

    if ($HAVE_ALG_DIFF) {
        # Algorithm::Diff::diff returns hunks of [op, a_idx, b_idx]
        my $diffs = Algorithm::Diff::diff($a, $b);
        my @ops;
        # Algorithm::Diff doesn't give us 'keep' ops directly; we need to
        # reconstruct them. Easier to use traverse_sequences.
        my $ai = 0;
        my $bi = 0;
        my @result;
        for my $hunk (@$diffs) {
            for my $change (@$hunk) {
                my ($op, $i, $j) = @$change;
                if ($op eq '-') {
                    # Emit keeps for anything before this
                    while ($ai < $i || $bi < $j) {
                        push @result, ['keep', $ai, $bi];
                        $ai++; $bi++;
                    }
                    push @result, ['delete', $i, $bi];
                    $ai = $i + 1;
                } elsif ($op eq '+') {
                    push @result, ['insert', $ai, $j];
                    $bi = $j + 1;
                }
            }
        }
        # Emit remaining keeps
        while ($ai < @$a && $bi < @$b) {
            push @result, ['keep', $ai, $bi];
            $ai++; $bi++;
        }
        # Emit remaining deletes
        while ($ai < @$a) {
            push @result, ['delete', $ai, $bi];
            $ai++;
        }
        # Emit remaining inserts
        while ($bi < @$b) {
            push @result, ['insert', $ai, $bi];
            $bi++;
        }
        return \@result;
    }

    # Fallback: classic LCS DP.
    return _lcs_diff($a, $b);
}

# Classic LCS dynamic programming diff. Returns list of [op, a_idx, b_idx].
sub _lcs_diff {
    my ($a, $b) = @_;
    my $na = scalar(@$a);
    my $nb = scalar(@$b);

    # dp[i][j] = length of LCS of a[0..i) and b[0..j)
    my @dp;
    for my $i (0 .. $na) {
        $dp[$i] = [(0) x ($nb + 1)];
    }
    for my $i (1 .. $na) {
        for my $j (1 .. $nb) {
            if ($a->[$i - 1] eq $b->[$j - 1]) {
                $dp[$i][$j] = $dp[$i - 1][$j - 1] + 1;
            } else {
                $dp[$i][$j] = $dp[$i - 1][$j] > $dp[$i][$j - 1]
                    ? $dp[$i - 1][$j]
                    : $dp[$i][$j - 1];
            }
        }
    }

    # Backtrack to produce ops (in reverse, then reverse the list).
    my @ops;
    my $i = $na;
    my $j = $nb;
    while ($i > 0 || $j > 0) {
        if ($i > 0 && $j > 0 && $a->[$i - 1] eq $b->[$j - 1]) {
            unshift @ops, ['keep', $i - 1, $j - 1];
            $i--; $j--;
        } elsif ($j > 0 && ($i == 0 || $dp[$i][$j - 1] >= $dp[$i - 1][$j])) {
            unshift @ops, ['insert', $i, $j - 1];
            $j--;
        } else {
            unshift @ops, ['delete', $i - 1, $j];
            $i--;
        }
    }
    return \@ops;
}

# ---------------------------------------------------------------------------
# Char-level diff (also LCS, but on individual characters)
# ---------------------------------------------------------------------------

sub _char_diff {
    my ($old_text, $new_text) = @_;

    # Split into characters. Don't use -1 (it preserves a trailing empty
    # field after the last char, creating a spurious null-char op).
    my @a = split //, $old_text;
    my @b = split //, $new_text;

    my $ops = _lcs_diff(\@a, \@b);

    my @char_ops;
    for my $entry (@$ops) {
        my ($op, $ai, $bi) = @$entry;
        if ($op eq 'keep') {
            push @char_ops, { op => 'keep', code => ord($a[$ai]) };
        } elsif ($op eq 'delete') {
            push @char_ops, { op => 'delete', code => ord($a[$ai]) };
        } elsif ($op eq 'insert') {
            push @char_ops, { op => 'insert', code => ord($b[$bi]) };
        }
    }
    return \@char_ops;
}

# ---------------------------------------------------------------------------
# Hunk construction
# ---------------------------------------------------------------------------

sub _flush_hunk {
    my ($cur_old, $cur_new, $target, $old_line_count) = @_;

    my $del_count = scalar(@$cur_old);
    my $ins_count = scalar(@$cur_new);

    my $old_text = join("\n", @$cur_old);
    my $new_text = join("\n", @$cur_new);

    my ($is_end_ins, $is_end_del) = (0, 0);

    if ($del_count == 0) {
        # Pure insertion: need a trailing/leading \n so the content becomes
        # a separate line instead of merging into the adjacent line.
        # Exception: empty old file (no existing line to separate from).
        $old_text = '';
        if ($old_line_count == 0) {
            # No separator needed.
        } elsif ($target > $old_line_count) {
            $new_text = "\n" . $new_text;
            $is_end_ins = 1;
        } else {
            $new_text = $new_text . "\n";
            $is_end_ins = 0;
        }
    } elsif ($ins_count == 0) {
        # Pure deletion: need to also remove a \n so the line vanishes.
        $new_text = '';
        if ($target + $del_count - 1 >= $old_line_count) {
            $old_text = "\n" . $old_text;
            $is_end_del = 1;
        } else {
            $old_text = $old_text . "\n";
            $is_end_del = 0;
        }
    }

    my $char_ops = _char_diff($old_text, $new_text);

    return {
        target_line   => $target,
        char_ops      => $char_ops,
        deleted_count => $del_count,
        inserted_count => $ins_count,
        is_end_insert => $is_end_ins,
        is_end_delete => $is_end_del,
        old_text      => $old_text,
        new_text      => $new_text,
    };
}

# ---------------------------------------------------------------------------
# File reading
# ---------------------------------------------------------------------------

# Read a file into a list of lines (without trailing newlines).
# Handles missing trailing newline correctly.
sub _read_lines {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return [''] unless defined $content && length($content);
    my @lines = split /\n/, $content, -1;
    # If the file ends with \n, split produces a trailing empty string.
    # Remove it (it represents the end-of-file, not a real line).
    pop @lines if @lines && $lines[-1] eq '' && $content =~ /\n\z/;
    return \@lines;
}

1;

__END__

=head1 NAME

DiffVim::Parser::Perl - Pure-Perl diff parser with char-level granularity

=head1 SYNOPSIS

    use DiffVim::Parser::Perl qw(parse_diff);
    my $result = parse_diff('old.txt', 'new.txt');
    for my $hunk (@{$result->{hunks}}) {
        for my $op (@{$hunk->{char_ops}}) {
            print "$op->{op} " . chr($op->{code}) . "\n";
        }
    }

=head1 DESCRIPTION

Computes a two-level diff: first a line-level LCS diff to identify changed
regions, then a char-level LCS diff within each changed region. This
produces the minimal set of character insert/delete/keep operations needed
to transform the old file into the new file.

If L<Algorithm::Diff> is installed, it is used for the line-level diff
(faster C implementation). Otherwise a pure-Perl LCS fallback is used.

=cut
