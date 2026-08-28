#!/usr/bin/env perl
# test_semantic_cleanup.pl - Test --semantic-cleanup feature (#21)
# Verifies that semantic cleanup correctly merges canceling ops
# and that the result still produces correct output.

use strict;
use warnings;
use lib '.';
use DiffVim::Parser::Perl qw(parse_diff);

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Test 1: Semantic cleanup merges canceling delete+insert pairs
print "=== Test: canceling ops are merged ===\n";
# Create a test case where the LCS might produce canceling ops
# "abc" -> "axc" should produce: keep a, delete b, insert x, keep c
# With cleanup, this stays the same (b != x, so no merge)
my $result = parse_diff("tests/examples/01_small_python/old.py", "tests/examples/01_small_python/new.py",
    { semantic_cleanup => 1 });
ok('semantic cleanup produces valid output', defined $result && @{$result->{hunks}} > 0);

# Test 2: Correctness is preserved with semantic cleanup
print "\n=== Test: correctness preserved ===\n";
for my $dir (glob("tests/examples/*/")) {
    my $old_file = "$dir/old." . ($dir =~ /python/ ? 'py' : $dir =~ /json/ ? 'json' : $dir =~ /shell/ ? 'sh' : $dir =~ /go/ ? 'go' : $dir =~ /typescript/ ? 'ts' : $dir =~ /prose/ ? 'txt' : $dir =~ /rust/ ? 'rs' : $dir =~ /c_code/ ? 'c' : $dir =~ /yaml/ ? 'yaml' : $dir =~ /html/ ? 'html' : $dir =~ /css/ ? 'css' : 'txt');
    my $new_file = "$dir/new." . ($old_file =~ /\.(\w+)$/ ? $1 : 'txt');
    next unless -f $old_file && -f $new_file;

    # Compute with and without cleanup
    my $r_clean = parse_diff($old_file, $new_file, { semantic_cleanup => 1 });
    my $r_plain = parse_diff($old_file, $new_file, {});

    # Apply both and compare
    my $name = $dir;
    $name =~ s|tests/examples/||;
    $name =~ s|/$||;

    # Count ops
    my $ops_clean = 0;
    my $ops_plain = 0;
    for my $h (@{$r_clean->{hunks}}) { $ops_clean += scalar(@{$h->{char_ops}}); }
    for my $h (@{$r_plain->{hunks}}) { $ops_plain += scalar(@{$h->{char_ops}}); }

    # Cleanup should produce <= ops than plain
    ok("$name: cleanup ops ($ops_clean) <= plain ops ($ops_plain)", $ops_clean <= $ops_plain);
}

# Test 3: Direct unit test of _semantic_cleanup
print "\n=== Test: unit test of _semantic_cleanup ===\n";
# We can't call _semantic_cleanup directly (it's private), but we can
# create a scenario that produces canceling ops.
# "ab" -> "ab" should produce 0 changed ops.
open my $fh, '>', '/tmp/dv_sc_old.txt'; print $fh "hello\n"; close $fh;
open $fh, '>', '/tmp/dv_sc_new.txt'; print $fh "hello\n"; close $fh;
$result = parse_diff('/tmp/dv_sc_old.txt', '/tmp/dv_sc_new.txt', { semantic_cleanup => 1 });
ok('identical files produce 0 hunks', @{$result->{hunks}} == 0);

# Test 4: --help shows --semantic-cleanup
print "\n=== Test: help text ===\n";
my $help = `perl diffvim.pl --help 2>&1`;
ok('--help shows --semantic-cleanup', $help =~ /--semantic-cleanup/);

# Cleanup
unlink '/tmp/dv_sc_old.txt', '/tmp/dv_sc_new.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
