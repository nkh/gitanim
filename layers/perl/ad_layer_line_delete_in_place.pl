#!/usr/bin/env perl
# ad_layer_line_delete_in_place.pl — Perl twin of the C layer.
#
# Algorithm (per user spec):
#   walk ops:
#     if op[i] is delete(\n) on line N
#        and op[i+1..k] is delete(content) on line N+1
#        and op[k+1] is delete(\n) on line N+1:
#          emit op[i+1..k]      (content, keep line=N+1)
#          emit op[k+1]         (content's \n, keep line=N+1)
#          decrement line of all LATER ops by 1
#          op[i] is still delete \n, re-iterate
#     else:
#          emit op[i] unchanged

use strict;
use warnings;
use utf8;

binmode(STDIN,  ':utf8');
binmode(STDOUT, ':utf8');
binmode(STDERR, ':utf8');

my $DEBUG = 0;
for my $arg (@ARGV) { $DEBUG = 1 if $arg eq "--debug"; }

sub debug_log {
    my ($msg) = @_;
    return unless $DEBUG;
    open(my $fh, '>>', '/tmp/ad_debug/postprocess.log') or return;
    print $fh "[line_delete_in_place (Perl)] $msg\n";
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
    my @work = @$ops;           # mutable copy
    my @out;

    my $i = 0;
    while ($i < scalar @work) {
        # ── Pattern 1: DELETE (joiner \n, content, content's \n) ──
        if ($i + 2 < scalar @work
            && $work[$i]{type} eq 'delete'
            && $work[$i]{code} == 10) {

            if ($work[$i+1]{type} eq 'delete'
                && $work[$i+1]{code} != 10) {

                my $ce = $i + 1;
                while ($ce < scalar @work
                       && $work[$ce]{type} eq 'delete'
                       && $work[$ce]{code} != 10) {
                    $ce++;
                }

                if ($ce < scalar @work
                    && $work[$ce]{type} eq 'delete'
                    && $work[$ce]{code} == 10) {

                    my $content_count = $ce - ($i + 1);

                    # Emit content deletes. Their positions were recomputed
                    # by reorder to be on the JOINED line. But we're moving
                    # them BEFORE the joiner \n, so at execution time the
                    # join hasn't happened — content is on the NEXT line.
                    for my $k ($i+1 .. $ce-1) {
                        my %tmp = %{$work[$k]};
                        $tmp{line} = $work[$i]{line} + 1;
                        push @out, \%tmp;
                    }
                    # Emit content's \n (also on next line)
                    {
                        my %tmp = %{$work[$ce]};
                        $tmp{line} = $work[$i]{line} + 1;
                        push @out, \%tmp;
                    }

                    for my $k ($ce+1 .. $#work) {
                        $work[$k]{line}--;
                    }

                    splice @work, $i+1, $content_count + 1;
                    next;
                }
            }
        }

        # No match — emit op[i] unchanged.
        push @out, $work[$i];
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

sub flush_hunk {
    return unless @hunk_ops;
    my $out_ops = transform_hunk(\@hunk_ops);
    debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " → "
        . scalar(@$out_ops) . " ops");

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

    if ($in_hunk) {
        my $op = parse_op($line);
        push @hunk_ops, $op if $op;
    }
}

flush_hunk() if $in_hunk && @hunk_ops;

print "\n";
debug_log("Total: $hunk_count hunks");
debug_log("Done");
exit 0;
