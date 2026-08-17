#!/usr/bin/env perl
# diffvim-postprocess — Post-processes raw char ops from diffvim-compute.
#
# Reads raw char ops (HUNK/keep/delete/insert) from stdin, applies
# post-processing transformations, and writes ordered ops to stdout.
#
# Multiple postprocess invocations can be piped:
#   diffvim-compute-c old.py new.py |
#     diffvim-postprocess --op-order optimize |
#     diffvim-postprocess --semantic-cleanup
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
# The op format (input and output) is:
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

GetOptions(
    'op-order=s'      => \$op_order,
    'semantic-cleanup' => \$semantic_cleanup,
    'indent-aware'     => \$indent_aware,
    'overwrite'        => \$overwrite,
    'help|h'           => \$help,
) or die "Usage: $0 [options]\n  Run '$0 --help' for details.\n";

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

# Parse input
my $current_hunk;
for my $line (@lines) {
    chomp $line;
    if ($line =~ /^#/) {
        push @header, $line;
        next;
    }
    if ($line =~ /^HUNK\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)$/) {
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
    if ($line =~ /^(keep|delete|insert)\s+(\d+)$/) {
        push @{$current_hunk->{ops}}, [$1, int($2)];
        next;
    }
    # Pass through unknown lines
    push @header, $line if !$current_hunk;
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

# Write output: header (with updated flags), then hunks
for my $line (@header) {
    if ($line =~ /^# semantic_cleanup/) {
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
    } else {
        print "$line\n";
    }
}

# Print hunks
for my $hunk (@hunks) {
    printf "HUNK %d %d %d %d %d\n",
        $hunk->{target}, $hunk->{del_count}, $hunk->{ins_count},
        $hunk->{end_ins}, $hunk->{end_del};
    for my $op (@{$hunk->{ops}}) {
        printf "%s %d\n", $op->[0], $op->[1];
    }
}

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
sub reorder_ops {
    my ($ops, $mode) = @_;

    # Group ops by line
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

# Optimize: within each "change region" (between keeps), put deletes before inserts
sub optimize_line {
    my ($ops) = @_;
    my @result;
    my @buffer;  # current change region

    for my $op (@$ops) {
        if ($op->[0] eq 'keep') {
            # Flush buffer: deletes first, then inserts
            if (@buffer) {
                my @dels = grep { $_->[0] eq 'delete' } @buffer;
                my @ins = grep { $_->[0] eq 'insert' } @buffer;
                push @result, @dels, @ins;
                @buffer = ();
            }
            push @result, $op;
        } else {
            push @buffer, $op;
        }
    }
    # Flush remaining
    if (@buffer) {
        my @dels = grep { $_->[0] eq 'delete' } @buffer;
        my @ins = grep { $_->[0] eq 'insert' } @buffer;
        push @result, @dels, @ins;
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
