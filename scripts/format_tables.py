#!/usr/bin/env python3
"""Format markdown tables: align columns so pipes line up vertically.

Usage:
  python3 scripts/format_tables.py <file.md>
  python3 scripts/format_tables.py docs/REQUIREMENTS.md
  python3 scripts/format_tables.py --all    # format all .md files

Aligns every markdown table like this:

  | Accuracy   | Relevance   | Decision   |
  | ---------- | ----------- | ---------- |
  | High       | High        | KEEP       |
  | Low        | Low         | ARCHIVE    |

Rules:
  - Every column is padded to the width of its longest cell + 1 space
  - Separator row uses dashes matching column width
  - No trailing whitespace
"""
import sys
import os
import re
import glob

def format_table(lines):
    """Format a contiguous block of markdown table lines."""
    if len(lines) < 2:
        return lines

    # Parse cells
    rows = []
    for line in lines:
        line = line.strip()
        if not line.startswith('|'):
            return lines
        # Split on |, drop first and last empty (from leading/trailing |)
        cells = line.split('|')[1:-1]
        cells = [c.strip() for c in cells]
        rows.append(cells)

    if len(rows) < 2:
        return lines

    # Check row 1 is the separator (---|---|---)
    is_separator = all(re.match(r'^-+:?$|^:?-+:?$|^:?-+$', c) for c in rows[1])
    if not is_separator:
        return lines

    # Determine column alignment from separator row
    alignments = []
    for c in rows[1]:
        left = c.startswith(':')
        right = c.endswith(':')
        if left and right:
            alignments.append('center')
        elif right:
            alignments.append('right')
        else:
            alignments.append('left')

    # Calculate max width per column
    n_cols = max(len(r) for r in rows)
    widths = [0] * n_cols
    for r in rows:
        for i, c in enumerate(r):
            widths[i] = max(widths[i], len(c))

    # Build formatted rows
    formatted = []
    for idx, r in enumerate(rows):
        # Pad row to n_cols
        while len(r) < n_cols:
            r.append('')
        
        cells = []
        for i, c in enumerate(r):
            w = widths[i]
            if idx == 1:
                # Separator row
                align = alignments[i] if i < len(alignments) else 'left'
                if align == 'center':
                    cells.append(':' + '-' * (w - 1) + ':')
                elif align == 'right':
                    cells.append('-' * (w - 1) + ':')
                else:
                    cells.append('-' * w)
            else:
                # Data rows
                align = alignments[i] if i < len(alignments) else 'left'
                if align == 'right':
                    cells.append(c.rjust(w))
                elif align == 'center':
                    cells.append(c.center(w))
                else:
                    cells.append(c.ljust(w))
        
        formatted.append('| ' + ' | '.join(cells) + ' |')

    return formatted

def process_file(filepath):
    """Process a markdown file, formatting all tables."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()

    output = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i].rstrip('\n')

        # Check if this line starts a table (has | and starts with |)
        if line.strip().startswith('|') and '\t' not in line:
            # Collect contiguous table lines
            table_lines = [line]
            j = i + 1
            while j < len(lines):
                next_line = lines[j].rstrip('\n')
                if next_line.strip().startswith('|') and '\t' not in next_line:
                    table_lines.append(next_line)
                    j += 1
                else:
                    break

            # Format the table
            formatted = format_table(table_lines)

            # Check if anything changed
            if formatted != table_lines:
                changed = True

            output.extend(formatted)
            i = j
        else:
            output.append(line)
            i += 1

    if changed:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(output) + '\n')
        return True
    return False

def main():
    if len(sys.argv) < 2 or sys.argv[1] in ('--help', '-h'):
        print("format_tables.py — Format markdown tables so columns align vertically.")
        print("")
        print("USAGE")
        print("    format_tables.py <file.md>...")
        print("    format_tables.py --all")
        print("    format_tables.py --help | -h")
        print("")
        print("OPTIONS")
        print("    --all       Process all .md files in the repo (except docs/design/)")
        print("    --help, -h  Show this help and exit")
        print("")
        print("EXAMPLES")
        print("    format_tables.py docs/README.md")
        print("    format_tables.py --all")
        sys.exit(0)

    if sys.argv[1] == '--all':
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        files = []
        for f in glob.glob(os.path.join(root, '**/*.md'), recursive=True):
            if '/.git/' in f or '/docs/design/' in f or '/tests/examples/' in f:
                continue
            files.append(f)
        count = 0
        for f in sorted(files):
            if process_file(f):
                print(f"  formatted: {os.path.relpath(f, root)}")
                count += 1
        print(f"\n{count} files formatted")
    else:
        for filepath in sys.argv[1:]:
            if process_file(filepath):
                print(f"  formatted: {filepath}")
            else:
                print(f"  no changes: {filepath}")

if __name__ == '__main__':
    main()
