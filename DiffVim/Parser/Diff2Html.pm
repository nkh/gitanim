package DiffVim::Parser::Diff2Html;
# Diff parser that shells out to the `diff2html` CLI with `-f json` to do
# the line-level parsing, then computes char-level ops in Perl.
#
# diff2html is a Node.js tool: https://github.com/rtfpessoa/diff2html-cli
# Install: npm install -g diff2html-cli
#
# The JSON output is line-level only (each line is context/insert/delete).
# We group consecutive delete+insert lines into hunks and compute char-level
# LCS diffs within each hunk, producing the same output format as
# DiffVim::Parser::Perl.

use strict;
use warnings;
use utf8;
use JSON::PP;

use Exporter qw(import);
our @EXPORT_OK = qw(parse_diff);

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# parse_diff($old_file, $new_file)
# Returns the same structure as DiffVim::Parser::Perl::parse_diff.
sub parse_diff {
    my ($old_file, $new_file) = @_;

    # Generate a unified diff, then feed it to diff2html.
    my $diff_text = _generate_unified_diff($old_file, $new_file);
    my $json_text = _run_diff2html($diff_text);
    my $files = decode_json($json_text);

    # Read old file to know line count (for end_insert/end_delete detection).
    my $old_lines = _read_lines($old_file);
    my $old_line_count = scalar(@$old_lines);

    # diff2html returns an array of file objects. We only handle the first
    # file (our use case is single-file diffs). If multiple files are
    # present, we concatenate their hunks.
    my @all_hunks;
    my $line_offset = 0;  # accumulates across files

    for my $file (@$files) {
        my $file_hunks = _parse_file($file, \$line_offset, $old_line_count);
        push @all_hunks, @$file_hunks;
    }

    return { hunks => \@all_hunks, parser => 'diff2html' };
}

# ---------------------------------------------------------------------------
# diff2html invocation
# ---------------------------------------------------------------------------

# Generate a unified diff using the system `diff` command.
sub _generate_unified_diff {
    my ($old_file, $new_file) = @_;
    # Use --label to make the diff header look like a git diff (diff2html
    # parses the ---/+++ headers for file names).
    my $old_label = "a/$old_file";
    my $new_label = "b/$new_file";
    my $output = `diff -u --label '$old_label' --label '$new_label' '$old_file' '$new_file' 2>/dev/null`;
    # diff returns 1 when files differ (that's expected).
    return $output;
}

# Run diff2html on the diff text and return the JSON output.
# Returns undef if the diff is empty (files are identical).
sub _run_diff2html {
    my ($diff_text) = @_;

    # If the diff is empty, files are identical — return empty array.
    return '[]' unless defined $diff_text && length($diff_text);

    # Write diff to a temp file (diff2html -i file is more reliable than stdin).
    my $tmpfile = "/tmp/dv_diff2html_" . $$ . ".diff";
    open my $fh, '>:raw', $tmpfile or die "Cannot write $tmpfile: $!";
    print $fh $diff_text;
    close $fh;

    # Run diff2html: -f json (JSON output), -o stdout (print to stdout),
    # -i file (read from file), -d char (char-level diff style, though the
    # JSON output is still line-level, this enables better line matching).
    my $json = `diff2html -f json -o stdout -i file -d char -- '$tmpfile' 2>/dev/null`;

    unlink $tmpfile;

    return '[]' unless defined $json && length($json);
    return $json;
}

# ---------------------------------------------------------------------------
# JSON parsing
# ---------------------------------------------------------------------------

# Parse a single file object from diff2html JSON.
# Each file has: oldName, newName, blocks[]
# Each block has: oldStartLine, newStartLine, header, lines[]
# Each line has: content (with diff prefix), type (context/insert/delete),
#                oldNumber, newNumber
sub _parse_file {
    my ($file, $line_offset_ref, $old_line_count) = @_;

    my @hunks;
    my $blocks = $file->{blocks} // [];

    for my $block (@$blocks) {
        my $lines = $block->{lines} // [];

        # Determine if this block has any old lines (context or delete).
        # If yes, oldStartLine is the first old line's number, and initial
        # old_pos should be oldStartLine - 1 (we haven't "seen" it yet).
        # If no (pure insertion), oldStartLine is the line after which to
        # insert, and old_pos = oldStartLine.
        my $has_old_lines = 0;
        for my $line (@$lines) {
            if (($line->{type} // '') eq 'context' || ($line->{type} // '') eq 'delete') {
                $has_old_lines = 1;
                last;
            }
        }
        my $old_pos = $has_old_lines
            ? (($block->{oldStartLine} // 1) - 1)
            : ($block->{oldStartLine} // 0);

        my @cur_old;
        my @cur_new;
        my $cur_target = $old_pos + 1;
        my $has_hunk = 0;

        for my $line (@$lines) {
            my $type = $line->{type};
            my $content = $line->{content};

            # Strip the diff prefix character (first char: ' ', '-', '+')
            my $text = length($content) > 1 ? substr($content, 1) : '';

            if ($type eq 'context') {
                if ($has_hunk) {
                    push @hunks, _flush_hunk(\@cur_old, \@cur_new,
                        $cur_target, $old_line_count);
                    @cur_old = ();
                    @cur_new = ();
                    $has_hunk = 0;
                }
                # Update old_pos to this context line's old number
                $old_pos = $line->{oldNumber} // $old_pos;
            } elsif ($type eq 'delete') {
                if (!$has_hunk) {
                    $cur_target = $line->{oldNumber} // ($old_pos + 1);
                    $has_hunk = 1;
                }
                $old_pos = $line->{oldNumber} // $old_pos;
                push @cur_old, $text;
            } elsif ($type eq 'insert') {
                if (!$has_hunk) {
                    # Inserts go after the last seen old line
                    $cur_target = $old_pos + 1;
                    $has_hunk = 1;
                }
                push @cur_new, $text;
            }
        }

        if ($has_hunk) {
            push @hunks, _flush_hunk(\@cur_old, \@cur_new,
                $cur_target, $old_line_count);
        }
    }

    return \@hunks;
}

# ---------------------------------------------------------------------------
# Char-level diff (LCS) — same algorithm as DiffVim::Parser::Perl
# ---------------------------------------------------------------------------

sub _char_diff {
    my ($old_text, $new_text) = @_;

    # Decode as UTF-8 so multi-byte characters are treated as single chars
    my $old_decoded = $old_text;
    my $new_decoded = $new_text;
    eval { require Encode; $old_decoded = Encode::decode('UTF-8', $old_text, Encode::FB_CROAK()); };
    $old_decoded = $old_text if $@;
    eval { require Encode; $new_decoded = Encode::decode('UTF-8', $new_text, Encode::FB_CROAK()); };
    $new_decoded = $new_text if $@;

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

sub _lcs_diff {
    my ($a, $b) = @_;
    my $na = scalar(@$a);
    my $nb = scalar(@$b);

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
# Hunk construction (same logic as Perl parser)
# ---------------------------------------------------------------------------

sub _flush_hunk {
    my ($cur_old, $cur_new, $target, $old_line_count) = @_;

    my $del_count = scalar(@$cur_old);
    my $ins_count = scalar(@$cur_new);

    my $old_text = join("\n", @$cur_old);
    my $new_text = join("\n", @$cur_new);

    my ($is_end_ins, $is_end_del) = (0, 0);

    if ($del_count == 0) {
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

sub _read_lines {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return [''] unless defined $content && length($content);
    my @lines = split /\n/, $content, -1;
    pop @lines if @lines && $lines[-1] eq '' && $content =~ /\n\z/;
    return \@lines;
}

1;

__END__

=head1 NAME

DiffVim::Parser::Diff2Html - Diff parser using diff2html CLI for line-level parsing

=head1 SYNOPSIS

    use DiffVim::Parser::Diff2Html qw(parse_diff);
    my $result = parse_diff('old.txt', 'new.txt');

=head1 DESCRIPTION

Shells out to C<diff2html -f json> to parse a unified diff into a
structured JSON representation, then computes char-level LCS diffs within
each hunk. This produces the same output format as L<DiffVim::Parser::Perl>,
allowing the two parsers to be used interchangeably.

Requires the C<diff2html> CLI: C<npm install -g diff2html-cli>.

=cut
