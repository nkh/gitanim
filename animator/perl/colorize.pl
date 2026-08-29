#!/usr/bin/env perl
# diffvim-colorize — Produce a color map file for the animator.
#
# Given a source file and a language, produces a color map file where
# each line is the ANSI-colored version of the corresponding source line.
# The animator loads this file and uses the colored lines for rendering.
#
# Backends:
#   vim         Use vim's syntax highlighting (most accurate)
#   pygmentize  Use Pygments Python library
#   none        No coloring (plain text)
#
# Usage:
#   diffvim-colorize [--backend vim|pygmentize|none] [--lang LANG] FILE OUTPUT
#
# The output file has one line per source line. Each line contains the
# ANSI-escaped colored version of that source line. Lines are separated
# by \n. ANSI escape sequences use \033[...m format.
#
# The animator reads this file into an array and uses the colored lines
# for rendering. When a char is deleted or inserted, the animator updates
# the colored line accordingly.

use strict;
use warnings;
use Getopt::Long qw(GetOptions);
use File::Temp qw(tempfile);

my $backend = 'auto';  # auto-detect: vim > pygmentize > none
my $lang = 'auto';     # auto-detect from file extension
my $help = 0;

GetOptions(
    'backend=s' => \$backend,
    'lang=s'    => \$lang,
    'help|h'    => \$help,
) or die "Usage: $0 [--backend vim|pygmentize|none] [--lang LANG] FILE OUTPUT\n";

if ($help) {
    print STDERR <<USAGE;
diffvim-colorize — Produce a color map file for the animator

Usage: diffvim-colorize [options] FILE OUTPUT

Options:
  --backend vim|pygmentize|none   Coloring backend (default: auto)
  --lang LANG                      Source language (default: auto-detect from extension)
  -h, --help                       Show this help

Backends:
  vim         Use vim's syntax highlighting (most accurate, requires vim)
  pygmentize  Use Pygments Python library (requires pygmentize)
  none        No coloring (plain text output)

Auto-detection order: vim > pygmentize > none

Output format:
  One line per source line. Each line is the ANSI-colored version
  of that source line, with embedded \\033[...m escape sequences.
  The animator loads this into an array and uses colored lines for
  rendering.

Examples:
  diffvim-colorize old.py old.colormap
  diffvim-colorize --backend vim --lang python old.py old.colormap
  diffvim-colorize --backend pygmentize new.py new.colormap
USAGE
    exit 0;
}

@ARGV >= 2 or die "Usage: $0 [--backend ...] [--lang ...] FILE OUTPUT\n";
my ($infile, $outfile) = @ARGV;

# Auto-detect language from file extension
if ($lang eq 'auto') {
    my %ext_map = (
        py => 'python', rb => 'ruby', js => 'javascript', ts => 'typescript',
        go => 'go', rs => 'rust', c => 'c', h => 'c',
        cpp => 'cpp', cxx => 'cpp', hpp => 'cpp', hxx => 'cpp',
        java => 'java', kt => 'kotlin', scala => 'scala',
        swift => 'swift', php => 'php', pl => 'perl', pm => 'perl',
        lua => 'lua', r => 'r', R => 'r', sql => 'sql',
        sh => 'sh', bash => 'sh', zsh => 'sh',
        html => 'html', htm => 'html', xml => 'xml',
        css => 'css', json => 'json', yaml => 'yaml', yml => 'yaml',
        toml => 'toml', md => 'markdown', Dockerfile => 'dockerfile',
        Makefile => 'make', ml => 'ocaml', fs => 'fsharp',
        hs => 'haskell', clj => 'clojure', ex => 'elixir',
        erl => 'erlang', vim => 'vim', el => 'emacs',
    );
    if ($infile =~ /\.(\w+)$/) {
        $lang = $ext_map{$1} // $1;
    } elsif ($infile =~ /(\w+)$/) {
        $lang = $ext_map{$1} // 'text';
    } else {
        $lang = 'text';
    }
}

# Auto-detect backend
if ($backend eq 'auto') {
    if (qx(which vim 2>/dev/null) =~ /\S/) {
        $backend = 'vim';
    } elsif (qx(which pygmentize 2>/dev/null) =~ /\S/) {
        $backend = 'pygmentize';
    } else {
        $backend = 'none';
    }
}

# Read input file
open my $fh, '<:raw', $infile or die "Cannot read $infile: $!\n";
my @lines = <$fh>;
close $fh;
chomp @lines;

# Map vim syntax IDs to ANSI colors

sub colorize_with_vim {
    my ($file, $lang, $lines_ref) = @_;
    my @colored;

    # Create a vimscript that extracts syntax colors per char.
    # NOTE: vimscript variable names must NOT use 'l:sid' — it's an illegal
    # name in vim. Use 'synid' without scope prefix instead.
    my ($vim_fh, $vim_script) = tempfile(UNLINK => 1, SUFFIX => '.vim');
    print $vim_fh <<'VIM';
" diffvim-colorize — extract ANSI colors per line using vim's syntax highlighting

" Map vim syntax group names to ANSI escape sequences (defined first!)
function! SynToAnsi(name) abort
    let n = tolower(a:name)
    if n =~# 'statement\|keyword\|conditional\|repeat\|label\|operator\|exception'
        return "\033[1;33m"
    elseif n =~# 'type\|storageclass\|structure\|typedef'
        return "\033[1;32m"
    elseif n =~# 'string\|character'
        return "\033[0;32m"
    elseif n =~# 'number\|boolean\|float'
        return "\033[0;33m"
    elseif n =~# 'function'
        return "\033[1;34m"
    elseif n =~# 'identifier'
        return "\033[0;34m"
    elseif n =~# 'constant'
        return "\033[0;35m"
    elseif n =~# 'preproc\|include\|define\|macro\|precondit'
        return "\033[0;35m"
    elseif n =~# 'comment\|specialcomment'
        return "\033[0;36m"
    elseif n =~# 'special\|tag\|delimiter'
        return "\033[0;35m"
    elseif n =~# 'error\|debug\|todo'
        return "\033[0;31m"
    endif
    return "\033[0m"
endfunction

" Enable syntax highlighting
syntax enable
filetype on

" Set filetype based on file extension
let ext = expand('%:e')
if ext ==# 'py'
    setfiletype python
elseif ext ==# 'rb'
    setfiletype ruby
elseif ext ==# 'js'
    setfiletype javascript
elseif ext ==# 'ts'
    setfiletype typescript
elseif ext ==# 'go'
    setfiletype go
elseif ext ==# 'rs'
    setfiletype rust
elseif ext ==# 'c' || ext ==# 'h'
    setfiletype c
elseif ext ==# 'cpp' || ext ==# 'cxx' || ext ==# 'hpp' || ext ==# 'hxx'
    setfiletype cpp
elseif ext ==# 'java'
    setfiletype java
elseif ext ==# 'pl' || ext ==# 'pm'
    setfiletype perl
elseif ext ==# 'sh' || ext ==# 'bash'
    setfiletype sh
elseif ext ==# 'html' || ext ==# 'htm'
    setfiletype html
elseif ext ==# 'xml'
    setfiletype xml
elseif ext ==# 'css'
    setfiletype css
elseif ext ==# 'json'
    setfiletype json
elseif ext ==# 'yaml' || ext ==# 'yml'
    setfiletype yaml
elseif ext ==# 'md'
    setfiletype markdown
elseif ext ==# 'lua'
    setfiletype lua
elseif ext ==# 'sql'
    setfiletype sql
endif

" Force syntax to load
execute 'runtime! syntax/' . &filetype . '.vim'

" Build the colored output
let out_lines = []
let ansi_cache = {}
let linecount = line('$')

for lnum in range(1, linecount)
    let line = getline(lnum)
    let colored = ''
    let prev_color = "\033[0m"
    let ncols = strchars(line)

    for col in range(1, ncols)
        let synid = synID(lnum, col, 1)
        let synname = synIDattr(synid, 'name')

        if !has_key(ansi_cache, synname)
            let ansi_cache[synname] = SynToAnsi(synname)
        endif
        let color = ansi_cache[synname]

        if color !=# prev_color
            let colored .= color
            let prev_color = color
        endif

        let byte = byteidx(line, col - 1)
        let nextbyte = byteidx(line, col)
        if nextbyte < 0
            let nextbyte = strlen(line)
        endif
        let ch = strpart(line, byte, nextbyte - byte)
        let colored .= ch
    endfor

    if prev_color !=# "\033[0m"
        let colored .= "\033[0m"
    endif

    call add(out_lines, colored)
endfor

call writefile(out_lines, g:colorize_output, 'b')
VIM
    close $vim_fh;

    # Run vim with the script — pass the output path via g:colorize_output.
    # Use list-form system() to avoid command injection via $file paths
    # containing shell metacharacters.
    my $rc = system("vim", "-u", "NONE", "-N", "-n", "-es",
           "-c", "let g:colorize_output = \"$outfile\"",
           "-c", "source $vim_script",
           $file);
    # Redirect stdin from /dev/null and stderr to /dev/null
    # (list-form system doesn't support shell redirects, so we do it via
    #  open3 or just accept the noise)
    # vim may exit non-zero but still produce output

    # Check if output was created
    if (-f $outfile) {
        open my $ofh, '<:raw', $outfile or die "Cannot read $outfile: $!\n";
        @colored = <$ofh>;
        close $ofh;
        chomp @colored;
    } else {
        # Fallback: no coloring
        @colored = @$lines_ref;
    }

    return @colored;
}

sub colorize_with_pygmentize {
    my ($file, $lang, $lines_ref) = @_;
    my @colored;

    # Use pygmentize with terminal256 formatter.
    # Use list-form system() with pipe capture to avoid command injection.
    my $output = '';
    my $pid = open(my $pyg_fh, '-|');
    if (defined $pid) {
        if ($pid == 0) {
            # Child: exec pygmentize with list form (safe, no shell)
            open(STDERR, '>', '/dev/null');
            exec('pygmentize', '-l', $lang, '-f', 'terminal256',
                 '-O', 'bg=dark', $file)
                or exit(1);
        }
        # Parent: read output
        local $/;
        $output = <$pyg_fh>;
        close $pyg_fh;
    }

    if ($? == 0 && $output) {
        @colored = split /\n/, $output, -1;
        # pygmentize adds a trailing newline, so last element might be empty
        pop @colored if @colored && $colored[-1] eq '';
        # Reset ANSI at the end of each line
        for my $i (0..$#colored) {
            $colored[$i] .= "\033[0m" unless $colored[$i] =~ /\033\[0m$/;
        }
    } else {
        # Fallback: no coloring
        @colored = @$lines_ref;
    }

    return @colored;
}

sub colorize_none {
    my ($lines_ref) = @_;
    return @$lines_ref;
}

# Run the appropriate backend
my @colored;
if ($backend eq 'vim') {
    @colored = colorize_with_vim($infile, $lang, \@lines);
} elsif ($backend eq 'pygmentize') {
    @colored = colorize_with_pygmentize($infile, $lang, \@lines);
} else {
    @colored = colorize_none(\@lines);
}

# Write output
open my $ofh, '>:raw', $outfile or die "Cannot write $outfile: $!\n";
for my $line (@colored) {
    print $ofh $line, "\n";
}
close $ofh;

print STDERR "diffvim-colorize: $backend backend, " . scalar(@colored) . " lines → $outfile\n";
