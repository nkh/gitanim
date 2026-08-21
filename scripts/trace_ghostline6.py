#!/usr/bin/env python3
"""Simulate the full postprocess output for 4->1 lines."""

emitted = [
    ('keep', 'a', 1, 1), ('keep', 'b', 1, 2), ('keep', 'c', 1, 3),
    # implicit keep \n at end of line 1
    ('keep', '\\n', 1, 4),
    # is_end_delete code: content deletes at cur_line=2, \n at cur_line-1=1
    ('delete', 'd', 2, 1), ('delete', 'e', 2, 1), ('delete', 'f', 2, 1),
    ('delete', '\\n', 1, 1),
    # "delete next line": cur_line++ -> 3, content at line 3, \n at line 2, cur_line-- -> 2
    ('delete', 'g', 3, 1), ('delete', 'h', 3, 1), ('delete', 'i', 3, 1),
    ('delete', '\\n', 2, 1),
    # "delete next line": cur_line++ -> 3, content at line 3, \n at line 2, cur_line-- -> 2
    ('delete', 'j', 3, 1), ('delete', 'k', 3, 1), ('delete', 'l', 3, 1),
    ('delete', '\\n', 2, 1),
]

buffer = ["abc", "def", "ghi", "jkl"]

def apply_op(op):
    global buffer
    t, ch, line, col = op
    li = line - 1
    if li < 0: li = 0
    if li >= len(buffer): li = len(buffer) - 1
    ci = col - 1
    if ci < 0: ci = 0
    if t == 'delete':
        if ch == '\\n':
            if li < len(buffer) - 1:
                buffer[li] = buffer[li] + buffer[li + 1]
                buffer.pop(li + 1)
            else:
                # \n delete on last line — no-op? or remove the line?
                pass
        else:
            if ci < len(buffer[li]):
                buffer[li] = buffer[li][:ci] + buffer[li][ci+1:]

print(f"Initial: {buffer}")
for op in emitted:
    apply_op(op)
    print(f"After {op}: {buffer}")
print(f"Final:   {buffer}")
print(f"Expected: ['abc']")
