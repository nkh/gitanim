#!/usr/bin/env python3
"""Fix the EX_CHECK macro in the Makefile to guard on the snapshot file
existing before running the diff. This prevents false MISMATCH when
running in interactive mode (no --snapshot passed)."""

MAKEFILE = "/home/z/my-project/gitanim/Makefile"

with open(MAKEFILE, "r") as f:
    lines = f.readlines()

new_lines = []
i = 0
while i < len(lines):
    line = lines[i]
    # Detect the EX_CHECK definition line
    if line.startswith("EX_CHECK = new="):
        # Replace the entire EX_CHECK block (multi-line, ends before a blank line or next var)
        replacement = (
            "EX_CHECK = if [ ! -f /tmp/$@_out.txt ]; then \\\n"
            "           echo \"  $@: no snapshot (interactive mode — use HEADLESS=1 to verify)\"; \\\n"
            "           else \\\n"
            "           new=$$(ls tests/examples/$$ex_dir/new.* | head -1); \\\n"
            "           if diff -q \"$$new\" /tmp/$@_out.txt >/dev/null 2>&1; then \\\n"
            "               echo \"  $@: snapshot matches new file\"; \\\n"
            "           else \\\n"
            "               echo \"  $@: MISMATCH (snapshot != new file)\"; \\\n"
            "           fi; \\\n"
            "           fi\n"
        )
        new_lines.append(replacement)
        # Skip the continuation lines (they end with \)
        i += 1
        while i < len(lines) and lines[i-1].rstrip().endswith("\\"):
            i += 1
        continue
    new_lines.append(line)
    i += 1

with open(MAKEFILE, "w") as f:
    f.writelines(new_lines)

print("Fixed EX_CHECK to guard on snapshot file existence")
