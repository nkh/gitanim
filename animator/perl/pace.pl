#!/usr/bin/env perl
# diffvim-pace — Transforms ordered char ops into a timed op stream.
#
# PACE ONLY HANDLES PACING (delays + batching). Cursor positioning is
# done by POSTPROCESS, which embeds (line, col) in every op. The
# animator reads positions directly from ops; pace just adds timing.
#
# Input: TSV op stream from diffvim-postprocess:
#   hunk_start\t<del>\t<ins>
#   op\tkeep|delete|insert\t<line>\t<col>\t<code>
#   newline_delete\t<line>
#   newline_insert\t<line>\t<col>
#
# Output: same op stream with delays and batch operations inserted:
#   delay\t<ms>
#   batch_delete\t<line>\t<col>\t<count>
#   batch_insert\t<line>\t<col>\t<code1>\t<code2>\t...
#
# Usage:
#   diffvim-pace [options] < ordered_ops > timed_ops
#
# Options:
#   --delete-pacing char|rapid-eol|rapid-identical|accel|word|instant
#       (default: word)
#   --delete-speed slow|normal|fast|instant   (default: normal)
#   --delete-threshold N                     (default: 3)
#   --insert-pacing char|word|accel          (default: char)
#   --insert-speed slow|normal|fast          (default: normal)
#   --pacing uniform|adaptive|gaussian|review (default: uniform)
#   --snapshot FILE   Insert a snapshot op at the end
#   --help, -h        Show help

use strict;
use warnings;
use Getopt::Long qw(GetOptions);

my $delete_pacing = 'word';
my $delete_speed = 'normal';
my $delete_threshold = 3;
my $insert_pacing = 'char';
my $insert_speed = 'normal';
my $pacing = 'uniform';
my $snapshot_file;
my $help = 0;

GetOptions(
    'delete-pacing=s'  => \$delete_pacing,
    'delete-speed=s'    => \$delete_speed,
    'delete-threshold=i' => \$delete_threshold,
    'insert-pacing=s'   => \$insert_pacing,
    'insert-speed=s'    => \$insert_speed,
    'pacing=s'          => \$pacing,
    'snapshot=s'        => \$snapshot_file,
    'help|h'            => \$help,
) or die "Usage: $0 [options]\n  Run '$0 --help' for details.\n";

if ($help) {
    print STDERR <<USAGE;
diffvim-pace — Transform ordered ops into a timed op stream (TSV v2)

Usage: diffvim-pace [options] < ordered_ops > timed_ops

Options:
  --delete-pacing char|rapid-eol|rapid-identical|accel|word|instant
                           Deletion strategy (default: word)
  --delete-speed slow|normal|fast|instant
                           Deletion speed (default: normal)
  --delete-threshold N     Min chars for rapid/word modes (default: 3)
  --insert-pacing char|word|accel
                           Insertion strategy (default: char)
  --insert-speed slow|normal|fast
                           Insertion speed (default: normal)
  --pacing uniform|adaptive|gaussian|review
                           Timing mode (default: uniform)
  --snapshot FILE          Insert a snapshot op at the end
  -h, --help               Show this help

Example:
  diffvim-compute-cpp old.py new.py raw.txt
  diffvim-postprocess < raw.txt | diffvim-pace --delete-pacing word |
    diffvim-animator-c old.py
USAGE
    exit 0;
}

# Validate options
my %valid_dp = map { $_ => 1 } qw(char rapid-eol rapid-identical accel word instant);
die "Invalid --delete-pacing '$delete_pacing'\n" unless $valid_dp{$delete_pacing};
my %valid_ds = map { $_ => 1 } qw(slow normal fast instant);
die "Invalid --delete-speed '$delete_speed'\n" unless $valid_ds{$delete_speed};
my %valid_ip = map { $_ => 1 } qw(char word accel);
die "Invalid --insert-pacing '$insert_pacing'\n" unless $valid_ip{$insert_pacing};
my %valid_is = map { $_ => 1 } qw(slow normal fast);
die "Invalid --insert-speed '$insert_speed'\n" unless $valid_is{$insert_speed};
my %valid_p = map { $_ => 1 } qw(uniform adaptive gaussian review);
die "Invalid --pacing '$pacing'\n" unless $valid_p{$pacing};

# Default timing values (ms)
my $type_delay = 50;
my $delete_delay = 40;
my $hunk_pause = 250;
my $rapid_eol_delay = 80;
my $rapid_eol_min = $delete_threshold;
my $awd_start_chars = 3;
my $awd_start_ms = 80;
my $awd_min_ms = 15;
my $awd_accel = 0.85;
my $awd_word_pause = 100;
my $word_pause = 150;

# Apply speed multipliers
if ($delete_speed eq 'fast') {
    $delete_delay = int($delete_delay / 2);
    $awd_start_ms = int($awd_start_ms / 2);
} elsif ($delete_speed eq 'instant') {
    $delete_delay = 1;
    $awd_start_ms = 1;
    $awd_min_ms = 1;
}
if ($insert_speed eq 'fast') {
    $type_delay = int($type_delay / 2);
    $word_pause = int($word_pause / 2);
} elsif ($insert_speed eq 'slow') {
    $type_delay = int($type_delay * 2);
    $word_pause = int($word_pause * 2);
}

# Read input — TSV format from postprocess.
# Each op carries (line, col). We pass them through unchanged and just
# insert delays + batching around them.
my @hunks;
my $current_hunk;

while (my $line = <STDIN>) {
    chomp $line;
    next if $line =~ /^#/;
    next if $line eq '';
    my @toks = split /\t/, $line;
    my $cmd = shift @toks // '';

    if ($cmd eq 'hunk_start') {
        my ($del, $ins) = @toks;
        $current_hunk = {
            del_count => $del + 0,
            ins_count => $ins + 0,
            ops       => [],
        };
        push @hunks, $current_hunk;
        next;
    }
    if ($cmd eq 'op') {
        # op\t<type>\t<line>\t<col>\t<code>
        my ($type, $op_line, $op_col, $code) = @toks;
        push @{$current_hunk->{ops}}, {
            kind => 'op', type => $type, line => $op_line + 0,
            col => $op_col + 0, code => $code + 0
        };
        next;
    }
    if ($cmd eq 'newline_delete') {
        my ($op_line) = @toks;
        push @{$current_hunk->{ops}}, {
            kind => 'newline_delete', type => 'delete',
            line => $op_line + 0, col => 1, code => 10
        };
        next;
    }
    if ($cmd eq 'newline_insert') {
        my ($op_line, $op_col) = @toks;
        push @{$current_hunk->{ops}}, {
            kind => 'newline_insert', type => 'insert',
            line => $op_line + 0, col => $op_col + 0, code => 10
        };
        next;
    }
    # hunk_end, done — ignore
}

# Generate timed op stream
print "# timed op stream v2\n";
print "# format: TSV, every op carries (line, col) — 1-indexed\n";
print "# delays are typed: delay\t<type>\t<ms>\n";
print "# generated by: diffvim-pace --delete-pacing $delete_pacing --delete-speed $delete_speed --insert-pacing $insert_pacing --pacing $pacing\n";
print "# delete_threshold $delete_threshold\n";

for my $hunk_idx (0 .. $#hunks) {
    my $hunk = $hunks[$hunk_idx];
    my $ops = $hunk->{ops};

    printf "hunk_start\t%d\t%d\n", $hunk->{del_count}, $hunk->{ins_count};

    my $i = 0;
    while ($i < @$ops) {
        my $op = $ops->[$i];

        if ($op->{type} eq 'keep') {
            if ($op->{kind} eq 'op') {
                printf "op\tkeep\t%d\t%d\t%d\n", $op->{line}, $op->{col}, $op->{code};
                print "delay\tkeep\t1\n";
            }
            # newline keep would have been emitted as op by postprocess
            $i++;
        } elsif ($op->{type} eq 'delete') {
            if ($op->{code} == 10) {
                # newline_delete
                printf "newline_delete\t%d\n", $op->{line};
                print "delay\tnewline_delete\t$delete_delay\n";
                $i++;
            } else {
                # Non-newline delete: apply delete-pacing
                $i = process_delete($ops, $i, $delete_pacing,
                    $delete_delay, $rapid_eol_delay, $rapid_eol_min,
                    $awd_start_chars, $awd_start_ms, $awd_min_ms, $awd_accel,
                    $awd_word_pause);
            }
        } elsif ($op->{type} eq 'insert') {
            if ($op->{code} == 10) {
                # newline_insert
                printf "newline_insert\t%d\t%d\n", $op->{line}, $op->{col};
                print "delay\tnewline_insert\t$type_delay\n";
                $i++;
            } else {
                if ($insert_pacing eq 'word') {
                    # Batch short words
                    my $word_len = 0;
                    my $j = $i;
                    while ($j < @$ops && $ops->[$j]{type} eq 'insert' && $ops->[$j]{code} != 10
                           && $ops->[$j]{code} != 32) {
                        $word_len++;
                        $j++;
                    }
                    if ($word_len >= 2 && $word_len <= 8) {
                        printf "batch_insert\t%d\t%d", $ops->[$i]{line}, $ops->[$i]{col};
                        for my $k ($i .. $i + $word_len - 1) {
                            printf "\t%d", $ops->[$k]{code};
                        }
                        print "\n";
                        print "delay\tword_insert\t$word_pause\n";
                        $i += $word_len;
                    } else {
                        printf "op\tinsert\t%d\t%d\t%d\n", $op->{line}, $op->{col}, $op->{code};
                        print "delay\ttype\t$type_delay\n";
                        $i++;
                    }
                } else {
                    printf "op\tinsert\t%d\t%d\t%d\n", $op->{line}, $op->{col}, $op->{code};
                    print "delay\ttype\t$type_delay\n";
                    $i++;
                }
            }
        } else {
            $i++;
        }
    }

    print "hunk_end\n";
    print "delay\thunk_pause\t$hunk_pause\n" if $hunk_idx < $#hunks;
}

# Snapshot at end if requested
if ($snapshot_file) {
    print "snapshot\t$snapshot_file\n";
}

print "done\n";

# --- Pacing functions ---
#
# IMPORTANT: deletes do NOT advance the column. After deleting a char at
# col C, the next char (which was at col C+1) is now at col C. So all
# deletes in this run target the SAME (line, col) = ops[start].(line, col).

sub process_delete {
    my ($ops, $start, $pacing, $del_delay, $rapid_delay, $rapid_min,
        $awd_start_chars, $awd_start_ms, $awd_min_ms, $awd_accel, $awd_word_pause) = @_;

    # Count consecutive non-newline deletes
    my $count = 0;
    my $j = $start;
    while ($j < @$ops && $ops->[$j]{type} eq 'delete' && $ops->[$j]{code} != 10) {
        $count++;
        $j++;
    }

    return $start + 1 if $count == 0;

    my $cur_line = $ops->[$start]{line};
    my $cur_col  = $ops->[$start]{col};

    if ($pacing eq 'char') {
        printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$start]{code};
        print "delay\tdelete\t$del_delay\n";
        return $start + 1;
    }

    if ($pacing eq 'instant') {
        printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $count;
        print "delay\trapid_eol\t$rapid_delay\n";
        return $start + $count;
    }

    if ($pacing eq 'rapid-eol') {
        my $next_op = $j < @$ops ? $ops->[$j] : undef;
        my $at_eol = (!$next_op) || ($next_op->{type} eq 'keep' && $next_op->{code} == 10)
                      || ($next_op->{type} eq 'delete' && $next_op->{code} == 10);
        if ($at_eol && $count >= $rapid_min) {
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $count;
            print "delay\trapid_eol\t$rapid_delay\n";
            return $start + $count;
        }
        printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$start]{code};
        print "delay\tdelete\t$del_delay\n";
        return $start + 1;
    }

    if ($pacing eq 'rapid-identical') {
        my $first_code = $ops->[$start]{code};
        my $all_same = 1;
        for my $k ($start .. $start + $count - 1) {
            if ($ops->[$k]{code} != $first_code) {
                $all_same = 0;
                last;
            }
        }
        if ($all_same && $count >= $rapid_min) {
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $count;
            print "delay\trapid_eol\t$rapid_delay\n";
            return $start + $count;
        }
        printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$start]{code};
        print "delay\tdelete\t$del_delay\n";
        return $start + 1;
    }

    if ($pacing eq 'accel') {
        if ($count >= 2) {
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $count;
            print "delay\tawd_word\t$awd_min_ms\n";
            return $start + $count;
        }
        printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$start]{code};
        print "delay\tdelete\t$del_delay\n";
        return $start + 1;
    }

    if ($pacing eq 'word') {
        return process_awd($ops, $start, $count, $del_delay, $awd_start_chars,
            $awd_start_ms, $awd_min_ms, $awd_accel, $awd_word_pause);
    }

    # Default
    printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$start]{code};
    print "delay\tdelete\t$del_delay\n";
    return $start + 1;
}

sub process_awd {
    my ($ops, $start, $count, $del_delay, $start_chars, $start_ms, $min_ms, $accel, $word_pause) = @_;

    my $i = $start;
    my $end = $start + $count;
    my $cur_line = $ops->[$start]{line};
    my $cur_col  = $ops->[$start]{col};

    # Phase 1: Skip spaces instantly
    while ($i < $end && ($ops->[$i]{code} == 32 || $ops->[$i]{code} == 9)) {
        $i++;
    }
    if ($i > $start) {
        my $space_count = $i - $start;
        printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $space_count;
        print "delay\tawd_space\t$min_ms\n";
        # cur_col NOT incremented: deletes don't advance.
    }

    # Count non-space chars remaining
    my $remaining = $end - $i;
    if ($remaining <= $start_chars) {
        if ($remaining > 0) {
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $remaining;
            print "delay\tawd_word\t$min_ms\n";
        }
        return $start + $count;
    }

    # Phase 2: Delete start_chars slowly (one at a time)
    for my $k ($i .. $i + $start_chars - 1) {
        printf "op\tdelete\t%d\t%d\t%d\n", $cur_line, $cur_col, $ops->[$k]{code};
        print "delay\tawd_start\t$start_ms\n";
        # cur_col NOT incremented.
    }
    $i += $start_chars;

    # Phase 3: Delete words with acceleration
    my $delay = $start_ms;
    while ($i < $end) {
        # Find word boundary (non-space chars until space or end)
        my $word_len = 0;
        my $j = $i;
        while ($j < $end && $ops->[$j]{code} != 32 && $ops->[$j]{code} != 9) {
            $word_len++;
            $j++;
        }
        if ($word_len > 0) {
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $word_len;
            $delay = int($delay * $accel);
            $delay = $min_ms if $delay < $min_ms;
            print "delay\tawd_word\t$delay\n";
            $i += $word_len;
            # cur_col NOT incremented.
        }
        # Skip spaces
        if ($i < $end && ($ops->[$i]{code} == 32 || $ops->[$i]{code} == 9)) {
            my $space_start = $i;
            while ($i < $end && ($ops->[$i]{code} == 32 || $ops->[$i]{code} == 9)) {
                $i++;
            }
            my $space_count = $i - $space_start;
            printf "batch_delete\t%d\t%d\t%d\n", $cur_line, $cur_col, $space_count;
            print "delay\tawd_space\t$min_ms\n";
            # cur_col NOT incremented.
        }
    }

    return $start + $count;
}
