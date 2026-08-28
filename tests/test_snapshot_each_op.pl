#!/usr/bin/env perl
# test_snapshot_each_op.pl — Snapshot the buffer after each op.
#
# Two test modes:
#   1. Final-output check: after running the full pipeline, verify the
#      buffer matches the new file (existing behaviour).
#   2. Per-op check: inject a snapshot op after every op in the timed
#      stream, run the animator, then walk the snapshots and verify
#      that the buffer state evolves monotonically — i.e., each
#      snapshot equals the previous snapshot with one op applied.
#      This catches op-application bugs that produce a correct final
#      buffer but a wrong intermediate state (which is what visual
#      flashing looks like).
#
# Per-op verification is done in a separate Perl "reference animator"
# that mirrors the C/Perl animator's delete_char/insert_char/keep_char
# logic. We then compare each snapshot file to the reference state.
#
# The reference animator operates on Unicode codepoints (matches both
# the C animator and the Perl animator with `:encoding(UTF-8)`).
#
# Usage: perl test_snapshot_each_op.pl

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $pass = 0; my $fail = 0;
my $tmpdir = tempdir(CLEANUP => 1);

my @cases = (
    ['simple_join',    "foo\nbar\n",            "foobar\n"],
    ['multi_delete',   "line1\nline2\nline3\n", "line1\nline3\n"],
    ['insert',         "hello\n",               "hello world\n"],
    ['replace',        "abc\n",                 "xyz\n"],
    ['empty_new',      "hello\n",               ""],
    ['empty_old',      "",                      "hello\n"],
    ['unicode',        decode('UTF-8', "caf\xc3\xa9\n"), "coffee\n"],
);

# ── Reference animator ───────────────────────────────────────────
# Mirrors the C/Perl animator's delete_char/insert_char/keep_char.
# Operates on Unicode codepoint strings (not byte strings).
sub ref_apply_op {
    my ($lines, $cursor_l, $cursor_c, $type, $code) = @_;
    if ($type eq 'keep') {
        if ($code == 10) {
            $cursor_l++;
            $cursor_l = $#$lines if $cursor_l > $#$lines;
            $cursor_c = 0;
        } else {
            $cursor_c++;
        }
    } elsif ($type eq 'insert') {
        if ($code == 10) {
            my $line = $lines->[$cursor_l];
            my @chars = split //, $line;
            my @before = $cursor_c > 0 ? @chars[0 .. $cursor_c - 1] : ();
            my @after  = $cursor_c <= $#chars ? @chars[$cursor_c .. $#chars] : ();
            $lines->[$cursor_l] = join("", @before);
            splice(@$lines, $cursor_l + 1, 0, join("", @after));
            $cursor_l++;
            $cursor_c = 0;
        } else {
            my $ch = chr($code);
            my $line = $lines->[$cursor_l];
            my @chars = split //, $line;
            splice(@chars, $cursor_c, 0, $ch);
            $lines->[$cursor_l] = join("", @chars);
            $cursor_c++;
        }
    } elsif ($type eq 'delete') {
        if ($code == 10) {
            # Standard "join with next" for \n deletes
            # (the postprocess handles that, not the animator).
            if ($cursor_l < $#$lines) {
                $lines->[$cursor_l] = $lines->[$cursor_l] . $lines->[$cursor_l + 1];
                splice(@$lines, $cursor_l + 1, 1);
            } elsif ($cursor_l > 0) {
                pop @$lines;
                $cursor_l--;
                $cursor_c = length($lines->[$cursor_l]);
            } else {
                @$lines = ("");
                $cursor_c = 0;
            }
        } else {
            my $line = $lines->[$cursor_l];
            my @chars = split //, $line;
            if ($cursor_c < @chars) {
                splice(@chars, $cursor_c, 1);
                $lines->[$cursor_l] = join("", @chars);
            }
        }
    }
    return ($cursor_l, $cursor_c);
}

sub set_cursor_ref {
    my ($lines, $line, $col) = @_;
    my $cursor_l = $line - 1;
    $cursor_l = 0 if $cursor_l < 0;
    if ($cursor_l > $#$lines) {
        $cursor_l = $#$lines;
        my $s = $lines->[$cursor_l] // '';
        my @chars = split //, $s;
        return ($cursor_l, scalar(@chars));
    }
    my $cursor_c = $col - 1;
    $cursor_c = 0 if $cursor_c < 0;
    my $s = $lines->[$cursor_l] // '';
    my @chars = split //, $s;
    my $max = scalar(@chars);
    $cursor_c = $max if $cursor_c > $max;
    return ($cursor_l, $cursor_c);
}

sub buffer_to_str {
    my ($lines) = @_;
    return "" if @$lines == 1 && $lines->[0] eq '';
    return join("\n", @$lines) . "\n";
}

for my $case (@cases) {
    my ($name, $old_content, $new_content) = @$case;
    # Encode the codepoint string to UTF-8 bytes for writing to disk
    my $old_bytes = encode('UTF-8', $old_content);
    my $new_bytes = encode('UTF-8', $new_content);

    my $old = "$tmpdir/$name.old"; my $new = "$tmpdir/$name.new";
    open my $fh, '>:raw', $old; print $fh $old_bytes; close $fh;
    open $fh,  '>:raw', $new; print $fh $new_bytes; close $fh;

    # Run the standard pipeline
    system("$root/bin/ad_compute '$old' '$new' $tmpdir/raw_$name.txt 2>/dev/null");
    system("$root/bin/ad_postprocess < $tmpdir/raw_$name.txt > $tmpdir/post_$name.txt 2>/dev/null");
    system("$root/bin/ad_layer_pace < $tmpdir/post_$name.txt > $tmpdir/timed_$name.txt 2>/dev/null");

    # ── Mode 1: final output ──
    system("$root/bin/ad --no-display --speed 1000 --snapshot $tmpdir/snap_$name.txt '$old' < $tmpdir/timed_$name.txt 2>/dev/null");
    open $fh, '<:raw', "$tmpdir/snap_$name.txt"; my $snap = do { local $/; <$fh> }; close $fh;

    my $ok1 = ($snap eq $new_bytes);
    if ($ok1) { $pass++; } else {
        $fail++;
        print "FAIL final: $name\n  expected: [" . unpack("H*", $new_bytes) . "]\n  got:      [" . unpack("H*", $snap) . "]\n";
    }

    # ── Mode 2: per-op snapshot ──
    # Build a new timed stream that injects "snapshot <file>" after every
    # keep/delete/insert op. Use a fresh dir for the per-op snapshots.
    my $snapdir = "$tmpdir/snaps_$name";
    mkdir $snapdir;

    my @timed_in;
    open $fh, '<', "$tmpdir/timed_$name.txt"; @timed_in = <$fh>; close $fh;

    my $idx = 0;
    my @timed_out;
    for my $l (@timed_in) {
        chomp $l;
        next if $l eq '' || $l =~ /^#/ || $l =~ /^(HUNK|HUNK_END)/;
        my @parts = split /\t/, $l;
        my $cmd = $parts[0] // '';
        if ($cmd eq 'keep' || $cmd eq 'delete' || $cmd eq 'insert') {
            push @timed_out, $l;
            push @timed_out, "snapshot\t$snapdir/snap_$idx.txt";
            $idx++;
        } else {
            push @timed_out, $l;
        }
    }
    open my $ofh, '>', "$tmpdir/timed_snaps_$name.txt";
    print $ofh join("\n", @timed_out), "\n\n";
    close $ofh;

    # Run the animator with the modified timed stream — it will write a
    # snapshot file after every op.
    system("$root/bin/ad --no-display --speed 1000 '$old' < $tmpdir/timed_snaps_$name.txt 2>/dev/null");

    # Now walk the timed stream with the reference animator and verify
    # each snapshot matches. Reference works on codepoints (decoded).
    my @old_lines = split /\n/, $old_content, -1;
    pop @old_lines if @old_lines && $old_lines[-1] eq '' && $old_content =~ /\n$/;
    @old_lines = ("") unless @old_lines;

    my @ref_lines = @old_lines;
    my ($ref_l, $ref_c) = (0, 0);
    my $ok2 = 1;
    my $fail_msg = '';
    my $snap_seen = 0;
    for my $l (@timed_out) {
        my @parts = split /\t/, $l;
        my $cmd = $parts[0] // '';
        if ($cmd eq 'keep' || $cmd eq 'delete' || $cmd eq 'insert') {
            my $line = $parts[1] + 0;
            my $col  = $parts[2] + 0;
            my $code = $parts[3] + 0;
            ($ref_l, $ref_c) = set_cursor_ref(\@ref_lines, $line, $col);
            ($ref_l, $ref_c) = ref_apply_op(\@ref_lines, $ref_l, $ref_c, $cmd, $code);
        } elsif ($cmd eq 'snapshot') {
            my $snap_file = $parts[1];
            if (-f $snap_file) {
                open my $sfh, '<:raw', $snap_file;
                my $actual_bytes = do { local $/; <$sfh> };
                close $sfh;
                my $expected_str = buffer_to_str(\@ref_lines);
                my $expected_bytes = encode('UTF-8', $expected_str);
                if ($actual_bytes ne $expected_bytes) {
                    $ok2 = 0;
                    $fail_msg = "snapshot $snap_seen mismatch:\n  expected: [" . unpack("H*", $expected_bytes) . "]\n  got:      [" . unpack("H*", $actual_bytes) . "]";
                    last;
                }
                $snap_seen++;
            }
        }
    }
    if ($ok2) { $pass++; } else {
        $fail++;
        print "FAIL per-op: $name\n$fail_msg\n";
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);

