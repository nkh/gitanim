#!/usr/bin/env python3
"""Trace the NEW postprocess logic on a minimal ghost-line case."""

# Simulate: old_text = "abc\ndef\nghi\njkl", new_text = "abc\nxyz"
# HUNK: delete "def", delete \n, delete "ghi", delete \n, delete "jkl", insert "xyz"
# Wait that's not quite right. Let me think about what compute produces.

# old_text = "abc\ndef\nghi\njkl"  (4 lines)
# new_text = "abc\nxyz"           (2 lines)
# diff: keep "abc\n", delete "def\nghi\njkl", insert "xyz"
# After compute char_diff: keep "abc", keep "\n", delete "def", delete "\n",
#   delete "ghi", delete "\n", delete "jkl", insert "x", insert "y", insert "z"
# After left_to_right reordering (per-line-group, split at \n):
#   Group 1 (line 1): keep a, keep b, keep c, keep \n
#   Group 2 (line 2): delete d, delete e, delete f, delete \n
#   Group 3 (line 3): delete g, delete h, delete i, delete \n
#   Group 4 (line 4): delete j, delete k, delete l, then insert x, insert y, insert z
#   Wait, but inserts at the end aren't split by \n.
#   Actually the \n inserts would be separate groups. Let me reconsider.

# Actually for this test, let's say new_text = "abc" (no xyz, just delete everything after abc\n)
# Actually simpler: new_text = "abc" (delete "def\nghi\njkl" — wait, that's only 3 lines deleted)
# Let me re-read: old="abc\ndef\nghi\njkl", new="abc"
# This deletes: \n (after abc), def, \n, ghi, \n, jkl
# Hmm, but the \n after abc is the line boundary between line 1 and line 2.
# If we delete it, line 1 ("abc") and line 2 ("def") merge.
# But we WANT to delete def, ghi, jkl, so we should NOT delete the \n.
# We should: keep abc, keep \n, move to line 2, delete def, delete \n (after def is gone),
#   move to line 3, delete ghi, delete \n, move to line 4, delete jkl, delete \n (end)

# Let me simulate the ops that compute+reorder produces:
ops = [
    # Line 1: keep abc, then \n
    ('keep', 'a'), ('keep', 'b'), ('keep', 'c'),
    # \n between line 1 and line 2
    ('keep', '\\n'),  # This is a KEEP \n, not delete — boundary stays
    # Line 2: delete def, then delete \n
    ('delete', 'd'), ('delete', 'e'), ('delete', 'f'),
    ('delete', '\\n'),  # DELETE this \n — line 2 is being removed
    # Line 3: delete ghi, then delete \n
    ('delete', 'g'), ('delete', 'h'), ('delete', 'i'),
    ('delete', '\\n'),  # DELETE this \n — line 3 is being removed
    # Line 4: delete jkl (no \n after — last line)
    ('delete', 'j'), ('delete', 'k'), ('delete', 'l'),
]

print("Input ops (after reorder):")
for i, op in enumerate(ops):
    print(f"  [{i}] {op[0]} {op[1]!r}")
print()

# Now trace the NEW postprocess logic
cur_line = 1  # target_line (1-indexed)
cur_col = 1
line_has_content = 0
emitted = []

i = 0
n_out = len(ops)
while i < n_out:
    op_type, op_code_str = ops[i]
    # Convert string code to int (10 = \n)
    op_code = 10 if op_code_str == '\\n' else ord(op_code_str)

    if op_code == 10:
        if op_type == 'keep':
            emitted.append(('keep', '\\n', cur_line, cur_col))
            cur_line += 1
            cur_col = 1
            line_has_content = 0
        elif op_type == 'delete':
            # Look ahead for content deletes
            j = i + 1
            while j < n_out and ops[j][0] == 'delete' and ops[j][1] != '\\n':
                j += 1
            n_content = j - (i + 1)
            followed_by_keep_or_insert = (j < n_out and ops[j][0] in ('keep', 'insert'))

            if n_content > 0 and not followed_by_keep_or_insert:
                # "Delete next line" pattern
                cur_line += 1  # MOVE to next line — DO NOT delete \n yet
                cur_col = 1
                line_has_content = 0
                # Emit content deletes on next line
                for k in range(i + 1, j):
                    emitted.append(('delete', ops[k][1], cur_line, 1))
                # NOW emit \n delete (next line is empty)
                emitted.append(('delete', '\\n', cur_line, 1))
                i = j
                continue

            # No content deletes follow
            # Check is_end_delete + first op
            is_end_delete = False  # not simulating this
            if i == 0 and is_end_delete and cur_line > 1:
                emitted.append(('delete', '\\n', cur_line - 1, 1))
                line_has_content = 0
            else:
                emitted.append(('delete', '\\n', cur_line, cur_col))
                line_has_content = 0
    else:
        emitted.append((op_type, op_code_str, cur_line, cur_col))
        if op_type == 'keep':
            cur_col += 1
            line_has_content = 1
        elif op_type == 'delete':
            pass  # col stays
        elif op_type == 'insert':
            cur_col += 1
    i += 1

print("Emitted ops (type, char, line, col):")
for e in emitted:
    print(f"  {e}")
print()
print(f"Final cur_line={cur_line}, cur_col={cur_col}")
