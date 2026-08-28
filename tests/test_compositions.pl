#!/usr/bin/env perl
# test_compositions.pl - Test compositions of the new unified options.
#
# This test verifies that the new unified options work correctly when
# combined with each other and with the existing options. It tests
# every 2-way combination of the 6 unified selectors, plus selected
# 3-way and 4-way combinations.

use strict;
use warnings;
use Time::HiRes qw(alarm);

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

sub run_with_timeout {
    my ($cmd, $timeout) = @_;
    $timeout //= 5;
    my $output = '';
    eval {
        local $SIG{ALRM} = sub { die "timeout\n" };
        alarm $timeout;
        $output = `$cmd 2>&1`;
        alarm 0;
    };
    if ($@ && $@ eq "timeout\n") {
        return "<TIMEOUT>";
    }
    return $output;
}

my $DIFFVIM = './diffvim';
my $OLD = 'tests/examples/01_small_python/old.py';
my $NEW = 'tests/examples/01_small_python/new.py';

sub runs_ok {
    my ($label, $args) = @_;
    my $out = run_with_timeout("$DIFFVIM $args --dry-run $OLD $NEW", 5);
    ok($label, $out =~ /---/);
}

# =====================================================================
# 2-way compositions: every pair of unified selectors
# =====================================================================
print "=== 2-way compositions ===\n";

# --op-order × --delete-pacing
for my $op (qw(natural optimize left-to-right end-first end-first-smart overwrite)) {
    for my $dp (qw(char rapid-eol word instant)) {
        runs_ok("--op-order $op + --delete-pacing $dp",
            "--op-order $op --delete-pacing $dp");
    }
}

# --op-order × --insert-pacing
for my $op (qw(natural optimize left-to-right overwrite)) {
    for my $ip (qw(char word accel)) {
        runs_ok("--op-order $op + --insert-pacing $ip",
            "--op-order $op --insert-pacing $ip");
    }
}

# --op-order × --pacing
for my $op (qw(natural optimize left-to-right end-first-smart)) {
    for my $p (qw(uniform adaptive gaussian review)) {
        runs_ok("--op-order $op + --pacing $p",
            "--op-order $op --pacing $p");
    }
}

# --op-order × --highlight
for my $op (qw(optimize left-to-right end-first-smart overwrite)) {
    for my $h (qw(none inline word hunk)) {
        runs_ok("--op-order $op + --highlight $h",
            "--op-order $op --highlight $h");
    }
}

# --delete-pacing × --insert-pacing
for my $dp (qw(char rapid-eol word instant)) {
    for my $ip (qw(char word accel)) {
        runs_ok("--delete-pacing $dp + --insert-pacing $ip",
            "--delete-pacing $dp --insert-pacing $ip");
    }
}

# --delete-pacing × --pacing
for my $dp (qw(char rapid-eol word instant)) {
    for my $p (qw(uniform adaptive gaussian)) {
        runs_ok("--delete-pacing $dp + --pacing $p",
            "--delete-pacing $dp --pacing $p");
    }
}

# --delete-pacing × --highlight
for my $dp (qw(char rapid-eol word instant)) {
    for my $h (qw(none inline word hunk)) {
        runs_ok("--delete-pacing $dp + --highlight $h",
            "--delete-pacing $dp --highlight $h");
    }
}

# --insert-pacing × --pacing
for my $ip (qw(char word accel)) {
    for my $p (qw(uniform adaptive gaussian review)) {
        runs_ok("--insert-pacing $ip + --pacing $p",
            "--insert-pacing $ip --pacing $p");
    }
}

# --insert-pacing × --highlight
for my $ip (qw(char word accel)) {
    for my $h (qw(none inline word hunk)) {
        runs_ok("--insert-pacing $ip + --highlight $h",
            "--insert-pacing $ip --highlight $h");
    }
}

# --pacing × --highlight
for my $p (qw(uniform adaptive gaussian review)) {
    for my $h (qw(none inline word hunk)) {
        runs_ok("--pacing $p + --highlight $h",
            "--pacing $p --highlight $h");
    }
}

# =====================================================================
# 3-way compositions: selected triples
# =====================================================================
print "\n=== 3-way compositions ===\n";

# The "review preset" combination
runs_ok("review combo: --pacing review --highlight hunk --op-order left-to-right",
    "--pacing review --highlight hunk --op-order left-to-right");

# The "ai-code preset" combination
runs_ok("ai-code combo: --op-order end-first-smart --highlight inline --insert-pacing word",
    "--op-order end-first-smart --highlight inline --insert-pacing word");

# The "fast-delete preset" combination
runs_ok("fast-delete combo: --delete-pacing word --delete-speed fast --op-order optimize",
    "--delete-pacing word --delete-speed fast --op-order optimize");

# The "demo preset" combination
runs_ok("demo combo: --pacing gaussian --highlight inline --insert-pacing word",
    "--pacing gaussian --highlight inline --insert-pacing word");

# The "presentation preset" combination
runs_ok("presentation combo: --pacing uniform --highlight none --op-order optimize",
    "--pacing uniform --highlight none --op-order optimize");

# =====================================================================
# 4-way compositions: all unified selectors at once
# =====================================================================
print "\n=== 4-way compositions ===\n";

runs_ok("all 4: --op-order optimize --delete-pacing rapid-eol --insert-pacing char --pacing uniform",
    "--op-order optimize --delete-pacing rapid-eol --insert-pacing char --pacing uniform");

runs_ok("all 4: --op-order end-first-smart --delete-pacing word --insert-pacing word --pacing review",
    "--op-order end-first-smart --delete-pacing word --insert-pacing word --pacing review");

runs_ok("all 4: --op-order overwrite --delete-pacing instant --insert-pacing accel --pacing adaptive",
    "--op-order overwrite --delete-pacing instant --insert-pacing accel --pacing adaptive");

# =====================================================================
# 5-way: all unified + --highlight
# =====================================================================
print "\n=== 5-way compositions ===\n";

runs_ok("all 5: full review preset",
    "--op-order left-to-right --delete-pacing word --insert-pacing word --pacing review --highlight hunk");

runs_ok("all 5: full ai-code preset",
    "--op-order end-first-smart --delete-pacing word --insert-pacing accel --pacing adaptive --highlight inline");

# =====================================================================
# Unified + legacy options (mixed)
# =====================================================================
print "\n=== Unified + legacy options ===\n";

runs_ok("--op-order optimize + --semantic-cleanup",
    "--op-order optimize --semantic-cleanup");

runs_ok("--delete-pacing word + --word-diff",
    "--delete-pacing word --word-diff");

runs_ok("--insert-pacing word + --word-diff",
    "--insert-pacing word --word-diff");

runs_ok("--pacing adaptive + --speed 2",
    "--pacing adaptive --speed 2");

runs_ok("--highlight hunk + --dim-unchanged",
    "--highlight hunk --dim-unchanged");

runs_ok("--op-order left-to-right + --algorithm patience",
    "--op-order left-to-right --algorithm patience");

# =====================================================================
# Speed and threshold combinations
# =====================================================================
print "\n=== Speed and threshold ===\n";

runs_ok("--delete-speed fast + --delete-threshold 5",
    "--delete-speed fast --delete-threshold 5");

runs_ok("--delete-speed instant + --insert-speed fast",
    "--delete-speed instant --insert-speed fast");

runs_ok("--delete-threshold 10 + --delete-pacing word",
    "--delete-threshold 10 --delete-pacing word");

# =====================================================================
# Multiple example files (correctness)
# =====================================================================
print "\n=== Correctness across examples ===\n";

for my $ex (qw(01_small_python 02_large_python 06_typescript 08_rust_code 33_large_python)) {
    my $old = `ls tests/examples/$ex/old.* 2>/dev/null | head -1`; chomp $old;
    my $new = `ls tests/examples/$ex/new.* 2>/dev/null | head -1`; chomp $new;
    next unless $old && $new;
    my $out = run_with_timeout("$DIFFVIM --op-order end-first-smart --delete-pacing word --insert-pacing word --pacing review --highlight hunk --dry-run $old $new", 10);
    ok("full combo produces diff for $ex", $out =~ /---/);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
