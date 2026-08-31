#!/usr/bin/env python3
"""Add provenance headers to all documentation files.

For each .md and .html file in docs/, adds (or updates) a header block
at the top (after the # title) with:
  - Created: commit hash + date
  - Last updated: commit hash + date
  - Based on repo HEAD: hash + date

Usage: python3 scripts/add_doc_provenance.py
"""
import os
import subprocess
import re

ROOT = "/home/z/my-project/gitanim"

def git_output(args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()

def get_created_commit(filepath):
    """Find the commit that first added this file."""
    try:
        return git_output(["git", "log", "--diff-filter=A", "--format=%h|%ci|%%s", "--", filepath]).split("\n")[0]
    except:
        return None

def get_last_modified_commit(filepath):
    """Find the last commit that modified this file."""
    try:
        return git_output(["git", "log", "-1", "--format=%h|%ci|%s", "--", filepath])
    except:
        return None

def get_head():
    """Get current HEAD."""
    h = git_output(["git", "rev-parse", "HEAD"])
    date = git_output(["git", "log", "-1", "--format=%ci", h])
    return h[:12], date

def format_provenance(created, modified, head_hash, head_date):
    lines = []
    if created:
        parts = created.split("|")
        lines.append(f"*Created:* `{parts[0]}` ({parts[1]})")
    if modified:
        parts = modified.split("|")
        lines.append(f"*Last updated:* `{parts[0]}` ({parts[1]})")
    lines.append(f"*Repo HEAD:* `{head_hash}` ({head_date})")
    return "\n".join(lines)

def add_provenance(filepath):
    """Add or update provenance header in a markdown file."""
    full_path = os.path.join(ROOT, filepath)
    if not os.path.exists(full_path):
        return False

    with open(full_path, "r") as f:
        content = f.read()

    created = get_created_commit(filepath)
    modified = get_last_modified_commit(filepath)
    head_hash, head_date = get_head()

    if not created and not modified:
        return False

    provenance = format_provenance(created, modified, head_hash, head_date)

    # Check if there's already a provenance block
    prov_pattern = r'(\*Created:\*.*?\*Repo HEAD:\*`[a-f0-9]+`.*?\n)'
    existing = re.search(prov_pattern, content, re.DOTALL)

    if existing:
        # Replace existing provenance
        content = content[:existing.start()] + provenance + "\n" + content[existing.end():]
    else:
        # Find the first blank line after the title (or after the first line)
        lines = content.split("\n")
        insert_after = 0
        for i, line in enumerate(lines):
            if i > 0 and line.strip() == "":
                insert_after = i
                break
            if i > 0 and line.startswith("##"):
                insert_after = i - 1
                break
            if i > 2:
                insert_after = 2
                break

        # Insert provenance after the first blank line
        lines.insert(insert_after, "")
        lines.insert(insert_after + 1, provenance)
        lines.insert(insert_after + 2, "")
        content = "\n".join(lines)

    with open(full_path, "w") as f:
        f.write(content)
    return True

# Process all markdown and HTML files in docs/
doc_files = []
for root, dirs, files in os.walk(os.path.join(ROOT, "docs")):
    # Skip docs/design/ (historical docs — don't modify)
    if "design" in root:
        continue
    for f in files:
        if f.endswith(".md") or f.endswith(".html"):
            rel = os.path.relpath(os.path.join(root, f), ROOT)
            doc_files.append(rel)

# Also add the root README.md
if os.path.exists(os.path.join(ROOT, "README.md")):
    doc_files.append("README.md")

count = 0
for filepath in sorted(doc_files):
    if add_provenance(filepath):
        print(f"  updated: {filepath}")
        count += 1

print(f"\n{count} files updated")
