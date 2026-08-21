#!/usr/bin/env python3
"""Trace: DON'T emit \n delete when moving to next line. Let empties be."""

ops = [
    ('keep', 'a'), ('keep', 'b'), ('keep', 'c'),
    ('keep', '\\n'),
    ('delete', 'd'), ('delete', 'e'), ('delete', 'f'),
    ('delete', '\\n'),
    ('delete', 'g'), ('delete', 'h'), ('delete', 'i'),
    ('delete', '\\n'),
    ('delete', 'j'), ('delete', 'k'), ('delete', 'l'),
]

cur_line = 1
cur_col = 1
line_has_content = 0
emitted = []

i = 0
n_out = len(ops)
while i < n_out:
    op_type, op_code_str = ops[i]
    op_code = 10 if op_code_str == '\\n' else ord(op_code_str)

    if op_code == 10:
        if op_type == 'keep':
            emitted.append(('keep', '\\n', cur_line, cur_col))
            cur_line += 1
            cur_col = 1
            line_has_content = 0
        elif op_type == 'delete':
            # Look ahead
            j = i + 1
            while j < n_out and ops[j][0] == 'delete' and ops[j][1] != '\\n':
                j += 1
            n_content = j - (i + 1)
            followed_by_keep_or_insert = (j < n_out and ops[j][0] in ('keep', 'insert'))

            if n_content > 0 and not followed_by_keep_or_insert:
                # Move to next line, delete content there, DON'T emit \n delete
                cur_line += 1
                cur_col = 1
                line_has_content = 0
                for k in range(i + 1, j):
                    emitted.append(('delete', ops[k][1], cur_line, 1))
                # SKIP the \n delete entirely — don't emit it
                i = j
                continue
            # No content follows — emit \n delete at cur_line - 1 (join empty line onto previous)
            if cur_line > 1:
                emitted.append(('delete', '\\n', cur_line - 1, 1))
            else:
                emitted.append(('delete', '\\n', cur_line, cur_col))
            line_has_content = 0
    else:
        emitted.append((op_type, op_code_str, cur_line, cur_col))
        if op_type == 'keep':
            cur_col += 1
            line_has_content = 1
    i += 1

print("Emitted ops:")
for e in emitted:
    print(f"  {e}")
print()

# Simulate animator
buffer = ["abc", "def", "ghi", "jkl"]
cursor_l = 0
cursor_c = 0

def apply_op(op):
    global cursor_l, cursor_c, buffer
    t, ch, line, col = op
    cursor_l = line - 1
    if cursor_l < 0: cursor_l = 0
    if cursor_l >= len(buffer): cursor_l = len(buffer) - 1
    cursor_c = col - 1
    if cursor_c < 0: cursor_c = 0
    if t == 'keep':
        if ch == '\\n':
            cursor_l += 1
            if cursor_l >= len(buffer): cursor_l = len(buffer) - 1
            cursor_c = 0
        else:
            cursor_c += 1
    elif t == 'delete':
        if ch == '\\n':
            if cursor_l < len(buffer) - 1:
                buffer[cursor_l] = buffer[cursor_l] + buffer[cursor_l + 1]
                buffer.pop(cursor_l + 1)
        else:
            if cursor_c < len(buffer[cursor_l]):
                buffer[cursor_l] = buffer[cursor_l][:cursor_c] + buffer[cursor_l][cursor_c+1:]
    elif t == 'insert':
        if ch == '\\n':
            before = buffer[cursor_l][:cursor_c]
            after = buffer[cursor_l][cursor_c:]
            buffer[cursor_l] = before
            buffer.insert(cursor_l + 1, after)
            cursor_l += 1
            cursor_c = 0
        else:
            buffer[cursor_l] = buffer[cursor_l][:cursor_c] + ch + buffer[cursor_l][cursor_c:]
            cursor_c += 1

print(f"Initial buffer: {buffer}")
for op in emitted:
    apply_op(op)
print(f"After all ops:   {buffer}")
print(f"Expected:        ['abc']")
