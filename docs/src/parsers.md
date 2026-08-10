# Diff Parsers

The `diffvim.pl` implementation supports pluggable diff parsers.

## Parser API

Every parser module must export a `parse_diff` function:

```perl
parse_diff($old_file, $new_file, \%options)
```

### Options

- `word_diff => 1` — use word-level diff instead of char-level

### Return Value

```perl
{
    hunks => [
        {
            target_line   => 2,          # 1-indexed line in old file
            char_ops      => [           # ordered char-level operations
                { op => 'keep',   code => 32 },
                { op => 'insert', code => 102 },
                { op => 'delete', code => 34 },
            ],
            deleted_count  => 1,
            inserted_count => 1,
            is_end_insert  => 0,
            is_end_delete  => 0,
            old_text       => '...',
            new_text       => '...',
        },
    ],
    parser => 'perl',
}
```

## Included Parsers

### DiffVim::Parser::Perl

Pure-Perl LCS diff. No external dependencies beyond Perl core.

- Line-level: LCS dynamic programming (O(N×M))
- Char-level: LCS on character arrays
- Word-level: LCS on word/whitespace tokens (with `--word-diff`)

### DiffVim::Parser::Diff2Html

Shells out to `diff2html -f json` CLI for line-level parsing, then
computes char-level LCS in Perl.

- Requires `diff2html-cli` (`npm install -g diff2html-cli`)
- Produces identical output to the Perl parser
- Handles identical files (empty diff) gracefully

## Selecting a Parser

```bash
# Default (perl)
perl diffvim.pl old.py new.py

# diff2html
perl diffvim.pl --parser diff2html old.py new.py

# With word-level diff
perl diffvim.pl --word-diff old.py new.py
```

## Writing a Custom Parser

Create a Perl module that exports `parse_diff`:

```perl
package DiffVim::Parser::MyParser;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(parse_diff);

sub parse_diff {
    my ($old_file, $new_file, $options) = @_;
    # ... your diff logic ...
    return { hunks => \@hunks, parser => 'myparser' };
}
1;
```

Then add it to `diffvim.pl`'s `compute_diff` function.
