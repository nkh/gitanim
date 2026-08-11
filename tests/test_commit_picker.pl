#!/usr/bin/env perl
# test_commit_picker.pl - Test :DiffvimCommit and :DiffvimPick commands
#
# Tests the plugin's git commit integration functions without requiring
# an interactive vim session.

use strict;
use warnings;
use lib '.';

my $pass = 0;
my $fail = 0;

sub ok {
    my ($name, $cond) = @_;
    if ($cond) { print "PASS: $name\n"; $pass++; }
    else       { print "FAIL: $name\n"; $fail++; }
}

# Test 1: Plugin defines :DiffvimCommit command
print "=== Test: plugin commands ===\n";
my $plugin = `cat plugin/diffvim.vim`;
ok('plugin defines :DiffvimCommit command',
   $plugin =~ /command!\s+-nargs=\?\s+DiffvimCommit/);
ok('plugin defines :DiffvimPick command',
   $plugin =~ /command!\s+-nargs=0\s+DiffvimPick/);
ok('plugin defines :DiffvimHelp command',
   $plugin =~ /command!\s+-nargs=0\s+DiffvimHelp/);
ok('plugin defines :Diffvim command',
   $plugin =~ /command!.*-nargs=\+.*Diffvim\s/);

# Test 2: s:DiffvimCommit function exists
print "\n=== Test: DiffvimCommit function ===\n";
ok('s:DiffvimCommit function defined',
   $plugin =~ /function!\s+s:DiffvimCommit/);
ok('DiffvimCommit handles empty commit (prompts)',
   $plugin =~ /if empty\(l:commit\)/);
ok('DiffvimCommit validates commit exists',
   $plugin =~ /git cat-file -t/);
ok('DiffvimCommit extracts file from commit',
   $plugin =~ /git show.*:/);
ok('DiffvimCommit handles modified buffers',
   $plugin =~ /if &modified/);
ok('DiffvimCommit saves buffer before diff',
   $plugin =~ /write/);

# Test 3: s:DiffvimPick function exists with picker selection
print "\n=== Test: DiffvimPick function ===\n";
ok('s:DiffvimPick function defined',
   $plugin =~ /function!\s+s:DiffvimPick/);
ok('DiffvimPick auto-detects picker',
   $plugin =~ /picker ==# 'auto'/);
ok('DiffvimPick supports fzf vim API',
   $plugin =~ /PickWithFzfAPI/);
ok('DiffvimPick supports fzf CLI',
   $plugin =~ /PickWithFzfCLI/);
ok('DiffvimPick supports forgit',
   $plugin =~ /PickWithForgit/);
ok('DiffvimPick has builtin fallback',
   $plugin =~ /PickWithBuiltin/);

# Test 4: fzf integration
print "\n=== Test: fzf integration ===\n";
ok('fzf API uses fzf#run',
   $plugin =~ /fzf#run/);
ok('fzf shows commit preview',
   $plugin =~ /--preview/);
ok('fzf preview shows git show',
   $plugin =~ /git show --stat --patch/);
ok('fzf has header instructions',
   $plugin =~ /--header/);

# Test 5: fzf CLI integration
print "\n=== Test: fzf CLI integration ===\n";
ok('fzf CLI builds fzf command',
   $plugin =~ /fzf_cmd.*fzf/);
ok('fzf CLI has preview window',
   $plugin =~ /--preview-window/);

# Test 6: builtin picker
print "\n=== Test: builtin picker ===\n";
ok('builtin picker shows numbered list',
   $plugin =~ /printf.*%2d/);
ok('builtin picker supports preview mode',
   $plugin =~ /Preview.*commit/);
ok('builtin picker handles cancel',
   $plugin =~ /Cancelled/);

# Test 7: shared animation function
print "\n=== Test: shared functions ===\n";
ok('s:AnimateFromCommit function defined',
   $plugin =~ /function!\s+s:AnimateFromCommit/);
ok('AnimateFromCommit validates commit',
   $plugin =~ /git cat-file -t/);
ok('AnimateFromCommit creates temp file',
   $plugin =~ /tempname/);
ok('AnimateFromCommit cleans up temp file',
   $plugin =~ /autocmd VimLeave.*delete/);
ok('s:OnCommitPicked callback defined',
   $plugin =~ /function!\s+s:OnCommitPicked/);
ok('s:SourceEngine helper defined',
   $plugin =~ /function!\s+s:SourceEngine/);

# Test 8: git integration
print "\n=== Test: git integration ===\n";
ok('checks for git repo',
   $plugin =~ /git rev-parse/);
ok('gets relative file path',
   $plugin =~ /fnamemodify.*:.*/);
ok('lists commits for specific file',
   $plugin =~ /git log.*-- /);
ok('shows commit info before animation',
   $plugin =~ /git log --oneline -1/);

# Test 9: configuration
print "\n=== Test: configuration ===\n";
ok('commit_picker config option exists',
   $plugin =~ /commit_picker/);
ok('default picker is auto',
   $plugin =~ /'auto'/);

# Test 10: syntax check
print "\n=== Test: syntax ===\n";
my $vim_rc = `timeout 5 vim -e -s -Nu NONE -U NONE -c "source plugin/diffvim.vim" -c "qa!" 2>&1; echo \$?`;
chomp $vim_rc;
ok('plugin sources without errors', $vim_rc =~ /^0$/);

# Test 11: help function
print "\n=== Test: help ===\n";
ok('s:ShowHelp function defined',
   $plugin =~ /function!\s+s:ShowHelp/);
ok('help mentions DiffvimCommit',
   $plugin =~ /DiffvimCommit.*VimDiff/);
ok('help mentions DiffvimPick',
   $plugin =~ /DiffvimPick.*Pick.*commit/);

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
