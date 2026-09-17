#!/usr/bin/env perl
# ad_layer_line_delete_in_place.pl — Delete content BEFORE joining lines.
#
# Perl twin of ad_layer_line_delete_in_place.c.
# Two modes: --mode batch (default) or --mode interleaved.
#
# Sliding-window algorithm (Phase 2 fix, handles arbitrary N lines):
#   Walk the ops. When a join_lines(L) is followed by content deletes
#   (first delete at col 1), start a block. Within the block, match
#   join + delete+ repeatedly. Each match:
#     - Emits content deletes at L + 1 + offset.
#     - Defers the join to a pending list.
#     - Advances offset by 1.
#   When the block ends, emit all pending joins.
#
# See C source for full documentation.

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $ldi_mode = 0;  # 0=batch, 1=interleaved

# Parse args
for (my $ai = 0; $ai < @ARGV; $ai++) {
    if ($ARGV[$ai] eq '--mode' && $ai + 1 < @ARGV) {
        $ai++;
        $ldi_mode = 1 if $ARGV[$ai] eq 'interleaved';
    } elsif ($ARGV[$ai] =~ /^--mode=(.*)/) {
        $ldi_mode = 1 if $1 eq 'interleaved';
    } elsif ($ARGV[$ai] eq '--help' || $ARGV[$ai] eq '-h') {
        print STDERR "ad_layer_line_delete_in_place — delete content before joining lines\n\n";
        print STDERR "Usage: ad_layer_line_delete_in_place [--mode batch|interleaved] < ops.tsv\n\n";
        print STDERR "Options:\n";
        print STDERR "  --mode batch        Delete all content first, then join all (default)\n";
        print STDERR "  --mode interleaved  Delete each line then immediately join\n";
        print STDERR "  --help, -h          Show this help\n";
        exit 0;
    }
}

# --- TSV parse / write ---------------------------------------------------

sub parse_op {
    my ($line) = @_;
    chomp $line;
    my @f = split /\t/, $line, -1;

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
            text => $line,
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
        printf "%s\n", $op->{text};
    } else {
        printf "%s\t%d\t%d\t%d\t%s\n",
            $op->{type}, $op->{line}, $op->{col}, $op->{code},
            char_repr($op->{code});
    }
}

sub is_line_op {
    my ($op) = @_;
    return defined $op && (
        $op->{type} eq 'keep_line' || $op->{type} eq 'join_lines' ||
        $op->{type} eq 'split_line' || $op->{type} eq 'delete_line' ||
        $op->{type} eq 'batch_insert'
    );
}

# --- Layer transform (batch mode) ---------------------------------------

sub transform_hunk {
    my ($ops) = @_;
    my @in = @$ops;
    my $n = scalar @in;
    my @out;

    my $i = 0;
    while ($i < $n) {
        # Check: is in[i] a join_lines followed by content deletes at col 1?
        if ($in[$i]{type} eq 'join_lines'
            && $i + 1 < $n
            && $in[$i+1]{type} eq 'delete'
            && !is_line_op($in[$i+1])
            && $in[$i+1]{col} == 1) {

            # ── Sliding-window block ──
            my $line_off = 0;
            my @pending_joins;
            my $j = $i;

            while ($j < $n && $in[$j]{type} eq 'join_lines') {
                my $join_line = $in[$j]{line};

                # Scan content deletes. First must be at col 1.
                my $ce = $j + 1;
                if ($ce < $n
                    && $in[$ce]{type} eq 'delete'
                    && !is_line_op($in[$ce])
                    && $in[$ce]{col} == 1) {
                    $ce++;
                    while ($ce < $n
                           && $in[$ce]{type} eq 'delete'
                           && !is_line_op($in[$ce])) {
                        $ce++;
                    }
                }

                if ($ce > $j + 1) {
                    # Content found (first at col 1). Emit at L+1+line_off.
                    for my $k ($j + 1 .. $ce - 1) {
                        my %op = %{$in[$k]};
                        $op{line} = $join_line + 1 + $line_off;
                        push @out, \%op;
                    }
                    push @pending_joins, $in[$j];
                    $line_off++;
                    $j = $ce;
                } else {
                    # No content — trailing join. End block.
                    push @pending_joins, $in[$j];
                    $j++;
                    last;
                }
            }

            # Emit all pending joins.
            push @out, @pending_joins;
            $i = $j;
            next;
        }

        # No match — emit unchanged.
        push @out, $in[$i];
        $i++;
    }

    return \@out;
}

# --- Main: hunk-by-hunk driver -------------------------------------------

my $in_hunk = 0;
my $hunk_count = 0;
my @hunk_ops;
my ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
    (0, 0, 0, 0, 0);

sub flush_hunk {
    return unless @hunk_ops;

    my $out_ops;
    if ($ldi_mode == 1) {
        # Interleaved mode: pass through.
        $out_ops = \@hunk_ops;
    } else {
        $out_ops = transform_hunk(\@hunk_ops);
    }

    printf "HUNK\t%d\t%d\t%d\t%d\t%d\n",
        $hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del;
    for my $op (@$out_ops) {
        write_op($op);
    }
    print "HUNK_END\n";
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
exit 0;
