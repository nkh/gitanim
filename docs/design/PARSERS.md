# Diff Parsers

This document describes the diff parser module used by `ad_vim.pl`
and how to write your own parser.

---

## Overview

`ad_vim.pl` uses a single built-in parser:

| Parser                  | File                       | Algorithm                          |
| ----------------------- | -------------------------- | ---------------------------------- |
| `DiffVim::Parser::Perl` | `DiffVim/Parser/Perl.pm`   | Pure-Perl Patience (line + char level)  |

The parser uses Patience dynamic programming at both the line level and the
character level, with the optional Patience algorithm at the
line level. It has no external dependencies beyond Perl 5.10+ and the
core `Algorithm::Diff` module (optional, for faster line-level diff).

---

## Parser API

Every parser module must export a single function:

```perl
parse_diff($old_file, $new_file)
```

### Parameters

- `$old_file` — absolute path to the old file (string)
- `$new_file` — absolute path to the new file (string)

### Return value

A hash reference with the following structure:

```perl
{
    hunks => [
        {
            target_line   => 2,          # 1-indexed line in old file where the hunk starts
            char_ops      => [           # ordered list of char-level operations
                { op => 'keep',   code => 32 },   # keep space (ASCII 32)
                { op => 'insert', code => 102 },  # insert 'f' (ASCII 102)
                { op => 'delete', code => 34 },   # delete '"' (ASCII 34)
                ...
            ],
            deleted_count  => 1,         # number of old lines deleted in this hunk
            inserted_count => 1,         # number of new lines inserted in this hunk
            is_end_insert  => 0,         # 1 if this is a pure insertion at end of file
            is_end_delete  => 0,         # 1 if this is a pure deletion at end of file
            old_text       => '    print("Hello, " + name)',
            new_text       => '    print(f"Hello, {name}!")',
        },
        ...
    ],
    parser => 'perl',   # parser identifier string
}
```

### Field semantics

#### `target_line`

The 1-indexed line number in the **old** file where the hunk begins.
This is where the cursor should be positioned before applying the
char ops.

For pure insertions at the start of the file, `target_line` is 1.
For pure insertions at the end of the file, `target_line` is
`old_line_count + 1` (one past the last line).

#### `char_ops`

An ordered list of character-level operations. Each operation is a
hash with two keys:

- `op` — one of `'keep'`, `'delete'`, or `'insert'`
- `code` — the ASCII/Unicode code point of the character

| Op        | Meaning                                                      |
| --------- | ------------------------------------------------------------ |
| `keep`    | The character at the current cursor position is unchanged. Advance the cursor. |
| `delete`  | Delete the character at the current cursor position. Cursor stays. |
| `insert`  | Insert the character at the current cursor position. Cursor advances past the inserted char. |

The operations are ordered so that applying them sequentially (starting
from `target_line`, column 1) transforms the old text into the new text.

**Newline handling:** `code = 10` (ASCII LF) represents a newline.
- For `keep`: advance the cursor to the next line, column 1.
- For `insert`: split the current line at the cursor position; the
  remainder becomes a new line.
- For `delete`: if the cursor is past the end of the line, join with
  the next line (removing the newline).

#### `deleted_count` / `inserted_count`

The number of old lines deleted and new lines inserted in this hunk.
Used to track the line offset (since subsequent hunks' target lines
shift as earlier hunks add/remove lines).

#### `is_end_insert` / `is_end_delete`

Flags indicating whether this hunk is a pure insertion or deletion at
the end of the file. These affect cursor positioning:

- `is_end_insert = 1`: the cursor should be positioned at the **end**
  of the last line (not the start of a new line), because the new
  content starts with a `\n` that creates a new line after the current
  last line.
- `is_end_delete = 1`: the cursor should be positioned at the **end**
  of the previous line, because the old text starts with a `\n` that
  joins the current line with the previous one.

#### `old_text` / `new_text`

The joined text of the deleted and inserted lines (for debugging).
These are not used by the animation engine — only `char_ops` is used
to apply the transformation.

#### `parser`

A string identifying which parser produced this result. Useful for
logging and debugging.

---

## Parser 1: `DiffVim::Parser::Perl`

### Algorithm

1. **Line-level diff** — Patience dynamic programming
   - If `Algorithm::Diff` is installed, uses it (faster C implementation)
   - Otherwise, uses a built-in Patience DP algorithm (O(N×M) time and space)
2. **Hunk grouping** — consecutive non-keep line ops are grouped
3. **Char-level diff** — Patience DP on the character arrays of the joined
   old/new text within each hunk

### Special cases handled

- **Pure insertion** (no deleted lines): adds a `\n` separator so the
  new content becomes a separate line instead of merging into the
  adjacent line.
  - If inserting at end of file: prepend `\n` to the new text
  - If inserting at start/middle: append `\n` to the new text
  - If old file is empty: no separator needed
- **Pure deletion** (no inserted lines): adds a `\n` to the old text
  so the line vanishes entirely (otherwise an empty line would remain).
  - If deleting at end of file: prepend `\n` to the old text
  - If deleting at start/middle: append `\n` to the old text

### Usage

```perl
use DiffVim::Parser::Perl qw(parse_diff);

my $result = parse_diff('old.txt', 'new.txt');
for my $hunk (@{$result->{hunks}}) {
    print "Hunk at line $hunk->{target_line}\n";
    for my $op (@{$hunk->{char_ops}}) {
        printf "  %s %s\n", $op->{op}, chr($op->{code});
    }
}
```

### Dependencies

- Perl 5.10+ (uses `//` operator)
- `Algorithm::Diff` (optional, for faster line-level diff)


## Writing a Custom Parser

To add a new parser, create a Perl module that exports a `parse_diff`
function matching the API above.

### Example: a minimal parser using Git

```perl
package DiffVim::Parser::Git;
use strict;
use warnings;
use Exporter qw(import);
our @EXPORT_OK = qw(parse_diff);

sub parse_diff {
    my ($old_file, $new_file) = @_;

    # Use git diff to compute the line-level diff
    my $diff = `git diff --no-index --unified=0 '$old_file' '$new_file' 2>/dev/null`;

    # Parse the git diff output...
    # (implementation omitted for brevity)

    # Build hunks with char_ops using the same Patience algorithm
    my @hunks;
    # ...

    return { hunks => \@hunks, parser => 'git' };
}

1;
```

### Registering a custom parser

To use a custom parser with `ad_vim.pl`, either:

1. **Modify `ad_vim.pl`** to add a new `--parser` option:

```perl
if ($parser_name eq 'git') {
    require DiffVim::Parser::Git;
    my $result = DiffVim::Parser::Git::parse_diff($old_file, $new_file);
    @hunks = @{$result->{hunks}};
    $parser_used = $result->{parser};
}
```

2. **Or set `PERL5LIB`** to include your module directory and modify
   the parser selection logic.

### Parser correctness

To verify your parser produces correct output, run the parser test
suite:

```bash
perl tests/test_parsers.pl
```

This tests 9 cases (9 assertions) and verifies that applying the char
ops to the old file produces exactly the new file.

You can also compare your parser's output against the Perl parser:

```perl
use DiffVim::Parser::Perl qw(parse_diff);
use Your::Parser qw(parse_diff);

my $r1 = DiffVim::Parser::Perl::parse_diff('old.txt', 'new.txt');
my $r2 = Your::Parser::parse_diff('old.txt', 'new.txt');

# Compare hunk counts, target lines, char ops, etc.
```

---

## Performance Notes

- **Line-level diff** is the bottleneck for large files. The Patience DP
  algorithm is O(N×M) in time and space. For files with >10,000 lines,
  consider using Patience diff instead.
- **Char-level diff** is fast because it operates on the joined hunk
  text (usually a few hundred characters), not the whole file.
- **`Algorithm::Diff`** uses a C implementation and is ~10x faster than
  the pure-Perl Patience fallback for large files.
- **Memory usage** for the Patience DP table: `N * M * sizeof(int)` bytes.
  For two 10,000-line files, this is ~400MB. Consider streaming diff
  algorithms for very large files.
