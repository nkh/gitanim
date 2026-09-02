#!/usr/bin/env perl
# ad_layer_overwrite.pl — Perl implementation of the overwrite layer.
#
# Merges adjacent delete+insert pairs (same line, same col) into
# overwrite_insert ops. This is the Perl twin of
# layers/c/ad_layer_overwrite.c. Both produce byte-identical output
# for the same input (parity verified by tests).
#
# Algorithm (mirror of the C version):
#   1. Walk ops in each hunk.
#   2. If op[i] is a non-newline delete AND op[i+1] is a non-newline
#      insert AND they have the same (line, col), AND the previous op
#      was NOT a delete at the same position (pd), AND the op after
#      next is NOT an insert at the same line (ni), then merge them
#      into a single overwrite_insert op.
#   3. Otherwise, pass the op through unchanged.
#   4. After merging, walk the output and set (line, col) on every op.
#
# Protocol: see docs/src/plugin-layers.md.

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $LAYER_NAME = 'ad_layer_overwrite (Perl)';
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
    my ($ops) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $i = 0;
    while ($i < $n) {
        # Check if we can merge op[i] (delete) + op[i+1] (insert).
        my $can_merge = 0;
        if ($i + 1 < $n
            && $in[$i]{type} eq 'delete' && $in[$i]{code} != 10
            && $in[$i+1]{type} eq 'insert' && $in[$i+1]{code} != 10
            && $in[$i]{line} == $in[$i+1]{line}
            && $in[$i]{col}  == $in[$i+1]{col}) {
            # Check pd (previous op was a delete at the same position).
            my $pd = 0;
            if ($i > 0
                && $in[$i-1]{type} eq 'delete' && $in[$i-1]{code} != 10
                && $in[$i-1]{line} == $in[$i]{line}
                && $in[$i-1]{col}  == $in[$i]{col}) {
                $pd = 1;
            }
            # Check ni (op after next is an insert at the same line).
            my $ni = 0;
            if ($i + 2 < $n
                && $in[$i+2]{type} eq 'insert' && $in[$i+2]{code} != 10
                && $in[$i+2]{line} == $in[$i+1]{line}) {
                $ni = 1;
            }
            $can_merge = 1 if !$pd && !$ni;
        }

        if ($can_merge) {
            # Merge: emit overwrite_insert with the insert's code/position.
            push @out, {
                type => 'overwrite_insert',
                code => $in[$i+1]{code},
                line => $in[$i+1]{line},
                col  => $in[$i+1]{col},
            };
            $i += 2;
        } else {
            push @out, $in[$i];
            $i++;
        }
    }

    # Set positions on the output.
    # For non-\n ops: assign (current_line, current_col).
    # For \n ops: KEEP original position (never touch a 'delete \n' op).
    my $cl = @out > 0 ? $out[0]{line} : 1;
    my $cc = 1;
    for my $op (@out) {
        next if is_debug_op($op);
        if ($op->{code} != 10) {
            $op->{line} = $cl;
            $op->{col}  = $cc;
            if ($op->{type} eq 'keep'
                || $op->{type} eq 'insert'
                || $op->{type} eq 'overwrite_insert') {
                $cc++;
            }
        } else {
            # \n op: KEEP original position. Don't touch.
            $cl = $op->{line} + 1;
            $cc = 1;
        }
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

    last if $line eq 'EOF';

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
