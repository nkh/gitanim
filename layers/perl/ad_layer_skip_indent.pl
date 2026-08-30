#!/usr/bin/env perl
# ad_layer_skip_indent.pl — Perl twin of ad_layer_skip_indent.c.
#
# Detects indent-only hunks and wraps them with delay markers so the
# pace layer applies them instantly (skip animation).
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
        print STDERR "ad_layer_skip_indent — skip animation for indent-only hunks\n\n";
        print STDERR "Usage: ad_layer_skip_indent [options] < post_ops > marked_ops\n\n";
        print STDERR "Options:\n";
        print STDERR "  --pause-after-ms N  Pause after indent-only hunk (default: 300)\n";
        print STDERR "  --help, -h          Show this help\n";
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

sub transform_hunk {
    my ($ops, $line_offset) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    # Check if ALL delete/insert ops are whitespace or newline.
    my $has_change = 0;
    my $is_indent_only = 1;
    for my $op (@in) {
        next if is_debug_op($op);
        if ($op->{type} eq 'delete' || $op->{type} eq 'insert' ||
            $op->{type} eq 'overwrite_insert') {
            $has_change = 1;
            if (!is_whitespace_code($op->{code})) {
                $is_indent_only = 0;
                last;
            }
        }
    }

    if (!$has_change || !$is_indent_only) {
        # Not indent-only — pass through unchanged.
        return (\@in, 0);
    }

    # Indent-only hunk — wrap with markers.
    push @out, { type => 'delay', code => 0, line => -1, col => 0 };
    push @out, @in;
    push @out, { type => 'delay', code => $pause_after_ms, line => -1, col => 1 };

    return (\@out, 0);
}

exit run_layer(\&transform_hunk, name => 'ad_layer_skip_indent (Perl)');
