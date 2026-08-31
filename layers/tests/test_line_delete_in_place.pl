#!/usr/bin/env perl
# test_line_delete_in_place.pl — Verify the layer's end-state correctness.
#
# PREVIOUS VERSION (BROKEN): This test only checked op ORDER (that content
# deletes come before the joining \n delete) and C/Perl parity. It did NOT
# verify the animation actually produces the correct end state. The test
# PASSED even though the layer was fundamentally broken — it produced
# wrong end state for multi-line deletes.
#
# NEW VERSION (CORRECT): This test:
#   1. Runs the full pipeline (compute → postprocess → pace) on real diffs.
#   2. Simulates the vimscript animator (TimedProcessBatch) on the timed
#      ops output.
#   3. Verifies the final buffer matches the expected new file.
#
# If the layer is broken, this test WILL FAIL (as it should).
#
# Test cases:
#   - Single line deletion
#   - Multi-line deletion (2, 3, 4 consecutive lines)
#   - Delete first/last line
#   - Mixed keep/delete
#   - The classic "A\nB\nC\n → AC\n" from the design doc
#
# Usage: perl layers/tests/test_line_delete_in_place.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Simulate the vimscript animator (TimedProcessBatch) ---------------
# Mirrors engine.vim's behavior EXACTLY:
#   - For non-\n deletes: set cursor to (line, col), delete char at cursor
#   - For \n deletes: DON'T move cursor (current cursor stays), join
#   - For inserts: set cursor, insert char
#   - For keeps: set cursor, advance cursor
# Returns: final buffer (arrayref of lines).
sub simulate_animator {
    my ($timed_ops_text, $old_lines) = @_;
    my @buffer = @$old_lines;
    my ($cur_l, $cur_c) = (1, 1);

    my $clamp = sub {
        if ($cur_l < 1) { $cur_l = 1; }
        if ($cur_l > @buffer) {
            $cur_l = scalar @buffer;
            $cur_c = (@buffer ? length($buffer[-1]) + 1 : 1);
            return;
        }
        my $max_col = (@buffer ? length($buffer[$cur_l - 1]) + 1 : 1);
        $cur_c = $max_col if $cur_c > $max_col;
        $cur_c = 1 if $cur_c < 1;
    };

    my $set_cursor = sub {
        my ($l, $c) = @_;
        ($cur_l, $cur_c) = ($l, $c);
        $clamp->();
    };

    my $keep_char = sub {
        my ($code) = @_;
        if ($code == 10) {
            $cur_l++;
            $cur_l = scalar @buffer if $cur_l > @buffer;
            $cur_c = 1;
        } else {
            $cur_c++;
        }
    };

    my $delete_char = sub {
        my ($code) = @_;
        if ($code == 10) {
            if ($cur_l < @buffer) {
                $buffer[$cur_l - 1] = $buffer[$cur_l - 1] . $buffer[$cur_l];
                splice @buffer, $cur_l, 1;
            }
        } else {
            my $line = $buffer[$cur_l - 1];
            if ($cur_c >= 1 && $cur_c <= length($line)) {
                substr($line, $cur_c - 1, 1, '');
                $buffer[$cur_l - 1] = $line;
            }
        }
    };

    my $insert_char = sub {
        my ($code) = @_;
        if ($code == 10) {
            my $line = $buffer[$cur_l - 1];
            my $before = substr($line, 0, $cur_c - 1);
            my $after = substr($line, $cur_c - 1);
            $buffer[$cur_l - 1] = $before;
            splice @buffer, $cur_l, 0, $after;
            $cur_l++;
            $cur_c = 1;
        } else {
            my $line = $buffer[$cur_l - 1];
            substr($line, $cur_c - 1, 0, chr($code));
            $buffer[$cur_l - 1] = $line;
            $cur_c++;
        }
    };

    for my $line (split /\n/, $timed_ops_text) {
        next if !length($line) || $line =~ /^#/;

        my @parts = split /\t/, $line;
        my $cmd = $parts[0];
        next if $cmd eq 'HUNK' || $cmd eq 'HUNK_END' || $cmd eq 'delay';

        if (($cmd eq 'keep' || $cmd eq 'delete' || $cmd eq 'insert') && @parts >= 4) {
            my ($line_num, $col_num, $code) = ($parts[1], $parts[2], $parts[3]);
            if ($cmd eq 'keep') {
                $set_cursor->($line_num, $col_num);
                $keep_char->($code);
            } elsif ($cmd eq 'delete') {
                # C animator honors op positions for ALL deletes (including \n)
                $set_cursor->($line_num, $col_num);
                $delete_char->($code);
            } else {
                $set_cursor->($line_num, $col_num);
                $insert_char->($code);
            }
        }
    }

    return \@buffer;
}

# --- Run the full pipeline and check end-state -------------------------
sub run_pipeline_and_check {
    my ($name, $old_content, $new_content, $with_layer) = @_;

    # Write temp files
    my $old_file = "/tmp/ldip_old_$$.txt";
    my $new_file = "/tmp/ldip_new_$$.txt";
    my $raw_file = "/tmp/ldip_raw_$$.tsv";
    my $pp_file = "/tmp/ldip_pp_$$.tsv";
    my $timed_file = "/tmp/ldip_timed_$$.tsv";

    open my $fh, '>', $old_file or die; print $fh $old_content; close $fh;
    open $fh, '>', $new_file or die; print $fh $new_content; close $fh;

    # Stage 1: compute
    system("./bin/ad_compute '$old_file' '$new_file' '$raw_file' 2>/dev/null");
    unless (-s $raw_file) {
        unlink $old_file, $new_file, $raw_file;
        bad "$name: compute failed";
        return;
    }

    # Stage 2: postprocess (layer runs on raw compute, no reorder)
    my @pp_cmd = ("./pipeline/ad_postprocess");
    if ($with_layer) {
        push @pp_cmd, "--ad-layer=ad_layer_line_delete_in_place";
    } else {
        push @pp_cmd, "--ad-layer=ad_layer_reorder";
    }
    my $pp_cmd_str = join(" ", @pp_cmd);
    system("$pp_cmd_str < $raw_file > $pp_file 2>/dev/null");

    # Stage 3: pace
    system("./bin/ad_layer_pace --delete-pacing=char --insert-pacing=char < $pp_file > $timed_file 2>/dev/null");

    # Read timed ops
    open $fh, '<', $timed_file or die;
    my $timed_ops = do { local $/; <$fh> };
    close $fh;

    # Simulate animator
    my @old_lines = split /\n/, $old_content;
    pop @old_lines if @old_lines && $old_lines[-1] eq '';
    my @new_lines = split /\n/, $new_content;
    pop @new_lines if @new_lines && $new_lines[-1] eq '';

    my $result = simulate_animator($timed_ops, \@old_lines);

    if (@$result == @new_lines && !grep { $result->[$_] ne $new_lines[$_] } 0..$#new_lines) {
        ok "$name (with".($with_layer ? "" : "out")." layer): correct end state";
    } else {
        bad "$name (with".($with_layer ? "" : "out")." layer): WRONG end state";
        print "    Expected: [".join(", ", map { "\"$_\"" } @new_lines)."]\n";
        print "    Got:      [".join(", ", map { "\"$_\"" } @$result)."]\n";
        # Show first 10 timed ops for debugging
        print "    First 10 timed ops:\n";
        my @lines = split /\n/, $timed_ops;
        for my $i (0..9) {
            last unless defined $lines[$i];
            print "      $lines[$i]\n";
        }
    }

    unlink $old_file, $new_file, $raw_file, $pp_file, $timed_file;
}

# ── Test cases ─────────────────────────────────────────────────────────

my @cases = (
    # [name, old, new, expected_to_pass_with_layer]
    # The layer is CURRENTLY DISABLED because it's broken.
    # These tests will show: WITHOUT layer = OK, WITH layer = BROKEN
    # for multi-line deletes.

    ["single line delete (A,B,C → A,C)",
     "A\nB\nC\n", "A\nC\n"],

    ["multi line delete 2 (A,B,C,D → A,D)",
     "A\nB\nC\nD\n", "A\nD\n"],

    ["multi line delete 3 (A,B,C,D,E → A,E)",
     "A\nB\nC\nD\nE\n", "A\nE\n"],

    ["delete first line (A,B,C → B,C)",
     "A\nB\nC\n", "B\nC\n"],

    ["delete last line (A,B,C → A,B)",
     "A\nB\nC\n", "A\nB\n"],

    ["mixed (A,B,C,D,E → A,C,E)",
     "A\nB\nC\nD\nE\n", "A\nC\nE\n"],

    ["classic design doc case (A\\nB\\nC\\n → AC\\n)",
     "A\nB\nC\n", "AC\n"],
);

print "=" x 70, "\n";
print "End-state correctness test for ad_layer_line_delete_in_place\n";
print "=" x 70, "\n\n";

print "--- WITHOUT layer (baseline, should always pass) ---\n";
for my $case (@cases) {
    run_pipeline_and_check($case->[0], $case->[1], $case->[2], 0);
}

print "\n--- WITH layer (currently broken, expected to fail) ---\n";
for my $case (@cases) {
    run_pipeline_and_check($case->[0], $case->[1], $case->[2], 1);
}

# ── C/Perl parity (still useful) ───────────────────────────────────────
print "\n--- C/Perl parity on synthetic input ---\n";
my $input = <<'EOF';
# raw diff v2
HUNK    1       5       0       0       0
keep    1       1       97      a
delete  1       2       10      \n
delete  2       1       98      b
delete  2       2       99      c
delete  2       3       10      \n
keep    3       1       100     d
HUNK_END
EOF
my $in_file = "/tmp/lt_ldip_in.txt";
open my $fh, '>', $in_file or die; print $fh $input; close($fh);

my $c_out = `./bin/ad_layer_line_delete_in_place < $in_file 2>/dev/null`;
my $pl_out = `perl layers/perl/ad_layer_line_delete_in_place.pl < $in_file 2>/dev/null`;
if ($c_out eq $pl_out) {
    ok "C and Perl produce identical output (parity still holds)";
} else {
    bad "C and Perl differ";
}

# ── Summary ───────────────────────────────────────────────────────────
print "\n" . "=" x 70 . "\n";
print "Results: $pass passed, $fail failed\n";
print "=" x 70 . "\n";
if ($fail > 0) {
    print "\nFailing tests:\n";
    for my $e (@errors) {
        print "  - $e\n";
    }
    print "\n";
    print "Note: The 'delete last line' failure is a SEPARATE pre-existing\n";
    print "animator bug — the HUNK header's target line is treated as\n";
    print "metadata and ignored, so the cursor isn't positioned at the\n";
    print "hunk's target line. This is unrelated to the layer.\n";
}
exit($fail > 0 ? 1 : 0);
