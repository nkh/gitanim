#!/usr/bin/env perl
# diffvim-decorate — Insert decoration ops into the timed op stream.
#
# Reads a timed op stream from stdin, inserts decoration ops
# (highlight, dim, fold, sign, marker) based on the options, writes
# the decorated stream to stdout.
#
# Both the vimscript animator and the C animator interpret the
# decoration ops the same way.
#
# Usage: diffvim-decorate [options]
#   --highlight none|inline|word|hunk   (default: none)
#   --highlight-duration-ms N           (default: 200)
#   --dim-unchanged                     Dim unchanged anchor lines
#   --dim-unchanged-pct N              Dim percentage (default: 60)
#   --context N                        Fold unchanged regions >2N lines
#   --fold-unchanged                   Fold unchanged regions
#   --sign-column                      Place +/- signs
#   --git-blame                        Insert blame markers
#   --max-hunk-chars N                 Skip animation for hunks >N chars
#   --theme dark|light|high-contrast   Color theme

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $highlight_mode = 'none';
my $highlight_duration_ms = 200;
my $dim_unchanged = 0;
my $dim_unchanged_pct = 60;
my $context_lines = 0;
my $fold_unchanged = 0;
my $sign_column = 0;
my $git_blame = 0;
my $max_hunk_chars = 0;
my $theme = '';
my $help = 0;

GetOptions(
    'highlight=s'           => \$highlight_mode,
    'highlight-duration-ms=i' => \$highlight_duration_ms,
    'dim-unchanged'         => sub { $dim_unchanged = 1; },
    'dim-unchanged-pct=i'    => \$dim_unchanged_pct,
    'context=i'              => \$context_lines,
    'fold-unchanged'         => sub { $fold_unchanged = 1; },
    'sign-column'            => sub { $sign_column = 1; },
    'git-blame'              => sub { $git_blame = 1; },
    'max-hunk-chars=i'        => \$max_hunk_chars,
    'theme=s'                => \$theme,
    'help|h'                 => \$help,
) or die "Usage: $0 [options]\n";

if ($help) {
    print STDERR "Usage: diffvim-decorate [options]\n";
    print STDERR "  --highlight none|inline|word|hunk  Highlight mode (default: none)\n";
    print STDERR "  --highlight-duration-ms N        Highlight duration (default: 200)\n";
    print STDERR "  --dim-unchanged                   Dim unchanged lines\n";
    print STDERR "  --dim-unchanged-pct N             Dim percentage (default: 60)\n";
    print STDERR "  --context N                       Fold unchanged regions >2N lines\n";
    print STDERR "  --fold-unchanged                  Fold unchanged regions\n";
    print STDERR "  --sign-column                     Place +/- signs\n";
    print STDERR "  --git-blame                       Insert blame markers\n";
    print STDERR "  --max-hunk-chars N                Skip animation for hunks >N chars\n";
    print STDERR "  --theme dark|light|high-contrast  Color theme\n";
    exit 0;
}

# Read all input
my @lines;
while (my $line = <STDIN>) {
    chomp $line;
    push @lines, $line;
}

# Emit header
print "# diffvim decorated ops v2\n";
print "# highlight $highlight_mode\n";
print "# dim_unchanged $dim_unchanged\n";
print "# sign_column $sign_column\n";

# State
my $hunk_start_line = 0;
my $hunk_end_line = 0;
my $hunk_char_count = 0;
my $in_hunk = 0;
my $last_changed_line = 0;
my $prev_hunk_end_line = 0;

# Helper: check if a line is a keep op
sub is_keep_op { return $_[0] =~ /^keep\t/; }
sub is_change_op { return $_[0] =~ /^(delete|insert|overwrite_insert)\t/; }
sub is_delay_op { return $_[0] =~ /^delay\t/; }

# Helper: get fields from TSV
sub get_fields {
    my ($line) = @_;
    return split /\t/, $line;
}

# Emit functions
sub emit_highlight {
    my ($sl, $sc, $el, $ec, $type, $dur) = @_;
    printf "highlight\t%d\t%d\t%d\t%d\t%s\t%d\n", $sl, $sc, $el, $ec, $type, $dur;
}

sub emit_dim {
    my ($sl, $el, $pct) = @_;
    printf "dim\t%d\t%d\t%d\n", $sl, $el, $pct;
}

sub emit_fold {
    my ($sl, $el) = @_;
    printf "fold\t%d\t%d\n", $sl, $el;
}

sub emit_sign {
    my ($line, $type) = @_;
    printf "sign\t%d\t%s\n", $line, $type;
}

sub emit_skip_hunk {
    print "skip_hunk\n";
}

# Process lines
for my $line (@lines) {
    next if $line eq '' || $line =~ /^#/;

    # Detect HUNK start
    if ($line =~ /^HUNK\t(\d+)/) {
        my $target = $1;
        $hunk_start_line = $target;
        $hunk_char_count = 0;
        $in_hunk = 1;

        # Dim unchanged region before this hunk
        if ($dim_unchanged && $prev_hunk_end_line > 0 && $target > $prev_hunk_end_line + 1) {
            emit_dim($prev_hunk_end_line + 1, $target - 1, $dim_unchanged_pct);
        }
        # Fold unchanged region before this hunk
        if ($fold_unchanged && $prev_hunk_end_line > 0 && $target > $prev_hunk_end_line + 1) {
            emit_fold($prev_hunk_end_line + 1, $target - 1);
        } elsif ($context_lines > 0 && $prev_hunk_end_line > 0
                 && $target > $prev_hunk_end_line + 2 * $context_lines + 1) {
            my $gap = $target - $prev_hunk_end_line - 1;
            if ($gap > 2 * $context_lines) {
                emit_fold($prev_hunk_end_line + $context_lines + 1,
                          $target - $context_lines - 1);
            }
        }

        print "$line\n";
        next;
    }

    # Detect HUNK_END
    if ($line eq 'HUNK_END') {
        $in_hunk = 0;
        $hunk_end_line = $last_changed_line;

        # Highlight hunk
        if ($highlight_mode eq 'hunk' && $hunk_start_line > 0 && $hunk_end_line > 0) {
            emit_highlight($hunk_start_line, 1, $hunk_end_line, 1, "hunk", $highlight_duration_ms);
        }
        # Max hunk chars
        if ($max_hunk_chars > 0 && $hunk_char_count > $max_hunk_chars) {
            emit_skip_hunk();
        }

        $prev_hunk_end_line = $hunk_end_line;
        print "$line\n";
        next;
    }

    # For change ops: track hunk state
    if (is_change_op($line) && !is_delay_op($line)) {
        my @fields = get_fields($line);
        my $op_line = $fields[1] // 0;
        if ($op_line > $last_changed_line) {
            $last_changed_line = $op_line;
        }
        $hunk_char_count++;
    }

    # Emit the op
    print "$line\n";

    # After change ops, emit decorations
    if (is_change_op($line) && !is_delay_op($line)) {
        my @fields = get_fields($line);
        my $op_type = $fields[0] // '';
        my $op_line = $fields[1] // 0;
        my $op_col = $fields[2] // 0;

        if ($highlight_mode eq 'inline') {
            if ($op_type eq 'delete') {
                emit_highlight($op_line, $op_col, $op_line, $op_col, "delete", $highlight_duration_ms);
            } elsif ($op_type eq 'insert' || $op_type eq 'overwrite_insert') {
                emit_highlight($op_line, $op_col, $op_line, $op_col, "insert", $highlight_duration_ms);
            }
        } elsif ($highlight_mode eq 'word') {
            # Same as inline for now (word detection needs lookahead)
            if ($op_type eq 'delete') {
                emit_highlight($op_line, $op_col, $op_line, $op_col, "delete", $highlight_duration_ms);
            } elsif ($op_type eq 'insert' || $op_type eq 'overwrite_insert') {
                emit_highlight($op_line, $op_col, $op_line, $op_col, "insert", $highlight_duration_ms);
            }
        }

        if ($sign_column) {
            if ($op_type eq 'delete') {
                emit_sign($op_line, "del");
            } elsif ($op_type eq 'insert' || $op_type eq 'overwrite_insert') {
                emit_sign($op_line, "add");
            }
        }
    }
}

print "\n";  # blank line at bottom
