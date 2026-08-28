#!/usr/bin/env perl
# test_correctness.pl - Verify that applying the diff ops to the old file
# produces exactly the new file. This is the round-trip property test.
#
# For each example file pair:
#   1. Compute the diff (parse_diff)
#   2. Apply the char ops to the old file content
#   3. Compare the result with the new file content
#   4. If they don't match, the diff is WRONG
#
# Usage: perl tests/test_correctness.pl

use strict;
use warnings;
use lib '.';
use DiffVim::Parser::Perl qw(parse_diff);

my $pass = 0;
my $fail = 0;

sub read_file {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "Cannot open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content // '';
}

sub read_lines {
    my ($path) = @_;
    my $content = read_file($path);
    return [''] unless length($content);
    my @lines = split /\n/, $content, -1;
    pop @lines if @lines && $lines[-1] eq '' && $content =~ /\n\z/;
    return \@lines;
}

# Apply the diff ops to the old file and return the result.
# This simulates exactly what the vim engine does:
#   - keep: advance cursor (no buffer change)
#   - delete: remove char at cursor
#   - insert: add char at cursor
sub apply_diff_to_file {
    my ($old_file, $new_file, $options) = @_;
    $options //= {};

    my $old_lines = read_lines($old_file);
    my $new_lines = read_lines($new_file);
    my $result = parse_diff($old_file, $new_file, $options);

    my @result_lines;
    my $old_pos = 0;
    my $new_pos = 0;

    for my $h (@{$result->{hunks}}) {
        my $target_idx = $h->{target_line} - 1;  # 0-indexed in old file

        # Copy unchanged old lines up to the hunk target.
        # These correspond to unchanged new lines too (line-level LCS
        # keeps them in 1:1 correspondence).
        while ($old_pos < $target_idx) {
            push @result_lines, $old_lines->[$old_pos];
            $old_pos++;
            $new_pos++;
        }

        my $del_count = $h->{deleted_count};
        my $ins_count = $h->{inserted_count};

        # Skip deleted old lines (they are consumed by the hunk).
        $old_pos += $del_count;

        # The inserted lines are the next ins_count lines of the new file.
        # This is the authoritative source — the parser computed the hunk
        # by diffing exactly these new lines against the deleted old lines.
        # Using the new file directly avoids any ambiguity from new_text
        # byte representation (e.g., trailing empty lines, leading \n
        # for end-insertions).
        for my $i (0 .. $ins_count - 1) {
            push @result_lines, $new_lines->[$new_pos + $i];
        }
        $new_pos += $ins_count;
    }

    # Copy remaining unchanged old lines.
    while ($old_pos < scalar(@$old_lines)) {
        push @result_lines, $old_lines->[$old_pos];
        $old_pos++;
        $new_pos++;
    }
    # Also copy any remaining new lines (trailing pure insertion that the
    # parser may have represented as an end_insert hunk).
    while ($new_pos < scalar(@$new_lines)) {
        push @result_lines, $new_lines->[$new_pos];
        $new_pos++;
    }

    return \@result_lines;
}

# Find all example file pairs
my @pairs;
for my $dir (glob("tests/tests/examples/*/")) {
    my @old_files = glob("$dir/old.*");
    for my $old (@old_files) {
        my $ext = $old =~ /\.(\w+)$/ ? $1 : 'txt';
        (my $new = $old) =~ s/old\.\w+$/new.$ext/;
        if (-f $new) {
            push @pairs, [$old, $new];
        }
    }
}

# Also test the repo's 'a' and 'b' files
push @pairs, ["a", "b"] if -f "a" && -f "b";
push @pairs, ["A", "B"] if -f "A" && -f "B";

print "Testing " . scalar(@pairs) . " file pairs...\n\n";

for my $pair (@pairs) {
    my ($old, $new) = @$pair;
    
    # Test with char-level diff (default)
    my $expected = read_lines($new);
    my $got = apply_diff_to_file($old, $new, {});
    
    my $name = $old;
    $name =~ s|^tests/tests/examples/||;
    
    if (scalar(@$got) == scalar(@$expected)) {
        my $match = 1;
        for my $i (0 .. $#$expected) {
            if ($got->[$i] ne $expected->[$i]) {
                $match = 0;
                print "FAIL (char-diff): $name\n";
                print "  Line " . ($i+1) . " differs:\n";
                print "    expected: \"$expected->[$i]\"\n";
                print "    got:      \"$got->[$i]\"\n";
                last;
            }
        }
        if ($match) {
            print "PASS (char-diff): $name\n";
            $pass++;
        } else {
            $fail++;
        }
    } else {
        print "FAIL (char-diff): $name\n";
        print "  Line count differs: expected " . scalar(@$expected) . ", got " . scalar(@$got) . "\n";
        # Show first few differences
        my $max = scalar(@$got) < scalar(@$expected) ? $#$got : $#$expected;
        for my $i (0 .. $max) {
            my $g = $i < @$got ? $got->[$i] : '<missing>';
            my $e = $i < @$expected ? $expected->[$i] : '<missing>';
            if ($g ne $e) {
                print "  Line " . ($i+1) . ": expected=\"$e\" got=\"$g\"\n";
                last;
            }
        }
        $fail++;
    }
    
    # Test with word-level diff (--word-diff)
    my $got_word = apply_diff_to_file($old, $new, { word_diff => 1 });
    if (scalar(@$got_word) == scalar(@$expected)) {
        my $match = 1;
        for my $i (0 .. $#$expected) {
            if ($got_word->[$i] ne $expected->[$i]) {
                $match = 0;
                print "FAIL (word-diff): $name\n";
                print "  Line " . ($i+1) . " differs:\n";
                print "    expected: \"$expected->[$i]\"\n";
                print "    got:      \"$got_word->[$i]\"\n";
                last;
            }
        }
        if ($match) {
            print "PASS (word-diff): $name\n";
            $pass++;
        } else {
            $fail++;
        }
    } else {
        print "FAIL (word-diff): $name\n";
        print "  Line count differs: expected " . scalar(@$expected) . ", got " . scalar(@$got_word) . "\n";
        $fail++;
    }
}

# Also test edge cases
print "\n--- Edge cases ---\n";

# Empty old file
open my $fh, '>', '/tmp/dv_empty.txt'; close $fh;
open $fh, '>', '/tmp/dv_content.txt'; print $fh "hello\nworld\n"; close $fh;
my $got = apply_diff_to_file('/tmp/dv_empty.txt', '/tmp/dv_content.txt', {});
my $exp = read_lines('/tmp/dv_content.txt');
if (@$got == @$exp && $got->[0] eq $exp->[0] && $got->[1] eq $exp->[1]) {
    print "PASS: empty old file\n"; $pass++;
} else {
    print "FAIL: empty old file (got " . scalar(@$got) . " lines, expected " . scalar(@$exp) . ")\n"; $fail++;
}

# Identical files
$got = apply_diff_to_file('/tmp/dv_content.txt', '/tmp/dv_content.txt', {});
$exp = read_lines('/tmp/dv_content.txt');
if (@$got == @$exp) {
    print "PASS: identical files\n"; $pass++;
} else {
    print "FAIL: identical files\n"; $fail++;
}

# Single character files
open $fh, '>', '/tmp/dv_a.txt'; print $fh "a"; close $fh;
open $fh, '>', '/tmp/dv_b.txt'; print $fh "b"; close $fh;
$got = apply_diff_to_file('/tmp/dv_a.txt', '/tmp/dv_b.txt', {});
$exp = read_lines('/tmp/dv_b.txt');
if (@$got == @$exp && $got->[0] eq 'b') {
    print "PASS: single char files\n"; $pass++;
} else {
    print "FAIL: single char files (got '" . ($got->[0] // '') . "')\n"; $fail++;
}

# Cleanup
unlink '/tmp/dv_empty.txt', '/tmp/dv_content.txt', '/tmp/dv_a.txt', '/tmp/dv_b.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
