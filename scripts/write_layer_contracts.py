#!/usr/bin/env python3
"""Write tests/test_layer_contracts.pl with real tab characters in the
heredoc inputs. The Write tool converts tabs to spaces, so we use
Python to emit real tabs.
"""
from pathlib import Path

T = "\t"

# Build the entire test file content with real tabs where needed.
# Heredoc inputs need real tabs in the op lines (type<TAB>line<TAB>col<TAB>code<TAB>char).
content = r'''#!/usr/bin/env perl
# test_layer_contracts.pl — Contract tests for every postprocess layer.
#
# Each layer has a documented contract: "given this input op stream,
# the output op stream must have this property." These tests feed
# hand-crafted input directly into the layer (NOT a full pipeline)
# and assert the layer's specific transform — not snapshot==target.
#
# Why hand-crafted input: snapshot==target passes with NO layer at all
# (the raw op stream already produces the right final buffer). It cannot
# tell whether the layer fires. Contract tests can.
#
# Usage: perl tests/test_layer_contracts.pl
#        VERBOSE=1 perl tests/test_layer_contracts.pl   (print op streams on fail)

use strict;
use warnings;

my $ROOT = "/home/z/my-project/gitanim";
chdir $ROOT or die "Cannot chdir to $ROOT: $!\n";

my $VERBOSE = $ENV{VERBOSE} // 0;
my $pass = 0;
my $fail = 0;
my @errors;

sub ok   { my ($m)=@_; print "  PASS: $m\n"; $pass++; }
sub bad  { my ($m)=@_; print "  FAIL: $m\n"; $fail++; push @errors, $m; }

sub run_layer {
    my ($bin, $input, @args) = @_;
    my $in_file = "/tmp/ltc_in.txt";
    open(my $fh, '>', $in_file) or die $!;
    print $fh $input;
    close($fh);
    my $arg_str = join(" ", @args);
    my $out = `$bin $arg_str < $in_file 2>/dev/null`;
    if ($VERBOSE && ($? != 0 || !$out)) {
        print "    --- stderr ---\n";
        print `$bin $arg_str < $in_file 2>&1 >/dev/null`;
    }
    return $out;
}

# Count ops of a given type in the output stream (skip comments/HUNK/EOF).
sub count_ops {
    my ($out, $type) = @_;
    return () = ($out =~ /^$type\t/mg);
}

# Get position of first occurrence of a pattern
sub first_pos {
    my ($out, $pattern) = @_;
    my $pos = index($out, $pattern);
    return $pos;
}

# Get position of last match of a regex
sub last_match_pos {
    my ($out, $pattern) = @_;
    my $last = -1;
    while ($out =~ /$pattern/mg) { $last = $-[0]; }
    return $last;
}

# ====================================================================
# 1. ad_layer_reorder
# ====================================================================
print "=== ad_layer_reorder ===\n";
{
    # Input: a single segment with interleaved delete/insert.
    # The keep op at the end is the segment boundary.
    # Without reorder: D I D I K
    # With reorder:    D D I I K  (deletes first, then inserts, then keep)
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "delete\t1\t1\t97\ta",
        "insert\t1\t1\t98\tb",
        "delete\t1\t2\t99\tc",
        "insert\t1\t2\t100\td",
        "keep\t1\t3\t101\te",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_reorder", $input);
    my $n_del = count_ops($out, "delete");
    my $n_ins = count_ops($out, "insert");

    ok "reorder runs" if $out;
    ok "preserves 2 delete ops" if $n_del == 2;
    ok "preserves 2 insert ops" if $n_ins == 2;
    # The 2 deletes must come before the 2 inserts in the output stream.
    my $first_ins_pos = first_pos($out, "insert\t");
    my $last_del_pos = last_match_pos($out, qr/^delete\t/m);
    if ($last_del_pos >= 0 && $first_ins_pos >= 0 && $last_del_pos < $first_ins_pos) {
        ok "all deletes before all inserts within segment";
    } else {
        bad "deletes not before inserts: last_del=$last_del_pos first_ins=$first_ins_pos";
    }
}

# ====================================================================
# 2. ad_layer_overwrite
# ====================================================================
print "\n=== ad_layer_overwrite ===\n";
{
    # Case 2a: The hello -> greet pattern. The LCS splits at the shared
    # 'e' (keep), producing two separate delete+insert runs on the same
    # line. Each run is 1 delete + N inserts.
    #
    # Layer contract: merge adjacent delete+insert at same (line,col)
    # into overwrite_insert.
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "keep\t1\t1\t100\td",
        "keep\t1\t2\t101\te",
        "keep\t1\t3\t102\tf",
        "keep\t1\t4\t32\tspace",
        "delete\t1\t5\t104\th",
        "insert\t1\t5\t103\tg",
        "insert\t1\t6\t114\tr",
        "keep\t1\t7\t101\te",
        "delete\t1\t8\t108\tl",
        "delete\t1\t8\t108\tl",
        "delete\t1\t8\t111\to",
        "insert\t1\t8\t101\te",
        "insert\t1\t9\t116\tt",
        "keep\t1\t10\t40\t(",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_overwrite", $input);
    my $n_ow = count_ops($out, "overwrite_insert");
    my $n_del = count_ops($out, "delete");

    ok "overwrite runs on hello->greet pattern" if $out;
    if ($n_del == 0) {
        ok "all 4 deletes absorbed into overwrite_insert (0 standalone deletes)";
    } else {
        bad "expected 0 standalone deletes (got $n_del) - overwrite layer did not fire on multi-delete run";
    }
    if ($n_ow >= 2) {
        ok ">=2 overwrite_insert ops produced (one per delete+insert run)";
    } else {
        bad "expected >=2 overwrite_insert ops, got $n_ow - only single-pair merges detected";
    }

    # Case 2b: 1 delete + 1 insert, no follow-up. The simplest case.
    my $input_b = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "keep\t1\t1\t97\ta",
        "delete\t1\t2\t98\tb",
        "insert\t1\t2\t66\tB",
        "keep\t1\t3\t99\tc",
        "HUNK_END",
        ""
    );
    my $out_b = run_layer("./bin/ad_layer_overwrite", $input_b);
    my $n_ow_b = count_ops($out_b, "overwrite_insert");
    my $n_del_b = count_ops($out_b, "delete");
    if ($n_ow_b == 1 && $n_del_b == 0) {
        ok "simple 1:1 merge: 1 overwrite_insert, 0 deletes";
    } else {
        bad "simple 1:1 merge failed: ow=$n_ow_b del=$n_del_b";
    }
}

# ====================================================================
# 3. ad_layer_indent_last
# ====================================================================
print "\n=== ad_layer_indent_last ===\n";
{
    # Input: 2 leading whitespace deletes + content deletes + \n op.
    # Without layer: ws_del ws_del content_del content_del \n_del
    # With layer:    content_del content_del (col bumped +2) ws_del ws_del \n_del
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "delete\t1\t1\t32\tspace",
        "delete\t1\t2\t32\tspace",
        "delete\t1\t3\t97\ta",
        "delete\t1\t4\t98\tb",
        "delete\t1\t5\t10\t\\n",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_indent_last", $input);

    ok "indent_last runs" if $out;
    # The first 'delete' op in the output should have col > 1
    # (i.e. it's a content delete, not an indent delete).
    if ($out =~ /^delete\t(\d+)\t(\d+)\t(\d+)/m) {
        my ($fl, $fc, $fcode) = ($1, $2, $3);
        if ($fc > 1) {
            ok "first delete is content (col $fc > 1), not leading whitespace";
        } elsif ($fc == 1 && $fcode == 32) {
            bad "first delete is leading whitespace (col 1, space) - not moved to end";
        } else {
            bad "first delete at col 1, code $fcode - unexpected";
        }
    } else {
        bad "could not parse first delete op";
    }
    # Content deletes should have their col bumped by +2 (the 2 indent deletes).
    # Original content delete was at col 3 (a). After bump: col 5.
    if ($out =~ /^delete\t1\t5\t97/m) {
        ok "content delete 'a' col bumped from 3 to 5 (+n_indent)";
    } else {
        bad "content delete col not bumped correctly";
    }
}

# ====================================================================
# 4. ad_layer_line_delete_in_place
# ====================================================================
print "\n=== ad_layer_line_delete_in_place ===\n";
{
    # Input: delete(line1 content) + join_lines + delete(line2 content) + join_lines
    # Layer should reorder to: delete(line1) + delete(line2 at L+1) + join + join
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t2\t0\t0\t0",
        "delete\t1\t1\t97\ta",
        "delete\t1\t2\t98\tb",
        "join_lines\t1",
        "delete\t1\t1\t99\tc",
        "delete\t1\t2\t100\td",
        "join_lines\t1",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_line_delete_in_place", $input);

    ok "line_delete_in_place runs" if $out;
    # All content deletes should come BEFORE any join_lines.
    my $first_join = first_pos($out, "join_lines\t");
    my $last_content_del = last_match_pos($out, qr/^delete\t/m);
    if ($first_join >= 0 && $last_content_del >= 0 && $last_content_del < $first_join) {
        ok "all content deletes come before all join_lines (batch mode)";
    } else {
        bad "content deletes not before joins: last_del=$last_content_del first_join=$first_join";
    }
}

# ====================================================================
# 5. ad_layer_split_in_place
# ====================================================================
print "\n=== ad_layer_split_in_place ===\n";
{
    # Input: insert(L, col 1, chars) + split_line(L, K)
    # Layer should reorder to: split_line(L, 1) + insert(L, col 1, chars)
    # Only fires when the hunk has del > 0 (line has old content).
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "insert\t1\t1\t97\ta",
        "insert\t1\t2\t98\tb",
        "split_line\t1\t3",
        "keep\t1\t4\t99\tc",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_split_in_place", $input);

    ok "split_in_place runs" if $out;
    # split_line should come BEFORE any insert.
    my $first_insert = first_pos($out, "insert\t");
    my $split_pos = first_pos($out, "split_line\t");
    if ($split_pos >= 0 && $first_insert >= 0 && $split_pos < $first_insert) {
        ok "split_line emitted before inserts";
    } else {
        bad "split_line not before inserts: split=$split_pos first_insert=$first_insert";
    }
}

# ====================================================================
# 6. ad_layer_join_insert_in_place
# ====================================================================
print "\n=== ad_layer_join_insert_in_place ===\n";
{
    # Input: join_lines(L) + insert(L, col 1, chars) + keep(L, ...)
    # Layer should reorder to: insert(L+1, col 1, chars) + keep(L+1, ...) + join_lines(L)
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "join_lines\t1",
        "insert\t1\t1\t97\ta",
        "insert\t1\t2\t98\tb",
        "keep\t1\t3\t99\tc",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_join_insert_in_place", $input);

    ok "join_insert_in_place runs" if $out;
    # join_lines should come AFTER the inserts (moved to the end of the run).
    my $first_insert = first_pos($out, "insert\t");
    my $join_pos = last_match_pos($out, qr/^join_lines\t/m);
    if ($join_pos >= 0 && $first_insert >= 0 && $first_insert < $join_pos) {
        ok "join_lines moved after inserts";
    } else {
        bad "join_lines not after inserts: first_insert=$first_insert join=$join_pos";
    }
    # The inserts should now be at line 2 (originally line 1, bumped +1).
    if ($out =~ /^insert\t2\t1\t97/m) {
        ok "insert line bumped from 1 to 2 (L+1)";
    } else {
        bad "insert line not bumped to L+1";
    }
}

# ====================================================================
# 7. ad_layer_batch_whitespace
# ====================================================================
print "\n=== ad_layer_batch_whitespace ===\n";
{
    # Input: 4 consecutive space inserts followed by content.
    # Layer should batch the 4 spaces into a single batch_insert op.
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "insert\t1\t1\t32\tspace",
        "insert\t1\t2\t32\tspace",
        "insert\t1\t3\t32\tspace",
        "insert\t1\t4\t32\tspace",
        "insert\t1\t5\t97\ta",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_batch_whitespace", $input);

    ok "batch_whitespace runs" if $out;
    my $n_batch = count_ops($out, "batch_insert");
    my $n_space_ins = () = ($out =~ /^insert\t\d+\t\d+\t32\t/mg);
    if ($n_batch >= 1) {
        ok ">=1 batch_insert op produced from whitespace run";
    } else {
        bad "no batch_insert op produced";
    }
    if ($n_space_ins == 0) {
        ok "all 4 standalone space inserts absorbed into batch";
    } else {
        bad "$n_space_ins standalone space inserts remain (expected 0)";
    }
}

# ====================================================================
# 8. ad_layer_skip_indent
# ====================================================================
print "\n=== ad_layer_skip_indent ===\n";
{
    # Input: indent-only hunk (all deletes/inserts are whitespace or \n).
    # Layer should wrap with delay markers for instant application.
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "delete\t1\t1\t32\tspace",
        "delete\t1\t2\t32\tspace",
        "insert\t1\t1\t32\tspace",
        "insert\t1\t2\t32\tspace",
        "insert\t1\t3\t32\tspace",
        "insert\t1\t4\t32\tspace",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_skip_indent", $input);

    ok "skip_indent runs" if $out;
    # The layer emits delay markers: "delay\t-1\t0\t0" (start) and
    # "delay\t-1\t1\t<N>" (end).
    if ($out =~ /^delay\t-1\t0\t/m) {
        ok "indent_skip_start marker emitted (delay -1 0 0)";
    } else {
        bad "no indent_skip_start marker found";
    }
    if ($out =~ /^delay\t-1\t1\t/m) {
        ok "indent_skip_end marker emitted (delay -1 1 <pause_ms>)";
    } else {
        bad "no indent_skip_end marker found";
    }

    # Case 8b: non-indent hunk (content change) - should NOT wrap.
    my $input_b = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "delete\t1\t1\t97\ta",
        "insert\t1\t1\t98\tb",
        "HUNK_END",
        ""
    );
    my $out_b = run_layer("./bin/ad_layer_skip_indent", $input_b);
    if ($out_b =~ /^delay\t-1\t0\t/m) {
        bad "indent_skip marker emitted on a non-indent hunk (false positive)";
    } else {
        ok "no skip marker on content-change hunk";
    }
}

# ====================================================================
# 9. ad_layer_line_replace
# ====================================================================
print "\n=== ad_layer_line_replace ===\n";
{
    # Input: line 1 has a char-level change (delete + insert).
    # Layer should collapse to: delete_line 1 + insert_line 1 <final_text>
    my $input = join("\n",
        "# raw diff v2",
        "HUNK\t1\t1\t1\t0\t0",
        "keep\t1\t1\t97\ta",
        "delete\t1\t2\t98\tb",
        "insert\t1\t2\t66\tB",
        "keep\t1\t3\t99\tc",
        "HUNK_END",
        ""
    );
    my $out = run_layer("./bin/ad_layer_line_replace", $input);

    ok "line_replace runs" if $out;
    my $n_dl = count_ops($out, "delete_line");
    my $n_il = count_ops($out, "insert_line");
    my $n_del = count_ops($out, "delete");
    my $n_ins = count_ops($out, "insert");
    if ($n_dl == 1 && $n_il == 1) {
        ok "1 delete_line + 1 insert_line emitted";
    } else {
        bad "expected 1 delete_line + 1 insert_line, got dl=$n_dl il=$n_il";
    }
    if ($n_del == 0 && $n_ins == 0) {
        ok "all char-level ops absorbed into line-level ops";
    } else {
        bad "char-level ops remain: del=$n_del ins=$n_ins (expected 0,0)";
    }
    # The insert_line should contain the final text "aBc".
    if ($out =~ /^insert_line\t1\taBc$/m) {
        ok "insert_line text is 'aBc' (final line content)";
    } else {
        bad "insert_line text not 'aBc'";
    }
}

# ====================================================================
# Final summary
# ====================================================================
print "\n=== Layer contract results: $pass passed, $fail failed ===\n";
if ($fail > 0) {
    print "Failed assertions:\n";
    for my $e (@errors) { print "  - $e\n"; }
}
exit($fail > 0 ? 1 : 0);
'''

# Replace literal \t escape sequences with real tabs in the join() calls.
# The content above has \t as two-character escapes inside double-quoted
# Perl strings, which Perl itself will interpret as tabs at runtime.
# So we don't need to do any post-processing — Perl handles it.

out = Path("/home/z/my-project/gitanim/tests/test_layer_contracts.pl")
out.write_text(content)
print(f"Wrote {out} ({len(content)} bytes)")
