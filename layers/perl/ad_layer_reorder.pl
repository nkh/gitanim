#!/usr/bin/env perl
# ad_layer_reorder.pl — Perl implementation of the reorder layer.
#
# 4-sweep reorder + cross-hunk position adjustment. This is the Perl
# twin of layers/c/ad_layer_reorder.c. Both produce byte-identical
# output for the same input (parity verified by tests).
#
# Algorithm (mirror of the C version):
#   1. Read ops hunk-by-hunk.
#   2. For each hunk, apply the cross-hunk line_offset to all ops
#      (cumulative \n_ins - \n_del from prior hunks).
#   3. Walk ops, breaking into "segments" at keep ops, \n ops, or hunk
#      end. A segment is the range [buf_start, boundary).
#   4. For each segment, emit ops in 4-sweep order:
#        a. non-newline deletes
#        b. non-newline inserts/overwrite_inserts
#        c. newline deletes (code==10)
#        d. newline inserts/overwrite_inserts (code==10)
#        e. debug ops (in original order)
#      Then emit the boundary op itself (keep or \n).
#   5. After reorder, walk the output and set (line, col) on every op
#      based on its type:
#        - keep/insert/overwrite_insert advance col by 1 (or reset on \n)
#        - delete doesn't advance position
#   6. Update line_offset based on \n inserts and \n deletes in output.
#
# Protocol (the ad_ layer plugin contract — see docs/src/plugin-layers.md):
#   * Reads V2 TSV from stdin: HUNK header, op lines, HUNK_END.
#   * Writes V2 TSV to stdout in the same format.
#   * Headers (# ...) and blank lines are passed through.
#   * Exit 0 on success.

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $LAYER_NAME = 'ad_layer_reorder (Perl)';
my $DEBUG = 0;
for my $arg (@ARGV) { $DEBUG = 1 if $arg eq "--debug"; }

sub debug_log {
    my ($msg) = @_;
    return unless $DEBUG;
    open(my $fh, '>>', '/tmp/ad_debug/postprocess.log') or return;
    print $fh "[$LAYER_NAME] $msg\n";
    close($fh);
}

# --- TSV parse / write ---------------------------------------------------

sub parse_op {
    my ($line) = @_;
    chomp $line;
    my @f = split /\t/, $line;
    return undef unless @f >= 4;
    return {
        type => $f[0],
        line => $f[1] + 0,
        col  => $f[2] + 0,
        code => $f[3] + 0,
    };
}

sub char_repr {
    my ($code) = @_;
    return "\\n"     if $code == 10;
    return "\\t"     if $code == 9;
    return "\\r"     if $code == 13;
    return "space"   if $code == 32;
    return "'" . chr($code) . "'" if $code >= 33 && $code <= 126;
    return "$code";
}

sub write_op {
    my ($op) = @_;
    printf "%s\t%d\t%d\t%d\t%s\n",
        $op->{type}, $op->{line}, $op->{col}, $op->{code},
        char_repr($op->{code});
}

sub is_debug_op {
    my ($op) = @_;
    return defined $op && $op->{type} eq 'debug';
}

# --- Layer transform -----------------------------------------------------

sub transform_hunk {
    my ($ops, $line_offset) = @_;
    my @in = @$ops;
    my $n = scalar @in;

    # Apply cross-hunk line_offset to all ops.
    for my $op (@in) {
        $op->{line} += $line_offset;
    }

    # 4-sweep reorder.
    my @out;
    my $buf_start = 0;
    for (my $i = 0; $i <= $n; $i++) {
        # Decide whether position $i is a flush boundary.
        my $is_flush = ($i == $n) ? 1 : 0;
        if (!$is_flush && !is_debug_op($in[$i])) {
            if ($in[$i]{type} eq 'keep' || $in[$i]{code} == 10) {
                $is_flush = 1;
            }
        }

        next unless $is_flush;

        # Sweep 1: non-newline deletes.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if ($in[$j]{type} eq 'delete' && $in[$j]{code} != 10) {
                push @out, $in[$j];
            }
        }
        # Sweep 2: non-newline inserts/overwrite_inserts.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if (($in[$j]{type} eq 'insert' || $in[$j]{type} eq 'overwrite_insert')
                && $in[$j]{code} != 10) {
                push @out, $in[$j];
            }
        }
        # Sweep 3: newline deletes.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if ($in[$j]{type} eq 'delete' && $in[$j]{code} == 10) {
                push @out, $in[$j];
            }
        }
        # Sweep 4: newline inserts/overwrite_inserts.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if (($in[$j]{type} eq 'insert' || $in[$j]{type} eq 'overwrite_insert')
                && $in[$j]{code} == 10) {
                push @out, $in[$j];
            }
        }
        # Sweep 5: debug ops (in original order).
        for (my $j = $buf_start; $j < $i; $j++) {
            push @out, $in[$j] if is_debug_op($in[$j]);
        }
        # Emit the boundary op itself.
        if ($i < $n) {
            push @out, $in[$i];
        }
        $buf_start = $i + 1;
    }

    # Set positions on the output.
    my $cl = @out > 0 ? $out[0]{line} : 1;
    my $cc = 1;
    for my $op (@out) {
        next if is_debug_op($op);
        $op->{line} = $cl;
        $op->{col}  = $cc;
        if ($op->{type} eq 'keep'
            || $op->{type} eq 'insert'
            || $op->{type} eq 'overwrite_insert') {
            if ($op->{code} == 10) {
                $cl++;
                $cc = 1;
            } else {
                $cc++;
            }
        }
    }

    # Compute line_offset delta.
    my $ni = 0;
    my $nd = 0;
    for my $op (@out) {
        if ($op->{type} eq 'insert' && $op->{code} == 10) { $ni++; }
        if ($op->{type} eq 'delete' && $op->{code} == 10) { $nd++; }
    }

    return (\@out, $ni - $nd);
}

# --- Main: hunk-by-hunk driver -------------------------------------------

debug_log("Starting");
if ($DEBUG) {
    mkdir '/tmp/ad_debug' unless -d '/tmp/ad_debug';
}

my $in_hunk = 0;
my $hunk_count = 0;
my @hunk_ops;
my ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
    (0, 0, 0, 0, 0);
my $line_offset = 0;
my $total_in = 0;
my $total_out = 0;

sub flush_hunk {
    return unless @hunk_ops;
    my ($out_ops, $delta) = transform_hunk(\@hunk_ops, $line_offset);
    $line_offset += $delta;
    debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → "
        . scalar(@$out_ops) . " ops (delta=$delta, line_offset=$line_offset)");

    printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
        $hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del;
    for my $op (@$out_ops) {
        write_op($op);
        $total_out++;
    }
    print "HUNK_END\n";
    $total_in += scalar(@hunk_ops);
    @hunk_ops = ();
}

while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq '';

    # Headers (# ...) — rewrite the top header, pass through the rest.
    if ($line =~ /^#/) {
        if ($line =~ /raw diff|post-processed/) {
            print "# diffvim post-processed v2\n";
        } else {
            print "$line\n";
        }
        next;
    }

    # HUNK header.
    if ($line =~ /^HUNK\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)/) {
        flush_hunk() if $in_hunk;
        ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
            ($1, $2, $3, $4, $5);
        $in_hunk = 1;
        $hunk_count++;
        next;
    }

    # HUNK_END.
    if ($line =~ /^HUNK_END/) {
        flush_hunk() if $in_hunk;
        $in_hunk = 0;
        next;
    }

    # Op line — add to current hunk's ops.
    if ($in_hunk) {
        my $op = parse_op($line);
        push @hunk_ops, $op if $op;
    }
}

# Trailing hunk without HUNK_END.
flush_hunk() if $in_hunk && @hunk_ops;

print "\n";  # trailing blank line, matches C layer
debug_log("Total: $hunk_count hunks, $total_in → $total_out ops");
debug_log("Done");
exit 0;
