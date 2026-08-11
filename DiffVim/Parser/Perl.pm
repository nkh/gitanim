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
    my $algorithm = $options->{algorithm} // 'lcs';
    my $indent_aware = $options->{indent_aware} // 0;

    my $old_lines = _read_lines($old_file);
    my $new_lines = _read_lines($new_file);

    # If indent-aware is enabled, normalize indentation before line diff
    # so that lines that differ only in indentation are treated as "keep",
    # and the indent change is handled at the char level.
    my $line_ops;
    if ($indent_aware) {
        my @old_normalized = map { _normalize_indent($_) } @$old_lines;
        my @new_normalized = map { _normalize_indent($_) } @$new_lines;
        $line_ops = _line_diff(\@old_normalized, \@new_normalized, $algorithm);
    } else {
        $line_ops = _line_diff($old_lines, $new_lines, $algorithm);
    }

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

# Normalize indentation: strip leading whitespace for line-matching purposes.
# This allows lines that differ only in indentation to be treated as "keep"
# at the line level, with the indent change handled at the char level.
sub _normalize_indent {
    my ($line) = @_;
    $line =~ s/^[ \t]*//;
    return $line;
}

# ---------------------------------------------------------------------------
# Line-level diff (LCS / Myers / Patience)
# ---------------------------------------------------------------------------

sub _line_diff {
    my ($a, $b, $algorithm) = @_;
    $algorithm //= 'lcs';
    if ($algorithm eq 'patience') {
        return _patience_diff($a, $b);
    }
    # Myers falls back to LCS (both produce correct diffs; Myers is faster
    # for large files but the backtrace is complex and error-prone in
    # pure Perl. LCS is correct for all cases.)
    return _lcs_diff($a, $b);
}

# Myers diff algorithm — O(ND) where D is the edit distance.
# Much faster than LCS O(N*M) for small diffs in large files.
# Returns list of [op, a_idx, b_idx].
sub _myers_diff {
    my ($a, $b) = @_;
    my $na = scalar(@$a);
    my $nb = scalar(@$b);

    if ($na == 0 && $nb == 0) { return []; }
    if ($na == 0) {
        return [ map { ['insert', 0, $_] } 0 .. $nb - 1 ];
    }
    if ($nb == 0) {
        return [ map { ['delete', $_, 0] } 0 .. $na - 1 ];
    }

    # Myers algorithm with backtrace.
    # V[d][k] = furthest x reached on diagonal k after d edits.
    my @trace;
    my %v;
    my $max = $na + $nb;
    my $found;

    for my $d (0 .. $max) {
        my %vd;
        for my $k (-$d .. $d) {
            my $x;
            if ($k == -$d || ($k != $d && ($v{$k - 1} // 0) < ($v{$k + 1} // 0))) {
                $x = $v{$k + 1} // 0;  # Insert (move down)
            } else {
                $x = ($v{$k - 1} // 0) + 1;  # Delete (move right)
            }
            my $y = $x - $k;
            while ($x < $na && $y < $nb && $a->[$x] eq $b->[$y]) {
                $x++; $y++;
            }
            $vd{$k} = $x;
            if ($x >= $na && $y >= $nb) {
                $found = $d;
                push @trace, { %v };
                # Backtrace
                return _myers_backtrace(\@trace, $a, $b, $na, $nb, $found);
            }
        }
        %v = %vd;
        push @trace, { %v };
    }
    # Fallback to LCS if Myers fails (shouldn't happen)
    return _lcs_diff($a, $b);
}

sub _myers_backtrace {
    my ($trace, $a, $b, $na, $nb, $max_d) = @_;
    my @ops;
    my $x = $na;
    my $y = $nb;

    for (my $d = $max_d; $d > 0; $d--) {
        my $v = $trace->[$d - 1];
        my $k = $x - $y;
        my $prev_x;
        if ($k == -$d || ($k != $d && ($v->{$k - 1} // 0) < ($v->{$k + 1} // 0))) {
            $prev_x = $v->{$k + 1} // 0;  # Came from insert
        } else {
            $prev_x = ($v->{$k - 1} // 0) + 1;  # Came from delete
        }
        my $prev_y = $prev_x - ($k + ($k == -$d || ($k != $d && ($v->{$k - 1} // 0) < ($v->{$k + 1} // 0)) ? -1 : 1));

        # Record snake (matches) in reverse
        while ($x > $prev_x && $y > $prev_y) {
            unshift @ops, ['keep', $x - 1, $y - 1];
            $x--; $y--;
        }

        if ($d > 1) {
            if ($x == $prev_x) {
                unshift @ops, ['insert', $x, $y - 1];
            } else {
                unshift @ops, ['delete', $x - 1, $y];
            }
        } elsif ($x == $prev_x) {
            unshift @ops, ['insert', $x, $y - 1];
        } elsif ($y == $prev_y) {
            unshift @ops, ['delete', $x - 1, $y];
        }

        $x = $prev_x;
        $y = $prev_y;
    }

    # Handle initial snake (d=0)
    while ($x > 0 && $y > 0) {
        unshift @ops, ['keep', $x - 1, $y - 1];
        $x--; $y--;
    }
    while ($x > 0) {
        unshift @ops, ['delete', $x - 1, $y];
        $x--;
    }
    while ($y > 0) {
        unshift @ops, ['insert', $x, $y - 1];
        $y--;
    }

    return \@ops;
}

# Patience diff algorithm — anchors on unique common lines, producing
# more human-readable diffs with fewer "jumping" hunks.
# Returns list of [op, a_idx, b_idx].
sub _patience_diff {
    my ($old_arr, $new_arr) = @_;
    my $na = scalar(@$old_arr);
    my $nb = scalar(@$new_arr);

    # Find unique common lines (anchors)
    my %a_count; $a_count{$_}++ for @$old_arr;
    my %b_count; $b_count{$_}++ for @$new_arr;

    my @anchors;  # [a_idx, b_idx] pairs
    my %a_unique;  # line -> a_idx for unique lines
    for my $i (0 .. $na - 1) {
        my $line = $old_arr->[$i];
        if ($a_count{$line} == 1 && ($b_count{$line} // 0) == 1) {
            $a_unique{$line} = $i;
        }
    }
    for my $j (0 .. $nb - 1) {
        my $line = $new_arr->[$j];
        if (exists $a_unique{$line}) {
            push @anchors, [$a_unique{$line}, $j];
        }
    }

    # Sort anchors by a_idx (numeric, since indices are integers)
    @anchors = sort { $a->[0] <=> $b->[0] } @anchors;

    # Find LIS (longest increasing subsequence) of b_idx values
    my @lis;
    if (@anchors) {
        @lis = _find_lis([map { $_->[1] } @anchors]);
    }
    my @matched_anchors;
    for my $idx (@lis) {
        next unless defined $idx && $idx >= 0 && $idx < scalar(@anchors);
        push @matched_anchors, $anchors[$idx];
    }

    # Recursively diff between anchors
    my @ops;
    my $a_start = 0;
    my $b_start = 0;

    for my $anchor (@matched_anchors) {
        my ($a_idx, $b_idx) = @$anchor;

        # Diff the gap before this anchor
        if ($a_idx > $a_start || $b_idx > $b_start) {
            my $sub_a = [ @{$old_arr}[$a_start .. $a_idx - 1] ];
            my $sub_b = [ @{$new_arr}[$b_start .. $b_idx - 1] ];
            my $sub_ops = _lcs_diff($sub_a, $sub_b);
            for my $op (@$sub_ops) {
                push @ops, [ $op->[0], $op->[1] + $a_start, $op->[2] + $b_start ];
            }
        }

        # Keep the anchor
        push @ops, ['keep', $a_idx, $b_idx];

        $a_start = $a_idx + 1;
        $b_start = $b_idx + 1;
    }

    # Diff the tail after the last anchor
    if ($a_start < $na || $b_start < $nb) {
        my $sub_a = [ @{$old_arr}[$a_start .. $na - 1] ];
        my $sub_b = [ @{$new_arr}[$b_start .. $nb - 1] ];
        my $sub_ops = _lcs_diff($sub_a, $sub_b);
        for my $op (@$sub_ops) {
            push @ops, [ $op->[0], $op->[1] + $a_start, $op->[2] + $b_start ];
        }
    }

    return \@ops;
}

# Find the longest increasing subsequence (for patience diff)
# Returns indices of the LIS elements.
sub _find_lis {
    my ($arr) = @_;
    return [] unless @$arr;

    my @tails;  # tails[i] = index of smallest tail of LIS of length i+1
    my @prev;   # prev[i] = index of previous element in LIS ending at i

    for my $i (0 .. $#$arr) {
        # Binary search for the position to replace
        my $lo = 0;
        my $hi = $#tails;
        while ($lo <= $hi) {
            my $mid = int(($lo + $hi) / 2);
            if ($arr->[$tails[$mid]] < $arr->[$i]) {
                $lo = $mid + 1;
            } else {
                $hi = $mid - 1;
            }
        }

        if ($lo > 0) {
            $prev[$i] = $tails[$lo - 1];
        } else {
            $prev[$i] = -1;
        }

        if ($lo >= scalar(@tails)) {
            push @tails, $i;
        } else {
            $tails[$lo] = $i;
        }
    }

    # Reconstruct the LIS
    my @result;
    my $idx = $tails[-1];
    while ($idx >= 0) {
        unshift @result, $idx;
        $idx = $prev[$idx];
    }
    return @result;
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
