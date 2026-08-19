# Diff Tool Replacement Analysis

## Question

Can `diffvim-compute-cpp` be replaced by an existing diff tool like
GNU diff, difftastic, or `git diff`? This would remove one executable
and its associated code.

## Answer: No — but the reasons are instructive.

### What diffvim-compute-cpp does

It produces **char-level ops** (keep/delete/insert with Unicode code
points) grouped into **hunks**. This is a TWO-LEVEL diff:

1. **Line-level diff** (Patience algorithm): produces hunks with
   target lines, deleted line counts, inserted line counts
2. **Char-level diff** (within each hunk): for each pair of
   old-line / new-line, produces char-level keep/delete/insert ops

The output format is custom:
```
HUNK <target_line> <del_count> <ins_count> <is_end_insert> <is_end_delete>
keep <char_code>
delete <char_code>
insert <char_code>
```

### GNU diff (`diff -u`)

**Cannot replace diffvim-compute-cpp.**

- Produces **unified diff** format (line-level only, no char-level ops)
- No char-level diffing — would need a second stage to diff within
  each changed line
- No hunk grouping with target line / del/ins counts / end_insert /
  end_delete flags
- Would require a **parser** (like `jq_filter` / `difft_json_to_lcs`
  which already exist in the project) to convert unified diff →
  diffvim's HUNK format
- Then would still need the **char-level diff** (line_diff /
  char_diff functions in the C++ code)
- **Net result**: replace ~700 lines of C++ with a parser + the same
  char-level diff code = MORE code, not less

### difftastic (`difft`)

**Cannot replace diffvim-compute-cpp.**

- Produces a **structured tree diff** (AST-level), not char-level ops
- Different output format (JSON or terminal rendering)
- Does structural matching (syntax-tree aware) which is great for
  understanding but wrong for animation — we need char-level ops, not
  "this function was moved"
- Would need a **complex parser** to convert its output to diffvim's
  char-level op format
- The conversion would be harder than just running our own diff
- difftastic also doesn't produce line-level hunk info (target line,
  del/ins counts)
- **Net result**: add a difftastic dependency + a complex parser =
  more complexity, not less

### `git diff --patience`

**Cannot replace diffvim-compute-cpp.**

- Same as GNU diff — produces unified diff format (line-level only)
- No char-level ops
- Would need the same parser + char-level diff as GNU diff
- Only does line-level Patience; diffvim-compute-cpp does both
  line-level Patience AND char-level LCS
- `git diff` also can't be piped to file easily in the format we need
- **Net result**: same as GNU diff — more code, not less

### Why keeping diffvim-compute-cpp is the right choice

1. **Two-level diff in one tool**: line-level (Patience) + char-level
   (LCS) in a single ~700-line C++ file. No external tool does both.

2. **Custom output format**: the HUNK/keep/delete/insert format is
   exactly what postprocess and pace consume. Any replacement would
   need a parser to convert to this format.

3. **Performance**: <2ms for most files. The overhead of calling an
   external diff + parsing its output + running char-level diff would
   be slower.

4. **No dependencies**: the C++ tool has no external dependencies beyond
   the C++ standard library. difftastic requires Rust; GNU diff has a
   different output format.

5. **Already the only compute tool**: after the refactor, we removed
   the C, Rust, and Go implementations. There's only one compute
   executable. Removing it would mean re-implementing the diff in
   Perl (already exists as `compute_builtin.pl` — but slower).

6. **The code is small**: after removing Myers, the C++ file is ~700
   lines. That's less code than a parser for GNU diff's output would
   require.

### What WOULD make sense

- **Add difftastic as an OPTIONAL compute backend** for structural
  diffing (when the user wants AST-aware diffs). But keep
  diffvim-compute-cpp as the default.
- **Add `git diff --patience` as a fallback** when the C++ binary
  isn't available and the Perl builtin is too slow. But this requires
  the parser + char-level diff code.
- **None of these reduce code**: the char-level diff code is needed
  regardless of which line-level diff produces the hunks.

## Conclusion

**Keep `diffvim-compute-cpp`.** It does two jobs (line-level + char-level
diff) in one small, fast, dependency-free executable. Replacing it with
GNU diff, difftastic, or git diff would require a parser + the same
char-level diff code, resulting in MORE code, not less.
