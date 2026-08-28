#!/usr/bin/env perl
# test_highlight.pl — Test the ad_layer_highlight layer.
#
# Verifies:
#   1. The layer is invokable standalone.
#   2. The layer accepts --highlight option.
#   3. The layer passes through ops when --highlight none.
#   4. C and Perl implementations produce similar output structure.
#
# Usage: perl layers/tests/test_highlight.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Setup: input with delay ops (timed stream) -------------------------
my $input = <<'EOF';
# diffvim timed ops v2
HUNK	1	2	2	0	0
delay	50	char
keep	1	1	97	a
delay	50	char
delete	1	2	98	b
delay	40	char
insert	1	2	66	B
delay	50	char
keep	1	3	100	d
delay	50	char
keep	2	1	10	\n
HUNK_END
EOF

my $in_file = "/tmp/lt_hl_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) --------------------------------------
system("./bin/ad_layer_highlight < $in_file > /tmp/lt_hl_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_hl_c.out") {
    ok "C ad_layer_highlight runs standalone";
} else {
    bad "C ad_layer_highlight failed to run";
}

# --- Test 2: accepts --highlight option ---------------------------------
system("./bin/ad_layer_highlight --highlight word < $in_file > /tmp/lt_hl_word.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_hl_word.out") {
    ok "accepts --highlight word option";
} else {
    bad "failed to accept --highlight option";
}

# --- Test 3: --highlight none passes through ----------------------------
system("./bin/ad_layer_highlight --highlight none < $in_file > /tmp/lt_hl_none.out 2>/dev/null");
my $output = "";
open($fh, '<', "/tmp/lt_hl_none.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

# Should pass through all original ops
my $input_keep_count = () = ($input =~ /^keep\t/mg);
my $output_keep_count = () = ($output =~ /^keep\t/mg);
if ($input_keep_count == $output_keep_count) {
    ok "--highlight none passes through ops unchanged ($output_keep_count keeps)";
} else {
    bad "--highlight none changed op count (input=$input_keep_count, output=$output_keep_count)";
}

# --- Test 4: C and Perl parity on --highlight none ----------------------
system("perl layers/perl/ad_layer_highlight.pl --highlight none < $in_file > /tmp/lt_hl_pl.out 2>/dev/null");
my $pl_output = "";
open($fh, '<', "/tmp/lt_hl_pl.out") or die;
while (my $line = <$fh>) { $pl_output .= $line; }
close($fh);
if ($output eq $pl_output) {
    ok "C and Perl ad_layer_highlight --highlight none produce identical output (parity)";
} else {
    bad "C and Perl ad_layer_highlight --highlight none differ";
}

# --- Final summary -------------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
