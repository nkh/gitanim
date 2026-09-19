#!/usr/bin/env perl
# ad_layer_overwrite.pl — Perl implementation of the overwrite layer.
#
# Merges maximal runs of delete+insert ops (same line, same col) into
# overwrite_insert ops. This is the Perl twin of
# layers/c/ad_layer_overwrite.c. Both produce byte-identical output
# for the same input (parity verified by tests).
#
# Algorithm (mirror of the C version — "Option C" from
# docs/design/LAYER_ANALYSIS_AND_FIX_PLAN.md §4.2):
#   1. Walk ops in each hunk.
#   2. When a non-line-op delete is found, scan the maximal run of N
#      non-line-op deletes at (L, C). Then scan the maximal run of M
#      non-line-op inserts starting at (L, C) and advancing by 1 col
#      each.
#   3. Emit min(N, M) overwrite_insert ops (using the first min(N, M)
#      insert codes), then |N - M| leftover deletes (from the tail of
#      the delete run) or leftover inserts (from the tail of the insert
#      run).
#   4. After merging, walk the output and set (line, col) on every op
#      (non-\n ops only — \n ops keep their original position).
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

sub char_repr {
    my ($code) = @_;
    return "\\n"     if $code == 10;
    return "\\t"      if $code == 9;
    return "\\r"       if $code == 13;
    return "space"     if $code == 32;
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

sub is_line_op {
    my ($op) = @_;
    return defined $op && (
        $op->{type} eq 'keep_line'
        || $op->{type} eq 'join_lines'
        || $op->{type} eq 'split_line'
        || $op->{type} eq 'delete_line'
        || $op->{type} eq 'batch_insert'
    );
}

# --- Layer transform -----------------------------------------------------

sub transform_hunk {
    my ($ops) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $i = 0;
    while ($i < $n) {
        # Detect start of a potential merge run: a non-line-op delete.
        if ($in[$i]{type} eq 'delete' && !is_line_op($in[$i])) {
            my $L = $in[$i]{line};
            my $C = $in[$i]{col};

            # Scan maximal run of non-line-op deletes at (L, C).
            my $del_start = $i;
            my $del_end = $i;
            while ($del_end < $n
                   && $in[$del_end]{type} eq 'delete'
                   && !is_line_op($in[$del_end])
                   && $in[$del_end]{line} == $L
                   && $in[$del_end]{col}  == $C) {
                $del_end++;
            }
            my $N = $del_end - $del_start;

            # Scan maximal run of non-line-op inserts starting at (L, C)
            # and advancing by 1 col each.
            my $ins_start = $del_end;
            my $ins_end = $ins_start;
            my $expected_col = $C;
            while ($ins_end < $n
                   && $in[$ins_end]{type} eq 'insert'
                   && !is_line_op($in[$ins_end])
                   && $in[$ins_end]{line} == $L
                   && $in[$ins_end]{col}  == $expected_col) {
                $expected_col++;
                $ins_end++;
            }
            my $M = $ins_end - $ins_start;

            if ($M > 0) {
                # Run-level merge.
                my $k = $N < $M ? $N : $M;
                for my $j (0 .. $k - 1) {
                    push @out, {
                        type => 'overwrite_insert',
                        code => $in[$ins_start + $j]{code},
                        line => $in[$ins_start + $j]{line},
                        col  => $in[$ins_start + $j]{col},
                    };
                }
                # Leftover deletes (N > M).
                for my $j ($k .. $N - 1) {
                    push @out, $in[$del_start + $j];
                }
                # Leftover inserts (M > N).
                for my $j ($k .. $M - 1) {
                    push @out, $in[$ins_start + $j];
                }
                $i = $ins_end;
                next;
            }

            # M == 0: pass all N deletes through unchanged.
            for my $j ($del_start .. $del_end - 1) {
                push @out, $in[$j];
            }
            $i = $del_end;
            next;
        }

        # Default: pass the op through unchanged.
        push @out, $in[$i];
        $i++;
    }

    # Set positions on the output.
    # For non-\n ops: assign (current_line, current_col).
    # For \n ops: KEEP original position (never touch a 'delete \n' op).
    # For line ops: KEEP original position but UPDATE current_line/
    # current_col so subsequent non-line ops get the right position:
    #   keep_line L, split_line L C, insert_line L → line L+1, col 1
    #   join_lines L → stays on line L (content joined, col unchanged)
    #   delete_line L → stays (line removed, lines shift up)
    #   batch_insert L C → col advances (rare, approximated)
    my $cl = @out > 0 ? $out[0]{line} : 1;
    my $cc = 1;
    for my $op (@out) {
        next if is_debug_op($op);
        if (is_line_op($op)) {
            # Line op: keep original position but update cursor for
            # subsequent non-line ops.
            if ($op->{type} eq 'keep_line'
                || $op->{type} eq 'split_line'
                || $op->{type} eq 'insert_line') {
                $cl = $op->{line} + 1;
                $cc = 1;
            } elsif ($op->{type} eq 'join_lines') {
                # Join: cursor stays on the joined line.
                $cl = $op->{line};
                # col stays — content is appended at current col.
            } elsif ($op->{type} eq 'delete_line') {
                # Delete: cursor stays (lines shift up).
                # $cl stays.
            }
            # batch_insert: col advances — approximated, not exact.
            next;
        }
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
