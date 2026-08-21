#!/usr/bin/env python3
"""Trace the CORRECT postprocess logic — DO NOT emit \n delete when
moving to next line. Let the next iteration handle the boundary."""

# Same input as before
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
            # Look ahead for content deletes on the next line
            j = i + 1
            while j < n_out and ops[j][0] == 'delete' and ops[j][1] != '\\n':
                j += 1
            n_content = j - (i + 1)
            followed_by_keep_or_insert = (j < n_out and ops[j][0] in ('keep', 'insert'))

            if n_content > 0 and not followed_by_keep_or_insert:
                # "Delete next line" pattern:
                # MOVE cursor to next line, emit content deletes there.
                # DO NOT emit \n delete — the \n is a line boundary that
                # stays. The now-empty next line will be handled by the
                # next iteration (which will see another delete \n and
                # recursively move to the next-next line).
                cur_line += 1
                cur_col = 1
                line_has_content = 0
                for k in range(i + 1, j):
                    emitted.append(('delete', ops[k][1], cur_line, 1))
                # DO NOT emit \n delete here!
                i = j
                continue

            # No content deletes follow — this is a genuine \n delete
            # (e.g. last line of file being deleted, or merging two
            # paragraphs into one).
            emitted.append(('delete', '\\n', cur_line, cur_col))
            line_has_content = 0
    else:
        emitted.append((op_type, op_code_str, cur_line, cur_col))
        if op_type == 'keep':
            cur_col += 1
            line_has_content = 1
        elif op_type == 'delete':
            pass
        elif op_type == 'insert':
            cur_col += 1
    i += 1

print("Emitted ops (type, char, line, col):")
for e in emitted:
    print(f"  {e}")
print()

# Now simulate the ANIMATOR applying these ops
print("=== Simulating animator ===")
buffer = ["abc", "def", "ghi", "jkl"]  # lines (0-indexed internally, but ops are 1-indexed)
cursor_l = 0  # 0-indexed
cursor_c = 0

def apply_op(op):
    global cursor_l, cursor_c, buffer
    t, ch, line, col = op
    # Convert 1-indexed to 0-indexed
    cursor_l = line - 1
    cursor_c = col - 1
    if cursor_l < 0:
        cursor_l = 0
    if cursor_l >= len(buffer):
        cursor_l = len(buffer) - 1

    if t == 'keep':
        if ch == '\\n':
            cursor_l += 1
            if cursor_l >= len(buffer):
                cursor_l = len(buffer) - 1
            cursor_c = 0
        else:
            cursor_c += 1
    elif t == 'delete':
        if ch == '\\n':
            # Delete \n — join this line with the next
            if cursor_l < len(buffer) - 1:
                buffer[cursor_l] = buffer[cursor_l] + buffer[cursor_l + 1]
                buffer.pop(cursor_l + 1)
        else:
            # Delete char at cursor
            if cursor_c < len(buffer[cursor_l]):
                buffer[cursor_l] = buffer[cursor_l][:cursor_c] + buffer[cursor_l][cursor_c+1:]
    elif t == 'insert':
        if ch == '\\n':
            # Split line
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
    print(f"After {op}: buffer={buffer}")

print(f"\nFinal buffer: {buffer}")
print(f"Expected: ['abc']  (old='abc\\ndef\\nghi\\njkl', new='abc')")
