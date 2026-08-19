#!/usr/bin/env perl
# diffvim-postprocess — Post-processes raw char ops from diffvim-compute.
#
# Reads raw char ops (HUNK/keep/delete/insert) from stdin, applies
# post-processing transformations, computes per-op (line, col) positions,
# and writes tab-separated ops to stdout.
#
# POSTPROCESS OWNS CURSOR POSITIONING. The pace stage only handles delays
# and batching. The animator reads (line, col) from each op and applies
# it at that exact position — scroll-safe.
#
# Output format (TSV, 1-indexed line/col):
#   hunk_start\t<del_count>\t<ins_count>
#   op\tkeep|delete|insert\t<line>\t<col>\t<code>
#   newline_delete\t<line>
#   newline_insert\t<line>\t<col>
#
# Usage:
#   diffvim-postprocess [options] < raw_ops > ordered_ops
#
# Options:
#   --op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite
#       (default: optimize)
#   --semantic-cleanup    Merge adjacent delete/insert pairs that cancel out
#   --indent-aware        Handle indent-only changes
#   --overwrite           Transform delete+insert into in-place overwrite
#   --help, -h            Show help
#
# Input format:
#   # header lines (passed through)
#   HUNK <target> <del> <ins> <end_ins> <end_del>
#   keep|delete|insert <code>
#   ...

use strict;
use warnings;
use utf8;
use Getopt::Long qw(GetOptions);

my $op_order = 'optimize';
my $semantic_cleanup = 0;
my $indent_aware = 0;
my $overwrite = 0;
my $help = 0;
my $list_transforms = 0;
my @transforms;

GetOptions(
    'op-order=s'      => \$op_order,
    'semantic-cleanup' => \$semantic_cleanup,
    'indent-aware'     => \$indent_aware,
    'overwrite'        => \$overwrite,
    'transform=s'      => \@transforms,
    'list-transforms'  => \$list_transforms,
    'help|h'           => \$help,
) or die "Usage: $0 [options]\n  Run '$0 --help' for details.\n";

if ($list_transforms) {
    print "Available transforms (use --transform NAME[:VALUE]):\n";
    print "  op-order:natural        No reordering (raw patience order)\n";
    print "  op-order:optimize       Deletes before inserts within each line (default)\n";
    print "  semantic-cleanup        Merge adjacent delete+insert pairs that cancel out\n";
    print "  indent-aware            Handle indent-only changes as keeps\n";
    print "  overwrite               Transform delete+insert into in-place overwrite\n";
    print "\nTransforms are applied in the order specified.\n";
    print "Multiple --transform flags can be given.\n";
    exit 0;
}

# Apply --transform flags
for my $spec (@transforms) {
    if ($spec =~ /^op-order:(.+)$/) {
        $op_order = $1;
    } elsif ($spec eq 'semantic-cleanup') {
        $semantic_cleanup = 1;
    } elsif ($spec eq 'indent-aware') {
        $indent_aware = 1;
    } elsif ($spec eq 'overwrite') {
        $overwrite = 1;
    } else {
        die "Unknown transform '$spec'. Run --list-transforms for available options.\n";
    }
}

if ($help) {
    print STDERR <<USAGE;
diffvim-postprocess — Post-process raw char ops

Usage: diffvim-postprocess [options] < raw_ops > ordered_ops

Options:
  --op-order natural|optimize|left-to-right|end-first|end-first-smart|overwrite
                           Op reordering mode (default: optimize)
  --semantic-cleanup       Merge canceling delete/insert pairs
  --indent-aware           Handle indent-only changes
  --overwrite              Transform delete+insert into in-place overwrite
  -h, --help               Show this help

Examples:
  diffvim-compute-c old.py new.py | diffvim-postprocess --op-order optimize
  diffvim-compute-c old.py new.py | diffvim-postprocess --semantic-cleanup | diffvim-postprocess --op-order left-to-right
USAGE
    exit 0;
}

# Validate op-order
my %valid_op_orders = map { $_ => 1 } qw(natural optimize left-to-right end-first end-first-smart overwrite);
die "Invalid --op-order '$op_order'. Valid: natural|optimize|left-to-right|end-first|end-first-smart|overwrite\n"
    unless $valid_op_orders{$op_order};

# Read all input
my @lines = <STDIN>;
my @header;
my @hunks;  # each: { target, del_count, ins_count, end_ins, end_del, ops => [] }

# Parse input (v2 TSV format: HUNK\t<target>\t<del>\t<ins>\t<end_ins>\t<end_del>)
my $current_hunk;
for my $line (@lines) {
    chomp $line;
    if ($line =~ /^#/ || $line eq '') {
        push @header, $line if $line =~ /^#/;
        next;
    }
    if ($line =~ /^HUNK\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)/) {
        $current_hunk = {
            target    => $1,
            del_count  => $2,
            ins_count  => $3,
            end_ins    => $4,
            end_del    => $5,
            ops        => [],
        };
        push @hunks, $current_hunk;
        next;
    }
    if ($line eq 'HUNK_END') {
        $current_hunk = undef;
        next;
    }
    # v2 format: keep/delete/insert\t<line>\t<col>\t<code>\t<char_repr>
    if ($line =~ /^(keep|delete|insert)\t(\d+)\t(\d+)\t(\d+)/) {
        push @{$current_hunk->{ops}}, [$1, int($4)] if $current_hunk;
        next;
    }
}

# Apply transformations
for my $hunk (@hunks) {
    my $ops = $hunk->{ops};
    next unless @$ops >= 2;

    # --semantic-cleanup: merge canceling delete/insert pairs
    if ($semantic_cleanup) {
        $ops = semantic_cleanup($ops);
    }

    # --indent-aware: treat indent-only changes as keeps
    if ($indent_aware) {
        $ops = indent_aware($ops);
    }

    # --op-order: reorder ops within each line
    if ($op_order ne 'natural') {
        $ops = reorder_ops($ops, $op_order);
    }

    # --overwrite: transform delete+insert into in-place overwrite
    if ($overwrite) {
        $ops = overwrite_transform($ops);
    }

    $hunk->{ops} = $ops;
}

# Write output: header (with updated flags), then hunks with per-op (line, col) TSV.
my $line_offset = 0;  # Cumulative (newline_inserts - newline_deletes) from prior hunks.

for my $line (@header) {
    if ($line =~ /^# diffvim raw diff/ || $line =~ /^# diffvim precomputed/) {
        print "# diffvim post-processed v2\n";
    } elsif ($line =~ /^# semantic_cleanup/) {
        print "# semantic_cleanup $semantic_cleanup\n";
    } elsif ($line =~ /^# indent_aware/) {
        print "# indent_aware $indent_aware\n";
    } elsif ($line =~ /^# optimize_sequence/) {
        my $val = ($op_order eq 'natural') ? 0 : 1;
        print "# optimize_sequence $val\n";
    } elsif ($line =~ /^# left_to_right/) {
        my $val = ($op_order eq 'left-to-right') ? 1 : 0;
        print "# left_to_right $val\n";
    } elsif ($line =~ /^# hunk_count/) {
        print "# hunk_count " . scalar(@hunks) . "\n";
    } elsif ($line =~ /^# word_diff/) {
        print "$line\n";
    }
    # skip unknown headers
}

# Helper: convert char code to readable representation
sub char_repr {
    my ($code) = @_;
    return "\\n" if $code == 10;
    return "\\t" if $code == 9;
    return "\\r" if $code == 13;
    return "space" if $code == 32;
    if ($code >= 33 && $code <= 126) {
        return "'" . chr($code) . "'";
    }
    return "$code";
}

# Helper: emit an op in v2 TSV format
sub emit_op {
    my ($type, $line, $col, $code) = @_;
    printf "%s\t%d\t%d\t%d\t%s\n", $type, $line, $col, $code, char_repr($code);
}

# Print hunks with per-op (line, col) TSV positions (v2 format).
for my $hunk (@hunks) {
    printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
        $hunk->{target}, $hunk->{del_count}, $hunk->{ins_count},
        $hunk->{end_ins}, $hunk->{end_del};

    my $cur_line = $hunk->{target} + $line_offset;
    my $cur_col = 1;
    my ($newl_ins, $newl_del) = (0, 0);
    my $line_has_content = 0;
    my $ops = $hunk->{ops};
    my $i = 0;
    my $n = @$ops;

    while ($i < $n) {
        my ($type, $code) = @{$ops->[$i]};
        if ($code == 10) {
            if ($type eq 'keep') {
                emit_op("keep", $cur_line, $cur_col, $code);
                $cur_line++;
                $cur_col = 1;
                $line_has_content = 0;
            } elsif ($type eq 'delete') {
                if ($line_has_content) {
                    my $j = $i + 1;
                    while ($j < $n && $ops->[$j][0] eq 'delete' && $ops->[$j][1] != 10) { $j++; }
                    my $n_content = $j - ($i + 1);
                    my $followed_by_keep = 0;
                    if ($j < $n && ($ops->[$j][0] eq 'keep' || $ops->[$j][0] eq 'insert')) {
                        $followed_by_keep = 1;
                    }
                    if ($n_content > 0 && !$followed_by_keep) {
                        for my $k ($i+1 .. $j-1) {
                            emit_op("delete", $cur_line + 1, 1, $ops->[$k][1]);
                        }
                        emit_op("delete", $cur_line + 1, 1, 10);
                        $newl_del++;
                        $i = $j;
                        next;
                    }
                }
                emit_op("delete", $cur_line, $cur_col, 10);
                $newl_del++;
                $line_has_content = 0;
            } elsif ($type eq 'insert') {
                emit_op("insert", $cur_line, $cur_col, 10);
                $cur_line++;
                $cur_col = 1;
                $newl_ins++;
                $line_has_content = 0;
            }
        } else {
            emit_op($type, $cur_line, $cur_col, $code);
            if ($type eq 'keep') {
                $cur_col++;
                $line_has_content = 1;
            } elsif ($type eq 'insert') {
                $cur_col++;
            }
        }
        $i++;
    }

    print "HUNK_END\n";
    $line_offset += $newl_ins - $newl_del;
}
print "\n";  # blank line at bottom

# --- Transformation functions ---

# Semantic cleanup: merge adjacent delete+insert pairs that cancel out.
# e.g., delete 'a' insert 'a' → keep 'a'
sub semantic_cleanup {
    my ($ops) = @_;
    my @result;
    my $i = 0;
    while ($i < @$ops) {
        if ($i + 1 < @$ops
            && $ops->[$i][0] eq 'delete'
            && $ops->[$i+1][0] eq 'insert'
            && $ops->[$i][1] == $ops->[$i+1][1]) {
            # delete X, insert X → keep X
            push @result, ['keep', $ops->[$i][1]];
            $i += 2;
        } elsif ($i + 1 < @$ops
            && $ops->[$i][0] eq 'insert'
            && $ops->[$i+1][0] eq 'delete'
            && $ops->[$i][1] == $ops->[$i+1][1]) {
            # insert X, delete X → keep X
            push @result, ['keep', $ops->[$i][1]];
            $i += 2;
        } else {
            push @result, $ops->[$i];
            $i++;
        }
    }
    return \@result;
}

# Indent-aware: if a line changes only in indentation, treat as keep
sub indent_aware {
    my ($ops) = @_;
    # Group ops by line (delimited by \n = code 10)
    my @lines;
    my @current;
    for my $op (@$ops) {
        push @current, $op;
        if ($op->[1] == 10) {
            push @lines, [@current];
            @current = ();
        }
    }
    push @lines, [@current] if @current;

    # For each line, if all deletes are whitespace and all inserts are whitespace,
    # convert to keeps
    my @result;
    for my $line_ops (@lines) {
        my $all_ws_del = 1;
        my $all_ws_ins = 1;
        my $has_del = 0;
        my $has_ins = 0;
        for my $op (@$line_ops) {
            if ($op->[0] eq 'delete') {
                $has_del = 1;
                $all_ws_del = 0 unless $op->[1] == 32 || $op->[1] == 9 || $op->[1] == 10;
            } elsif ($op->[0] eq 'insert') {
                $has_ins = 1;
                $all_ws_ins = 0 unless $op->[1] == 32 || $op->[1] == 9 || $op->[1] == 10;
            }
        }
        if ($has_del && $has_del && $all_ws_del && $all_ws_ins) {
            # Convert all to keeps
            for my $op (@$line_ops) {
                push @result, ['keep', $op->[1]];
            }
        } else {
            push @result, @$line_ops;
        }
    }
    return \@result;
}

# Reorder ops within each line based on the op-order mode.
# A "line" is delimited by keep-\n, delete-\n, or insert-\n (code 10).
# Mirrors the C postprocess: split at \n, reorder each line group
# (content deletes, \n deletes, then inserts). No special merging.
sub reorder_ops {
    my ($ops, $mode) = @_;

    # Group ops by line. Each line group includes its trailing \n.
    my @lines;
    my @current;
    for my $op (@$ops) {
        push @current, $op;
        if ($op->[1] == 10) {
            push @lines, [@current];
            @current = ();
        }
    }
    push @lines, [@current] if @current;

    # Reorder each line
    my @result;
    for my $line_ops (@lines) {
        my $reordered = reorder_line($line_ops, $mode);
        push @result, @$reordered;
    }
    return \@result;
}

# Reorder ops within a single line.
sub reorder_line {
    my ($ops, $mode) = @_;
    return $ops if $mode eq 'natural';
    return $ops if @$ops < 2;

    # Separate by type
    my @keeps;
    my @deletes;
    my @inserts;
    for my $op (@$ops) {
        if ($op->[0] eq 'keep') {
            push @keeps, $op;
        } elsif ($op->[0] eq 'delete') {
            push @deletes, $op;
        } elsif ($op->[0] eq 'insert') {
            push @inserts, $op;
        }
    }

    if ($mode eq 'optimize') {
        # Deletes before inserts (keeps in original position)
        # Actually, optimize means: within a change region, deletes come first
        # We need to preserve the relative order of keeps
        return optimize_line($ops);
    } elsif ($mode eq 'left-to-right') {
        # Keeps, then deletes, then inserts
        return (@keeps, @deletes, @inserts);
    } elsif ($mode eq 'end-first' || $mode eq 'end-first-smart') {
        # Trailing deletes first, then inserts
        # For end-first-smart, also group the deletes
        return end_first_line($ops, $mode);
    } elsif ($mode eq 'overwrite') {
        # Don't reorder — overwrite is handled separately
        return $ops;
    }
    return $ops;
}

# Optimize: within each "change region" (between keeps), put content
# deletes first, then \n deletes, then inserts.
sub optimize_line {
    my ($ops) = @_;
    my @result;
    my @buffer;

    for my $op (@$ops) {
        if ($op->[0] eq 'keep') {
            if (@buffer) {
                my @content_dels = grep { $_->[0] eq 'delete' && $_->[1] != 10 } @buffer;
                my @nl_dels = grep { $_->[0] eq 'delete' && $_->[1] == 10 } @buffer;
                my @ins = grep { $_->[0] eq 'insert' } @buffer;
                push @result, @content_dels, @nl_dels, @ins;
                @buffer = ();
            }
            push @result, $op;
        } else {
            push @buffer, $op;
        }
    }
    if (@buffer) {
        my @content_dels = grep { $_->[0] eq 'delete' && $_->[1] != 10 } @buffer;
        my @nl_dels = grep { $_->[0] eq 'delete' && $_->[1] == 10 } @buffer;
        my @ins = grep { $_->[0] eq 'insert' } @buffer;
        push @result, @content_dels, @nl_dels, @ins;
    }
    return \@result;
}

# End-first: detect trailing deletes (at end of line) and move them before inserts
sub end_first_line {
    my ($ops, $mode) = @_;
    # Find if the last ops are deletes (before the \n)
    my $has_newline = @$ops && $ops->[-1][1] == 10;
    my @body = $has_newline ? @$ops[0 .. $#$ops - 1] : @$ops;
    my $nl = $has_newline ? $ops->[-1] : undef;

    # Find trailing deletes in body
    my $i = $#body;
    while ($i >= 0 && $body[$i][0] eq 'delete') {
        $i--;
    }
    my @trailing_dels = @body[$i+1 .. $#body];
    my @rest = @body[0 .. $i];

    # Within rest, also optimize (deletes before inserts)
    @rest = @{optimize_line(\@rest)};

    # Result: rest, then trailing deletes, then \n
    # Actually, end-first means: trailing deletes FIRST, then the rest
    # No — end-first means: delete the end of the line first, then insert
    # So: trailing_dels, then rest (which has keeps + inserts), then \n
    my @result;
    if (@trailing_dels) {
        push @result, @trailing_dels;
    }
    push @result, @rest;
    push @result, $nl if $nl;
    return \@result;
}

# Overwrite transform: replace delete+insert sequences with in-place overwrites
# This is a simplified version — a full implementation would need to match
# positions more carefully.
sub overwrite_transform {
    my ($ops) = @_;
    # For now, just optimize (deletes before inserts)
    # A full overwrite would replace delete 'a' insert 'b' with a single
    # "overwrite" op, but our op format doesn't have that.
    # Keep as-is for now — the animator can handle delete+insert as-is.
    return optimize_line($ops);
}
