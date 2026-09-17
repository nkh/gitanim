#!/usr/bin/env perl
# ad_layer_indent_last.pl — Perl implementation of the indent-last layer.
#
# For each line segment that starts with leading whitespace deletes
# (space OR tab), moves those whitespace deletes to AFTER the content
# deletes. The trailing \n char op (if any) is moved to the very end
# (after the indent deletes) so the join doesn't pull the next line up
# at the now-deleted indentation level. Content op cols are bumped by
# +n_indent (the indent is still in the buffer when content runs
# first). Indent deletes are placed at col 1.
#
# Output order per segment: content (col +n_indent) → indent (col 1)
# → \n op (original position). This is "Option C-correct" per
# docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md §4.3 (Phase 2 fix).
#
# This is the Perl twin of layers/c/ad_layer_indent_last.c. Both
# produce byte-identical output for the same input — see
# test_indent_last.pl and tests/test_layers_discovery.pl for the
# parity assertion.
#
# Protocol (the ad_vim layer plugin contract — see FLEXIBILITY.md):
#   * Reads V2 TSV from stdin: HUNK header, op lines, HUNK_END.
#   * Writes V2 TSV to stdout in the same format.
#   * Headers (# ...) and blank lines are passed through.
#   * Exit 0 on success.
#
# Usage:
#   perl ad_layer_indent_last.pl < post_ops > adjusted_ops
#   --debug perl ad_layer_indent_last.pl < in > out   # debug dump

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

# --- Configuration --------------------------------------------------------

my $LAYER_NAME = 'ad_layer_indent_last (Perl)';
my $DEBUG = 0;
for my $arg (@ARGV) { $DEBUG = 1 if $arg eq "--debug"; }

# --- Debug helpers -------------------------------------------------------

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

# --- TSV parse / write ---------------------------------------------------

# Parse a TSV line into an Op hashref. Returns undef on parse failure.
sub parse_op {
    my ($line) = @_;
    chomp $line;
    my @f = split /\t/, $line, -1;  # keep trailing empty fields

    # Standard 4-field format: type\tline\tcol\tcode (optionally \tchar_repr)
    if (@f >= 4
        && $f[0] ne 'insert_line' && $f[0] ne 'batch_insert'
        && $f[0] ne 'delete_line' && $f[0] ne 'keep_line'
        && $f[0] ne 'join_lines'  && $f[0] ne 'split_line') {
        return {
            type => $f[0],
            line => $f[1] + 0,
            col  => $f[2] + 0,
            code => $f[3] + 0,
        };
    }

    # insert_line format: insert_line\t<line>\t<text>
    if (@f >= 3 && $f[0] eq 'insert_line') {
        return {
            type => 'insert_line',
            line => $f[1] + 0,
            col  => 0,
            code => 0,
            text => $f[2],
        };
    }

    # batch_insert format: batch_insert\t<line>\t<col>\t<codes>
    if (@f >= 4 && $f[0] eq 'batch_insert') {
        return {
            type => 'batch_insert',
            line => $f[1] + 0,
            col  => $f[2] + 0,
            code => 0,
            text => $f[3],
        };
    }

    # split_line format: split_line\t<line>\t<col>
    if (@f >= 3 && $f[0] eq 'split_line') {
        return {
            type => 'split_line',
            line => $f[1] + 0,
            col  => $f[2] + 0,
            code => 0,
        };
    }

    # keep_line / join_lines / delete_line format: <type>\t<line>
    if (@f >= 2
        && ($f[0] eq 'keep_line' || $f[0] eq 'join_lines'
            || $f[0] eq 'delete_line')) {
        return {
            type => $f[0],
            line => $f[1] + 0,
            col  => 0,
            code => 0,
        };
    }

    # Catch-all: store the raw line for verbatim pass-through of unknown
    # op types (delay, snapshot, highlight, dim, fold, sign, marker, etc.).
    if (@f >= 1) {
        return {
            type => $f[0],
            line => $f[1] ? ($f[1] + 0) : 0,
            col  => $f[2] ? ($f[2] + 0) : 0,
            code => $f[3] ? ($f[3] + 0) : 0,
            text => $line,   # raw line for verbatim output
            raw  => 1,
        };
    }

    return undef;
}

# Pretty representation of a char code (cosmetic 5th field).
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
    if ($op->{type} eq 'keep_line') {
        printf "keep_line\t%d\n", $op->{line};
    } elsif ($op->{type} eq 'join_lines') {
        printf "join_lines\t%d\n", $op->{line};
    } elsif ($op->{type} eq 'split_line') {
        printf "split_line\t%d\t%d\n", $op->{line}, $op->{col};
    } elsif ($op->{type} eq 'insert_line') {
        printf "insert_line\t%d\t%s\n", $op->{line}, $op->{text} // '';
    } elsif ($op->{type} eq 'delete_line') {
        printf "delete_line\t%d\n", $op->{line};
    } elsif ($op->{type} eq 'batch_insert') {
        printf "batch_insert\t%d\t%d\t%s\n",
            $op->{line}, $op->{col}, $op->{text} // '';
    } elsif ($op->{raw}) {
        # Catch-all: pass through the raw line for unknown op types.
        printf "%s\n", $op->{text};
    } else {
        printf "%s\t%d\t%d\t%d\t%s\n",
            $op->{type}, $op->{line}, $op->{col}, $op->{code},
            char_repr($op->{code});
    }
}

sub is_debug_op {
    my ($op) = @_;
    return defined $op && $op->{type} eq 'debug';
}

# --- Layer transform -----------------------------------------------------
#
# Takes an arrayref of Op hashrefs for a single hunk and returns a new
# arrayref with indent deletes moved to the end of each line segment.
#
# Algorithm (mirror of ad_layer_indent_last.c):
#   1. Walk ops, breaking into "segments" — a segment ends at a \n op or
#      when the line number changes.
#   2. For each segment, find the leading run of indent deletes (space/tab)
#      at the start: that's [seg_start, indent_end).
#   3. If the run is empty, pass the segment through unchanged.
#   4. Otherwise:
#        a. Find the \n op at the end of the segment (search backward).
#        b. Emit content ops [indent_end, nl) with col += n_indent.
#        c. Emit the indent deletes [seg_start, indent_end) with col = 1.
#        d. Emit the \n op unchanged (if present).

sub transform_hunk {
    my ($ops) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $seg_start = 0;
    for (my $i = 0; $i <= $n; $i++) {
        # Decide whether position $i is a segment boundary (or end of array).
        my $is_boundary = ($i == $n) ? 1 : 0;
        if (!$is_boundary && $i > $seg_start) {
            # \n op (non-debug) is always a boundary.
            if ($in[$i]{code} == 10 && !is_debug_op($in[$i])) {
                $is_boundary = 1;
            }
            # Line number change is a boundary (skip debug ops in the test).
            if (!$is_boundary && !is_debug_op($in[$i]) && !is_debug_op($in[$i - 1])) {
                if ($in[$i]{line} != $in[$i - 1]{line}) {
                    $is_boundary = 1;
                }
            }
        }

        next unless $is_boundary;

        my $seg_len = $i - $seg_start;
        if ($seg_len > 0) {
            # Find leading run of indent deletes (space or tab).
            my $indent_end = $seg_start;
            for (my $j = $seg_start; $j < $i; $j++) {
                next if is_debug_op($in[$j]);
                if ($in[$j]{type} eq 'delete'
                    && ($in[$j]{code} == 32 || $in[$j]{code} == 9)) {
                    $indent_end = $j + 1;
                } else {
                    last;
                }
            }
            my $n_indent = $indent_end - $seg_start;

            if ($n_indent == 0) {
                # No indent deletes — pass segment through unchanged.
                for (my $j = $seg_start; $j < $i; $j++) {
                    push @out, $in[$j];
                }
            } else {
                # Find \n op at the tail of the segment (search backward).
                my $nl = -1;
                for (my $j = $i - 1; $j >= $indent_end; $j--) {
                    if (!is_debug_op($in[$j]) && $in[$j]{code} == 10) {
                        $nl = $j;
                        last;
                    }
                }
                my $content_end = ($nl >= 0) ? $nl : $i;

                # Content ops: bump col by +n_indent (indent still in buffer).
                for (my $j = $indent_end; $j < $content_end; $j++) {
                    my %op = %{$in[$j]};
                    $op{col} = $in[$j]{col} + $n_indent;
                    push @out, \%op;
                }
                # Indent deletes: keep at col 1.
                for (my $j = $seg_start; $j < $indent_end; $j++) {
                    my %op = %{$in[$j]};
                    $op{col} = 1;
                    push @out, \%op;
                }
                # \n op: keep as-is.
                if ($nl >= 0) {
                    push @out, $in[$nl];
                }
            }
        }
        $seg_start = $i;
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
    debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " ops input");
    debug_dump("perl_indent_last_input.txt",
        map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @hunk_ops);

    my $out_ops = transform_hunk(\@hunk_ops);

    debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → "
        . scalar(@$out_ops) . " ops");
    debug_dump("perl_indent_last_output.txt",
        map { "$_->{type}\t$_->{line}\t$_->{col}\t$_->{code}" } @$out_ops);

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

    last if $line eq 'EOF';

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
