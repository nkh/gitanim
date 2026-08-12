#!/usr/bin/env perl
# test_precomputed.pl - Verify that --precomputed FILE produces the same
# buffer content as inline computation. The external compute tools (C, C++,
# Rust, Go) produce a file that diffvim consumes via --precomputed; the
# resulting animation must produce exactly the same buffer as diffvim's
# built-in vimscript LCS diff.

use strict;
use warnings;

my $pass = 0;
my $fail = 0;
my $engine_file = '/tmp/dv_pc_engine.vim';

sub extract_engine {
    open my $fh, '<', 'diffvim' or die "Cannot open diffvim: $!";
    my $in_engine = 0;
    my @lines;
    while (my $line = <$fh>) {
        if ($line =~ /^cat > "\$VIMSCRIPT" <<.__DIFFVIM_VIMSCRIPT_EOF__.$/) {
            $in_engine = 1;
            next;
        }
        if ($line =~ /^__DIFFVIM_VIMSCRIPT_EOF__$/) {
            last;
        }
        push @lines, $line if $in_engine;
    }
    close $fh;
    my $content = join('', @lines);
    $content =~ s/^augroup diffvim\n.*?\naugroup END\n//ms;
    return $content;
}

sub run_vim {
    my ($oldf, $newf, $outf, $precomputed) = @_;
    my $engine = extract_engine();
    $engine .= <<'VIM';

function! s:RunTest() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
        endif
        return
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'idle'
    let s:state.stopped = 0
    let s:state.paused = 0
    let s:cur_l = line('.')
    let s:cur_c = col('.')
    while s:state.hunk_idx < len(s:state.hunks)
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let s:state.op_idx = 0
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line('$')
            let s:cur_l = line('$')
            let s:cur_c = len(getline(line('$'))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line('$') | let l:prev = line('$') | endif
            let s:cur_l = l:prev
            let s:cur_c = len(getline(l:prev)) + 1
        else
            let s:cur_l = l:target_line
            let s:cur_c = 1
        endif
        call s:PlaceCursor()
        let l:ops = l:hunk.char_ops
        while s:state.op_idx < len(l:ops)
            let l:op = l:ops[s:state.op_idx]
            if l:op[0] ==# 'delete' && g:diffvim.rapid_eol_delete
                let l:rc = s:LookaheadEOLDelete(l:ops, s:state.op_idx)
                if l:rc >= g:diffvim.rapid_eol_min_chars
                    for l:i in range(l:rc)
                        call s:DeleteCharAtCursor()
                    endfor
                    let s:state.op_idx += l:rc
                    continue
                endif
            endif
            if l:op[0] ==# 'keep'
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
            endif
            let s:state.op_idx += 1
        endwhile
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
    endwhile
    if !empty(g:diffvim.output_file)
        execute 'w! ' . g:diffvim.output_file
    endif
endfunction

call s:RunTest()
qa!
VIM

    open my $fh, '>', $engine_file; print $fh $engine; close $fh;

    if (defined $precomputed) {
        $ENV{DIFFVIM_PRECOMPUTED} = $precomputed;
    } else {
        delete $ENV{DIFFVIM_PRECOMPUTED};
    }

    system("vim -e -s -n -Nu NONE -U NONE " .
           "-c \"let g:diffvim_new_file = '$newf'\" " .
           "-c \"let g:diffvim = {'output_file': '$outf'}\" " .
           "-c \"source $engine_file\" " .
           "\"$oldf\" > /dev/null 2>&1");

    my $got = '';
    if (-f $outf) {
        local $/;
        open $fh, '<:raw', $outf; $got = <$fh>; close $fh;
    }
    return $got;
}

sub read_file {
    my ($path) = @_;
    local $/;
    open my $fh, '<:raw', $path or return '';
    return <$fh>;
}

# Test with all example file pairs
my @pairs;
for my $dir (glob("examples/*/")) {
    my @old_files = glob("$dir/old.*");
    for my $old (@old_files) {
        my $ext = $old =~ /\.(\w+)$/ ? $1 : 'txt';
        (my $new = $old) =~ s/old\.\w+$/new.$ext/;
        if (-f $new) {
            push @pairs, [$old, $new];
        }
    }
}

print "=== Precomputed Diff Correctness Test ===\n";
print "Verifies that --precomputed produces the same buffer as inline.\n\n";

my $compute_c = $ENV{DIFFVIM_COMPUTE_TOOL} || "compute/bin/diffvim-compute-c";
die "$compute_c not found. Run 'make -C compute' first.\n" unless -f $compute_c;

my $tmp = "/tmp/dv_pc_test";
mkdir $tmp unless -d $tmp;

for my $pair (@pairs) {
    my ($old, $new) = @$pair;
    my $name = $old;
    $name =~ s|^examples/||;

    my $expected = read_file($new);
    $expected =~ s/\n+$//;

    # Run with precomputed
    my $pc_file = "$tmp/precomputed.txt";
    system("$compute_c '$old' '$new' '$pc_file' > /dev/null 2>&1");
    my $out_pc = "$tmp/out_pc.txt";
    unlink $out_pc if -f $out_pc;
    my $got_pc = run_vim($old, $new, $out_pc, $pc_file);
    $got_pc =~ s/\n+$//;

    # Run without precomputed (inline)
    my $out_inline = "$tmp/out_inline.txt";
    unlink $out_inline if -f $out_inline;
    my $got_inline = run_vim($old, $new, $out_inline, undef);
    $got_inline =~ s/\n+$//;

    if ($got_pc eq $expected && $got_inline eq $expected) {
        print "PASS: $name\n";
        $pass++;
    } else {
        print "FAIL: $name\n";
        if ($got_inline ne $expected) {
            print "  inline differs from expected\n";
        }
        if ($got_pc ne $expected) {
            print "  precomputed differs from expected\n";
            # Show first diff
            my @pc = split /\n/, $got_pc;
            my @ex = split /\n/, $expected;
            for my $i (0 .. $#ex) {
                next if $i > $#pc;
                if ($pc[$i] ne $ex[$i]) {
                    print "    line " . ($i+1) . ": expected=\"$ex[$i]\" got=\"$pc[$i]\"\n";
                    last;
                }
            }
        }
        $fail++;
    }
}

print "\n=== Results: $pass passed, $fail failed ===\n";
exit($fail == 0 ? 0 : 1);
