#!/usr/bin/env perl
# test_streaming.pl — Verify --stream produces the same output as batch mode.
use strict;
use warnings;

my $root = "/home/z/my-project/gitanim";
my $pass = 0;
my $fail = 0;

for my $ex (qw(01_small_python 07_text_prose 32_python_classes)) {
    my $old = (glob("$root/tests/tests/examples/$ex/old.*"))[0];
    my $new = (glob("$root/tests/tests/examples/$ex/new.*"))[0];
    
    system("$root/bin/ad_compute '$old' '$new' /tmp/raw.txt 2>/dev/null");
    
    # Batch mode
    system("$root/bin/ad_postprocess < /tmp/raw.txt > /tmp/batch.txt 2>/dev/null");
    
    # Stream mode
    system("$root/bin/ad_postprocess --stream < /tmp/raw.txt > /tmp/stream.txt 2>/dev/null");
    
    # Compare (ignore hunk_count and hunk_end differences)
    my $batch = `grep -v 'hunk_count\\|hunk_end' /tmp/batch.txt`;
    my $stream = `grep -v 'hunk_count\\|hunk_end' /tmp/stream.txt`;
    
    if ($batch eq $stream) {
        $pass++;
    } else {
        $fail++;
        print "FAIL: $ex\n";
    }
}

print "\n=== Streaming: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
