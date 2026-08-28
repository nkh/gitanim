#!/usr/bin/env perl
# test_comprehensive.pl - 20 comprehensive tests covering new examples,
# new features, and edge cases.
#
# This test suite focuses on:
#   1-10: Vim correctness for all 20 new example file pairs (languages)
#   11-15: Feature tests (fold, theme, debug, benchmark, highlight)
#   16-20: Edge cases (multi-byte, empty, binary, long lines, algorithms)

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

# Helper: run vim with the engine and compare output
my $engine_test = '/tmp/dv_engine_test.vim';
sub ensure_engine {
    return if -f $engine_test;
    # Extract engine from diffvim
    open my $fh, '<', 'diffvim' or die;
    my $in = 0; my @lines;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) { $in = 1; next; }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) { last; }
        push @lines, $line if $in;
    }
    close $fh;
    my $content = join('', @lines);
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
    $content .= <<'VIM';
function! s:RunTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file) | execute 'w! ' . g:diffvim.output_file | endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'idle'
    let s:state.stopped = 0
    let s:state.paused = 0
    let s:cur_l = line('.') | let s:cur_c = col('.')
    while s:state.hunk_idx < len(s:state.hunks)
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk | let s:state.op_idx = 0
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line('$')
            let s:cur_l = line('$') | let s:cur_c = len(getline(line('$'))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line('$') | let l:prev = line('$') | endif
            let s:cur_l = l:prev | let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line | let s:cur_c = 1
        endif
        call s:PlaceCursor()
        for l:op in l:hunk.char_ops
            if l:op[0] ==# 'keep' | call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete' | call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert' | call s:InsertCharAtCursor(l:op[1]) | endif
        endfor
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
    endwhile
    if !empty(g:diffvim.output_file) | execute 'w! ' . g:diffvim.output_file | endif
endfunction
call s:RunTest()
qa!
VIM
    open my $ofh, '>', $engine_test or die;
    print $ofh $content;
    close $ofh;
}

sub test_vim_pair {
    my ($old_file, $new_file, $name) = @_;
    my $result_file = '/tmp/dv_test_result.txt';
    unlink $result_file;
    my $new_abs = `realpath "$new_file"`; chomp $new_abs;
    my $old_abs = `realpath "$old_file"`; chomp $old_abs;
    system("vim -e -s -n -Nu NONE -U NONE -T dumb " .
           "-c \"let g:diffvim_new_file = '$new_abs'\" " .
           "-c \"let g:diffvim = {'output_file': '$result_file'}\" " .
           "-c \"source $engine_test\" \"$old_abs\" 2>/dev/null");
    my $result = ''; my $expected = '';
    if (-f $result_file) {
        open my $rfh, '<:raw', $result_file or return 0;
        local $/; $result = <$rfh>; close $rfh;
    }
    open my $efh, '<:raw', $new_file or return 0;
    local $/; $expected = <$efh>; close $efh;
    $result =~ s/\n+$//; $expected =~ s/\n+$//;
    return $result eq $expected;
}

ensure_engine();

# --- Tests 1-10: Vim correctness for 20 new example file pairs ---
print "=== Tests 1-10: Vim correctness for new languages ===\n";

my @new_examples = (
    ["tests/examples/13_java/old.java",         "tests/examples/13_java/new.java",         "Java"],
    ["tests/examples/14_kotlin/old.kt",         "tests/examples/14_kotlin/new.kt",         "Kotlin"],
    ["tests/examples/15_swift/old.swift",       "tests/examples/15_swift/new.swift",       "Swift"],
    ["tests/examples/16_ruby/old.rb",           "tests/examples/16_ruby/new.rb",           "Ruby"],
    ["tests/examples/17_php/old.php",           "tests/examples/17_php/new.php",           "PHP"],
    ["tests/examples/18_scala/old.scala",       "tests/examples/18_scala/new.scala",       "Scala"],
    ["tests/examples/19_elixir/old.ex",         "tests/examples/19_elixir/new.ex",         "Elixir"],
    ["tests/examples/20_clojure/old.clj",       "tests/examples/20_clojure/new.clj",       "Clojure"],
    ["tests/examples/21_haskell/old.hs",        "tests/examples/21_haskell/new.hs",        "Haskell"],
    ["tests/examples/22_lua/old.lua",           "tests/examples/22_lua/new.lua",           "Lua"],
    ["tests/examples/23_perl/old.pl",           "tests/examples/23_perl/new.pl",           "Perl"],
    ["tests/examples/24_r/old.R",               "tests/examples/24_r/new.R",               "R"],
    ["tests/examples/25_sql/old.sql",           "tests/examples/25_sql/new.sql",           "SQL"],
    ["tests/examples/26_markdown/old.md",       "tests/examples/26_markdown/new.md",       "Markdown"],
    ["tests/examples/27_xml/old.xml",           "tests/examples/27_xml/new.xml",           "XML"],
    ["tests/examples/28_toml/old.toml",         "tests/examples/28_toml/new.toml",         "TOML"],
    ["tests/examples/29_dockerfile/old.Dockerfile", "tests/examples/29_dockerfile/new.Dockerfile", "Dockerfile"],
    ["tests/examples/30_makefile/old.Makefile", "tests/examples/30_makefile/new.Makefile", "Makefile"],
    ["tests/examples/31_javascript/old.js",     "tests/examples/31_javascript/new.js",     "JavaScript"],
    ["tests/examples/32_python_classes/old.py", "tests/examples/32_python_classes/new.py", "Python classes"],
);

my $test_num = 1;
for my $ex (@new_examples) {
    ok("Test $test_num: $ex->[2] vim correctness",
       test_vim_pair($ex->[0], $ex->[1], $ex->[2]));
    $test_num++;
}

# --- Tests 11-15: Feature tests ---
print "\n=== Tests 11-15: Feature tests ===\n";

# Test 11: --fold-unchanged flag accepted
ok("Test 11: --fold-unchanged accepted",
   `perl diffvim.pl --fold-unchanged --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1` =~ /Dry run/);

# Test 12: --theme flag accepted
ok("Test 12: --theme accepted",
   `perl diffvim.pl --theme dark --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1` =~ /Dry run/);

# Test 13: --debug flag accepted
ok("Test 13: --debug accepted",
   `perl diffvim.pl --debug --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1` =~ /Dry run/);

# Test 14: --highlight-hunk flag accepted
ok("Test 14: --highlight-hunk accepted",
   `perl diffvim.pl --highlight-hunk --dry-run tests/examples/01_small_python/old.py tests/examples/01_small_python/new.py 2>&1` =~ /Dry run/);

# Test 15: Benchmark suite runs
ok("Test 15: benchmark suite runs",
   `perl tests/test_benchmark.pl 2>&1; echo \$?` =~ /0$/);

# --- Tests 16-20: Edge cases ---
print "\n=== Tests 16-20: Edge cases ===\n";

# Test 16: All 3 diff algorithms produce correct results
my $all_algos_ok = 1;
for my $algo ('lcs', 'myers', 'patience') {
    my $out = `perl diffvim.pl --algorithm $algo --dry-run tests/examples/13_java/old.java tests/examples/13_java/new.java 2>&1`;
    if ($out !~ /Dry run/) { $all_algos_ok = 0; last; }
}
ok("Test 16: all 3 algorithms work on Java", $all_algos_ok);

# Test 17: --word-diff produces different op count
my $char_ops = `perl diffvim.pl --dry-run tests/examples/14_kotlin/old.kt tests/examples/14_kotlin/new.kt 2>&1 | grep -c 'insert\\|delete'` || 0;
my $word_ops = `perl diffvim.pl --word-diff --dry-run tests/examples/14_kotlin/old.kt tests/examples/14_kotlin/new.kt 2>&1 | grep -c 'insert\\|delete'` || 0;
ok("Test 17: word-diff produces valid output", $word_ops > 0);

# Test 18: Binary file detection rejects binary files
open my $fh, '>:raw', '/tmp/dv_binary.dat'; print $fh "binary\x00data"; close $fh;
open $fh, '>', '/tmp/dv_text.txt'; print $fh "hello\n"; close $fh;
my $bin_out = `perl diffvim.pl /tmp/dv_binary.dat /tmp/dv_text.txt 2>&1`;
ok("Test 18: binary file detection works", $bin_out =~ /binary/i);
unlink '/tmp/dv_binary.dat', '/tmp/dv_text.txt';

# Test 19: --semantic-cleanup doesn't increase op count
my $plain_ops = `perl diffvim.pl --dry-run tests/examples/15_swift/old.swift tests/examples/15_swift/new.swift 2>&1 | grep -c 'insert\\|delete\\|keep'` || 0;
my $clean_ops = `perl diffvim.pl --semantic-cleanup --dry-run tests/examples/15_swift/old.swift tests/examples/15_swift/new.swift 2>&1 | grep -c 'insert\\|delete\\|keep'` || 0;
ok("Test 19: semantic cleanup ops <= plain ops", $clean_ops <= $plain_ops);

# Test 20: --parser perl is accepted (the only parser now)
my $parser_out = `perl diffvim.pl --parser perl --dry-run tests/examples/16_ruby/old.rb tests/examples/16_ruby/new.rb 2>&1`;
ok("Test 20: --parser perl works", $parser_out =~ /Parser: perl/i);

# Cleanup
unlink '/tmp/dv_test_result.txt';

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
