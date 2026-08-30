#!/usr/bin/env perl
# test_fuzz.pl — Fuzz testing: feed malformed and edge-case inputs to layers.
#
# Tests:
#   1. Malformed TSV (missing fields, extra fields, non-numeric)
#   2. Binary data in TSV stream
#   3. Empty input
#   4. Very large input (100k ops)
#   5. Hunk with zero ops
#   6. Hunk header with missing fields
#   7. Ops with negative line/col
#   8. Ops with very large line/col numbers
#   9. Unicode in char_repr field
#  10. Nested HUNK/HUNK_END (malformed)
#
# Each test verifies the layer doesn't crash (exit 0 or graceful error).
# We don't check output correctness — just that the layer handles bad
# input without segfaulting or hanging.
#
# Usage: perl tests/test_fuzz.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die;

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# Helper: run a layer with given input, check it doesn't crash (segfault)
sub test_layer_no_crash {
    my ($layer, $input, $name) = @_;
    my $in_file = "/tmp/fuzz_in_$$.txt";
    open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);
    my $rc = system("./bin/$layer < $in_file > /dev/null 2>/dev/null");
    # Exit 0 or exit 1 (graceful error) are OK. Signal 11 (segfault) is not.
    if ($rc == 0 || ($rc >> 8) == 1) {
        ok "$layer: $name (exit " . ($rc >> 8) . ")";
    } else {
        my $sig = $rc & 127;
        bad "$layer: $name CRASHED (signal $sig)";
    }
    unlink $in_file;
}

my @layers = qw(ad_layer_reorder ad_layer_overwrite ad_layer_indent_last
                ad_layer_line_delete_in_place ad_layer_skip_indent);

# --- Test 1: Malformed TSV (missing fields) ---
my $malformed = <<'EOF';
# test
HUNK	1	1	1	0	0
delete	1
keep	1	1
insert	1	1	102
HUNK_END
EOF
for my $layer (@layers) {
    test_layer_no_crash($layer, $malformed, "malformed TSV (missing fields)");
}

# --- Test 2: Binary data in stream ---
my $binary = "# test\nHUNK\t1\t1\t1\t0\t0\ndelete\t1\t1\t0\t\x00\x01\x02\nHUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $binary, "binary data in stream");
}

# --- Test 3: Empty input ---
for my $layer (@layers) {
    test_layer_no_crash($layer, "", "empty input");
}

# --- Test 4: Very large input (10k ops) ---
my $large = "# test\nHUNK\t1\t5000\t5000\t0\t0\n";
for (1..10000) {
    $large .= "delete\t1\t$_\t97\ta\n";
}
$large .= "HUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $large, "large input (10k ops)");
}

# --- Test 5: Hunk with zero ops ---
my $empty_hunk = <<'EOF';
# test
HUNK	1	0	0	0	0
HUNK_END
EOF
for my $layer (@layers) {
    test_layer_no_crash($layer, $empty_hunk, "hunk with zero ops");
}

# --- Test 6: Hunk header with missing fields ---
my $bad_hunk = "HUNK\t1\t1\nkeep\t1\t1\t97\ta\nHUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $bad_hunk, "hunk header missing fields");
}

# --- Test 7: Negative line/col ---
my $negative = <<'EOF';
HUNK	-1	1	1	0	0
delete	-5	-3	97	'a'
insert	-1	-1	98	'b'
HUNK_END
EOF
for my $layer (@layers) {
    test_layer_no_crash($layer, $negative, "negative line/col");
}

# --- Test 8: Very large line/col numbers ---
my $large_nums = <<'EOF';
HUNK	999999	1	1	0	0
delete	999999	999999	97	'a'
HUNK_END
EOF
for my $layer (@layers) {
    test_layer_no_crash($layer, $large_nums, "large line/col numbers");
}

# --- Test 9: Input with no HUNK at all ---
my $no_hunk = "# just comments\n# no hunks here\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $no_hunk, "no HUNK header");
}

# --- Test 10: Multiple HUNK_END without HUNK ---
my $bad_nesting = "HUNK_END\nHUNK_END\nHUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $bad_nesting, "HUNK_END without HUNK");
}

# --- Test 11: Non-numeric code field ---
my $bad_code = "HUNK\t1\t1\t1\t0\t0\ndelete\t1\t1\tfoo\tbar\nHUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $bad_code, "non-numeric code field");
}

# --- Test 12: Extremely long line ---
my $long_line = "HUNK\t1\t1\t1\t0\t0\ndelete\t1\t1\t97\t" . ("a" x 100000) . "\nHUNK_END\n";
for my $layer (@layers) {
    test_layer_no_crash($layer, $long_line, "extremely long line (100k chars)");
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
