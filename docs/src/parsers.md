# Diff Parsers

*Created:* `4692a55` (2026-08-10 13:37:07 +0000)
*Last updated:* `da64fdb` (2026-08-26 21:10:06 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


The `diffvim.pl` implementation uses a single built-in diff parser.

## Parser API

The parser module exports a `parse_diff` function:

```perl
parse_diff($old_file, $new_file, \%options)
```

### Options

- `word_diff => 1` — use word-level diff instead of char-level
- `algorithm => 'patience'|'patience'` — line-level algorithm

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

## The Built-in Parser: DiffVim::Parser::Perl

Pure-Perl Patience diff. No external dependencies beyond Perl core.

- Line-level: Patience dynamic programming (O(N×M)), with optional
  Patience algorithm (Patience is the default)
- Char-level: Patience on character arrays
- Word-level: Patience on word/whitespace tokens (with `--word-diff`)

## Selecting the Parser

The Perl parser is the default and only parser. The `--parser perl`
flag is accepted for backwards compatibility but has no effect (it
was the only value even before the diff2html removal):

```bash
# Default (perl)
perl diffvim.pl old.py new.py

# Explicit (same as default)
perl diffvim.pl --parser perl old.py new.py

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

Then add it to `diffvim.pl`'s `compute_diff` function. See
`docs/PARSERS.md` for the full reference.
