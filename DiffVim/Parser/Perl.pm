package DiffVim::Parser::Perl;
# Pure-Perl diff parser. Computes line-level and char-level diffs using
# the classic LCS dynamic-programming algorithm. No external dependencies
# beyond Perl core.

use strict;
use warnings;
use utf8;

use Exporter qw(import);
our @EXPORT_OK = qw(parse_diff);

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# parse_diff($old_file, $new_file, \%options)
# Options:
#   word_diff => 1   Use word-level diff (#19) instead of char-level
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
    my ($old_file, $new_file, $options) = @_;
    $options //= {};
    my $use_word_diff = $options->{word_diff} // 0;
    my $use_semantic_cleanup = $options->{semantic_cleanup} // 0;

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
                    $cur_target, scalar(@$old_lines), $use_word_diff, $use_semantic_cleanup);
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
            $cur_target, scalar(@$old_lines), $use_word_diff, $use_semantic_cleanup);
    }

    return { hunks => \@hunks, parser => 'perl' };
}

# ---------------------------------------------------------------------------
# Line-level diff (LCS)
# ---------------------------------------------------------------------------

sub _line_diff {
    my ($a, $b) = @_;
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

    # Decode as UTF-8 so multi-byte characters (e.g. em-dash —) are treated
    # as single characters, not individual bytes.  This is critical: if we
    # split on bytes, the vim engine's nr2char() creates wrong characters
    # (e.g. nr2char(226) creates 'â' instead of the first byte of '—').
    # Fall back to byte-level split if the text isn't valid UTF-8.
    my $old_decoded = $old_text;
    my $new_decoded = $new_text;
    eval {
        require Encode;
        $old_decoded = Encode::decode('UTF-8', $old_text,
            Encode::FB_CROAK());
    };
    if ($@) {
        $old_decoded = $old_text;  # Not valid UTF-8, use bytes
    }
    eval {
        require Encode;
        $new_decoded = Encode::decode('UTF-8', $new_text,
            Encode::FB_CROAK());
    };
    if ($@) {
        $new_decoded = $new_text;
    }

    # Split into characters (not bytes). For UTF-8 text, multi-byte chars
    # are treated as single elements.
    my @a = split //, $old_decoded;
    my @b = split //, $new_decoded;

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
# Word-level diff (#19) — intermediate between line and char level
# Splits text into words (non-space sequences) and spaces, then runs LCS.
# Returns char_ops but groups consecutive insert/delete within a word.
# ---------------------------------------------------------------------------

sub _word_diff {
    my ($old_text, $new_text) = @_;

    # Decode as UTF-8 (same as _char_diff)
    my $old_decoded = $old_text;
    my $new_decoded = $new_text;
    eval { require Encode; $old_decoded = Encode::decode('UTF-8', $old_text, Encode::FB_CROAK()); };
    $old_decoded = $old_text if $@;
    eval { require Encode; $new_decoded = Encode::decode('UTF-8', $new_text, Encode::FB_CROAK()); };
    $new_decoded = $new_text if $@;

    # Split into tokens: words (non-space) and whitespace
    my @a = _split_words($old_decoded);
    my @b = _split_words($new_decoded);

    my $ops = _lcs_diff(\@a, \@b);

    # Convert word-level ops to char-level ops
    my @char_ops;
    for my $entry (@$ops) {
        my ($op, $ai, $bi) = @$entry;
        my $token;
        if ($op eq 'keep' || $op eq 'delete') {
            $token = $a[$ai];
        } else {
            $token = $b[$bi];
        }
        # Expand token into individual char ops
        for my $ch (split //, $token) {
            push @char_ops, { op => $op, code => ord($ch) };
        }
    }
    return \@char_ops;
}

# Split text into words and whitespace tokens
sub _split_words {
    my ($text) = @_;
    my @tokens;
    while ($text =~ /(\S+|\s+)/g) {
        push @tokens, $1;
    }
    return @tokens;
}

# ---------------------------------------------------------------------------
# Hunk construction
# ---------------------------------------------------------------------------

sub _flush_hunk {
    my ($cur_old, $cur_new, $target, $old_line_count, $use_word_diff, $use_semantic_cleanup) = @_;

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

    my $char_ops = $use_word_diff ? _word_diff($old_text, $new_text)
                                  : _char_diff($old_text, $new_text);

    # Semantic cleanup (#21): merge adjacent insert/delete pairs that cancel
    # out, reducing unnecessary typing. For example, if the LCS produces:
    #   delete 'a', insert 'a', delete 'b', insert 'c'
    # the first delete+insert pair cancels out, so we can simplify to:
    #   keep 'a', delete 'b', insert 'c'
    if ($use_semantic_cleanup) {
        $char_ops = _semantic_cleanup($char_ops);
    }

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
# Semantic cleanup (#21)
# ---------------------------------------------------------------------------

# Post-process char ops to merge adjacent insert/delete pairs that cancel out.
# If a delete is immediately followed by an insert of the same character,
# replace both with a keep (the character didn't actually change).
# Also merges adjacent same-type ops for cleaner output.
sub _semantic_cleanup {
    my ($char_ops) = @_;
    return $char_ops unless @$char_ops >= 2;

    my @cleaned;
    my $i = 0;
    while ($i < @$char_ops) {
        my $op = $char_ops->[$i];

        # Check if this is a delete immediately followed by an insert of
        # the same character — they cancel out, replace with keep
        if ($i + 1 < @$char_ops
            && $op->{op} eq 'delete'
            && $char_ops->[$i + 1]{op} eq 'insert'
            && $op->{code} == $char_ops->[$i + 1]{code}) {
            push @cleaned, { op => 'keep', code => $op->{code} };
            $i += 2;
            next;
        }

        # Check if this is an insert immediately followed by a delete of
        # the same character — they also cancel out
        if ($i + 1 < @$char_ops
            && $op->{op} eq 'insert'
            && $char_ops->[$i + 1]{op} eq 'delete'
            && $op->{code} == $char_ops->[$i + 1]{code}) {
            push @cleaned, { op => 'keep', code => $op->{code} };
            $i += 2;
            next;
        }

        push @cleaned, $op;
        $i++;
    }

    return \@cleaned;
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

Uses a pure-Perl LCS dynamic-programming implementation with no external
dependencies.

=cut
