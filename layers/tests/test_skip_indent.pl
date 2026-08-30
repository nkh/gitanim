#!/usr/bin/env perl
# test_skip_indent.pl — Test the ad_layer_skip_indent layer.
#
# Verifies:
#   1. The layer is invokable standalone.
#   2. Indent-only hunks get wrapped with skip markers.
#   3. Non-indent hunks pass through unchanged.
#   4. C and Perl implementations produce identical output (parity).
#
# Usage: perl layers/tests/test_skip_indent.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Setup: input with an indent-only hunk and a content hunk --------
# Hunk 1: indent-only (delete 4 spaces, insert 8 spaces)
# Hunk 2: content change (delete 'x', insert 'y')
my $input = <<'EOF';
# diffvim post-processed v2
HUNK	2	1	1	0	0
delete	2	1	32	space
delete	2	2	32	space
delete	2	3	32	space
delete	2	4	32	space
insert	2	1	32	space
insert	2	2	32	space
insert	2	3	32	space
insert	2	4	32	space
insert	2	5	32	space
insert	2	6	32	space
insert	2	7	32	space
insert	2	8	32	space
keep	2	5	102	f
HUNK_END
HUNK	4	1	1	0	0
delete	4	1	120	x
insert	4	1	121	y
keep	4	2	10	\n
HUNK_END
EOF

my $in_file = "/tmp/lt_si_in.txt";
open(my $fh, '>', $in_file) or die; print $fh $input; close($fh);

# --- Test 1: layer is invokable (C) -----------------------------------
system("./bin/ad_layer_skip_indent < $in_file > /tmp/lt_si_c.out 2>/dev/null");
if ($? == 0 && -s "/tmp/lt_si_c.out") {
    ok "C ad_layer_skip_indent runs standalone";
} else {
    bad "C ad_layer_skip_indent failed to run";
}

# --- Test 2: indent-only hunk gets skip markers -----------------------
my $output = "";
open($fh, '<', "/tmp/lt_si_c.out") or die;
while (my $line = <$fh>) { $output .= $line; }
close($fh);

# The first hunk should be wrapped with delay markers (line=-1).
# Check for the marker: delay\t-1\t0\t0 (start) and delay\t-1\t1\t300 (end)
if ($output =~ /delay\t-1\t0\t0/) {
    ok "indent_skip_start marker found (delay with line=-1, col=0)";
} else {
    bad "indent_skip_start marker not found";
}

if ($output =~ /delay\t-1\t1\t300/) {
    ok "indent_skip_end marker found (delay with line=-1, col=1, code=300)";
} else {
    bad "indent_skip_end marker not found";
}

# --- Test 3: content hunk passes through unchanged -------------------
# The second hunk should NOT have skip markers.
my @hunks = split /HUNK_END/, $output;
if (@hunks >= 2) {
    my $second_hunk = $hunks[1];
    if ($second_hunk !~ /delay\t-1/) {
        ok "content hunk (hunk 2) has no skip markers (correct)";
    } else {
        bad "content hunk (hunk 2) should not have skip markers";
    }
} else {
    bad "expected 2 hunks, got " . scalar(@hunks);
}

# --- Test 4: C and Perl parity ---------------------------------------
system("perl layers/perl/ad_layer_skip_indent.pl < $in_file > /tmp/lt_si_pl.out 2>/dev/null");
my $pl_output = "";
open($fh, '<', "/tmp/lt_si_pl.out") or die;
while (my $line = <$fh>) { $pl_output .= $line; }
close($fh);
if ($output eq $pl_output) {
    ok "C and Perl ad_layer_skip_indent produce identical output (parity)";
} else {
    bad "C and Perl ad_layer_skip_indent differ";
    print "C output:\n$output\n";
    print "Perl output:\n$pl_output\n";
}

# --- Test 5: --pause-after-ms option ---------------------------------
system("./bin/ad_layer_skip_indent --pause-after-ms 500 < $in_file > /tmp/lt_si_pause.out 2>/dev/null");
my $pause_output = "";
open($fh, '<', "/tmp/lt_si_pause.out") or die;
while (my $line = <$fh>) { $pause_output .= $line; }
close($fh);
if ($pause_output =~ /delay\t-1\t1\t500/) {
    ok "--pause-after-ms 500 changes the end marker code to 500";
} else {
    bad "--pause-after-ms did not change the pause value";
}

# --- Final summary ----------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail > 0 ? 1 : 0);
