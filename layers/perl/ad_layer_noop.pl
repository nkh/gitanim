#!/usr/bin/env perl
# ad_layer_noop.pl — No-op postprocess layer (Perl version).
#
# A Perl passthrough layer that reads V2 TSV from stdin, passes it
# through unchanged, and writes to stdout. Includes debug logging.
#
# This is the Perl equivalent of the C no-op layers. It can be used
# in a pipeline:
#   compute | perl ad_layer_noop.pl | pace
#
# Or as a template for implementing real layers in Perl.
#
# Usage:
#   perl ad_layer_noop.pl < input.tsv > output.tsv
#   --debug perl ad_layer_noop.pl < input.tsv > output.tsv
#
# Debug:
#   When --debug is given, writes a log to
#   /tmp/ad_debug/postprocess.log and op dumps to
#   /tmp/ad_debug/perl_layer_input.txt and perl_layer_output.txt

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# ── Configuration ────────────────────────────────────────────────────

my $LAYER_NAME = 'Perl Layer (no-op)';
my $DEBUG = 0;
for my $arg (@ARGV) { $DEBUG = 1 if $arg eq "--debug"; }

# ── Debug helpers ────────────────────────────────────────────────────

sub debug_log {
    my ($msg) = @_;
    return unless $DEBUG;
    open(my $fh, '>>', '/tmp/ad_debug/postprocess.log') or return;
    print $fh "[$LAYER_NAME] $msg\n";
    close($fh);
}

sub debug_dump {
    my ($filename, @lines) = @_;
    return unless $DEBUG;
    open(my $fh, '>', "/tmp/ad_debug/$filename") or return;
    print $fh join("\n", @lines), "\n";
    close($fh);
}

# ── Parse a TSV line into an Op ──────────────────────────────────────

sub parse_op {
    my ($line) = @_;
    chomp $line;
    my @fields = split /\t/, $line;
    return undef unless @fields >= 4;
    return {
        type => $fields[0],
        line => $fields[1] + 0,
        col  => $fields[2] + 0,
        code => $fields[3] + 0,
    };
}

# ── Write an Op as TSV ───────────────────────────────────────────────

sub write_op {
    my ($op) = @_;
    printf "%s\t%d\t%d\t%d\n", $op->{type}, $op->{line}, $op->{col}, $op->{code};
}

# ── Layer function (no-op) ──────────────────────────────────────────

# Takes an arrayref of Op hashes, returns an arrayref of Op hashes.
# This is where the actual transformation happens.
# Currently: passthrough (return input unchanged).
sub layer_transform {
    my ($ops) = @_;
    debug_log("Layer function: passthrough (" . scalar(@$ops) . " ops)");
    return $ops;  # no-op: return input unchanged
}

# ── Main ────────────────────────────────────────────────────────────

debug_log("Starting");

# Ensure debug directory exists
if ($DEBUG) {
    mkdir '/tmp/ad_debug' unless -d '/tmp/ad_debug';
}

my @input_lines;
my $in_hunk = 0;
my $hunk_count = 0;
my $hunk_target = 0;
my $hunk_del = 0;
my $hunk_ins = 0;
my $hunk_end_ins = 0;
my $hunk_end_del = 0;
my @hunk_ops;
my $total_ops = 0;

while (my $line = <STDIN>) {
    chomp $line;

    # Skip empty lines
    if ($line eq '') {
        next;
    }

    # Headers (# ...) — pass through
    if ($line =~ /^#/) {
        if ($line =~ /raw diff|post-processed/) {
            print "# diffvim post-processed v2\n";
        } else {
            print "$line\n";
        }
        next;
    }

    # HUNK header
    if ($line =~ /^HUNK\t(\d+)\t(\d+)\t(\d+)\t(\d+)\t(\d+)/) {
        # If we were in a hunk, process it
        if ($in_hunk && @hunk_ops) {
            debug_log("Processing hunk $hunk_count: " . scalar(@hunk_ops) . " ops input");
            debug_dump("perl_layer_input.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @hunk_ops);

            my $out_ops = layer_transform(\@hunk_ops);

            debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → " . scalar(@$out_ops) . " ops");
            debug_dump("perl_layer_output.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @$out_ops);

            printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
                $hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del;
            for my $op (@$out_ops) {
                write_op($op);
                $total_ops++;
            }
            print "HUNK_END\n";

            @hunk_ops = ();
        }

        $hunk_target = $1;
        $hunk_del = $2;
        $hunk_ins = $3;
        $hunk_end_ins = $4;
        $hunk_end_del = $5;
        $in_hunk = 1;
        $hunk_count++;
        next;
    }

    # HUNK_END
    if ($line =~ /^HUNK_END/) {
        if ($in_hunk && @hunk_ops) {
            debug_log("Processing hunk $hunk_count: " . scalar(@hunk_ops) . " ops input");
            debug_dump("perl_layer_input.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @hunk_ops);

            my $out_ops = layer_transform(\@hunk_ops);

            debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → " . scalar(@$out_ops) . " ops");
            debug_dump("perl_layer_output.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @$out_ops);

            printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
                $hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del;
            for my $op (@$out_ops) {
                write_op($op);
                $total_ops++;
            }
            print "HUNK_END\n";

            @hunk_ops = ();
        }
        $in_hunk = 0;
        next;
    }

    # Op line — parse and add to current hunk's ops
    if ($in_hunk) {
        my $op = parse_op($line);
        push @hunk_ops, $op if $op;
    }
}

# Handle last hunk if no HUNK_END was seen
if ($in_hunk && @hunk_ops) {
    debug_log("Processing last hunk: " . scalar(@hunk_ops) . " ops");
    debug_dump("perl_layer_input.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @hunk_ops);

    my $out_ops = layer_transform(\@hunk_ops);

    debug_log("Last hunk: " . scalar(@hunk_ops) . " → " . scalar(@$out_ops) . " ops");
    debug_dump("perl_layer_output.txt", map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @$out_ops);

    printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
        $hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del;
    for my $op (@$out_ops) {
        write_op($op);
        $total_ops++;
    }
    print "HUNK_END\n";
}

# Trailing blank line
print "\n";

debug_log("Total: $hunk_count hunks, $total_ops ops processed");
debug_log("Done");
