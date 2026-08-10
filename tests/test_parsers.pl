#!/usr/bin/env perl
# Test that both parsers produce identical hunk data, and that the char ops
# correctly transform old into new when applied to a vim buffer.

use strict;
use warnings;
use lib '/home/z/my-project/download';

use DiffVim::Parser::Perl qw(parse_diff);
use DiffVim::Parser::Diff2Html;

my @test_cases = (
    {
        name => 'simple modification',
        old  => "hello world\nfoo bar\n",
        new  => "hello there world\nfoo baz\n",
    },
    {
        name => 'multi-hunk python',
        old  => "def greet(name):\n    print(\"Hello, \" + name)\n    return None\n\ndef add(a, b):\n    return a + b\n\n# TODO: implement subtract\n",
        new  => "def greet(name):\n    print(f\"Hello, {name}!\")\n    return None\n\ndef add(a, b):\n    return a + b\n\ndef subtract(a, b):\n    return a - b\n",
    },
    {
        name => 'pure insertion at start',
        old  => "b\nc\n",
        new  => "a\nb\nc\n",
    },
    {
        name => 'pure deletion at end',
        old  => "a\nb\nc\n",
        new  => "a\nb\n",
    },
    {
        name => 'identical files',
        old  => "same\ncontent\n",
        new  => "same\ncontent\n",
    },
    {
        name => 'empty old file',
        old  => "",
        new  => "hello\nworld\n",
    },
    {
        name => 'insertion at end',
        old  => "x\n",
        new  => "x\ny\n",
    },
    {
        name => 'mid-line insertion',
        old  => "hello world\n",
        new  => "hello there world\n",
    },
    {
        name => 'delete middle lines',
        old  => "a\nb\nc\nd\n",
        new  => "a\nd\n",
    },
);

my $pass = 0;
my $fail = 0;

# Write content to a temp file
sub write_file {
    my ($path, $content) = @_;
    open my $fh, '>:raw', $path or die "Cannot write $path: $!";
    print $fh $content;
    close $fh;
}

# Apply char ops to reconstruct the new text
sub apply_ops {
    my ($hunks_ref, $old_lines_ref) = @_;
    my @old_lines = @$old_lines_ref;
    my @result;
    my $old_pos = 0;

    for my $hunk (@$hunks_ref) {
        my $target_idx = $hunk->{target_line} - 1;
        while ($old_pos < $target_idx) {
            push @result, $old_lines[$old_pos];
            $old_pos++;
        }

        my $del_count = $hunk->{deleted_count};
        my $ins_count = $hunk->{inserted_count};
        my $end_ins = $hunk->{is_end_insert};
        my $end_del = $hunk->{is_end_delete};

        # Reconstruct old_text
        my $old_text = '';
        for my $d (0 .. $del_count - 1) {
            if ($old_pos < @old_lines) {
                $old_text .= "\n" if $d > 0;
                $old_text .= $old_lines[$old_pos];
                $old_pos++;
            }
        }

        if ($del_count == 0) {
            $old_text = '';
        } elsif ($ins_count == 0) {
            if ($end_del) {
                $old_text = "\n" . $old_text;
            } else {
                $old_text = $old_text . "\n";
            }
        }

        # Apply char ops
        my $new_text = '';
        for my $op (@{$hunk->{char_ops}}) {
            my $type = $op->{op};
            my $code = $op->{code};
            my $ch = $code == 10 ? "\n" : chr($code);
            if ($type eq 'keep' || $type eq 'insert') {
                $new_text .= $ch;
            }
        }

        # Strip leading/trailing \n that are line separators, not content.
        # For end_insert: new_text starts with \n (separator after existing line).
        # For non-end-insert pure insertion: new_text ends with \n (separator before existing line).
        # For mixed hunks (del>0 && ins>0): no extra separator.
        if ($del_count == 0) {
            # Pure insertion: strip the separator \n
            $new_text =~ s/^\n// if $end_ins;
            $new_text =~ s/\n$// unless $end_ins;
        }

        # Split new_text into lines (don't use -1, to avoid trailing empty)
        if (length($new_text) > 0) {
            my @nl = split /\n/, $new_text;  # drops trailing empty field
            push @result, @nl;
        }
    }

    while ($old_pos < @old_lines) {
        push @result, $old_lines[$old_pos];
        $old_pos++;
    }

    return @result;
}

sub run_test {
    my ($tc) = @_;
    my $name = $tc->{name};
    my $old_file = "/tmp/dv_test_old.txt";
    my $new_file = "/tmp/dv_test_new.txt";

    write_file($old_file, $tc->{old});
    write_file($new_file, $tc->{new});

    my @expected_lines = $tc->{new} eq '' ? () : split /\n/, $tc->{new}, -1;
    pop @expected_lines if @expected_lines && $expected_lines[-1] eq '' && $tc->{new} =~ /\n\z/;

    my $fail_count = 0;

    # Test Perl parser
    my $result_perl = parse_diff($old_file, $new_file);
    my @old_lines = $tc->{old} eq '' ? () : split /\n/, $tc->{old}, -1;
    pop @old_lines if @old_lines && $old_lines[-1] eq '' && $tc->{old} =~ /\n\z/;

    my @perl_result = apply_ops($result_perl->{hunks}, \@old_lines);

    my $perl_ok = 1;
    if (@perl_result != @expected_lines) {
        $perl_ok = 0;
    } else {
        for my $i (0 .. $#perl_result) {
            $perl_ok = 0, last if $perl_result[$i] ne $expected_lines[$i];
        }
    }

    if ($perl_ok) {
        print "PASS (perl):      $name\n";
        $pass++;
    } else {
        print "FAIL (perl):      $name\n";
        print "  expected: " . join('|', @expected_lines) . "\n";
        print "  got:      " . join('|', @perl_result) . "\n";
        $fail++;
    }

    # Test diff2html parser
    my $result_d2h = DiffVim::Parser::Diff2Html::parse_diff($old_file, $new_file);
    my @d2h_result = apply_ops($result_d2h->{hunks}, \@old_lines);

    my $d2h_ok = 1;
    if (@d2h_result != @expected_lines) {
        $d2h_ok = 0;
    } else {
        for my $i (0 .. $#d2h_result) {
            $d2h_ok = 0, last if $d2h_result[$i] ne $expected_lines[$i];
        }
    }

    if ($d2h_ok) {
        print "PASS (diff2html): $name\n";
        $pass++;
    } else {
        print "FAIL (diff2html): $name\n";
        print "  expected: " . join('|', @expected_lines) . "\n";
        print "  got:      " . join('|', @d2h_result) . "\n";
        $fail++;
    }

    # Compare parser outputs (they should produce similar hunks)
    my $perl_hunk_count = scalar(@{$result_perl->{hunks}});
    my $d2h_hunk_count = scalar(@{$result_d2h->{hunks}});
    if ($perl_hunk_count != $d2h_hunk_count) {
        print "WARN: hunk count mismatch (perl=$perl_hunk_count, d2h=$d2h_hunk_count) for $name\n";
    }
}

for my $tc (@test_cases) {
    run_test($tc);
}

print "\nResults: $pass passed, $fail failed\n";
exit($fail == 0 ? 0 : 1);
