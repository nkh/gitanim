# Testing

This document describes how to test the `diffvim` implementations.

---

## Test Overview

| Test Type         | What it tests                          | Command                          |
| ----------------- | -------------------------------------- | -------------------------------- |
| Parser tests      | Both parsers produce correct output    | `perl tests/test_parsers.pl`     |
| End-to-end tests  | Full animation in tmux + vim           | `perl tests/test_e2e_perl.pl`    |
| Manual tests      | Visual verification of animation       | See below                        |

---

## Parser Tests

### What they test

The parser tests verify that:

1. Both parsers (`DiffVim::Parser::Perl` and
   `DiffVim::Parser::Diff2Html`) produce correct char ops
2. Applying the char ops to the old file produces exactly the new file
3. Edge cases are handled correctly

### Test cases

| #  | Name                        | Old → New                                    |
| -- | --------------------------- | -------------------------------------------- |
| 1  | simple modification         | Two lines, both modified                     |
| 2  | multi-hunk python           | Replace + insert in a Python file            |
| 3  | pure insertion at start     | Add a line at the beginning                  |
| 4  | pure deletion at end        | Remove the last line                         |
| 5  | identical files             | No changes (should produce 0 hunks)          |
| 6  | empty old file              | Old is empty, new has content                |
| 7  | insertion at end            | Add a line at the end                        |
| 8  | mid-line insertion          | Insert text in the middle of a line          |
| 9  | delete middle lines         | Remove lines from the middle                 |

Each case is tested with both parsers, for a total of **18 assertions**.

### Running the tests

```bash
# Ensure PATH includes diff2html (for the diff2html parser tests)
export PATH="/home/z/.local/bin:/home/z/.npm-global/bin:$PATH"
export LD_LIBRARY_PATH="/home/z/.local/lib:${LD_LIBRARY_PATH:-}"

# Run the tests
perl tests/test_parsers.pl
```

### Expected output

```
PASS (perl):      simple modification
PASS (diff2html): simple modification
PASS (perl):      multi-hunk python
PASS (diff2html): multi-hunk python
PASS (perl):      pure insertion at start
PASS (diff2html): pure insertion at start
PASS (perl):      pure deletion at end
PASS (diff2html): pure deletion at end
PASS (perl):      identical files
PASS (diff2html): identical files
PASS (perl):      empty old file
PASS (diff2html): empty old file
PASS (perl):      insertion at end
PASS (diff2html): insertion at end
PASS (perl):      mid-line insertion
PASS (diff2html): mid-line insertion
PASS (perl):      delete middle lines
PASS (diff2html): delete middle lines

Results: 18 passed, 0 failed
```

### How the tests work

The test script (`tests/test_parsers.pl`):

1. Writes the old and new content to temp files
2. Calls `parse_diff()` with both parsers
3. Applies the returned char ops to the old file content (simulating
   the animation)
4. Compares the result with the expected new content
5. Reports PASS/FAIL for each parser

The char op application simulates what vim would do:

```perl
# Simulate applying char ops
my $new_text = '';
for my $op (@{$hunk->{char_ops}}) {
    if ($op->{op} eq 'keep' || $op->{op} eq 'insert') {
        $new_text .= chr($op->{code});
    }
    # delete: skip (don't add to new_text)
}
```

---

## End-to-End Tests

### What they test

End-to-end tests run the full animation in a tmux session and verify
that the vim buffer matches the expected new file after the animation
completes.

### Prerequisites

- tmux 3+ installed and in PATH
- vim 8+ installed and in PATH
- Perl 5.10+
- For the diff2html test: `diff2html-cli` installed

### Running the tests

```bash
export PATH="/home/z/.local/bin:/home/z/.npm-global/bin:$PATH"
export LD_LIBRARY_PATH="/home/z/.local/lib:${LD_LIBRARY_PATH:-}"

# Run the E2E test
perl tests/test_e2e_perl.pl
```

### Expected output

```
==================================================
Testing parser: perl
==================================================
diffvim: 2 hunk(s) to animate (parser: perl).
Launching vim in tmux...
Animation done: 1
RESULT (perl): MATCH

==================================================
Testing parser: diff2html
==================================================
diffvim: 2 hunk(s) to animate (parser: diff2html).
Launching vim in tmux...
Animation done: 1
RESULT (diff2html): MATCH

Results: 2 passed, 0 failed
```

### Known issues

The E2E tests may fail due to tmux `send-keys` race conditions (see
[IMPROVEMENTS.md #1](../IMPROVEMENTS.md)). If the animation crashes
mid-way, the buffer won't match the expected output. This is a known
limitation of the tmux-based implementations.

The `diffvim` (Vimscript) implementation doesn't have this issue, but
it doesn't have an automated E2E test yet (manual testing only).

---

## Manual Tests

### Test 1: Basic animation

```bash
# Create test files
cat > /tmp/old.py <<'EOF'
def greet(name):
    print("Hello, " + name)
    return None
EOF

cat > /tmp/new.py <<'EOF'
def greet(name):
    print(f"Hello, {name}!")
    return None
EOF

# Run the animation
./diffvim /tmp/old.py /tmp/new.py
```

**Expected behavior:**
1. Vim opens with `old.py` content
2. Cursor glides to line 2, column 1
3. Characters are deleted and inserted to transform the line
4. Animation completes, message displayed
5. Buffer contains the `new.py` content

### Test 2: Controls

Run the animation and test each control:

1. **Space** — press during animation; it should pause. Press again to
   resume.
2. **n** — press during a hunk; it should skip to the next hunk
   instantly.
3. **b** — press after completing a hunk; it should revert to the
   previous hunk and restart it.
4. **q** — press at any time; animation should stop and buffer should
   be left for editing.

### Test 3: Identical files

```bash
cp /tmp/old.py /tmp/same.py
./diffvim /tmp/old.py /tmp/same.py
```

**Expected behavior:** Message "diffvim: files are identical, nothing
to animate." Vim opens with the file for normal editing.

### Test 4: Empty old file

```bash
echo -n "" > /tmp/empty.py
cat > /tmp/content.py <<'EOF'
hello
world
EOF
./diffvim /tmp/empty.py /tmp/content.py
```

**Expected behavior:** Vim opens with an empty buffer, then types in
the new content line by line.

### Test 5: Large file

```bash
# Generate a large file
seq 1 1000 > /tmp/large_old.txt
seq 1 500 > /tmp/large_new.txt
seq 501 1000 >> /tmp/large_new.txt

# This should still work, just slower
./diffvim /tmp/large_old.txt /tmp/large_new.txt
```

**Expected behavior:** Animation runs, but the LCS computation may
take a few seconds for large files.

---

## Writing New Tests

### Adding a parser test case

Edit `tests/test_parsers.pl` and add a new entry to the `@test_cases`
array:

```perl
my @test_cases = (
    # ... existing cases ...
    {
        name => 'my new test case',
        old  => "old content\n",
        new  => "new content\n",
    },
);
```

The test harness will automatically:
1. Write the old/new content to temp files
2. Run both parsers
3. Apply the char ops
4. Compare with the expected new content

### Adding an E2E test case

Edit `tests/test_e2e_perl.pl` and modify the `$old_content` and
`$new_content` variables, or add a loop to test multiple cases.

---

## Continuous Integration

### GitHub Actions example

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          sudo apt-get install -y vim tmux
          npm install -g diff2html-cli
      - name: Parser tests
        run: perl tests/test_parsers.pl
      - name: End-to-end tests
        run: perl tests/test_e2e_perl.pl
```

### Test coverage

To measure test coverage:

```bash
# Install Devel::Cover
cpanm Devel::Cover

# Run tests with coverage
PERL5OPT=-MDevel::Cover perl tests/test_parsers.pl

# Generate report
cover
```

This generates an HTML report in `cover_db/coverage.html` showing
which lines of code were executed during testing.
