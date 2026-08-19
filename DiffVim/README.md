# DiffVim/

Perl module for diff parsing. Used by `compute/perl/compute_builtin.pl`
(the Perl fallback for the C++ compute tool).

## Files

- `Parser/Perl.pm` — Perl diff parser. Implements Patience and LCS
  algorithms, produces char-level ops.

## Usage

This module is loaded by `compute/perl/compute_builtin.pl`:

```perl
use DiffVim::Parser::Perl qw(parse_diff);
my $result = parse_diff($old_file, $new_file, { algorithm => 'patience' });
```

The `parse_diff` function returns a hash with:
- `hunks` — array of hunk objects, each containing:
  - `target_line` — target line in old file
  - `deleted_count`, `inserted_count` — line counts
  - `is_end_insert`, `is_end_delete` — EOF flags
  - `char_ops` — array of `{ op => 'keep|delete|insert', code => N }`

## Related

- `../compute/perl/compute_builtin.pl` — Uses this module
- `../compute/README.md` — Compute stage documentation
