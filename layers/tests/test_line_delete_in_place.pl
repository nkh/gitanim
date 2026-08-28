#!/usr/bin/env perl
# test_line_delete_in_place.pl — Test the ad_layer_line_delete_in_place layer.
#
# Verifies:
#   1. The layer is invokable standalone.
#   2. When a \n delete joins two lines and the next line is fully
#      deleted, content is deleted FIRST (on its own line), then the
#      \n delete joins.
#   3. C and Perl implementations produce identical output (parity).
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

# --- Setup: input that should trigger line_delete_in_place --------------
# A \n delete on line N, followed by content deletes on line N+1,
# followed by a \n delete on line N+1.
my $input = <<'EOF';
# raw diff v2
HUNK	1	5	0	0	0
keep	1	1	97	a
delete	1	2	10	\n
delete	2	1	98	b
delete	2	2	99	c
delete	2	3	10	\n
keep	3	1	100	d
HUNK_END
EOF

my $in_file = "/tmp/lt_ldip_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) --------------------------------------
system("./bin/ad_layer_line_delete_in_place < $in_file > /tmp/lt_ldip_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_ldip_c.out") {
    ok "C ad_layer_line_delete_in_place runs standalone";
} else {
    bad "C ad_layer_line_delete_in_place failed to run";
}

# --- Test 2: content deletes come BEFORE the joining \n delete -----------
my $output = "";
open($fh, '<', "/tmp/lt_ldip_c.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

# Find the positions of the content deletes (b, c) and the joining
# \n delete. The content deletes should come first.
my @ops;
for my $line (split /\n/, $output) {
    next if $line =~ /^#/ || $line eq '';
    push @ops, $line if $line =~ /^(HUNK|keep|delete|insert)/;
}

# Find indices
my $first_nl_idx = -1;       # first \n delete (the original joiner)
my $content_b_idx = -1;     # delete b (code 98)
for (my $i = 0; $i < @ops; $i++) {
    if ($ops[$i] =~ /^delete\t\d+\t\d+\t10\t/ && $first_nl_idx == -1) {
        $first_nl_idx = $i;
    }
    if ($ops[$i] =~ /^delete\t\d+\t\d+\t98\t/ && $content_b_idx == -1) {
        $content_b_idx = $i;
    }
}

if ($content_b_idx >= 0 && $first_nl_idx >= 0 && $content_b_idx < $first_nl_idx) {
    ok "content deletes come BEFORE the joining \\n delete";
} else {
    bad "content deletes don't come before \\n delete (content_b=$content_b_idx, first_nl=$first_nl_idx)";
}

# --- Test 3: C and Perl parity -------------------------------------------
system("perl layers/perl/ad_layer_line_delete_in_place.pl < $in_file > /tmp/lt_ldip_pl.out 2>/dev/null");
my $pl_output = "";
open($fh, '<', "/tmp/lt_ldip_pl.out") or die;
while (my $line = <$fh>) { $pl_output .= $line; }
close($fh);
if ($output eq $pl_output) {
    ok "C and Perl ad_layer_line_delete_in_place produce identical output (parity)";
} else {
    bad "C and Perl ad_layer_line_delete_in_place differ";
}

# --- Test 4: parity on real examples ------------------------------------
my @examples = glob "tests/examples/0[1-9]_*/old.* tests/examples/1[0-9]_*/old.*";
my $parity_pass = 0;
my $parity_total = 0;
for my $old_path (@examples) {
    my $new_path = $old_path;
    $new_path =~ s/old\./new./;
    next unless -f $new_path;
    system("AD_LEFT_TO_RIGHT=1 ./bin/ad_compute '$old_path' '$new_path' /tmp/lt_ldip_raw.txt 2>/dev/null");
    next unless -s "/tmp/lt_ldip_raw.txt";
    system("./bin/ad_layer_reorder < /tmp/lt_ldip_raw.txt > /tmp/lt_ldip_reord.txt 2>/dev/null");
    $parity_total++;
    my $c_res = `./bin/ad_layer_line_delete_in_place < /tmp/lt_ldip_reord.txt 2>/dev/null`;
    my $pl_res = `perl layers/perl/ad_layer_line_delete_in_place.pl < /tmp/lt_ldip_reord.txt 2>/dev/null`;
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
