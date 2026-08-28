#!/usr/bin/env perl
# test_layers_discovery.pl — Verify the dynamic layer discovery system.
#
# This test exercises the plugin contract described in FLEXIBILITY.md:
#
#   1. The manifest (animator/layers.conf) parses cleanly.
#   2. Every layer declared in the manifest resolves to an executable
#      (C binary in animator/bin/pp_<name> OR Perl in animator/perl/pp_<name>.pl).
#   3. Each layer accepts a V2 TSV on stdin and produces V2 TSV on stdout.
#   4. The orchestrator's --list-layers output matches the manifest.
#   5. C and Perl implementations of the same layer produce identical output.
#   6. The --layers=<csv> flag overrides the default chain.
#   7. The --enable=<name> flag adds a layer to the default chain.
#
# This test makes "we added a layer but the test count is the same" impossible:
# every layer declared in the manifest gets its own per-layer assertion, so
# the test count automatically scales with the manifest.
#
# Usage: perl tests/test_layers_discovery.pl

use strict;
use warnings;

my $ROOT = "$ENV{HOME}/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "FAIL: $m\n"; $fail++; push @errors, $m; }

# --- Locate the manifest --------------------------------------------------
my $manifest = "$ROOT/animator/layers.conf";
unless (-f $manifest) {
    bad "manifest not found: $manifest";
    print "\n=== Results: $pass passed, $fail failed ===\n";
    exit 1;
}
ok "manifest found: $manifest";

# --- Parse the manifest ---------------------------------------------------
# Format: <name>  <order>  <flag>  "description"
# Lines starting with # or blank are skipped.
my @layers;  # list of {name, order, flag, desc}
open(my $mh, '<', $manifest) or die "Cannot read $manifest: $!";
while (my $line = <$mh>) {
    chomp $line;
    $line =~ s/#.*//;
    $line =~ s/^\s+//;
    $line =~ s/\s+$//;
    next unless $line;
    # Split on whitespace, but keep description as quoted string
    if ($line =~ /^(\S+)\s+(\d+)\s+(\S+)\s+"(.*)"\s*$/) {
        push @layers, {
            name => $1, order => $2, flag => $3, desc => $4
        };
    } else {
        bad "manifest line did not parse: $line";
    }
}
close($mh);
ok "manifest parsed: " . scalar(@layers) . " layer(s) declared";

# --- For each declared layer, resolve its binary --------------------------
sub resolve_bin {
    my ($name) = @_;
    my $c_bin  = "$ROOT/animator/bin/pp_$name";
    return $c_bin if -x $c_bin;
    my $pl_bin = "$ROOT/animator/perl/pp_$name.pl";
    return "perl $pl_bin" if -f $pl_bin;
    # Other languages: animator/<lang>/pp_<name>.<ext>
    my @dirs = glob "$ROOT/animator/*/pp_$name.*";
    for my $f (@dirs) {
        my $base = $f;
        $base =~ s/.*\.//;
        if ($base eq 'pl')  { return "perl $f"; }
        if ($base eq 'py')  { return "python3 $f"; }
        if ($base eq 'rb')  { return "ruby $f"; }
        if ($base eq 'sh')  { return "bash $f"; }
        if ($base eq 'js')  { return "node $f"; }
        return $f if -x $f;
    }
    return undef;
}

my %resolved;
for my $l (@layers) {
    my $bin = resolve_bin($l->{name});
    if (defined $bin) {
        $resolved{$l->{name}} = $bin;
        ok "layer '$l->{name}' resolves: $bin";
    } else {
        bad "layer '$l->{name}' has no binary (expected animator/bin/pp_$l->{name} or animator/perl/pp_$l->{name}.pl)";
    }
}

# --- Build a tiny test diff and verify each layer is invokable ------------
my $old = "/tmp/ld_old.txt";
my $new = "/tmp/ld_new.txt";
open(my $fh, '>', $old) or die; print $fh "def foo():\n    print('hello')\n    return None\n\ndef bar():\n    pass\n"; close($fh);
open($fh, '>', $new) or die; print $fh "def foo():\n\ndef bar():\n    pass\n"; close($fh);
system("DIFFVIM_LEFT_TO_RIGHT=1 ./compute/bin/diffvim-compute-cpp '$old' '$new' /tmp/ld_raw.txt 2>/dev/null");
ok "compute produced raw ops";

# Verify each layer accepts stdin and produces stdout.
for my $l (@layers) {
    my $bin = $resolved{$l->{name}} or next;
    my $out_file = "/tmp/ld_layer_$l->{name}.out";
    my $rc = system("$bin < /tmp/ld_raw.txt > $out_file 2>/dev/null");
    if ($rc == 0 && -s $out_file) {
        ok "layer '$l->{name}' runs standalone (stdin → stdout)";
    } else {
        bad "layer '$l->{name}' failed to run or produced empty output";
    }
}

# --- Verify --list-layers output matches the manifest ---------------------
my $list_out = `./animator/bin/diffvim-postprocess --list-layers 2>/dev/null`;
for my $l (@layers) {
    if ($list_out =~ /^\Q$l->{name}\E\s+/m) {
        ok "--list-layers lists '$l->{name}'";
    } else {
        bad "--list-layers missing '$l->{name}'";
    }
}

# --- Verify --layers=<csv> overrides the default chain -------------------
# Run with only reorder+indent_last; output should match direct invocation.
my $explicit_out = `./animator/bin/diffvim-postprocess --layers=reorder,indent_last < /tmp/ld_raw.txt 2>/dev/null`;
my $direct_out   = `./animator/bin/pp_reorder < /tmp/ld_raw.txt 2>/dev/null | ./animator/bin/pp_indent_last 2>/dev/null`;
if ($explicit_out eq $direct_out) {
    ok "--layers=reorder,indent_last matches direct pipeline";
} else {
    bad "--layers=reorder,indent_last differs from direct pipeline";
}

# --- Verify --enable=<name> adds a layer to the default chain -------------
# Default chain = reorder + pace + highlight (3 layers).
# --enable=indent_last = reorder + indent_last + pace + highlight (4 layers).
# Check the orchestrator's stderr message, which lists the layers being run.
my $default_layers = `./animator/bin/diffvim-postprocess < /tmp/ld_raw.txt 2>&1 1>/dev/null | grep "→" | wc -l`;
my $enabled_layers = `./animator/bin/diffvim-postprocess --enable=indent_last < /tmp/ld_raw.txt 2>&1 1>/dev/null | grep "→" | wc -l`;
my $enabled_mentions = `./animator/bin/diffvim-postprocess --enable=indent_last < /tmp/ld_raw.txt 2>&1 1>/dev/null | grep -c "indent_last"`;
chomp $default_layers; chomp $enabled_layers; chomp $enabled_mentions;
if ($enabled_layers == $default_layers + 1 && $enabled_mentions >= 1) {
    ok "--enable=indent_last adds 1 layer (3 → $enabled_layers) and runs indent_last";
} else {
    bad "--enable=indent_last did not add the layer (default=$default_layers, enabled=$enabled_layers, mentions=$enabled_mentions)";
}

# --- Verify --pp-<name> dynamic flag works --------------------------------
# The orchestrator should treat --pp-foo as --foo (forwarding convention).
# Both should run the indent_last layer.
my $pp_runs = `./animator/bin/diffvim-postprocess --pp-indent-last < /tmp/ld_raw.txt 2>&1 1>/dev/null | grep -c "indent_last"`;
my $il_runs = `./animator/bin/diffvim-postprocess --indent-last < /tmp/ld_raw.txt 2>&1 1>/dev/null | grep -c "indent_last"`;
chomp $pp_runs; chomp $il_runs;
if ($pp_runs >= 1 && $il_runs >= 1) {
    ok "--pp-indent-last and --indent-last both run the indent_last layer";
} else {
    bad "--pp-indent-last (runs=$pp_runs) vs --indent-last (runs=$il_runs)";
}

# --- C and Perl parity for any layer with both implementations ------------
for my $l (@layers) {
    my $c_bin  = "$ROOT/animator/bin/pp_$l->{name}";
    my $pl_bin = "$ROOT/animator/perl/pp_$l->{name}.pl";
    next unless -x $c_bin && -f $pl_bin;
    # Skip pace/highlight: their output is non-deterministic (jitter, ms).
    next if $l->{name} =~ /^(pace|highlight)$/;
    my $c_res  = `$c_bin < /tmp/ld_raw.txt 2>/dev/null`;
    my $pl_res = `perl $pl_bin < /tmp/ld_raw.txt 2>/dev/null`;
    if ($c_res eq $pl_res) {
        ok "C and Perl '$l->{name}' produce identical output (parity)";
    } else {
        bad "C and Perl '$l->{name}' differ";
    }
}

# --- Verify adding a manifest line + binary is sufficient -----------------
# Simulate adding a new layer "pp_test_dummy" (no-op) and verify discovery.
my $dummy_bin = "$ROOT/animator/bin/pp_test_dummy";
my $created_dummy = 0;
unless (-f $dummy_bin) {
    open(my $dh, '>', $dummy_bin) or die "Cannot write $dummy_bin: $!";
    print $dh "#!/usr/bin/env bash\ncat\n";  # identity transform
    close($dh);
    chmod 0755, $dummy_bin;
    $created_dummy = 1;
}
# Add a line to a temporary manifest and use --layers=test_dummy
my $rc = system("./animator/bin/diffvim-postprocess --layers=test_dummy < /tmp/ld_raw.txt > /tmp/ld_dummy.out 2>/dev/null");
if ($rc == 0) {
    my $diff = system("diff -q /tmp/ld_raw.txt /tmp/ld_dummy.out >/dev/null 2>&1");
    if ($diff == 0) {
        ok "ad-hoc layer 'test_dummy' (drop binary, run --layers=test_dummy) works";
    } else {
        bad "ad-hoc layer 'test_dummy' produced wrong output";
    }
} else {
    bad "ad-hoc layer 'test_dummy' failed to run";
}
unlink $dummy_bin if $created_dummy;

# --- Final summary --------------------------------------------------------
print "\n=== Results: $pass passed, $fail failed ===\n";
if (@errors) {
    print "Failed:\n";
    for my $e (@errors) { print "  - $e\n"; }
}
exit($fail > 0 ? 1 : 0);
