# diff_engine/

The diff engine: computes the LCS-based character-level diff between
an old and new file, producing raw char ops (HUNK/keep/delete/insert).

## Contents

- `cpp/compute.cpp` — C++ implementation (preferred; built to `bin/ad_compute`)
- `perl/compute.pl` — Perl fallback (produces identical output)
- `tests/l2r/` — left-to-right algorithm tests (35 cases)
- `Makefile` — local build rules (the top-level Makefile also builds this)

## Binary

`bin/ad_compute` — built from `cpp/compute.cpp` by `make`.

Usage:

    ./bin/ad_compute old.py new.py raw_ops.txt

## Output format

V2 TSV: HUNK header, op lines (keep/delete/insert), HUNK_END. See
`docs/src/plugin-layers.md` for the full spec.
