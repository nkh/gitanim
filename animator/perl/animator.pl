#!/usr/bin/env perl
# diffvim-animator (Perl) — Standalone terminal animation application.
#
# Reads a timed op stream and animates the transformation.
# Supports --no-display for testing (process ops without rendering).
#
# Usage:
#   diffvim-animator [options] <oldfile>
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
    print STDERR "Usage: diffvim-animator [options] <oldfile>\n";
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

sub keep_char {
    my ($code) = @_;
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
        # Delete newline: if the current line is NOT empty, do NOT
        # delete the \n. Just move the cursor to the next line.
        # Never bring the next line's text onto the current line.
        # If the current line IS empty, deleting the \n just removes
        # the empty line — harmless.
        my $line = $lines[$cursor_l];
        if (length($line) == 0) {
            # Empty line — safe to join (removes empty line)
            if ($cursor_l < $#lines) {
                $lines[$cursor_l] .= $lines[$cursor_l + 1];
                splice(@lines, $cursor_l + 1, 1);
            }
        } else {
            # Line has content — do NOT delete the \n.
            # Move cursor to the next line.
            if ($cursor_l < $#lines) {
                $cursor_l++;
                $cursor_c = 0;
            }
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
    if ($code == 10) {
        my $line = $lines[$cursor_l];
        my @chars = split //, $line;
        my @before = @chars[0 .. $cursor_c - 1];
        my @after = @chars[$cursor_c .. $#chars];
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

sub batch_delete {
    my ($n) = @_;
    my $line = $lines[$cursor_l];
    my @chars = split //, $line;
    my $end = $cursor_c + $n;
    $end = scalar(@chars) if $end > scalar(@chars);
    splice(@chars, $cursor_c, $n);
    $lines[$cursor_l] = join("", @chars);
}

sub batch_insert {
    my @codes = @_;
    for my $code (@codes) {
        insert_char($code);
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

# Process timed op stream
while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq "" || $line =~ /^#/;

    my @parts = split /\s+/, $line;
    my $cmd = shift @parts;

    if ($cmd eq 'op') {
        my ($type, $code) = @parts;
        $code = int($code);
        keep_char($code) if $type eq 'keep';
        delete_char($code) if $type eq 'delete';
        insert_char($code) if $type eq 'insert';
        render();
    } elsif ($cmd eq 'delay') {
        my $ms = int($parts[0]);
        $ms = int($ms / $speed) if $speed > 0;
        usleep($ms * 1000) if $ms > 0 && !$no_display;
    } elsif ($cmd eq 'batch_delete') {
        batch_delete(int($parts[0]));
        render();
    } elsif ($cmd eq 'batch_insert') {
        batch_insert(map { int($_) } @parts);
        render();
    } elsif ($cmd eq 'newline_delete') {
        delete_char(10);
        render();
    } elsif ($cmd eq 'newline_insert') {
        insert_char(10);
        render();
    } elsif ($cmd eq 'glide') {
        my ($l, $c) = split /:/, $parts[0];
        $cursor_l = $l - 1;
        $cursor_c = $c - 1;
        $cursor_l = 0 if $cursor_l < 0;
        $cursor_l = $#lines if $cursor_l > $#lines;
        render();
    } elsif ($cmd eq 'snapshot') {
        write_buffer($parts[0]);
    } elsif ($cmd eq 'hunk_start' || $cmd eq 'hunk_end' || $cmd eq 'file_start') {
        # Metadata — no action
    } elsif ($cmd eq 'done') {
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
