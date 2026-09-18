#!/usr/bin/env perl
# ad_layer_skip_indent.pl — Perl twin of ad_layer_skip_indent.c.
#
# Phase 2: per-LINE detection (was per-hunk).
#
# Detects LINES where all delete/insert/overwrite_insert ops are
# whitespace (space=32, tab=9) or newline (code=10), and wraps each
# such line with delay markers so the pace layer applies them
# instantly (skip animation). Other lines in the same hunk animate
# normally.
#
# A LINE is a maximal run of ops between line boundaries. Line
# boundaries are line ops (keep_line, join_lines, split_line,
# delete_line, insert_line, batch_insert) and \n char ops (code 10).
# The boundary op is included in the line.
#
# Usage: perl ad_layer_skip_indent.pl [--pause-after-ms N] < post_ops > marked_ops

use strict;
use warnings;
use utf8;
use FindBin;
use lib "$FindBin::Bin/../../perl";

use DiffVim::Layer qw(run_layer parse_op write_op char_repr is_debug_op);

my $pause_after_ms = 300;

# Parse CLI args
for my $arg (@ARGV) {
    if ($arg =~ /^--pause-after-ms=(\d+)$/) {
        $pause_after_ms = $1;
    } elsif ($arg eq '--pause-after-ms') {
        # handled in the main loop below
    } elsif ($arg eq '--help' || $arg eq '-h') {
        print STDERR "ad_layer_skip_indent — skip animation for whitespace-only LINES\n\n";
        print STDERR "Usage: ad_layer_skip_indent [options] < post_ops > marked_ops\n\n";
        print STDERR "Options:\n";
        print STDERR "  --pause-after-ms N  Pause after each whitespace-only line (default: 300)\n";
        print STDERR "  --help, -h          Show this help\n\n";
        print STDERR "Detects LINES where all changes are whitespace (spaces/tabs/newlines).\n";
        print STDERR "Wraps each such line with delay markers so the pace layer applies\n";
        print STDERR "them instantly. Other lines in the same hunk animate normally.\n\n";
        print STDERR "Phase 2: per-LINE detection (was per-hunk in Phase 1).\n";
        exit 0;
    }
}

# Check for --pause-after-ms with separate value
for (my $i = 0; $i < @ARGV; $i++) {
    if ($ARGV[$i] eq '--pause-after-ms' && $i + 1 < @ARGV) {
        $pause_after_ms = $ARGV[$i + 1];
    }
}

sub is_whitespace_code {
    my ($code) = @_;
    return ($code == 32 || $code == 9 || $code == 10);
}

sub is_line_op_type {
    my ($type) = @_;
    return defined $type && (
        $type eq 'keep_line' || $type eq 'join_lines' ||
        $type eq 'split_line' || $type eq 'delete_line' ||
        $type eq 'insert_line' || $type eq 'batch_insert'
    );
}

sub transform_hunk {
    my ($ops, $line_offset) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $i = 0;
    while ($i < $n) {
        # Find the end of the current line. Line boundaries are line
        # ops and \n ops. The boundary op is included in this line.
        my $line_start = $i;
        my $j = $i;
        while ($j < $n) {
            my $op = $in[$j];
            next if is_debug_op($op);
            if (is_line_op_type($op->{type})) { $j++; last; }
            if (defined $op->{code} && $op->{code} == 10) { $j++; last; }
            $j++;
        }
        my $line_end = $j;

        # Check if all delete/insert/overwrite_insert ops in this line
        # are whitespace or \n.
        my $has_change = 0;
        my $is_ws_only = 1;
        for my $k ($line_start .. $line_end - 1) {
            my $op = $in[$k];
            next if is_debug_op($op);
            if ($op->{type} eq 'delete' || $op->{type} eq 'insert' ||
                $op->{type} eq 'overwrite_insert') {
                $has_change = 1;
                if (!is_whitespace_code($op->{code})) {
                    $is_ws_only = 0;
                    last;
                }
            }
        }

        if ($has_change && $is_ws_only) {
            # Whitespace-only line — wrap with markers.
            push @out, { type => 'delay', code => 0, line => -1, col => 0 };
            push @out, @in[$line_start .. $line_end - 1];
            push @out, { type => 'delay', code => $pause_after_ms, line => -1, col => 1 };
        } else {
            # Normal line — pass through unchanged.
            push @out, @in[$line_start .. $line_end - 1];
        }

        $i = $line_end;
    }

    return (\@out, 0);
}

exit run_layer(\&transform_hunk, name => 'ad_layer_skip_indent (Perl)');
