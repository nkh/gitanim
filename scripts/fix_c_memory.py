#!/usr/bin/env python3
"""Fix realloc anti-pattern: ptr = realloc(ptr, size);
Replace with: { Type *tmp = realloc(ptr, size); if(!tmp){fprintf(stderr,"OOM\\n");exit(1);} ptr = tmp; }

Also add NULL checks after malloc if missing.
"""
import re
import os

os.chdir('/home/z/my-project/gitanim')

def fix_realloc(path):
    with open(path, 'r') as f:
        text = f.read()
    orig = text

    # Pattern: <indent>varname = (Cast *)realloc(varname, size);
    # or:     <indent>varname = realloc(varname, size);
    def repl(m):
        indent = m.group('indent')
        varname = m.group('var')
        cast = m.group('cast') or ''
        size = m.group('size')
        # The cast type (e.g. "Op *") — extract from "(Op *)"
        cast_type = ''
        if cast:
            # Remove the outer parens
            inner = cast.strip().strip('()').strip()
            cast_type = inner + ' '
        return (f"{indent}{{ {cast_type}*_tmp = realloc({varname}, {size}); "
                f"if (!_tmp) {{ fprintf(stderr, \"out of memory\\n\"); exit(1); }} "
                f"{varname} = _tmp; }}")

    # Match: indent + var = (Cast *)realloc(var, size);
    # The cast group is optional
    pattern = r'(?P<indent>^[ \t]*)(?P<var>\w+)\s*=\s*(?P<cast>\([^)]+\))?\s*realloc\(\s*(?P=var)\s*,\s*(?P<size>[^;)]+(?:\)[^;)]*)*)\);'
    text = re.sub(pattern, repl, text, flags=re.MULTILINE)

    if text != orig:
        with open(path, 'w') as f:
            f.write(text)
        return True
    return False

def add_malloc_check(path):
    """Add 'if (!ptr) { OOM }' after malloc if not already checked."""
    with open(path, 'r') as f:
        lines = f.readlines()

    changes = 0
    i = 0
    new_lines = []
    while i < len(lines):
        line = lines[i]
        new_lines.append(line)
        # Match: var = (Cast *)malloc(size);
        m = re.match(r'^(\s*)(\w+)\s*=\s*\([^)]+\)\s*malloc\(([^;]+)\);\s*$', line)
        if m:
            indent = m.group(1)
            varname = m.group(2)
            # Check next line for existing NULL check
            if i + 1 < len(lines):
                next_stripped = lines[i + 1].strip()
                if (next_stripped.startswith(f'if (!{varname}') or
                    next_stripped.startswith(f'if ({varname} ==') or
                    next_stripped.startswith('if (!')):
                    i += 1
                    continue
            new_lines.append(f'{indent}if (!{varname}) {{ fprintf(stderr, "out of memory\\n"); exit(1); }}\n')
            changes += 1
        i += 1

    if changes > 0:
        with open(path, 'w') as f:
            f.writelines(new_lines)
        print(f"  {path}: +{changes} malloc checks")
    return changes

c_files = [
    'layers/c/ad_layer_reorder.c',
    'layers/c/ad_layer_overwrite.c',
    'layers/c/ad_layer_indent_last.c',
    'layers/c/ad_layer_line_delete_in_place.c',
    'layers/c/ad_layer_pace.c',
    'layers/c/ad_layer_highlight.c',
    'layers/c/ad_layer_common.h',
    'animator/c/ad.c',
]

for f in c_files:
    if not os.path.exists(f):
        continue
    changed = fix_realloc(f)
    if changed:
        print(f"  {f}: fixed realloc")
    add_malloc_check(f)
