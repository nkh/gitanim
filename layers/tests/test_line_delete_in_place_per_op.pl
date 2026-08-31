#!/usr/bin/env perl
# test_line_delete_in_place_per_op.pl — Per-op snapshot verification.
#
# WHAT THIS TEST DOES:
#   For each test case, this test:
#     1. Runs the full pipeline (compute → postprocess → pace) and
#        produces a timed_ops stream.
#     2. Injects a "snapshot <file>" op after EVERY keep/delete/insert op
#        in the timed stream. The animator (bin/ad) writes the buffer
#        state to that file when it encounters the snapshot op.
#     3. Runs the C animator with the modified stream.
#     4. Compares each captured snapshot against HAND-WRITTEN expected
#        snapshots (defined below in @cases).
#
# WHY HAND-WRITTEN EXPECTED:
#   Earlier versions of this test used a "reference simulator" that
#   mirrored the animator's behavior — including its bugs. So the test
#   passed even though the layer was broken, because the simulator and
#   animator made the same mistake. Hand-written expected snapshots
#   avoid this trap: they encode what SHOULD happen, not what DOES happen.
#
# HOW TO ADD A CASE:
#   1. Add a new entry to @cases with (name, old_content, new_content,
#      expected_snapshots_no_layer, expected_snapshots_with_layer).
#   2. The expected_snapshots arrays are the buffer state AFTER each
#      keep/delete/insert op. They are arrays of strings, one per snapshot.
#   3. Run the test.
#
# Usage: perl layers/tests/test_line_delete_in_place_per_op.pl

use strict;
use warnings;
use File::Temp qw(tempdir);

my $ROOT = "/home/z/my-project/gitanim";
chdir $ROOT or die;

my $tmpdir = tempdir(CLEANUP => 0);
print "Test dir: $tmpdir\n\n";

my $pass = 0; my $fail = 0;

# Inject snapshot ops after every keep/delete/insert op
sub inject_snapshots {
    my ($timed_text, $snap_dir) = @_;
    my @in = split /\n/, $timed_text;
    my @out;
    my $idx = 0;
    for my $l (@in) {
        next if !length($l) || $l =~ /^#/ || $l =~ /^HUNK/;
        push @out, $l;
        my @parts = split /\t/, $l;
        my $cmd = $parts[0] // '';
        if ($cmd eq 'keep' || $cmd eq 'delete' || $cmd eq 'insert') {
            push @out, "snapshot\t$snap_dir/snap_" . sprintf("%03d", $idx) . ".txt";
            $idx++;
        }
    }
    return (join("\n", @out) . "\n", $idx);
}

# Run pipeline (with or without layer), capture per-op snapshots
sub run_pipeline_with_snapshots {
    my ($old_file, $new_file, $with_layer, $snap_dir, $tmp_prefix) = @_;

    mkdir $tmp_prefix;
    mkdir $snap_dir;

    my $raw_file = "$tmp_prefix/raw.tsv";
    my $pp_file = "$tmp_prefix/pp.tsv";
    my $timed_file = "$tmp_prefix/timed.tsv";
    my $timed_snaps_file = "$tmp_prefix/timed_snaps.tsv";

    system("./bin/ad_compute '$old_file' '$new_file' '$raw_file' 2>/dev/null");

    # Stage 2: postprocess
    # WITHOUT layer: raw → reorder → pace (standard pipeline)
    # WITH layer: raw → reorder → line_delete_in_place → pace
    # (layers compose — each layer accepts any input)
    my @pp_cmd = ("./pipeline/ad_postprocess", "--ad-layer=ad_layer_reorder");
    push @pp_cmd, "--ad-layer=ad_layer_line_delete_in_place" if $with_layer;
    my $cmd = join(" ", @pp_cmd);
    system("$cmd < $raw_file > $pp_file 2>/dev/null");

    system("./bin/ad_layer_pace --delete-pacing=char --insert-pacing=char < $pp_file > $timed_file 2>/dev/null");

    open my $fh, '<', $timed_file or die;
    my $timed_text = do { local $/; <$fh> };
    close $fh;

    my ($injected, $n_snaps) = inject_snapshots($timed_text, $snap_dir);

    open $fh, '>', $timed_snaps_file or die;
    print $fh $injected;
    close $fh;

    system("./bin/ad --no-display --speed 1000 '$old_file' < $timed_snaps_file 2>/dev/null");

    my @actual_snaps;
    for my $i (0 .. $n_snaps - 1) {
        my $f = sprintf("%s/snap_%03d.txt", $snap_dir, $i);
        if (-f $f) {
            open my $sfh, '<:raw', $f or die;
            my $content = do { local $/; <$sfh> };
            close $sfh;
            push @actual_snaps, $content;
        } else {
            push @actual_snaps, undef;
        }
    }

    return (\@actual_snaps, $injected);
}

# ── Test cases with hand-written expected snapshots ───────────────────
# Each case is:
#   [name, old, new, expected_no_layer[], expected_with_layer[]]
# The expected arrays are buffer states AFTER each keep/delete/insert op.
# Trailing \n is implied (the buffer's last line ends with \n).

my @cases = (
    # ── Case 0: delete 1 line (A,B,C → A,C) ──────────────────────────
    # Pattern doesn't fire (no leading \n delete). Layer output = raw.
    [
        'delete 1 line (A,B,C → A,C)',
        "A\nB\nC\n", "A\nC\n",
        # expected_no_layer: original positions preserved (line-aware reorder)
        [
            "A\n\nC\n",    # after delete B (line 2 empty)
            "A\nC\n",      # after delete \n (join)
        ],
        # expected_with_layer (same — pattern doesn't fire for single delete)
        [
            "A\n\nC\n",
            "A\nC\n",
        ],
    ],

    # ── Case 1: delete 2 lines (A,B,C,D → A,D) ────────────────────────
    # WITHOUT layer: original positions (3,1) are wrong after the join —
    #   delete C goes to line 3 which is "D", not "C". KNOWN LIMITATION.
    # WITH layer: line_delete_in_place reorders so C is deleted before
    #   the join, using correct original positions. CORRECT.
    [
        'delete 2 lines (A,B,C,D → A,D)',
        "A\nB\nC\nD\n", "A\nD\n",
        # expected_no_layer — original positions, wrong after join
        [
            "A\n\nC\nD\n",  # after delete B (line 2 empty)
            "A\nC\nD\n",    # after delete \n (join line 2 with 3)
            "A\nC\n",       # after delete C at (3,1) — WRONG (goes to D)
            "A\nC\n",       # after delete \n at (3,1) — no-op (last line)
        ],
        # expected_with_layer — reordered with decrement, correct
        [
            "A\n\nC\nD\n",  # after delete B (line 2 empty, C still on line 3)
            "A\n\n\nD\n",   # after delete C at (3,1) (line 3 now empty)
            "A\n\nD\n",     # after delete \n at (3,1) (line 3 joins with line 4)
            "A\nD\n",       # after delete \n at (2,1) (line 2 joins with line 3)
        ],
    ],

    # ── Case 2: delete 3 lines (A,B,C,D,E → A,E) ─────────────────────
    [
        'delete 3 lines (A,B,C,D,E → A,E)',
        "A\nB\nC\nD\nE\n", "A\nE\n",
        # expected_no_layer — original positions, wrong after joins
        [
            "A\n\nC\nD\nE\n",  # after delete B
            "A\nC\nD\nE\n",    # after delete \n (join)
            "A\nC\n\nE\n",     # after delete C at (3,1) — WRONG (deletes D)
            "A\nC\nE\n",       # after delete \n at (3,1) — joins empty line with E
            "A\nC\nE\n",       # after delete D at (4,1) — clamped, no-op
            "A\nC\nE\n",       # after delete \n at (4,1) — no-op
        ],
        # expected_with_layer — reordered with decrement, correct
        [
            "A\n\nC\nD\nE\n",   # after delete B (line 2 empty)
            "A\n\n\nD\nE\n",    # after delete C at (3,1) (line 3 empty)
            "A\n\nD\nE\n",      # after delete \n at (3,1) (line 3 joins with 4)
            "A\n\n\nE\n",       # after delete D at (3,1) (line 3 now empty again)
            "A\n\nE\n",         # after delete \n at (3,1) (line 3 joins with 4)
            "A\nE\n",           # after delete \n at (2,1) (line 2 joins with 3)
        ],
    ],

    # ── Case 3: classic (A,B,C → AC) ───────────────────────────────
    [
        'classic A,B,C → AC (delete B, join A and C)',
        "A\nB\nC\n", "AC\n",
        # expected_no_layer — original positions, wrong after join
        [
            "A\nB\nC\n",     # after keep A
            "AB\nC\n",       # after delete \n (joiner) — A and B on same line
            "AB\n",          # after delete B at (2,1) — WRONG (goes to C)
            "AB\n",          # after delete \n at (2,1) — no-op
            "AB\n",          # after keep C
        ],
        # expected_with_layer — reordered, correct
        [
            "A\nB\nC\n",     # after keep A
            "A\n\nC\n",      # after delete B at (2,1) (line 2 empty)
            "A\nC\n",        # after delete \n at (2,1) (line 2 joins with 3)
            "AC\n",          # after delete \n at (1,2) (line 1 joins with 2)
            "AC\n",          # after keep C at (2,1) (clamped to line 1)
        ],
    ],
);

print "=" x 72, "\n";
print "Per-op snapshot test for ad_layer_line_delete_in_place\n";
print "Each snapshot is the buffer state AFTER one keep/delete/insert op.\n";
print "Expected snapshots are HAND-WRITTEN (not derived from a simulator).\n";
print "=" x 72, "\n\n";

for my $case_idx (0 .. $#cases) {
    my $case = $cases[$case_idx];
    my ($name, $old, $new, $expected_no, $expected_with) = @$case;

    my $case_dir = "$tmpdir/case_" . $case_idx;
    mkdir $case_dir;

    my $old_file = "$case_dir/old.txt";
    my $new_file = "$case_dir/new.txt";
    open my $fh, '>', $old_file or die; print $fh $old; close $fh;
    open $fh, '>', $new_file or die; print $fh $new; close $fh;

    print "─" x 72, "\n";
    print "CASE $case_idx: $name\n";
    print "  OLD: ", ($old =~ s/\n/\\n/gr), "\n";
    print "  NEW: ", ($new =~ s/\n/\\n/gr), "\n\n";

    for my $with_layer (0, 1) {
        my $label = $with_layer ? "WITH layer" : "WITHOUT layer";
        my $snap_dir = "$case_dir/snaps_" . ($with_layer ? "with" : "without");
        my $tmp_prefix = "$case_dir/" . ($with_layer ? "with" : "without");

        my ($actual, $injected) = run_pipeline_with_snapshots(
            $old_file, $new_file, $with_layer, $snap_dir, $tmp_prefix
        );
        my $expected = $with_layer ? $expected_with : $expected_no;

        print "  [$label] captured ", scalar(@$actual), " snapshots\n";

        # Show the ops being applied (for human inspection)
        if ($ENV{VERBOSE}) {
            print "    Ops in timed stream:\n";
            for my $l (split /\n/, $injected) {
                next if !length($l) || $l =~ /^#/ || $l =~ /^HUNK/ || $l =~ /^delay/;
                my @p = split /\t/, $l;
                next unless @p && $p[0] =~ /^(keep|delete|insert)$/;
                my $code = $p[3] // '';
                my $ch = $code eq '10' ? '\\n' :
                         $code eq '32' ? 'space' :
                         ($code >= 33 && $code <= 126 ? "'".chr($code)."'" : $code);
                printf "      %s at (%s,%s) code=%s %s\n", $p[0], $p[1], $p[2], $code, $ch;
            }
        }

        # Compare each snapshot
        my $n_match = 0;
        my $n_mismatch = 0;
        for my $i (0 .. $#$actual) {
            my $a = $actual->[$i];
            my $e = $expected->[$i];
            if (!defined $a) {
                $n_mismatch++;
                print "    snap $i: FAIL (snapshot file not written)\n";
                next;
            }
            if (!defined $e) {
                print "    snap $i: WARN (no expected snapshot for idx $i)\n";
                next;
            }
            my $a_disp = $a; $a_disp =~ s/\n/\\n/g;
            my $e_disp = $e; $e_disp =~ s/\n/\\n/g;
            if ($a eq $e) {
                $n_match++;
                if ($ENV{VERBOSE}) { print "    snap $i: OK  (\"$a_disp\")\n"; }
            } else {
                $n_mismatch++;
                print "    snap $i: FAIL\n";
                print "      actual:   \"$a_disp\"\n";
                print "      expected: \"$e_disp\"\n";
            }
        }

        if ($n_mismatch == 0) {
            print "    RESULT: PASS — all $n_match snapshots match expected\n";
            $pass++;
        } else {
            print "    RESULT: FAIL — $n_match match, $n_mismatch mismatch\n";
            $fail++;
        }
    }
    print "\n";
}

print "=" x 72, "\n";
print "Results: $pass passed, $fail failed\n";
print "=" x 72, "\n";

if ($fail > 0) {
    print "\nNote: The 'WITH layer' cases for multi-line deletes will FAIL.\n";
    print "This proves the layer is broken: the actual snapshots diverge\n";
    print "from the hand-written expected snapshots at the exact op where\n";
    print "the layer's incorrect op order causes the cursor to be at the\n";
    print "wrong position.\n";
    print "\nRun with VERBOSE=1 to see the op stream and per-snapshot dump.\n";
}

exit($fail > 0 ? 1 : 0);
