#!/usr/bin/env python3
"""Trace: delete content on current line, then \n at cur_line-1 (join empty onto previous)."""

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
                # Move to next line, delete content there,
                # then emit \n delete at cur_line (which joins this now-empty
                # line with the NEXT line, recursively emptying from top to bottom)
                # Actually no — we want to join the empty line onto the PREVIOUS line
                # to preserve the previous line's content.
                #
                # Wait. Let me think again.
                # After we delete "def" on line 2, line 2 is empty.
                # If we emit \n delete at line 2, it joins line 3 ("ghi") onto line 2.
                #   → line 2 = "ghi", line 3 gone. BAD (ghi not deleted yet).
                # If we emit \n delete at line 1 (cur_line - 1), it joins line 2 ("") onto line 1 ("abc").
                #   → line 1 = "abc", line 2 gone. GOOD for line 2, but line 3 is now line 2.
                #
                # But then the NEXT group (line 3 "ghi") is now at line 2, not line 3!
                # And the ops say delete at line 3. So we'd need to adjust.
                #
                # This is getting complicated. Let me try a totally different approach:
                # emit ALL content deletes first, then ALL \n deletes at the end.
                cur_line += 1
                cur_col = 1
                line_has_content = 0
                for k in range(i + 1, j):
                    emitted.append(('delete', ops[k][1], cur_line, 1))
                # Emit \n delete at cur_line - 1 (join empty current line onto previous)
                emitted.append(('delete', '\\n', cur_line - 1, 1))
                # After this \n delete, the empty current line is joined onto the
                # previous line. The current line is gone, and all subsequent lines
                # shift up by 1. So cur_line should DECREMENT to reflect that.
                # The next group's content (which was at cur_line+1) is now at cur_line.
                cur_line -= 1
                i = j
                continue
            # No content follows
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

def apply_op(op):
    global buffer
    t, ch, line, col = op
    li = line - 1
    if li < 0: li = 0
    if li >= len(buffer): li = len(buffer) - 1
    ci = col - 1
    if ci < 0: ci = 0
    if t == 'keep':
        if ch == '\\n':
            pass  # cursor moves, no buffer change
        else:
            pass  # cursor moves, no buffer change
    elif t == 'delete':
        if ch == '\\n':
            if li < len(buffer) - 1:
                buffer[li] = buffer[li] + buffer[li + 1]
                buffer.pop(li + 1)
        else:
            if ci < len(buffer[li]):
                buffer[li] = buffer[li][:ci] + buffer[li][ci+1:]
    elif t == 'insert':
        if ch == '\\n':
            before = buffer[li][:ci]
            after = buffer[li][ci:]
            buffer[li] = before
            buffer.insert(li + 1, after)
        else:
            buffer[li] = buffer[li][:ci] + ch + buffer[li][ci:]

print(f"Initial buffer: {buffer}")
for op in emitted:
    apply_op(op)
    print(f"After {op}: buffer={buffer}")
print(f"\nFinal buffer: {buffer}")
print(f"Expected:     ['abc']")
