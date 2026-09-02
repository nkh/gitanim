#!/usr/bin/env perl
# ad (Perl) — Standalone terminal animation application.
#
# Reads a TSV timed op stream and animates the transformation.
# Every op carries its own (line, col); the animator moves the cursor
# to that position before applying the op. This makes the animator
# scroll-safe — even if the user scrolls mid-animation, each op is
# applied at the right place.
#
# Supports --no-display for testing (process ops without rendering).
#
# Usage:
#   ad [options] <oldfile>
#
# Options:
#   --no-display       Process ops without rendering (for testing)
#   --speed N          Speed multiplier (default: 1.0)
#   --output FILE      Write final buffer to FILE
#   --snapshot FILE    Write buffer to FILE at end of processing
#   --help, -h         Show help

use strict;
use warnings;
use utf8;
use Encode qw(decode encode);
use Time::HiRes qw(usleep);

# Enable Unicode for STDIN/STDOUT
binmode(STDIN, ':encoding(UTF-8)');
binmode(STDOUT, ':encoding(UTF-8)');
binmode(STDERR, ':encoding(UTF-8)');

# Handle Ctrl+C: restore terminal before exiting
$SIG{INT} = $SIG{TERM} = sub {
    print STDERR "\033[?25h\033[0m\033[2J\033[H";
    exit 1;
};

my $no_display = 0;
my $speed = 1.0;
my $output_file;
my $snapshot_file;
my $old_file;
my $help = 0;

for (my $i = 0; $i < @ARGV; $i++) {
    if ($ARGV[$i] eq '--no-display') { $no_display = 1; }
    elsif ($ARGV[$i] eq '--speed') { $i++; $speed = $ARGV[$i] + 0; }
    elsif ($ARGV[$i] eq '--output') { $i++; $output_file = $ARGV[$i]; }
    elsif ($ARGV[$i] eq '--snapshot') { $i++; $snapshot_file = $ARGV[$i]; }
    elsif ($ARGV[$i] eq '--help' || $ARGV[$i] eq '-h') { $help = 1; }
    elsif ($ARGV[$i] !~ /^-/) { $old_file = $ARGV[$i]; }
}

if ($help) {
    print STDERR "Usage: ad [options] <oldfile>\n";
    print STDERR "  --no-display       Process without rendering\n";
    print STDERR "  --speed N          Speed multiplier\n";
    print STDERR "  --output FILE      Write final buffer to FILE\n";
    print STDERR "  --snapshot FILE    Write buffer to FILE\n";
    exit 0;
}

die "Error: oldfile is required\n" unless $old_file && -f $old_file;

# --- Virtual Buffer ---
my @lines;
my $cursor_l = 0;  # 0-indexed
my $cursor_c = 0;  # 0-indexed

sub load_file {
    my ($path) = @_;
    open my $fh, '<:encoding(UTF-8)', $path or die "Cannot open $path: $!";
    local $/;
    my $content = <$fh>;
    close $fh;
    $content //= '';
    @lines = split /\n/, $content, -1;
    pop @lines if @lines && $lines[-1] eq '' && $content =~ /\n$/;
    @lines = ("") unless @lines;
}

sub buffer_to_string {
    return "" if @lines == 1 && $lines[0] eq "";
    return join("\n", @lines) . "\n";
}

sub write_buffer {
    my ($path) = @_;
    open my $fh, '>:encoding(UTF-8)', $path or die "Cannot write $path: $!";
    print $fh buffer_to_string();
    close $fh;
}

sub line_chars {
    my ($l) = @_;
    return 0 if $l < 0 || $l > $#lines;
    my $s = $lines[$l];
    my $count = 0;
    my @chars = split //, $s;
    return scalar(@chars);
}

# Set cursor position (1-indexed line/col → 0-indexed internal).
# Clamps to buffer bounds. When the target line is past the end of
# the buffer (end-insert case), the cursor is placed at the END of
# the last line so subsequent inserts append after existing content.
sub set_cursor {
    my ($line, $col) = @_;
    $cursor_l = $line - 1;
    $cursor_l = 0 if $cursor_l < 0;
    if ($cursor_l > $#lines) {
        # Past end of buffer — clamp to last line, position at END.
        $cursor_l = $#lines;
        $cursor_c = line_chars($cursor_l);
        return;
    }
    $cursor_c = $col - 1;
    $cursor_c = 0 if $cursor_c < 0;
    my $max_col = line_chars($cursor_l);
    $cursor_c = $max_col if $cursor_c > $max_col;
}

sub keep_char {
    my ($code) = @_;
    # With per-op positioning, keep_char only advances the cursor within
    # the same line. Line transitions are handled by set_cursor() calls.
    if ($code == 10) {
        $cursor_l++;
        $cursor_l = $#lines if $cursor_l > $#lines;
        $cursor_c = 0;
    } else {
        $cursor_c++;
    }
}

sub delete_char {
    my ($code) = @_;
    if ($code == 10) {
        # Delete \n — join current line with the next line.
        # Natural result of removing a newline from a line-based buffer.
        # No special cases. If there is no next line, the op is a no-op —
        # the postprocess must not emit delete-\n at the last line.
        if ($cursor_l < $#lines) {
            $lines[$cursor_l] = $lines[$cursor_l] . $lines[$cursor_l + 1];
            splice(@lines, $cursor_l + 1, 1);
        }
    } else {
        my $line = $lines[$cursor_l];
        my @chars = split //, $line;
        if ($cursor_c < @chars) {
            splice(@chars, $cursor_c, 1);
            $lines[$cursor_l] = join("", @chars);
        }
    }
}

sub insert_char {
    my ($code) = @_;
    # Clamp cursor_c to line length to prevent slice issues
    my $linelen = length($lines[$cursor_l]);
    $cursor_c = $linelen if $cursor_c > $linelen;
    if ($code == 10) {
        my $line = $lines[$cursor_l];
        my @chars = split //, $line;
        my @before = $cursor_c > 0 ? @chars[0 .. $cursor_c - 1] : ();
        my @after = $cursor_c <= $#chars ? @chars[$cursor_c .. $#chars] : ();
        $lines[$cursor_l] = join("", @before);
        splice(@lines, $cursor_l + 1, 0, join("", @after));
        $cursor_l++;
        $cursor_c = 0;
    } else {
        my $ch = chr($code);
        my $line = $lines[$cursor_l];
        my @chars = split //, $line;
        splice(@chars, $cursor_c, 0, $ch);
        $lines[$cursor_l] = join("", @chars);
        $cursor_c++;
    }
}

sub render {
    return if $no_display;
    print "\033[2J\033[H";  # Clear screen
    my $max = @lines;
    $max = 40 if $max > 40;  # TODO: detect terminal height
    for my $i (0 .. $max - 1) {
        if ($i == $cursor_l) {
            my $line = $lines[$i];
            my @chars = split //, $line;
            my $before = $cursor_c > 0 ? join("", @chars[0 .. $cursor_c - 1]) : "";
            my $at = $cursor_c < @chars ? $chars[$cursor_c] : " ";
            my $after = $cursor_c < @chars ? join("", @chars[$cursor_c + 1 .. $#chars]) : "";
            printf "%s\033[7m%s\033[0m%s\n", $before, $at, $after;
        } else {
            print "$lines[$i]\n";
        }
    }
    printf "\033[%d;%dH", $cursor_l + 1, $cursor_c + 1;
}

# --- Main ---
load_file($old_file);

if (!$no_display) {
    print "\033[?25l";  # Hide cursor
}

# Process timed op stream (v2 TSV format)
while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq "" || $line =~ /^#/;

    my @parts = split /\t/, $line;
    my $cmd = shift @parts;

    # v2 format: keep/delete/insert directly (no 'op' prefix)
    if ($cmd eq 'keep' && @parts >= 3) {
        my ($op_line, $op_col, $code) = @parts;
        $code = int($code);
        set_cursor($op_line + 0, $op_col + 0);
        keep_char($code);
        render();
    } elsif ($cmd eq 'delete' && @parts >= 3) {
        my ($op_line, $op_col, $code) = @parts;
        $code = int($code);
        set_cursor($op_line + 0, $op_col + 0);
        delete_char($code);
        render();
    } elsif ($cmd eq 'insert' && @parts >= 3) {
        my ($op_line, $op_col, $code) = @parts;
        $code = int($code);
        set_cursor($op_line + 0, $op_col + 0);
        insert_char($code);
        render();
    } elsif ($cmd eq 'delay' && @parts >= 2) {
        # delay\t<ms>\t<type>
        my $ms = int($parts[0]);
        $ms = int($ms / $speed) if $speed > 0;
        usleep($ms * 1000) if $ms > 0 && !$no_display;
    } elsif ($cmd eq 'HUNK' || $cmd eq 'HUNK_END') {
        # Metadata — no action
    } elsif ($cmd eq 'snapshot' && @parts >= 1) {
        write_buffer($parts[0]);
    } elsif ($cmd eq 'done' || $cmd eq 'EOF') {
        last;
    }
}

# Write snapshot if requested
write_buffer($snapshot_file) if $snapshot_file;
write_buffer($output_file) if $output_file;

if (!$no_display) {
    print "\033[?25h\033[0m\n";  # Restore cursor
    print "Animation complete. Buffer has " . scalar(@lines) . " lines.\n";
}
