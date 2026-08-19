#!/usr/bin/env bash
# generate_minimal_tests.sh — Create the minimal test cases for debugging.
#
# Each test case consists of two files: `old` and `new` in a directory
# named after the case. The cases are designed to isolate one specific
# transformation, so you can debug a single behavior at a time.
#
# Usage: bash tests/generate_minimal_tests.sh

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tests/minimal"
mkdir -p "$OUT"

write_case() {
    local name="$1"
    local old_content="$2"
    local new_content="$3"
    mkdir -p "$OUT/$name"
    printf '%s' "$old_content" > "$OUT/$name/old"
    printf '%s' "$new_content" > "$OUT/$name/new"
}

# 01 - Simple char replace (no \n)
write_case 01_simple_replace \
    "hello world
" \
    "hello world!
"

# 02 - Simple char insert (no \n)
write_case 02_simple_insert \
    "hello world
" \
    "hello world!
"

# 03 - Simple char delete (no \n)
write_case 03_simple_delete \
    "hello world
" \
    "hello world
"

# 04 - Whole word replace
write_case 04_word_replace \
    "def hello():
    print('hi')
" \
    "def greet():
    print('hi')
"

# 05 - Delete to end of line
write_case 05_delete_to_eol \
    "abc def ghi
" \
    "abc
"

# 06 - Insert at end of line
write_case 06_insert_at_eol \
    "abc
" \
    "abc def
"

# 07 - Insert at beginning of line
write_case 07_insert_at_bol \
    "abc
" \
    "XX abc
"

# 08 - Line replace (one line replaced, \n keep)
write_case 08_line_replace \
    "abc
def
ghi
" \
    "abc
XYZ
ghi
"

# 09 - Delete middle line
write_case 09_delete_middle_line \
    "line1
line2
line3
" \
    "line1
line3
"

# 10 - Delete first line
write_case 10_delete_first_line \
    "line1
line2
line3
" \
    "line2
line3
"

# 11 - Delete last line (the tricky one)
write_case 11_delete_last_line \
    "line1
line2
line3
" \
    "line1
line2
"

# 12 - Insert line at EOF
write_case 12_insert_line_at_end \
    "line1
line2
" \
    "line1
line2
line3
"

# 13 - Insert line at start
write_case 13_insert_line_at_start \
    "line2
line3
" \
    "line1
line2
line3
"

# 14 - Insert line in middle
write_case 14_insert_line_in_middle \
    "line1
line3
" \
    "line1
line2
line3
"

# 15 - Join two lines (delete \n)
write_case 15_join_two_lines \
    "foo
bar
" \
    "foobar
"

# 16 - Split line (insert \n)
write_case 16_split_line \
    "foobar
" \
    "foo
bar
"

# 17 - Multi-line delete
write_case 17_multi_line_delete \
    "line1
line2
line3
line4
line5
" \
    "line1
line5
"

# 18 - Indent change only
write_case 18_indent_change \
    "def foo():
    bar
" \
    "def foo():
        bar
"

# 19 - Trailing whitespace change
write_case 19_trailing_whitespace \
    "abc
" \
    "abc
"

# 20 - Unicode
write_case 20_unicode \
    "cafe
" \
    "café
"

# 21 - Empty old
write_case 21_empty_old \
    "" \
    "hello
"

# 22 - Empty new
write_case 22_empty_new \
    "hello
" \
    ""

# 23 - Identical files
write_case 23_identical_files \
    "hello
world
" \
    "hello
world
"

# 24 - Pure addition at EOF
write_case 24_pure_add_at_eof \
    "abc
" \
    "abc
def
"

# 25 - Complex mix
write_case 25_complex_mix \
    "import os
import sys

def main():
    print('hello')

if __name__ == '__main__':
    main()
" \
    "import os
import sys
import json

def main():
    print('hello world')

if __name__ == '__main__':
    main()
"

# Print summary
echo "Created $(ls -d "$OUT"/*/ | wc -l) test cases in $OUT/"
ls -d "$OUT"/*/ | sed 's|.*/||' | sort | head -30
