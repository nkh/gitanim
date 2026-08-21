#!/usr/bin/env python3
"""Simplest fix: keep original line numbers, just reorder so content
deletes come before \n deletes. The animator's set_cursor moves to
the right line for each op."""

# Original compute output (line numbers are original):
ops = [
    # Line 1: keep abc, keep \n (boundary stays)
    ('keep', 'a', 1, 1), ('keep', 'b', 1, 2), ('keep', 'c', 1, 3),
    ('keep', '\\n', 1, 4),
    # Line 2: delete \n, delete def (compute order: \n first, then content)
    # BUT: the \n at line 2 col 1 means the \n BETWEEN line 1 and line 2
    # Wait no — let me re-read the compute output.
    # The compute output was:
    #   HUNK 2 3 0 0 1  (target=2)
    #   delete \n  line=2 col=1   — \n at start of line 2 = \n between line 1 and 2
    #   delete d   line=3 col=1   — but this is line 3??
    #
    # Actually, I think compute uses a "current line" that starts at target_line
    # and increments on each \n. So:
    #   cur_line=2, delete \n → \n between line 1 and 2 (line 2 col 1)
    #   then cur_line++ → 3 (because \n was deleted, moving to next line)
    #   Wait no, compute increments cur_line on ANY \n op (keep/delete/insert)
    #   delete \n at line 2 → cur_line++ → 3
    #   delete d at line 3 → cur_line stays 3, col++ → 2
    #   delete e at line 3 → col++ → 3
    #   delete f at line 3 → col++ → 4
    #   delete \n at line 3 → cur_line++ → 4
    #   delete g at line 4 → ...
    #
    # So the compute line numbers are: line 2 for first \n, line 3 for "def" + second \n, etc.
    # The ORIGINAL line numbers would be:
    #   \n between line 1-2 (delete at line 2)
    #   "def" on line 2 (delete at line 2)
    #   \n between line 2-3 (delete at line 2)
    #   "ghi" on line 3 (delete at line 3)
    #   \n between line 3-4 (delete at line 3)
    #   "jkl" on line 4 (delete at line 4)
    #
    # But compute says "def" is at line 3, not line 2. That's because
    # compute increments cur_line AFTER the \n delete, so "def" is at
    # the NEXT line. This is the BUG in compute's line tracking!
    #
    # The correct line numbers should be:
    #   delete \n at line 1 (between line 1 and 2) — but we DON'T want to delete this!
    #   delete "def" at line 2
    #   delete \n at line 2 (between line 2 and 3) — but we DON'T want to delete this either!
    #   delete "ghi" at line 3
    #   delete \n at line 3
    #   delete "jkl" at line 4
    #
    # Wait, but we DO need to delete \n somewhere to remove the empty lines.
    # The issue is WHICH \n to delete.
    #
    # If we delete the \n BEFORE the content (between line 1 and 2), we join
    # line 2 ("def") onto line 1 ("abc") → "abcdef". Then "def" is on line 1.
    # BAD.
    #
    # If we delete the \n AFTER the content (between line 2 and 3), we join
    # line 3 ("ghi") onto line 2 (now empty after deleting "def") → "".
    # Then "ghi" is on line 2. We delete "ghi" on line 2. Then delete \n
    # between line 2 and 3 (now empty). Etc.
    #
    # So the correct order is:
    #   1. Delete content on line 2 ("def")
    #   2. Delete \n between line 2 and 3 (joins line 3 "ghi" onto empty line 2)
    #   3. Delete content on line 2 ("ghi" — now on line 2)
    #   4. Delete \n between line 2 and 3 (joins line 3 "jkl" onto empty line 2)
    #   5. Delete content on line 2 ("jkl" — now on line 2)
    #
    # But the line numbers keep changing! This is why it's hard.
    #
    # ALTERNATIVE: delete content on each line FIRST (using original line numbers),
    # THEN delete \n from the bottom up.
    #
    #   1. Delete "def" at line 2
    #   2. Delete "ghi" at line 3
    #   3. Delete "jkl" at line 4
    #   4. Delete \n at line 3 (joins empty line 4 onto empty line 3) → line 3 = "", line 4 gone
    #   5. Delete \n at line 2 (joins empty line 3 onto empty line 2) → line 2 = "", line 3 gone
    #   6. Delete \n at line 1 (joins empty line 2 onto line 1 "abc") → line 1 = "abc", line 2 gone
    #
    # But the input only has 2 \n deletes (at lines 2 and 3), not 3.
    # We need 3 \n deletes to remove 3 empty lines.
    # The third \n delete is... missing from the input?
    #
    # Wait. old = "abc\ndef\nghi\njkl\n" has \n after abc, def, ghi, jkl = 4 \n
    # new = "abc\n" has \n after abc = 1 \n
    # diff: delete 3 \n (after def, after ghi, after jkl)
    # But compute only shows 2 \n deletes! Let me check again.
    pass
]

# Let me just re-run compute and look at the ACTUAL output
import subprocess
result = subprocess.run(['./compute/bin/diffvim-compute-cpp', '/tmp/old4.txt', '/tmp/new1.txt', '/tmp/raw4b.txt'],
                       capture_output=True, text=True, cwd='/home/z/my-project/gitanim')
with open('/tmp/raw4b.txt') as f:
    print("=== Compute output ===")
    print(f.read())
