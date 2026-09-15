#!/usr/bin/env python3
"""edit_corpus_analysis.py — Analyze edit categories in the corpus.

Sources:
  1. tests/minimal/*  (27 cases, no extension)
  2. tests/examples/* (41 cases, various extensions)
  3. gitanim's own git history (sample ~200 commits, every modified file)

For each hunk in each diff:
  - Parse the unified diff
  - Extract features (line counts, char counts, word overlap, whitespace)
  - Classify into an edit category using heuristic rules
  - Record (source, file, hunk_idx, category, features)

Outputs:
  analysis/edit_corpus.csv       — one row per hunk
  analysis/edit_corpus_summary.md — histogram + per-category examples
"""
import csv
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path("/home/z/my-project/gitanim")
OUTDIR = ROOT / "analysis"
OUTDIR.mkdir(exist_ok=True)

# ---------- Diff parsing ----------

def parse_unified_diff(diff_text):
    """Return list of hunks. Each hunk = (header, list of (tag, line))."""
    hunks = []
    cur_hunk = None
    for line in diff_text.splitlines():
        if line.startswith("@@"):
            if cur_hunk is not None:
                hunks.append(cur_hunk)
            cur_hunk = {"header": line, "lines": []}
        elif cur_hunk is not None:
            if line.startswith("+"):
                cur_hunk["lines"].append(("+", line[1:]))
            elif line.startswith("-"):
                cur_hunk["lines"].append(("-", line[1:]))
            elif line.startswith(" "):
                cur_hunk["lines"].append((" ", line[1:]))
            # skip \ No newline at end of file etc.
    if cur_hunk is not None:
        hunks.append(cur_hunk)
    return hunks

# ---------- Feature extraction ----------

def split_words(line):
    """Tokenize a line into words (identifier-like + whitespace + punctuation)."""
    return re.findall(r"[A-Za-z_][A-Za-z0-9_]*|\s+|[^\sA-Za-z0-9_]", line)

def line_features(removed, added):
    """Compute features for an intra-line or line-level hunk."""
    n_rem = len(removed)
    n_add = len(added)
    rem_text = "\n".join(removed)
    add_text = "\n".join(added)
    rem_words = set(w for w in split_words(rem_text) if w.strip() and w[0].isalpha())
    add_words = set(w for w in split_words(add_text) if w.strip() and w[0].isalpha())
    common = rem_words & add_words
    union = rem_words | add_words
    word_jaccard = len(common) / len(union) if union else 1.0
    # Whitespace-only change?
    rem_nospace = re.sub(r"\s", "", rem_text)
    add_nospace = re.sub(r"\s", "", add_text)
    whitespace_only = (rem_nospace == add_nospace and rem_text != add_text)
    # Indent change only (same content, different leading whitespace)
    def leading_ws(s):
        m = re.match(r"^[ \t]*", s)
        return m.group(0) if m else ""
    if n_rem == n_add and n_rem > 0:
        same_after_indent = all(
            re.sub(r"^[ \t]+", "", r) == re.sub(r"^[ \t]+", "", a)
            for r, a in zip(removed, added)
        )
        indent_only = same_after_indent and any(
            leading_ws(r) != leading_ws(a) for r, a in zip(removed, added)
        ) and rem_nospace == add_nospace
    else:
        indent_only = False
    return {
        "n_removed": n_rem,
        "n_added": n_add,
        "rem_chars": len(rem_text),
        "add_chars": len(add_text),
        "rem_words": len(rem_words),
        "add_words": len(add_words),
        "common_words": len(common),
        "word_jaccard": round(word_jaccard, 3),
        "whitespace_only": whitespace_only,
        "indent_only": indent_only,
    }

# ---------- Categorization ----------

def categorize(features):
    """Map features → category string. Rules in priority order."""
    f = features
    n_rem = f["n_removed"]
    n_add = f["n_added"]

    # Pure noise categories
    if f["whitespace_only"] and not f["indent_only"]:
        if n_rem == 0 and n_add == 0:
            return "no_change"
        return "format_only"

    if f["indent_only"]:
        return "indent_change"

    # Line-level: one side is empty
    if n_rem == 0 and n_add == 1:
        return "line_insert"
    if n_rem == 0 and n_add >= 2:
        return "block_insert"
    if n_rem == 1 and n_add == 0:
        return "line_delete"
    if n_rem >= 2 and n_add == 0:
        return "block_delete"

    # Single-line modification
    if n_rem == 1 and n_add == 1:
        # Intra-line change
        if f["word_jaccard"] >= 0.8:
            # Mostly the same words — small edit
            if f["rem_chars"] - f["add_chars"] in (-2, -1, 0, 1, 2) and f["common_words"] >= 2:
                return "typo_fix"
            return "literal_replace"
        if f["word_jaccard"] >= 0.3:
            return "word_replace"
        # Very low overlap → swap
        return "line_replace"

    # Block-level
    if n_rem >= 2 and n_add >= 2:
        if f["word_jaccard"] >= 0.5:
            return "block_modify"
        # Could be a move, but we'd need to check the rest of the file.
        # Default: block_replace
        return "block_replace"

    # Mixed (1 vs many)
    if n_rem == 1 and n_add >= 2:
        return "line_expand"
    if n_rem >= 2 and n_add == 1:
        return "line_collapse"

    return "other"

# ---------- Per-hunk move detection ----------

def detect_moves_in_file(hunks):
    """Mark hunks as block_move if removed lines reappear as added lines elsewhere."""
    # Collect all removed and added line-texts with their hunk idx
    rem_by_hunk = defaultdict(list)
    add_by_hunk = defaultdict(list)
    for idx, h in enumerate(hunks):
        for tag, line in h["lines"]:
            if tag == "-":
                rem_by_hunk[idx].append(line)
            elif tag == "+":
                add_by_hunk[idx].append(line)
    # Build a map: line_text → list of (hunk_idx, side)
    rem_lines = defaultdict(list)
    add_lines = defaultdict(list)
    for idx, lines in rem_by_hunk.items():
        for line in lines:
            rem_lines[line].append(idx)
    for idx, lines in add_by_hunk.items():
        for line in lines:
            add_lines[line].append(idx)
    # If a hunk has 2+ removed lines that all appear as added in a single other hunk, mark both as move-related
    move_pairs = set()
    for idx, lines in rem_by_hunk.items():
        if len(lines) < 2:
            continue
        # Find the most common other-hunk that contains these as adds
        targets = Counter()
        for line in lines:
            for t in add_lines.get(line, []):
                if t != idx:
                    targets[t] += 1
        if targets:
            best_target, best_count = targets.most_common(1)[0]
            if best_count >= 2:  # at least 2 lines moved
                move_pairs.add((idx, best_target))
    return move_pairs

# ---------- Corpus sources ----------

def collect_corpus_files():
    """Yield (source_label, name, old_path, new_path) tuples."""
    # Minimal corpus
    for d in sorted((ROOT / "tests" / "minimal").iterdir()):
        if not d.is_dir():
            continue
        old = d / "old"
        new = d / "new"
        if old.is_file() and new.is_file():
            yield ("minimal", d.name, old, new)
    # Examples corpus
    for d in sorted((ROOT / "tests" / "examples").iterdir()):
        if not d.is_dir():
            continue
        old = None
        new = None
        for ext in ("py","txt","go","rs","c","ts","sh","yaml","yml","json","xml",
                    "html","css","js","rb","php","java","kt","swift","scala","ex",
                    "clj","cl","md","toml","lua","Dockerfile","Makefile","R",
                    "cs","hs","pl"):
            if old is None and (d / f"old.{ext}").is_file():
                old = d / f"old.{ext}"
            if new is None and (d / f"new.{ext}").is_file():
                new = d / f"new.{ext}"
        if old and new:
            yield ("examples", d.name, old, new)

def collect_git_history(sample_size=200):
    """Sample commits from gitanim's own history. For each commit, take every
    modified file's diff (parent..commit). Skip merge commits."""
    try:
        log = subprocess.check_output(
            ["git", "-C", str(ROOT), "log", "--pretty=%H", "--no-merges",
             f"-n{sample_size}"],
            text=True, stderr=subprocess.DEVNULL
        ).strip().split("\n")
    except subprocess.CalledProcessError:
        return
    for commit in log:
        if not commit:
            continue
        try:
            files = subprocess.check_output(
                ["git", "-C", str(ROOT), "diff", "--name-only",
                 f"{commit}^..{commit}", "--", "*.c", "*.cpp", "*.h",
                 "*.py", "*.pl", "*.sh", "*.vim", "*.md"],
                text=True, stderr=subprocess.DEVNULL
            ).strip().split("\n")
        except subprocess.CalledProcessError:
            continue
        for fpath in files:
            if not fpath:
                continue
            try:
                diff = subprocess.check_output(
                    ["git", "-C", str(ROOT), "diff", f"{commit}^..{commit}",
                     "--", fpath],
                    text=True, stderr=subprocess.DEVNULL
                )
            except subprocess.CalledProcessError:
                continue
            if not diff.strip():
                continue
            yield ("gitanim_history", f"{commit[:8]}/{Path(fpath).name}", diff)

# ---------- Main ----------

def main():
    rows = []  # (source, case, hunk_idx, category, n_rem, n_add, jaccard, ws_only, indent_only)
    examples_by_cat = defaultdict(list)  # cat → list of (case, hunk_header)

    # 1. Corpus files (old/new pairs)
    for source, name, old, new in collect_corpus_files():
        # `diff -u` exits 1 when files differ (which is what we want), 0 if same
        r = subprocess.run(["diff", "-u", str(old), str(new)],
                           capture_output=True, text=True)
        diff = r.stdout
        if not diff.strip():
            continue
        hunks = parse_unified_diff(diff)
        move_pairs = detect_moves_in_file(hunks)
        for idx, h in enumerate(hunks):
            removed = [l for tag, l in h["lines"] if tag == "-"]
            added = [l for tag, l in h["lines"] if tag == "+"]
            f = line_features(removed, added)
            cat = categorize(f)
            # Override: move detection
            for (src, dst) in move_pairs:
                if idx == src:
                    cat = "block_move"
                # dst hunk keeps its own category (it's the insertion side)
            rows.append({
                "source": source,
                "case": name,
                "hunk_idx": idx,
                "category": cat,
                "n_removed": f["n_removed"],
                "n_added": f["n_added"],
                "rem_chars": f["rem_chars"],
                "add_chars": f["add_chars"],
                "word_jaccard": f["word_jaccard"],
                "whitespace_only": int(f["whitespace_only"]),
                "indent_only": int(f["indent_only"]),
                "hunk_header": h["header"],
            })
            if len(examples_by_cat[cat]) < 3:
                examples_by_cat[cat].append((name, h["header"], removed[:3], added[:3]))

    # 2. Git history
    for source, name, diff_text in collect_git_history(sample_size=200):
        hunks = parse_unified_diff(diff_text)
        move_pairs = detect_moves_in_file(hunks)
        for idx, h in enumerate(hunks):
            removed = [l for tag, l in h["lines"] if tag == "-"]
            added = [l for tag, l in h["lines"] if tag == "+"]
            f = line_features(removed, added)
            cat = categorize(f)
            for (src, dst) in move_pairs:
                if idx == src:
                    cat = "block_move"
            rows.append({
                "source": source,
                "case": name,
                "hunk_idx": idx,
                "category": cat,
                "n_removed": f["n_removed"],
                "n_added": f["n_added"],
                "rem_chars": f["rem_chars"],
                "add_chars": f["add_chars"],
                "word_jaccard": f["word_jaccard"],
                "whitespace_only": int(f["whitespace_only"]),
                "indent_only": int(f["indent_only"]),
                "hunk_header": h["header"],
            })
            if len(examples_by_cat[cat]) < 5:
                examples_by_cat[cat].append((name, h["header"], removed[:3], added[:3]))

    # Write CSV
    csv_path = OUTDIR / "edit_corpus.csv"
    with csv_path.open("w", newline="") as f:
        if rows:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
    print(f"Wrote {len(rows)} hunk rows to {csv_path}")

    # Summary
    by_cat = Counter(r["category"] for r in rows)
    by_source = Counter(r["source"] for r in rows)
    print("\nBy source:")
    for src, cnt in by_source.most_common():
        print(f"  {src:25s} {cnt:5d}")
    print("\nBy category:")
    for cat, cnt in by_cat.most_common():
        pct = 100.0 * cnt / len(rows)
        print(f"  {cat:20s} {cnt:5d}  ({pct:5.1f}%)")

    # Write markdown summary
    md = []
    md.append("# Edit Corpus Analysis\n")
    md.append(f"**Total hunks analyzed:** {len(rows)}\n")
    md.append("\n## By source\n")
    md.append("| Source | Hunks |\n|---|---:|\n")
    for src, cnt in by_source.most_common():
        md.append(f"| {src} | {cnt} |\n")
    md.append("\n## By category\n")
    md.append("| Category | Count | % | Median lines (rem→add) | Example |\n")
    md.append("|---|---:|---:|---|---|\n")
    # Per-category stats
    cat_rows = defaultdict(list)
    for r in rows:
        cat_rows[r["category"]].append(r)
    for cat, cnt in by_cat.most_common():
        pct = 100.0 * cnt / len(rows)
        med_rem = sorted(r["n_removed"] for r in cat_rows[cat])[len(cat_rows[cat])//2]
        med_add = sorted(r["n_added"] for r in cat_rows[cat])[len(cat_rows[cat])//2]
        ex = examples_by_cat[cat][0] if examples_by_cat[cat] else ("?","?",[],[])
        ex_text = f"{ex[0]}: {ex[1]}"
        if ex[2] or ex[3]:
            ex_text += f" — -:{ex[2][:1]!r} +:{ex[3][:1]!r}"
        md.append(f"| `{cat}` | {cnt} | {pct:.1f}% | {med_rem}→{med_add} | {ex_text} |\n")
    md.append("\n## Examples per category\n")
    for cat in sorted(by_cat.keys()):
        md.append(f"\n### `{cat}`\n\n")
        for (case, header, rem, add) in examples_by_cat[cat][:3]:
            md.append(f"**{case}** — `{header}`\n")
            md.append("```\n")
            for r in rem[:3]:
                md.append(f"- {r}\n")
            for a in add[:3]:
                md.append(f"+ {a}\n")
            md.append("```\n")
    md_path = OUTDIR / "edit_corpus_summary.md"
    md_path.open("w").write("".join(md))
    print(f"\nWrote summary to {md_path}")

if __name__ == "__main__":
    main()
