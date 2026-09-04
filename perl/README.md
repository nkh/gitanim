# perl/

Shared Perl library code for the ad pipeline.

## Contents

- `DiffVim/Layer.pm` — Shared layer runner (`run_layer` function).
  Handles hunk-by-hunk TSV I/O, line_offset tracking, and debug logging.
  All Perl layers use this module.
- `DiffVim/Parser/Perl.pm` — Perl diff parser (used by the Perl compute fallback).

## Usage

Perl layers source this module:
```perl
use FindBin;
use lib "$FindBin::Bin/../../perl";
use DiffVim::Layer qw(run_layer parse_op write_op char_repr is_debug_op);

exit run_layer(\&transform_hunk, name => 'my_layer (Perl)');
```

## Namespace

The `DiffVim` namespace is historical — the project was originally called
`diffvim`. The namespace is kept for compatibility with existing Perl code.
