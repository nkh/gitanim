#!/usr/bin/env python3
"""layer_audit.py — For each edit category, run a representative case
through (a) the default pipeline (reorder only) and (b) each individual
layer alone, then print the resulting op stream so we can see what
the layer actually does to that category.

For each (category, layer) pair we record:
  - did the snapshot match the target? (correctness)
  - did the op stream contain forbidden patterns?
      - 'delete X, insert Y, delete X, insert Y' (interleaving flicker)
      - 'delete' immediately followed by 'insert' at same (line,col) that
        wasn't merged by overwrite
      - delete-then-insert for what should be a word_replace (multiple
        delete/insert pairs inside one word)
"""
import subprocess
import re
import csv
import sys
from pathlib import Path
from collections import defaultdict

ROOT = Path("/home/z/my-project/gitanim")
OUTDIR = ROOT / "analysis"

# Representative case per category (hand-picked from the corpus)
CASES = {
    "typo_fix":         ("tests/minimal/01_simple_replace", "old", "new"),
    "word_replace":     ("tests/minimal/04_word_replace",   "old", "new"),
    "line_replace":     ("tests/minimal/08_line_replace",   "old", "new"),
    "line_insert":      ("tests/minimal/13_insert_line_at_start", "old", "new"),
    "line_delete":      ("tests/minimal/10_delete_first_line",    "old", "new"),
    "block_insert":     ("tests/examples/13_java", "old.java", "new.java"),
    "block_delete":     ("tests/minimal/17_multi_line_delete", "old", "new"),
    "block_modify":     ("tests/examples/04_shell_script", "old.sh", "new.sh"),
    "block_replace":    ("tests/examples/01_small_python", "old.py", "new.py"),
    "line_expand":      ("tests/minimal/16_split_line", "old", "new"),
    "line_collapse":    ("tests/minimal/15_join_two_lines", "old", "new"),
    "indent_change":    ("tests/minimal/18_indent_change", "old", "new"),
    "format_only":      ("tests/minimal/19_trailing_whitespace", "old", "new"),
    "block_move":       None,  # no canonical case in corpus; will synthesize
    "literal_replace":  ("tests/minimal/05_delete_to_eol", "old", "new"),
}

LAYERS = [
    "ad_layer_reorder",
    "ad_layer_overwrite",
    "ad_layer_indent_last",
    "ad_layer_line_delete_in_place",
    "ad_layer_split_in_place",
    "ad_layer_join_insert_in_place",
    "ad_layer_batch_whitespace",
    "ad_layer_skip_indent",
    "ad_layer_line_replace",
]

def run(cmd, stdin=None):
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    return r.stdout, r.stderr, r.returncode

def run_pipeline(old, new, layer=None):
    """Run compute + (optional single layer) + pace + animator. Return
    (raw_ops, post_ops, snap, ok)."""
    import tempfile
    raw_path = "/tmp/layer_audit_raw.txt"
    snap_path = "/tmp/layer_audit_snap.txt"
    # Stage 1: compute (requires output file path, doesn't support stdout)
    subprocess.run([str(ROOT/"bin/ad_compute"), str(old), str(new), raw_path],
                   capture_output=True, check=False)
    raw = Path(raw_path).read_text() if Path(raw_path).exists() else ""

    # Stage 2: postprocess (optional layer)
    if layer:
        r = subprocess.run([str(ROOT/"pipeline/ad_postprocess"),
                            f"--ad-layer={layer}"],
                           input=raw, capture_output=True, text=True)
        post = r.stdout
    else:
        post = raw

    # Stage 3: pace
    r = subprocess.run([str(ROOT/"bin/ad_layer_pace")],
                       input=post, capture_output=True, text=True)
    timed = r.stdout

    # Stage 4: animator
    Path(snap_path).unlink(missing_ok=True)
    subprocess.run([str(ROOT/"bin/ad"), "--no-display", "--speed", "1000",
                    "--snapshot", snap_path, str(old)],
                   input=timed, capture_output=True, text=True)
    snap_file = Path(snap_path).read_text() if Path(snap_path).exists() else ""
    with open(new) as f:
        target = f.read()
    ok = (snap_file == target)
    return raw, post, snap_file, ok

def op_stream_metrics(ops_text):
    """Compute quality metrics on an op stream."""
    ops = []
    for line in ops_text.splitlines():
        if line.startswith("#") or line.startswith("HUNK") or not line.strip():
            continue
        if line.startswith("HUNK_END") or line.startswith("EOF"):
            continue
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        ops.append(parts)  # [op_type, line, col, code, ...]

    metrics = {
        "n_ops": len(ops),
        "n_delete": sum(1 for o in ops if o[0] == "delete"),
        "n_insert": sum(1 for o in ops if o[0] == "insert"),
        "n_overwrite_insert": sum(1 for o in ops if o[0] == "overwrite_insert"),
        "n_keep": sum(1 for o in ops if o[0] == "keep"),
        # Interleaving flicker: delete X, insert Y, delete X, insert Y at same line
        "interleave_flicker": 0,
        # Unmerged delete-insert pairs at same (line,col)
        "unmerged_del_ins_pairs": 0,
    }

    # Detect interleaving: within a line, delete and insert alternate
    by_line = defaultdict(list)
    for o in ops:
        if o[0] in ("delete", "insert", "overwrite_insert"):
            by_line[o[1]].append((o[0], o[2]))
    for line, seq in by_line.items():
        # Count transitions between delete and insert (excluding overwrite_insert)
        transitions = 0
        prev = None
        for typ, col in seq:
            if typ == "overwrite_insert":
                continue
            if prev is not None and prev != typ:
                transitions += 1
            prev = typ
        if transitions >= 2:  # at least 2 transitions = D-I-D or I-D-I
            metrics["interleave_flicker"] += 1

    # Detect unmerged delete-insert pairs at same (line, col)
    for i in range(len(ops) - 1):
        if (ops[i][0] == "delete" and ops[i+1][0] == "insert"
            and ops[i][1] == ops[i+1][1] and ops[i][2] == ops[i+1][2]):
            metrics["unmerged_del_ins_pairs"] += 1

    return metrics

def synthesize_block_move_case():
    """Create a synthetic block-move case: lines 3-5 moved to after line 7."""
    case_dir = Path("/tmp/layer_audit_block_move")
    case_dir.mkdir(exist_ok=True)
    old = case_dir / "old"
    new = case_dir / "new"
    old.write_text("line1\nline2\nBLOCK_A\nBLOCK_B\nBLOCK_C\nline6\nline7\nline8\n")
    new.write_text("line1\nline2\nline6\nline7\nBLOCK_A\nBLOCK_B\nBLOCK_C\nline8\n")
    return old, new

def main():
    rows = []
    print(f"{'CATEGORY':<20} {'LAYER':<35} {'OK':<4} {'OPS':>5} {'DEL':>5} {'INS':>5} {'OVR':>5} {'FLK':>4} {'UNM':>4}")
    print("-" * 110)

    for cat, case_spec in CASES.items():
        if case_spec is None and cat == "block_move":
            old, new = synthesize_block_move_case()
        else:
            case_dir, old_name, new_name = case_spec
            old = ROOT / case_dir / old_name
            new = ROOT / case_dir / new_name

        # First: no layer (raw compute output)
        for layer in [None] + LAYERS:
            layer_name = layer if layer else "(no layer)"
            raw, post, snap, ok = run_pipeline(old, new, layer)
            m = op_stream_metrics(post)
            ok_str = "✓" if ok else "✗"
            print(f"{cat:<20} {layer_name:<35} {ok_str:<4} {m['n_ops']:>5} "
                  f"{m['n_delete']:>5} {m['n_insert']:>5} {m['n_overwrite_insert']:>5} "
                  f"{m['interleave_flicker']:>4} {m['unmerged_del_ins_pairs']:>4}")
            rows.append({
                "category": cat,
                "layer": layer_name,
                "correct": int(ok),
                **m
            })

    # Write CSV
    csv_path = OUTDIR / "layer_audit.csv"
    with csv_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"\nWrote {csv_path}")

    # Summary: for each category, which layer gives best quality?
    print("\n=== Per-category best layer (by lowest interleave_flicker, then lowest unmerged, then most ops saved) ===")
    by_cat = defaultdict(list)
    for r in rows:
        by_cat[r["category"]].append(r)
    for cat in sorted(by_cat.keys()):
        candidates = by_cat[cat]
        # Filter to correct only
        correct = [r for r in candidates if r["correct"]]
        if not correct:
            print(f"  {cat:<20} NO CORRECT LAYER (all broken)")
            continue
        # Pick best
        best = min(correct, key=lambda r: (r["interleave_flicker"],
                                            r["unmerged_del_ins_pairs"],
                                            r["n_ops"]))
        print(f"  {cat:<20} best: {best['layer']:<35} "
              f"flk={best['interleave_flicker']} unm={best['unmerged_del_ins_pairs']} ops={best['n_ops']}")

if __name__ == "__main__":
    main()
