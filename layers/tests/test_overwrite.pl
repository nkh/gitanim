#!/usr/bin/env perl
# test_overwrite.pl — Test the ad_layer_overwrite layer.
#
# Verifies:
#   1. The layer is invokable standalone.
#   2. Adjacent delete+insert pairs at the same (line, col) merge into
#      overwrite_insert ops.
#   3. C and Perl implementations produce identical output (parity).
#
# Usage: perl layers/tests/test_overwrite.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Setup: input that should trigger overwrite merge --------------------
# Input has adjacent delete+insert at same (line, col) — these should
# merge into overwrite_insert ops.
my $input = <<'EOF';
# raw diff v2
HUNK	1	2	2	0	0
keep	1	1	97	a
delete	1	2	98	b
insert	1	2	66	B
delete	1	3	99	c
insert	1	3	67	C
keep	1	4	100	d
keep	2	1	10	\n
HUNK_END
EOF

my $in_file = "/tmp/lt_overwrite_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) --------------------------------------
system("./bin/ad_layer_overwrite < $in_file > /tmp/lt_overwrite_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_overwrite_c.out") {
    ok "C ad_layer_overwrite runs standalone";
} else {
    bad "C ad_layer_overwrite failed to run";
}

# --- Test 2: overwrite_insert ops are emitted ----------------------------
my $output = "";
open($fh, '<', "/tmp/lt_overwrite_c.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

if ($output =~ /^overwrite_insert\t/m) {
    ok "output contains overwrite_insert ops (merge happened)";
} else {
    bad "output missing overwrite_insert ops (merge didn't happen)";
}

# Count overwrite_insert ops — should be 2 (b→B, c→C)
my $ow_count = () = ($output =~ /^overwrite_insert\t/mg);
if ($ow_count == 2) {
    ok "exactly 2 overwrite_insert ops emitted (b→B, c→C)";
} else {
    bad "expected 2 overwrite_insert ops, got $ow_count";
}

# --- Test 3: C and Perl parity -------------------------------------------
system("perl layers/perl/ad_layer_overwrite.pl < $in_file > /tmp/lt_overwrite_pl.out 2>/dev/null");
my $pl_output = "";
open($fh, '<', "/tmp/lt_overwrite_pl.out") or die;
while (my $line = <$fh>) { $pl_output .= $line; }
close($fh);
if ($output eq $pl_output) {
    ok "C and Perl ad_layer_overwrite produce identical output (parity)";
} else {
    bad "C and Perl ad_layer_overwrite differ";
}

# --- Test 4: parity on real examples ------------------------------------
my @examples = glob "tests/examples/0[1-9]_*/old.* tests/examples/1[0-9]_*/old.*";
my $parity_pass = 0;
my $parity_total = 0;
for my $old_path (@examples) {
    my $new_path = $old_path;
    $new_path =~ s/old\./new./;
    next unless -f $new_path;
    system("AD_LEFT_TO_RIGHT=1 ./bin/ad_compute '$old_path' '$new_path' /tmp/lt_ow_raw.txt 2>/dev/null");
    next unless -s "/tmp/lt_ow_raw.txt";
    # Run reorder first to get post-reorder input
    system("./bin/ad_layer_reorder < /tmp/lt_ow_raw.txt > /tmp/lt_ow_reord.txt 2>/dev/null");
    $parity_total++;
    my $c_res = `./bin/ad_layer_overwrite < /tmp/lt_ow_reord.txt 2>/dev/null`;
    my $pl_res = `perl layers/perl/ad_layer_overwrite.pl < /tmp/lt_ow_reord.txt 2>/dev/null`;
    if ($c_res eq $pl_res) {
        $parity_pass++;
    }
}
if ($parity_total > 0 && $parity_pass == $parity_total) {
    ok "C/Perl parity verified on $parity_pass/$parity_total real examples";
} elsif ($parity_total > 0) {
    bad "C/Perl parity failed: $parity_pass/$parity_total examples match";
}

# --- Final summary -------------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
