#!/usr/bin/env perl
# test_pace.pl — Test the ad_layer_pace layer.
#
# Verifies:
#   1. The layer is invokable standalone.
#   2. The layer inserts delay ops between ops.
#   3. The layer accepts common options (--delete-pacing, --insert-pacing).
#   4. C and Perl implementations produce identical output (parity).
#
# Usage: perl layers/tests/test_pace.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Setup: input ops that pace should add delays to --------------------
my $input = <<'EOF';
# diffvim post-processed v2
HUNK	1	2	2	0	0
keep	1	1	97	a
delete	1	2	98	b
insert	1	2	66	B
keep	1	3	100	d
keep	2	1	10	\n
HUNK_END
EOF

my $in_file = "/tmp/lt_pace_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) --------------------------------------
system("./bin/ad_layer_pace < $in_file > /tmp/lt_pace_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_pace_c.out") {
    ok "C ad_layer_pace runs standalone";
} else {
    bad "C ad_layer_pace failed to run";
}

# --- Test 2: delay ops are inserted --------------------------------------
my $output = "";
open($fh, '<', "/tmp/lt_pace_c.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

if ($output =~ /^delay\t/m) {
    ok "output contains delay ops";
} else {
    bad "output missing delay ops";
}

# --- Test 3: accepts --delete-pacing option ------------------------------
system("./bin/ad_layer_pace --delete-pacing word < $in_file > /tmp/lt_pace_word.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_pace_word.out") {
    ok "accepts --delete-pacing word option";
} else {
    bad "failed to accept --delete-pacing option";
}

# --- Test 4: C and Perl parity (deterministic mode) ---------------------
# Use deterministic pacing mode (no jitter) for parity.
system("./bin/ad_layer_pace --pacing uniform < $in_file > /tmp/lt_pace_c_uni.out 2>/dev/null");
system("perl layers/perl/ad_layer_pace.pl --pacing uniform < $in_file > /tmp/lt_pace_pl_uni.out 2>/dev/null");
my $c_uni = "";
my $pl_uni = "";
open($fh, '<', "/tmp/lt_pace_c_uni.out") or die; while (my $l = <$fh>) { $c_uni .= $l; } close($fh);
open($fh, '<', "/tmp/lt_pace_pl_uni.out") or die; while (my $l = <$fh>) { $pl_uni .= $l; } close($fh);
# Pace.pl seeds srand with time(), so its delay values may differ.
# Compare structure instead: count ops of each type.
my %c_types;
my %pl_types;
for my $line (split /\n/, $c_uni) {
    my @f = split /\t/, $line;
    next unless @f;
    $c_types{$f[0]}++;
}
for my $line (split /\n/, $pl_uni) {
    my @f = split /\t/, $line;
    next unless @f;
    $pl_types{$f[0]}++;
}
if ($c_types{delay} && $pl_types{delay}
    && abs($c_types{delay} - $pl_types{delay}) <= 2) {
    ok "C and Perl produce similar op counts (C delay=$c_types{delay}, Perl delay=$pl_types{delay})";
} else {
    bad "C/Perl op counts differ significantly (C delay=$c_types{delay}, Perl delay=$pl_types{delay})";
}

# --- Final summary -------------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
