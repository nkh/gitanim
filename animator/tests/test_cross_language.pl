#!/usr/bin/env perl
# test_cross_language.pl — Cross-language parity tests.
# Verifies that the C and Perl implementations of postprocess and pace
# produce byte-for-byte identical output. (Go versions were removed in
# the refactor — only C and Perl remain.)

use strict;
use warnings;
use File::Temp qw(tempdir);

my $root = "/home/z/my-project/gitanim";
my $compute = "$root/compute/bin/diffvim-compute-cpp";

# Tool implementations — only C and Perl remain.
my %postprocess = (
    perl => "perl $root/animator/perl/postprocess.pl",
    c    => "$root/animator/bin/diffvim-postprocess",
);

my %pace = (
    perl => "perl $root/animator/perl/pace.pl",
    c    => "$root/animator/bin/diffvim-pace",
);

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

my @cases = (
    ['simple', "hello\n", "hello world\n"],
    ['multi-line delete', "line1\nline2\nline3\n", "line1\nline3\n"],
    ['python func', "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n",
                    "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"],
    ['indent change', "def foo():\n    x = 1\n", "def foo():\n        x = 1\n"],
    ['unicode', "x = \"caf\xc3\xa9\"\n", "x = \"coffee\"\n"],
);

my $tmpdir = tempdir(CLEANUP => 1);

for my $case (@cases) {
    my ($name, $old, $new) = @$case;
    my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
    my $rf = "$tmpdir/raw.txt";

    open my $fh, '>:raw', $of; print $fh $old; close $fh;
    open $fh, '>:raw', $nf; print $fh $new; close $fh;
    system("$compute '$of' '$nf' '$rf' 2>/dev/null");

    # --- Postprocess parity ---
    my %post_out;
    for my $lang (keys %postprocess) {
        my $out_file = "$tmpdir/post_$lang.txt";
        system("$postprocess{$lang} --op-order optimize < '$rf' 2>/dev/null > '$out_file'");
        open $fh, '<:raw', $out_file; $post_out{$lang} = do { local $/; <$fh> }; close $fh;
    }

    ok("postprocess: $name — C==Perl", $post_out{c} eq $post_out{perl});

    # --- Pace parity ---
    my %pace_out;
    for my $lang (keys %pace) {
        my $out_file = "$tmpdir/pace_$lang.txt";
        system("$pace{$lang} --delete-pacing word < '$tmpdir/post_perl.txt' 2>/dev/null > '$out_file'");
        open $fh, '<:raw', $out_file; $pace_out{$lang} = do { local $/; <$fh> }; close $fh;
    }

    ok("pace: $name — C==Perl", $pace_out{c} eq $pace_out{perl});
}

# --- Test different pacing modes ---
print "\n=== Pacing mode parity ===\n";
my $of = "$tmpdir/old.txt"; my $nf = "$tmpdir/new.txt";
my $rf = "$tmpdir/raw.txt"; my $pf = "$tmpdir/post.txt";
open my $fh, '>:raw', $of; print $fh "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n"; close $fh;
open $fh, '>:raw', $nf; print $fh "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n"; close $fh;
system("$compute '$of' '$nf' '$rf' 2>/dev/null");
system("$postprocess{perl} --op-order optimize < '$rf' 2>/dev/null > '$pf'");

for my $mode (qw(char rapid-eol word instant)) {
    my %out;
    for my $lang (keys %pace) {
        my $out_file = "$tmpdir/pace_${lang}_$mode.txt";
        system("$pace{$lang} --delete-pacing $mode < '$pf' 2>/dev/null > '$out_file'");
        open $fh, '<:raw', $out_file; $out{$lang} = do { local $/; <$fh> }; close $fh;
    }
    ok("pace --delete-pacing $mode: C==Perl", $out{c} eq $out{perl});
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
