#!/usr/bin/env perl
# test_highlight_resolution.pl - Verify that --highlight MODE correctly
# sets the underlying env vars that the vimscript engine reads.
#
# Bug being tested: The highlight resolution block was placed AFTER
# the export block, so DIFFVIM_HIGHLIGHT_WORD/HUNK/INLINE were exported
# as empty (0) before the resolution set the shell variables to 1.
#
# We verify this by checking the line numbers in the diffvim script:
# the resolution block must come BEFORE the export lines.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Read the diffvim script
open my $fh, '<', 'diffvim' or die "Cannot open diffvim: $!";
my @lines = <$fh>;
close $fh;

# Find line numbers (1-indexed) for key sections
my ($resolve_line, $export_hunk, $export_word, $export_inline);

for my $i (0 .. $#lines) {
    my $line = $i + 1;  # 1-indexed
    if ($lines[$i] =~ /^# Resolve --highlight into the individual/) {
        $resolve_line = $line;
    }
    if ($lines[$i] =~ /^export DIFFVIM_HIGHLIGHT_HUNK=/) {
        $export_hunk = $line;
    }
    if ($lines[$i] =~ /^export DIFFVIM_HIGHLIGHT_WORD=/) {
        $export_word = $line;
    }
    if ($lines[$i] =~ /^export DIFFVIM_INLINE_HIGHLIGHT=/) {
        $export_inline = $line;
    }
}

ok('Resolution block found', defined $resolve_line);
ok('Export HIGHLIGHT_HUNK found', defined $export_hunk);
ok('Export HIGHLIGHT_WORD found', defined $export_word);
ok('Export INLINE_HIGHLIGHT found', defined $export_inline);

if (defined $resolve_line) {
    ok('Resolution before export HIGHLIGHT_HUNK',
       defined $export_hunk && $resolve_line < $export_hunk);
    ok('Resolution before export HIGHLIGHT_WORD',
       defined $export_word && $resolve_line < $export_word);
    ok('Resolution before export INLINE_HIGHLIGHT',
       defined $export_inline && $resolve_line < $export_inline);
}

# Also verify the same for all other unified selectors
my %resolution_blocks;
my %export_lines;

for my $i (0 .. $#lines) {
    my $line = $i + 1;
    if ($lines[$i] =~ /^# Resolve (--[a-z-]+) into the individual/) {
        $resolution_blocks{$1} = $line;
    }
}

# Check that all resolution blocks are before line 770 (the export block start)
for my $name (sort keys %resolution_blocks) {
    my $line = $resolution_blocks{$name};
    ok("$name resolution at line $line (before exports)", $line < 770);
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
