# tests/minimal/

25 minimal old/new file pairs, each testing ONE specific transformation:
simple replace, simple insert, simple delete, delete to EOL, insert at
BOL/EOL, line replace, insert/delete line at start/middle/end, multi-line
delete, split line, join two lines, indent change, trailing whitespace,
unicode, empty old/new, identical files, pure add at EOF, complex mix.

## Usage

    bash tests/run_minimal_tests.sh

Each pair is run through the full pipeline. The final buffer must match
`new`. 25/25 should pass.
