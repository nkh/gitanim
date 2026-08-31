#!/usr/bin/env perl
# verify_md5_cont.pl — continuation of verify_md5.pl starting from example 20.
# Reuses the extracted engine.

use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Basename qw(basename dirname);
use Digest::MD5 qw(md5_hex);

$| = 1;
select(STDERR); $| = 1;
select(STDOUT); $| = 1;

my $root     = "/home/z/my-project/gitanim";
my $outdir   = "$root/verify_out";
my $engine   = "$outdir/engine.vim";
my $tmpdir   = tempdir(CLEANUP => 1);

mkdir $outdir unless -d $outdir;

sub md5_file {
    my ($f) = @_;
    return 'MISSING' unless -f $f;
    open my $fh, '<:raw', $f or return "ERR:$!";
    my $data = do { local $/; <$fh> };
    close $fh;
    return Digest::MD5::md5_hex($data);
}

sub run_cmd {
    my ($cmd) = @_;
    my $rc = system("$cmd");
    if ($rc == -1) { return -1; }
    if ($rc & 127) { return $rc; }
    return $rc >> 8;
}

opendir(my $dh, "$root/examples") or die "opendir: $!";
my @dirs = sort grep { -d "$root/tests/examples/$_" && /^\d+_/ } readdir($dh);
closedir $dh;

my @rows;
my $env = "AD_TICK_MS=16 AD_TYPE_DELAY_MS=50 AD_DELETE_DELAY_MS=40 " .
          "AD_MOVE_MIN_MS=250 AD_MOVE_MAX_MS=1600 AD_MOVE_MS_PER_UNIT=6 " .
          "AD_HUNK_PAUSE_MS=250 AD_SPEED=1 " .
          "AD_OP_ORDER=optimize AD_DELETE_PACING=word " .
          "AD_INSERT_PACING=char AD_PACING=uniform AD_HIGHLIGHT=none " .
          "AD_ADAPTIVE_WORD_DELETE=1 AD_RAPID_EOL_DELETE=1";

for my $d (@dirs) {
    # Skip examples 01 through 19 (already verified)
    next if $d =~ /^0?[1-9]_/ || $d =~ /^1[0-9]_/;

    my @new_candidates = glob("$root/tests/examples/$d/new.*");
    unless (@new_candidates) {
        push @rows, [$d, 'NO_NEW', '-', '-', '-', '-', ''];
        next;
    }
    my $new = $new_candidates[0];
    my @old_candidates = glob("$root/tests/examples/$d/old.*");
    my $old = $old_candidates[0] if @old_candidates;

    my $new_md5 = md5_file($new);

    # --- ad_vim run ------------------------------------------------------
    my $dv_out = "$tmpdir/dv_$d.out";
    unlink $dv_out if -f $dv_out;
    my $cmd = "env $env AD_OUTPUT='$dv_out' timeout 8 vim -u NONE -N -n -es " .
              "-c 'let g:diffvim_new_file = \"$new\"' " .
              "-c 'source $engine' " .
              "'$old' >/dev/null 2>&1";
    my $rc = run_cmd($cmd);
    my $dv_md5     = md5_file($dv_out);
    my $dv_status  = ($dv_md5 eq $new_md5) ? 'OK' : 'MISMATCH';

    # --- ad_pipeline run --------------------------------------------
    my $pipe_out = "$tmpdir/pipe_$d.out";
    unlink $pipe_out if -f $pipe_out;
    my $pcmd = "cd $root && animator/ad_pipeline --no-display --snapshot '$pipe_out' '$old' '$new' >/dev/null 2>&1";
    my $prc = run_cmd($pcmd);
    my $pipe_md5    = md5_file($pipe_out);
    my $pipe_status = ($pipe_md5 eq $new_md5) ? 'OK' : 'MISMATCH';
    my $pipe_err    = ($prc != 0) ? "rc=$prc" : '';

    printf "PROGRESS %-28s new=%s dv=%s(%s) pipe=%s(%s %s)\n",
        $d, substr($new_md5,0,8), substr($dv_md5,0,8), $dv_status,
        substr($pipe_md5,0,8), $pipe_status, $pipe_err;

    # Also append to a results file immediately so we don't lose progress
    open my $rfh, '>>', "$outdir/results_live.txt" or die $!;
    print $rfh join("\t", $d, $new_md5, $dv_md5, $dv_status, $pipe_md5, $pipe_status, $pipe_err), "\n";
    close $rfh;

    push @rows, [$d, $new_md5, $dv_md5, $dv_status, $pipe_md5, $pipe_status, $pipe_err];
}

# Save results to a file for later merging
open my $out, '>', "$outdir/results_20plus.txt" or die $!;
for my $r (@rows) {
    print $out join("\t", @$r), "\n";
}
close $out;
print "DONE. Results saved to $outdir/results_20plus.txt\n";
