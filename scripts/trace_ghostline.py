#!/usr/bin/env python3
"""Trace the postprocess logic on a minimal ghost-line case."""

# Simulate: HUNK deletes lines 2-3 (content + \n + content + \n)
# old_text: "abc\ndef\nghi"
# new_text: "abc"
# (deletes "def\n" and "\n" — actually "def\nghi" + \n)
# Wait, let me think about what compute produces.

# If old = "abc\ndef\nghi" and new = "abc":
# compute: keep "abc", delete \n, delete "def", delete \n, delete "ghi"
# After left_to_right reordering (deletes before inserts, keeps first):
#   keep "abc" (3 ops)
#   Then the rest is in a group with \n boundaries...
#   Actually let me re-read reorder_hunk_ops. It splits at \n boundaries.
#   So: Group 1 = [keep a, keep b, keep c, delete \n]
#       Group 2 = [delete d, delete e, delete f, delete \n]
#       Group 3 = [delete g, delete h, delete i]
#   After left_to_right on each group:
#     Group 1: [keep a, keep b, keep c, delete \n]  (keeps first, then deletes)
#     Group 2: [delete d, delete e, delete f, delete \n]  (all deletes, \n last)
#     Group 3: [delete g, delete h, delete i]

# So the ops seen by postprocess loop are:
#   keep a (line=2, col=1)
#   keep b (line=2, col=2)
#   keep c (line=2, col=3)
#   delete \n  ← ghost-line fix triggers? line_has_content=1, next ops are content deletes
#   delete d
#   delete e
#   delete f
#   delete \n  ← another \n delete! line_has_content=0 now (was reset)
#   delete g
#   delete h
#   delete i

# The ghost-line fix at the FIRST \n delete:
#   - Finds next content deletes (d, e, f) — but NOT the next \n delete
#   - Emits content deletes at (cur_line+1, 1) — line 3
#   - Emits \n delete at (cur_line+1, 1) — line 3 \n
#   - Sets i = j (skips past content deletes)
#   - cur_line NOT incremented (per comment "cur_line stays the same")
#   - line_has_content NOT reset (no explicit reset)
#   - Actually wait, let me re-read...

print("Tracing postprocess ghost-line fix on 'abc\\ndef\\nghi' -> 'abc'")
print()

# The ops after reorder (in order):
ops = [
    ('keep', 'a'), ('keep', 'b'), ('keep', 'c'),
    ('delete', '\\n'),  # 1st \n delete
    ('delete', 'd'), ('delete', 'e'), ('delete', 'f'),
    ('delete', '\\n'),  # 2nd \n delete
    ('delete', 'g'), ('delete', 'h'), ('delete', 'i'),
]

cur_line = 2  # target_line
cur_col = 1
line_has_content = 0
emitted = []

i = 0
while i < len(ops):
    op_type, op_code = ops[i]
    if op_code == '\\n':
        if op_type == 'delete':
            # Ghost-line fix check
            if line_has_content:
                # Find end of content deletes
                j = i + 1
                while j < len(ops) and ops[j][0] == 'delete' and ops[j][1] != '\\n':
                    j += 1
                n_content = j - (i + 1)
                followed_by_keep_or_insert = (j < len(ops) and ops[j][0] in ('keep', 'insert'))
                if n_content > 0 and not followed_by_keep_or_insert:
                    # Ghost-line pattern!
                    for k in range(i + 1, j):
                        emitted.append(('delete', ops[k][1], cur_line + 1, 1))
                    emitted.append(('delete', '\\n', cur_line + 1, 1))
                    i = j
                    continue
            # Normal \n delete
            emitted.append(('delete', '\\n', cur_line, cur_col))
            line_has_content = 0
        elif op_type == 'keep':
            emitted.append(('keep', '\\n', cur_line, cur_col))
            cur_line += 1
            cur_col = 1
            line_has_content = 0
    else:
        emitted.append((op_type, op_code, cur_line, cur_col))
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
