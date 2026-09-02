package DiffVim::Layer;

# Shared infrastructure for Perl postprocess layers.
# Provides parse_op, write_op, char_repr, is_debug_op, debug_log, and
# a run_layer driver that handles the hunk-by-hunk stdin→stdout loop.
#
# Usage:
#   use DiffVim::Layer qw(parse_op write_op char_repr is_debug_op debug_log run_layer);
#
#   run_layer(sub {
#       my ($ops, $line_offset) = @_;
#       # ... transform @$ops ...
#       return (\@out, $line_offset_delta);
#   });

use strict;
use warnings;
use utf8;
use Exporter qw(import);

our @EXPORT_OK = qw(parse_op write_op char_repr is_debug_op debug_log run_layer);

# ── Parse a TSV line into an Op hashref ────────────────────────────────
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

# ── Pretty representation of a char code ───────────────────────────────
sub char_repr {
    my ($code) = @_;
    return "\\n"     if $code == 10;
    return "\\t"     if $code == 9;
    return "\\r"     if $code == 13;
    return "space"   if $code == 32;
    return "'" . chr($code) . "'" if $code >= 33 && $code <= 126;
    return "$code";
}

# ── Write an Op as V2 TSV ──────────────────────────────────────────────
sub write_op {
    my ($op) = @_;
    printf "%s\t%d\t%d\t%d\t%s\n",
        $op->{type}, $op->{line}, $op->{col}, $op->{code},
        char_repr($op->{code});
}

# ── Check if an op is a debug op ───────────────────────────────────────
sub is_debug_op {
    my ($op) = @_;
    return defined $op && $op->{type} eq 'debug';
}

# ── Debug logging (enabled by --debug flag) ────────────────────────────
my $DEBUG = 0;
my $LAYER_NAME = 'layer';

sub debug_log {
    my ($msg) = @_;
    return unless $DEBUG;
    open(my $fh, '>>', '/tmp/ad_debug/postprocess.log') or return;
    print $fh "[$LAYER_NAME] $msg\n";
    close($fh);
}

sub _set_debug {
    my ($name, $debug) = @_;
    $LAYER_NAME = $name;
    $DEBUG = $debug;
    if ($DEBUG) {
        mkdir '/tmp/ad_debug' unless -d '/tmp/ad_debug';
    }
}

# ── Run a layer function on stdin→stdout ───────────────────────────────
# The $transform function receives (\@ops, $line_offset) and returns
# (\@out_ops, $line_offset_delta).
sub run_layer {
    my ($transform, %opts) = @_;

    my $debug = 0;
    for my $arg (@ARGV) {
        $debug = 1 if $arg eq '--debug';
    }
    my $layer_name = $opts{name} // 'layer';
    _set_debug($layer_name, $debug);

    debug_log("Starting");

    my $in_hunk = 0;
    my $hunk_count = 0;
    my @hunk_ops;
    my ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
        (0, 0, 0, 0, 0);
    my $line_offset = 0;
    my $total_in = 0;
    my $total_out = 0;

    my $flush_hunk = sub {
        return unless @hunk_ops;
        debug_log("Hunk $hunk_count: " . scalar(@hunk_ops) . " ops input");
        my ($out_ops, $delta) = $transform->(\@hunk_ops, $line_offset);
        $line_offset += $delta // 0;
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
    };

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
            $flush_hunk->() if $in_hunk;
            ($hunk_target, $hunk_del, $hunk_ins, $hunk_end_ins, $hunk_end_del) =
                ($1, $2, $3, $4, $5);
            $in_hunk = 1;
            $hunk_count++;
            next;
        }

        if ($line =~ /^HUNK_END/) {
            $flush_hunk->() if $in_hunk;
            $in_hunk = 0;
            next;
        }

        last if $line eq 'EOF';

        if ($in_hunk) {
            my $op = parse_op($line);
            push @hunk_ops, $op if $op;
        }
    }

    $flush_hunk->() if $in_hunk && @hunk_ops;

    print "\n";  # trailing blank line
    debug_log("Total: $hunk_count hunks, $total_in → $total_out ops");
    debug_log("Done");
    return 0;
}

1;
