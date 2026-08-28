#!/usr/bin/env perl
# ad_layer_line_delete_in_place.pl — Perl implementation of the
# line_delete_in_place layer.
#
# When a \n delete would join two lines, and the next line is fully
# deleted, reorder so content is deleted FIRST (on its own line),
# then the \n delete joins. Prevents "join then delete" visual.
#
# This is the Perl twin of layers/c/ad_layer_line_delete_in_place.c.
# Both produce byte-identical output for the same input (parity
# verified by tests).
#
# Algorithm (mirror of the C version):
#   1. Walk ops in each hunk.
#   2. Detect pattern: \n delete on line N, followed by content deletes
#      on line N+1, followed by \n delete on line N+1.
#   3. When matched: emit content deletes, then \n delete on N+1, then
#      \n delete on N (the join).
#   4. Otherwise, pass the op through.
#   5. Positions are passed through unchanged from ad_layer_reorder.
#
# Protocol: see docs/src/plugin-layers.md.

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $LAYER_NAME = 'ad_layer_line_delete_in_place (Perl)';
my $DEBUG = ($ENV{AD_DEBUG_LAYERS} // '0') eq '1';

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

# --- Layer transform -----------------------------------------------------

sub transform_hunk {
    my ($ops) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $i = 0;
    while ($i < $n) {
        # Check for pattern:
        #   op[i]   = \n delete on line N
        #   op[i+1] = content delete on line N+1
        #   op[...] = more content deletes on line N+1
        #   op[ce]  = \n delete on line N+1
        my $matched = 0;
        if ($i + 2 < $n
            && $in[$i]{type} eq 'delete' && $in[$i]{code} == 10
            && $in[$i+1]{type} eq 'delete' && $in[$i+1]{code} != 10
            && $in[$i+1]{line} == $in[$i]{line} + 1) {
            my $dl = $in[$i]{line} + 1;
            my $cs = $i + 1;
            my $ce = $cs;
            while ($ce < $n
                   && $in[$ce]{type} eq 'delete'
                   && $in[$ce]{code} != 10
                   && $in[$ce]{line} == $dl) {
                $ce++;
            }
            if ($ce < $n
                && $in[$ce]{type} eq 'delete'
                && $in[$ce]{code} == 10
                && $in[$ce]{line} == $dl) {
                # Pattern matched: emit content+nl first, then the join.
                for (my $k = $cs; $k < $ce; $k++) {
                    push @out, $in[$k];
                }
                push @out, $in[$ce];   # \n delete on N+1
                push @out, $in[$i];     # \n delete on N (the join)
                $i = $ce + 1;
                $matched = 1;
            }
        }
        next if $matched;
        push @out, $in[$i];
        $i++;
    }

    return \@out;
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
my $total_in = 0;
my $total_out = 0;

sub flush_hunk {
    return unless @hunk_ops;
    my $out_ops = transform_hunk(\@hunk_ops);
    debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → "
        . scalar(@$out_ops) . " ops");

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

    if ($line =~ /^#/) {
        if ($line =~ /raw diff|post-processed/) {
            print "# diffvim post-processed v2\n";
        } else {
            print "$line\n";
        }
        next;
    }

    if ($line =~ /^HUNK\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)/) {
        flush_hunk() if $in_hunk;
        ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
            ($1, $2, $3, $4, $5);
        $in_hunk = 1;
        $hunk_count++;
        next;
    }

    if ($line =~ /^HUNK_END/) {
        flush_hunk() if $in_hunk;
        $in_hunk = 0;
        next;
    }

    if ($in_hunk) {
        my $op = parse_op($line);
        push @hunk_ops, $op if $op;
    }
}

flush_hunk() if $in_hunk && @hunk_ops;

print "\n";
debug_log("Total: $hunk_count hunks, $total_in → $total_out ops");
debug_log("Done");
exit 0;
