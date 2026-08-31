#!/usr/bin/env python3
"""Find and fix all 'diffvim' references in user-facing code and docs.

Replaces 'diffvim' with 'ad_vim' (or 'ad') in:
  - apps/vim/ad_vim (help text, error messages, comments)
  - docs/src/*.md (installation, compute, parsers, etc.)
  - man/*.1 (cross-references)
  - scripts/*.sh (help text, comments)
  - completion/* (file references)

Preserves:
  - g:diffvim (vimscript internal variable name)
  - autoload_diffvim (directory name)
  - diffvim_new_file (vimscript global)
  - __DIFFVIM_VIMSCRIPT_EOF__ (heredoc delimiter)
  - "diffvim post-processed" / "diffvim raw" / "diffvim timed" (TSV headers)
  - diffvim.log / diffvim-debug.log (log file names — historical)
  - apps/vim/ad_vim (the backward-compat wrapper file itself)
"""
import os
import re

ROOT = "/home/z/my-project/gitanim"

# Files to process (exclude design docs, test examples, git)
SKIP_DIRS = {".git", "docs/design", "tests/examples", "tests/minimal", "bin"}
SKIP_FILES = {
    "apps/vim/diffvim",  # the backward-compat wrapper — keep its name
}

# Patterns to preserve (don't replace these)
PRESERVE_PATTERNS = [
    r'g:diffvim',
    r'autoload_diffvim',
    r'diffvim_new_file',
    r'__DIFFVIM_VIMSCRIPT_EOF__',
    r'diffvim post-processed',
    r'diffvim raw',
    r'diffvim timed',
    r'diffvim precomputed',
    r'diffvim decorated',
    r'diffvim-debug',
    r'diffvim\.log',
    r'diffvim\.vim',
    r'diffvim-fifo',
    r'diffvim_debug',
    r'diffvim_snapshots',
    r'diffvim_pipe',
    r'DiffVim::Parser',
    r'DiffVim::Layer',
    r'DiffVim/',
    r'perl/DiffVim',
]

def should_preserve(line, pos):
    """Check if the 'diffvim' at position pos in line should be preserved."""
    for pattern in PRESERVE_PATTERNS:
        for m in re.finditer(pattern, line):
            if m.start() <= pos < m.end():
                return True
    return False

def replace__ad_vim(text):
    """Replace user-facing 'diffvim' references with 'ad_vim' or 'ad'."""
    lines = text.split('\n')
    new_lines = []
    changes = 0
    
    for line in lines:
        result = []
        pos = 0
        while pos < len(line):
            idx = line.find('diffvim', pos)
            if idx == -1:
                result.append(line[pos:])
                break
            
            # Check if this occurrence should be preserved
            if should_preserve(line, idx):
                result.append(line[pos:idx + len('diffvim')])
                pos = idx + len('diffvim')
                continue
            
            # Determine replacement based on context
            after = line[idx + len('diffvim'):] if idx + len('diffvim') < len(line) else ""
            
            # ad_tmux → ad_tmux
            if after.startswith('-tmux'):
                result.append(line[pos:idx])
                result.append('ad_tmux')
                pos = idx + len('ad_tmux')
                changes += 1
                continue
            
            # ad_vim.pl → ad_vim.pl
            if after.startswith('.pl'):
                result.append(line[pos:idx])
                result.append('ad_vim.pl')
                pos = idx + len('ad_vim.pl')
                changes += 1
                continue
            
            # ad_compare → ad_compare
            if after.startswith('-compare'):
                result.append(line[pos:idx])
                result.append('ad_compare')
                pos = idx + len('ad_compare')
                changes += 1
                continue
            
            # ad_jogger → ad_jogger
            if after.startswith('-jogger'):
                result.append(line[pos:idx])
                result.append('ad_jogger')
                pos = idx + len('ad_jogger')
                changes += 1
                continue
            
            # ad_compute → ad_compute
            if after.startswith('-compute'):
                result.append(line[pos:idx])
                result.append('ad_compute')
                pos = idx + len('ad_compute')
                changes += 1
                continue
            
            # ad_colorize → ad_colorize
            if after.startswith('-colorize'):
                result.append(line[pos:idx])
                result.append('ad_colorize')
                pos = idx + len('ad_colorize')
                changes += 1
                continue
            
            # ad_postprocess → ad_postprocess
            if after.startswith('-postprocess'):
                result.append(line[pos:idx])
                result.append('ad_postprocess')
                pos = idx + len('ad_postprocess')
                changes += 1
                continue
            
            # ad_pipeline → ad_pipeline
            if after.startswith('-pipeline'):
                result.append(line[pos:idx])
                result.append('ad_pipeline')
                pos = idx + len('ad_pipeline')
                changes += 1
                continue
            
            # ad → ad
            if after.startswith('-animator'):
                result.append(line[pos:idx])
                result.append('ad')
                pos = idx + len('ad')
                changes += 1
                continue
            
            # ad_layer_pace → ad_layer_pace
            if after.startswith('-pace'):
                result.append(line[pos:idx])
                result.append('ad_layer_pace')
                pos = idx + len('ad_layer_pace')
                changes += 1
                continue
            
            # ad_vim.1 → ad_vim.1
            if after.startswith('.1'):
                result.append(line[pos:idx])
                result.append('ad_vim.1')
                pos = idx + len('ad_vim.1')
                changes += 1
                continue
            
            # ad_vim.bash → ad_vim.bash
            if after.startswith('.bash'):
                result.append(line[pos:idx])
                result.append('ad_vim.bash')
                pos = idx + len('ad_vim.bash')
                changes += 1
                continue
            
            # ad_vim.fish → ad_vim.fish
            if after.startswith('.fish'):
                result.append(line[pos:idx])
                result.append('ad_vim.fish')
                pos = idx + len('ad_vim.fish')
                changes += 1
                continue
            
            # __ad_vim → _ad_vim (zsh completion)
            if idx > 0 and line[idx-1] == '_':
                result.append(line[pos:idx])
                result.append('_ad_vim')
                pos = idx + len('diffvim')
                changes += 1
                continue
            
            # "man ad_vim" → "man ad_vim"
            if idx >= 4 and line[idx-4:idx] == 'man ':
                result.append(line[pos:idx])
                result.append('ad_vim')
                pos = idx + len('diffvim')
                changes += 1
                continue
            
            # "ad_vim:" (error message prefix) → "ad_vim:"
            if after.startswith(':'):
                result.append(line[pos:idx])
                result.append('ad_vim')
                pos = idx + len('diffvim')
                changes += 1
                continue
            
            # "ad_vim " (command usage) → "ad_vim "
            if after.startswith(' ') or after.startswith('\t') or after.startswith(']') or after.startswith(')'):
                result.append(line[pos:idx])
                result.append('ad_vim')
                pos = idx + len('diffvim')
                changes += 1
                continue
            
            # "diffvim\n" (end of line) or "diffvim" at end → "ad_vim"
            if len(after) == 0 or after[0] == '\n':
                result.append(line[pos:idx])
                result.append('ad_vim')
                pos = idx + len('diffvim')
                changes += 1
                continue
            
            # Default: just copy it through (don't replace ambiguous cases)
            result.append(line[pos:idx + len('diffvim')])
            pos = idx + len('diffvim')
        
        new_lines.append(''.join(result))
    
    return '\n'.join(new_lines), changes

# Process files
total_changes = 0
files_changed = 0

for root, dirs, files in os.walk(ROOT):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for f in files:
        filepath = os.path.join(root, f)
        rel = os.path.relpath(filepath, ROOT)
        
        if rel in SKIP_FILES:
            continue
        
        if not f.endswith(('.md', '.1', '.sh', '.pl', '.vim', '.bash', '.fish', '.rb', '.py')):
            continue
        
        with open(filepath, 'r', errors='replace') as fh:
            content = fh.read()
        
        new_content, changes = replace__ad_vim(content)
        
        if changes > 0:
            with open(filepath, 'w') as fh:
                fh.write(new_content)
            print(f"  {rel}: {changes} replacements")
            total_changes += changes
            files_changed += 1

print(f"\n{files_changed} files changed, {total_changes} replacements")
