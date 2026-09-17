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

    # Catch-all: store the raw line for verbatim pass-through.
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

sub is_line_op {
    my ($op) = @_;
    return defined $op && (
        $op->{type} eq 'keep_line' || $op->{type} eq 'join_lines' ||
        $op->{type} eq 'split_line' || $op->{type} eq 'delete_line' ||
        $op->{type} eq 'batch_insert'
    );
}

# --- Layer transform -----------------------------------------------------

sub transform_hunk {
    my ($ops, $line_offset) = @_;
    my @in = @$ops;
    my $n = scalar @in;

    # NOTE: The C version does NOT apply line_offset to ops. It just
    # updates line_offset at the end (split_line - join_lines count).
    # The Perl twin must match — do NOT adjust op lines here.

    # Per-segment 4-sweep: segments are bounded by keeps, \n ops, and
    # line ops (keep_line, join_lines, split_line, delete_line,
    # batch_insert). Within each segment, emit non-\n deletes, then
    # non-\n inserts, then debug ops. Boundaries are emitted in place.
    # NEVER touches a 'delete \n' op — doesn't reorder it, doesn't
    # recompute its position.
    my @out;
    my $buf_start = 0;
    for (my $i = 0; $i <= $n; $i++) {
        my $is_flush = ($i == $n) ? 1 : 0;
        if (!$is_flush && !is_debug_op($in[$i])) {
            if ($in[$i]{type} eq 'keep' || $in[$i]{code} == 10
                || is_line_op($in[$i])) {
                $is_flush = 1;
            }
        }
        next unless $is_flush;

        # Sweep 1: non-newline, non-line-op deletes.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if ($in[$j]{type} eq 'delete' && $in[$j]{code} != 10
                && !is_line_op($in[$j])) {
                push @out, $in[$j];
            }
        }
        # Sweep 2: non-newline, non-line-op inserts/overwrite_inserts.
        for (my $j = $buf_start; $j < $i; $j++) {
            next if is_debug_op($in[$j]);
            if (($in[$j]{type} eq 'insert' || $in[$j]{type} eq 'overwrite_insert')
                && $in[$j]{code} != 10 && !is_line_op($in[$j])) {
                push @out, $in[$j];
            }
        }
        # Sweep 3: debug ops (in original order).
        for (my $j = $buf_start; $j < $i; $j++) {
            push @out, $in[$j] if is_debug_op($in[$j]);
        }
        # Emit the boundary op itself (keep, \n, or line op) in place.
        if ($i < $n) {
            push @out, $in[$i];
        }
        $buf_start = $i + 1;
    }

    # Position-walk REMOVED — the C version does NOT recompute positions
    # (it preserves the diff engine's original positions). The Perl
    # twin must match. Only the 4-sweep reorder is performed; positions
    # are left as-is from the input.

    # Compute line_offset delta: net split_line - join_lines from output.
    # (Matches the C version's line_offset update.)
    my $ni = 0;
    my $nd = 0;
    for my $op (@out) {
        if ($op->{type} eq 'split_line') { $ni++; }
        if ($op->{type} eq 'join_lines')  { $nd++; }
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
