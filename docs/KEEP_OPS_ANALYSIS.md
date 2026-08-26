# Analysis: Are `keep` ops still needed?

## Question

Since every op carries its own `(line, col)` position, do we still need
`keep` ops in the diff / post-processed / paced data files? When is
`keep` ever used?

## Short answer

**Yes, keep ops are still needed.** Removing them would break:

1. **The pace stage** — it uses keep ops to insert the right delays
   (1ms per keep char, so the cursor "walks" through unchanged text
   at a natural pace)
2. **The op ordering logic** — keeps are the anchors that define
   "change regions" (sequences of deletes/inserts between keeps)
3. **The animator's keep_char** — currently a no-op except for cursor
   advancement, BUT removing keeps would remove the visual effect of
   the cursor walking through unchanged text

However, **the animator's `keep_char` could be simplified** — with
per-op positioning, the cursor is already set by `set_cursor()` before
each op, so `keep_char`'s cursor-advancement is redundant (the next
op's `set_cursor` will overwrite it).

## Detailed analysis

### 1. Compute stage (produces keep ops)

The diff algorithm (Patience/LCS) naturally produces keep ops for
matching characters. Example:

```
OLD: abcXYZ
NEW: abcdefXYZ

Diff: keep a, keep b, keep c, insert d, insert e, insert f, keep X, keep Y, keep Z
```

The keep ops represent the "common subsequence" — the characters that
match between old and new. Without them, you'd only have deletes and
inserts, and you'd lose the information about which characters are
unchanged.

**Could the compute stage omit keeps?** Yes — the compute could
emit only deletes and inserts, with the understanding that "any
character not mentioned is kept." But this would require the
downstream stages (postprocess, pace, animator) to reconstruct the
keeps by diffing the old file against the op positions. That's more
complex than just emitting the keeps.

### 2. Postprocess stage (uses keep ops for ordering)

The postprocess's `optimize_line` function splits ops at keep
boundaries:

```c
/* Optimize: within each change region (between keeps), deletes before inserts. */
int optimize_line(Op *in, int count, Op *out) {
    int buf_start = 0;
    for (int i = 0; i <= count; i++) {
        if (i == count || strcmp(in[i].type, "keep") == 0) {
            /* Flush buffer: content deletes, \n deletes, then inserts */
            ...
            if (i < count) out[n_out++] = in[i]; /* the keep */
            buf_start = i + 1;
        }
    }
}
```

Keeps define the "change regions" — sequences of deletes/inserts
that happen between two keeps. Without keeps, the postprocess
couldn't know where one change region ends and the next begins.

**Could the postprocess work without keeps?** It could use `\n`
(newline) as the boundary instead of keeps. But this would change
the semantics — a "change region" would be a whole line, not a
sub-line region between keeps. The current behavior (deletes before
inserts within each inter-keep region) produces more natural
animation.

### 3. Pace stage (inserts delays based on keeps)

The pace stage inserts a 1ms delay after each keep:

```c
if (strcmp(toks[0], "keep") == 0) {
    passthrough(all_lines[i]);
    emit_delay(1, "char");   /* 1ms per keep char */
    i++;
}
```

This 1ms delay is what makes the cursor "walk" through unchanged
text at a visible (but fast) pace. Without keeps, the pace stage
would have no way to insert these walking delays — the animator
would just jump from one delete/insert to the next, with no visual
indication of the cursor moving through unchanged text.

**Could the pace stage work without keeps?** It could insert delays
based on the gap between op positions (if op N is at col 10 and op
N+1 is at col 20, insert 10ms of "walking" delay). But this would
require the pace stage to understand positions, which it currently
doesn't — it just emits delays op-by-op.

### 4. Animator (keep_char is mostly redundant)

The animator's `keep_char` function:

```c
void keep_char(int code) {
    if (code == 10) {
        cursor_l++;
        cursor_c = 0;
    } else {
        cursor_c++;
    }
}
```

With per-op positioning, the cursor is set by `set_cursor()` before
each op. So `keep_char`'s cursor advancement is **redundant** — the
next op's `set_cursor` will overwrite `cursor_l` and `cursor_c`
anyway.

**However**, `keep_char` still serves a purpose: it advances the
cursor DURING the delay between ops. If the pace stage inserts a 1ms
delay after a keep, and the animator renders the cursor position
during that delay, the cursor needs to be at the right place — which
`keep_char` provides.

If keeps were removed, the animator would need to compute the cursor
position from the op's `(line, col)` during the delay — which it
already does via `set_cursor()`. So `keep_char` is truly redundant
IF the animator renders cursor position based on `set_cursor()` and
not based on incremental advancement.

### 5. What would change if keeps were removed?

**If keeps were removed from the timed stream:**

- The animator would receive only deletes, inserts, and delays
- The animator's `set_cursor()` would still position the cursor
  correctly before each delete/insert
- The visual effect: the cursor would "jump" from one change to the
  next, with no walking-through-unchanged-text animation
- The pace stage would need a different way to insert walking delays
  (based on position gaps)

**If keeps were removed from the post-processed stream (but kept
internally by postprocess):**

- The postprocess would still use keeps internally for ordering
- But the output would only contain deletes, inserts, and delays
- The animator would receive fewer ops, but the positions would
  still be correct

**If keeps were removed from the raw diff stream (but kept
internally by compute):**

- The compute would still produce keeps internally
- But the raw output would only contain deletes and inserts
- The postprocess would need to reconstruct keeps (or work without
  them)

## Recommendation

**Keep the current design.** The keep ops serve multiple purposes
that would be hard to replicate without them:

1. They define change regions for the postprocess ordering
2. They trigger walking delays in the pace stage
3. They make the diff human-readable (you can see the common
   subsequence)
4. They're useful for debugging (the snapshot tool shows them)

The only simplification that makes sense is **in the animator's
`keep_char`** — it could be a no-op (just `set_cursor` handles
positioning). But even there, the 1ms delay from pace means the
animator needs to render the cursor at the keep's position during
that delay, which `keep_char`'s cursor advancement provides.

**Do NOT remove keeps from the data files.**
