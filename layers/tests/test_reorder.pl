#!/usr/bin/env perl
# test_reorder.pl — Test the ad_layer_reorder layer.
#
# Verifies:
#   1. The layer is invokable standalone (stdin → stdout, exit 0).
#   2. Known input produces expected output (4-sweep reorder).
#   3. C and Perl implementations produce identical output (parity).
#
# This test is run automatically by `make test-layer-reorder` and is
# part of the `make test-layers` aggregate target.
#
# Usage: perl layers/tests/test_reorder.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Setup: known input ---------------------------------------------------
# A simple diff with interleaved deletes and inserts that exercises
# the 4-sweep reorder. The input is post-reorder-cleanup, so positions
# are set by the layer itself.
my $input = <<'EOF';
# raw diff v2
# algorithm patience
HUNK	1	3	2	0	0
keep	1	1	97	a
delete	1	2	98	b
insert	1	2	66	B
delete	1	3	99	c
keep	1	3	100	d
keep	2	1	10	\n
HUNK_END
EOF

my $in_file = "/tmp/lt_reorder_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) --------------------------------------
system("./bin/ad_layer_reorder < $in_file > /tmp/lt_reorder_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_reorder_c.out") {
    ok "C ad_layer_reorder runs standalone (exit 0, non-empty output)";
} else {
    bad "C ad_layer_reorder failed to run";
}

# --- Test 2: layer produces expected output structure -------------------
my $output = "";
open($fh, '<', "/tmp/lt_reorder_c.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

# Expected: HUNK header, then ops in 4-sweep order:
#   - Non-newline deletes first (b, c)
#   - Non-newline inserts (B)
#   - Newline deletes (none in this input)
#   - Newline inserts (none in this input)
#   - Keeps at boundaries (a, d, \n)
# So the order should be: keep a, delete b, delete c, insert B, keep d, keep \n
my @ops;
for my $line (split /\n/, $output) {
    next if $line =~ /^#/ || $line eq '';
    push @ops, $line if $line =~ /^(HUNK|keep|delete|insert|overwrite_insert)/;
}
if (@ops >= 2 && $ops[0] =~ /^HUNK/) {
    ok "output has HUNK header";
} else {
    bad "output missing HUNK header";
}

# Find the order of op types after HUNK header
my @types;
for my $op (@ops[1..$#ops]) {
    push @types, ($op =~ /^(\w+)/)[0] if $op !~ /^HUNK_END/;
}
# Verify: keep, then deletes, then inserts, then keeps
my $saw_keep_first = $types[0] && $types[0] eq 'keep';
my $saw_delete_before_insert = 0;
for (my $i = 0; $i < @types - 1; $i++) {
    if ($types[$i] eq 'delete' && $types[$i+1] eq 'insert') {
        $saw_delete_before_insert = 1;
        last;
    }
}
if ($saw_keep_first && $saw_delete_before_insert) {
    ok "4-sweep reorder: keep first, then delete before insert";
} else {
    bad "4-sweep reorder order wrong (types: @types)";
}

# --- Test 3: C and Perl parity -------------------------------------------
system("perl layers/perl/ad_layer_reorder.pl < $in_file > /tmp/lt_reorder_pl.out 2>/dev/null");
my $pl_output = "";
open($fh, '<', "/tmp/lt_reorder_pl.out") or die;
while (my $line = <$fh>) { $pl_output .= $line; }
close($fh);
if ($output eq $pl_output) {
    ok "C and Perl ad_layer_reorder produce identical output (parity)";
} else {
    bad "C and Perl ad_layer_reorder differ";
    # Show diff for debugging
    print "C output:\n$output\n";
    print "Perl output:\n$pl_output\n";
}

# --- Test 4: parity on real examples ------------------------------------
my @examples = glob "tests/examples/0[1-9]_*/old.* tests/examples/1[0-9]_*/old.*";
my $parity_pass = 0;
my $parity_total = 0;
for my $old_path (@examples) {
    my $new_path = $old_path;
    $new_path =~ s/old\./new./;
    next unless -f $new_path;
    system("AD_LEFT_TO_RIGHT=1 ./bin/ad_compute '$old_path' '$new_path' /tmp/lt_reord_raw.txt 2>/dev/null");
    next unless -s "/tmp/lt_reord_raw.txt";
    $parity_total++;
    my $c_res = `./bin/ad_layer_reorder < /tmp/lt_reord_raw.txt 2>/dev/null`;
    my $pl_res = `perl layers/perl/ad_layer_reorder.pl < /tmp/lt_reord_raw.txt 2>/dev/null`;
    if ($c_res eq $pl_res) {
        $parity_pass++;
    }
}
if ($parity_total > 0 && $parity_pass == $parity_total) {
    ok "C/Perl parity verified on $parity_pass/$parity_total real examples";
} elsif ($parity_total > 0) {
    bad "C/Perl parity failed: $parity_pass/$parity_total examples match";
} else {
    bad "no real examples found for parity test";
}

# --- Final summary -------------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
