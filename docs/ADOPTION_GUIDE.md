# Adoption Guide — Bringing diffvim to Your Team

diffvim has grown into a complex tool with **50+ CLI options**, three
implementations (`diffvim`, `diffvim-tmux`, `diffvim.pl`), one
external compute tool (C++) with a Perl fallback, and six presets.
That flexibility is great for power users but can be intimidating
for newcomers. This document explains how to introduce diffvim to
your team in a way that **sticks** — so developers actually use it
daily, not just once for a demo.

> **Audience:** team leads, developer advocates, anyone rolling out
> diffvim to a group of developers.
>
> **Status:** up to date with diffvim 1.4.

---

## 1. Why Adoption Is Hard (and How to Fix It)

The five most common reasons developers try diffvim once and never
again:

| Reason                              | Symptom                                          | Fix in this guide        |
| ----------------------------------- | ------------------------------------------------ | ------------------------ |
| Too many options, no clear default | User runs `diffvim --help`, panics, gives up    | §2 — Presets as on-ramp  |
| Slow startup on large files         | User waits 4 seconds before animation starts    | §3 — External compute    |
| No integration with existing flow   | User forgets diffvim exists, uses `git diff`    | §4 — Editor + git hooks  |
| Hard to share with teammates        | User has to explain what they're watching       | §5 — Recording + sharing |
| Defaults don't match the team       | Everyone reconfigures diffvim differently       | §6 — Shared team config  |

Each fix is small on its own. Together they remove the friction that
kills tool adoption.

---

## 2. Presets as the On-Ramp

**The single most effective adoption trick: never show new users the
full `--help` output. Show them the six presets.**

```bash
# BAD — overwhelming
diffvim --help | head -100     # 50+ options, instant paralysis

# GOOD — six clear use cases
diffvim --preset review old.py new.py
diffvim --preset demo old.py new.py
diffvim --preset ai-code old.py new.py
```

### Recommended onboarding sequence

1. **Day 1:** `diffvim old.py new.py` (default preset, no flags)
2. **Day 2:** `diffvim --preset review --git-blame old.py new.py`
3. **Day 3:** `diffvim --preset demo old.py new.py` (in a team meeting)
4. **Week 2:** `diffvim --preset ai-code old.py new.py` (for AI diffs)
5. **Week 3:** rely on the default C++ compute tool for large files
   (no `--tool` flag needed — it's automatic)
6. **Month 2:** customize via `DIFFVIM_PRESET` env var

**Never** introduce raw options like `--word-diff`, `--semantic-cleanup`,
or `--left-to-right` until the user has used presets for at least a
week. By then they'll have a mental model and will understand what
each option does.

---

## 3. External Compute as the Default for Real Codebases

The in-vim LCS is fast enough for toy examples but takes seconds on
real codebases. **Make `compute/bin/diffvim-compute-cpp` the default**,
not `diffvim` without pre-computation:

```bash
# diffvim searches for compute/bin/diffvim-compute-cpp automatically.
# Recommend this alias in every team member's shell config:
alias dv='diffvim'

# With the C++ binary on PATH, `dv old.py new.py` is:
#   1. ~1ms compute (C++) + ~50ms vim startup = 51ms total
#   2. vs. ~3500ms vimscript LCS + 50ms startup = 3550ms total
```

A 50x speedup at startup is the difference between "diffvim feels
instant" and "diffvim feels slow." Users who feel a tool is slow will
stop using it within a week.

### Build the compute tool once, share via PATH

```bash
# Build the C++ binary (only one compute implementation now)
make -C compute

# Symlink to /usr/local/bin (or anywhere on PATH)
sudo ln -sf "$(pwd)/compute/bin/diffvim-compute-cpp" /usr/local/bin/
sudo ln -sf "$(pwd)/diffvim" /usr/local/bin/
```

Now `diffvim` and `diffvim-compute-cpp` are available to everyone on
the machine. (No more `--tool c|cpp|rust|go` flag — that was removed
in the refactor; only the C++ tool remains.)

---

## 4. Editor and Git Integration

A diff tool that isn't integrated into the existing workflow will be
forgotten. diffvim ships with several integration points — use them.

### 4.1 Vim plugin (zero config)

```vim
" In ~/.vimrc or ~/.config/nvim/init.vim
source /path/to/diffvim/plugin/diffvim.vim

" Now you have:
"   :Diffvim old.py new.py
"   :DiffvimCommit       " animate the last commit
"   :DiffvimPick         " fzf picker for commits
```

Once the plugin is loaded, developers don't need to leave vim to
animate a diff. This is the **single biggest stickiness factor**.

### 4.2 Git alias

```bash
# In ~/.gitconfig
[alias]
    animate = "!f() { compute/bin/diffvim-compute-cpp \"$1\"^:\"$2\" \"$1\":\"$2\"; }; f"
```

Now `git animate HEAD src/main.py` animates the last commit's changes
to `src/main.py`.

### 4.3 Pre-commit hook (optional, for team review)

```bash
# .git/hooks/pre-commit (chmod +x)
#!/bin/bash
# After staging, run diffvim on the staged changes
compute/bin/diffvim-compute-cpp --preset review --no-vimrc \
    <(git show :src/main.py) src/main.py
```

This is aggressive — only do it if your team is on board.

### 4.4 GitHub Actions (for PR previews)

Use `diffvim --log-mode 2` to generate a textual log of the animation,
attach it to PRs as a comment. The log shows the line, the operation
marker, and the result — a kind of "diff storyboard" that's perfect for
async review.

```yaml
# .github/workflows/diffvim-preview.yml
name: diffvim-preview
on: [pull_request]
jobs:
  preview:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - run: |
          git diff origin/main...HEAD -- src/ | \
            diffvim --diff - --log-mode 2 --log-file preview.log
      - uses: actions/github-script@v6
        with:
          script: |
            const fs = require('fs');
            const log = fs.readFileSync('preview.log', 'utf8');
            github.rest.issues.createComment({
              ...context.repo,
              issue_number: context.issue.number,
              body: '```diffvim\n' + log + '\n```'
            });
```

---

## 5. Recording and Sharing Animations

A big adoption driver is **social proof**: when developers see their
colleagues using diffvim in standup, demos, or PR comments, they want
to use it too.

### 5.1 Record a GIF

```bash
# Use asciinema to record the terminal
asciinema rec demo.cast
diffvim --preset demo old.py new.py
# Ctrl-D to stop recording

# Convert to GIF
agg demo.cast demo.gif
```

### 5.2 Embed in a README

Record once, embed in your project README:

```markdown
## Refactor: extract session_scope

![diffvim animation](docs/assets/session_scope_refactor.gif)

Run it yourself: `diffvim --preset review old.py new.py`
```

### 5.3 Share log-mode output

For async review (Slack, GitHub PR comments), use log mode instead of
a video — it's text, copy-pasteable, and accessible:

```bash
diffvim --log-mode 2 --log-file - old.py new.py | \
    curl -F 'f=<-' https://paste.example.com
```

---

## 6. Shared Team Configuration

When every developer configures diffvim differently, the team can't
help each other. Standardize via a checked-in config.

### 6.1 Project-level `.diffvimrc`

```bash
# In your repo, at the root:
cat > .diffvimrc <<'EOF'
# Team default: review preset + Rust compute + inline highlight
DIFFVIM_PRESET="review --highlight-inline"
DIFFVIM_COMPUTE_TOOL=rust
DIFFVIM_COMPUTE_DIR="$(git rev-parse --show-toplevel)/compute"
EOF
```

Developers source it once:

```bash
# In ~/.bashrc or ~/.zshrc
[ -f ./.diffvimrc ] && source ./.diffvimrc
```

Now everyone on the team gets the same defaults.

### 6.2 Editor config snippet

Check in a `.vimrc.local` snippet that team members can `source`:

```vim
" .vimrc.local (checked into the repo)
source /path/to/diffvim/plugin/diffvim.vim

" Team mapping: <leader>d animates the current buffer's last commit
nnoremap <leader>d :DiffvimCommit<CR>

" Team mapping: <leader>p picks a commit to animate
nnoremap <leader>p :DiffvimPick<CR>
```

---

## 7. Suggested Onboarding Workshop (45 minutes)

A structured workshop gets a team from "never used diffvim" to "uses
it daily" in one session.

### Minute 0–5: Demo (no slides)

Open a real recent refactor from your repo. Run:

```bash
diffvim --preset review --git-blame old.py new.py
```

Walk through the animation. **Don't explain options yet** — just show
the result. The wow factor does the selling.

### Minute 5–15: Everyone installs

```bash
git clone https://github.com/nkh/gitanim.git ~/diffvim
cd ~/diffvim
make -C compute rust         # 1 minute
echo 'export PATH="$HOME/diffvim:$PATH"' >> ~/.bashrc
source ~/.bashrc
diffvim --version
```

Verify everyone has `diffvim --version` working before moving on.

### Minute 15–25: First run

Pick a recent commit from your repo. Everyone runs:

```bash
diffvim --preset review --git-blame \
    <(git show HEAD~1:src/main.py) src/main.py
```

Walk around and help anyone whose animation didn't start.

### Minute 25–35: Vim plugin

```bash
echo 'source ~/diffvim/plugin/diffvim.vim' >> ~/.vimrc
```

In vim: `:DiffvimCommit`. Now everyone has it integrated.

### Minute 35–45: Pick a preset, set `DIFFVIM_PRESET`

Have each developer pick the preset that matches their style:

```bash
echo 'export DIFFVIM_PRESET="review --highlight-word"' >> ~/.bashrc
```

Set up `git animate` alias together. End with: "Tomorrow, replace one
`git diff` per day with `git animate`."

---

## 8. Measuring Adoption

You can't improve what you don't measure. Track:

| Metric                                | How to measure                              | Target     |
| ------------------------------------- | ------------------------------------------- | ---------- |
| % of developers with diffvim installed | `which diffvim | wc -l` across the team    | 100%       |
| Animations per developer per week     | Wrap `diffvim` in a logging wrapper         | 5+         |
| % of PRs that mention a diffvim log   | GitHub search `body:"diffvim"`              | 20%+       |
| Average session duration              | Wrap in a timer                             | 30-120s    |

If a metric stalls, ask "what's the friction?" — usually it's one of
the five reasons from §1.

---

## 9. Common Pushback (and Answers)

> **"I already use `git diff` and it's fine."**

`git diff` shows you *what* changed. diffvim shows you *how* it
changed — the order of edits, the cursor movement, the rhythm. For
trivial diffs they're equivalent. For non-trivial refactors, diffvim
is qualitatively easier to follow. Try it on a 200-line refactor and
decide for yourself.

> **"Vim isn't my editor."**

diffvim works in any terminal vim. You don't have to use vim as your
daily editor — just `diffvim old.py new.py` opens vim temporarily,
animates, and `:q` quits. It's a viewer, not an editor.

> **"It's too slow on large files."**

Use `compute/bin/diffvim-compute-cpp`. The C++ compute tool finishes
in ~1ms on a 1000-line file. The in-vim LCS is the bottleneck, not
the animation. (diffvim searches for the C++ binary automatically —
no flag needed.)

> **"Too many options, I'll never learn them."**

You don't have to. Use presets. There are six. Pick one that matches
your use case and stop. You'll learn individual options naturally
over time.

> **"My team's diffs are too big."**

Try `--preset review --fold-unchanged`. Folding unchanged regions
collapses 90% of typical PRs to a few hunks. For really big diffs,
use `--max-hunk-chars 200` to skip char-by-char animation on huge
hunks.

> **"AI-generated diffs are too messy to animate."**

That's exactly what the `ai-code` preset is for. It enables
`--semantic-cleanup`, `--left-to-right`, and `--word-diff` together,
which turn a chaotic char-level diff into something that reads like
human edits.

---

## 10. The 30-Day Adoption Checklist

Use this as a shared checklist in your team channel:

```
Week 1 — Install and first runs
  [ ] Everyone has `diffvim --version` working
  [ ] Everyone has run `diffvim old.py new.py` on a real file
  [ ] Everyone has run `diffvim --preset review --git-blame ...`
  [ ] Everyone has installed the vim plugin

Week 2 — Integrate into daily flow
  [ ] `git animate` alias set up
  [ ] `DIFFVIM_PRESET` env var customized per developer
  [ ] One diffvim GIF shared in the team channel
  [ ] One PR comment includes a diffvim log

Week 3 — Compute tools and large files
  [ ] `compute/bin/diffvim-compute-cpp` is the default for files >500 lines
  [ ] `make -C compute` runs in CI to verify the binary builds
  [ ] Everyone has tried `--preset ai-code` on an AI-generated diff

Week 4 — Share and refine
  [ ] Team has agreed on a shared `.diffvimrc`
  [ ] At least one teammate has presented a refactor using diffvim in standup
  [ ] Adoption metric: 5+ animations per developer per week
```

When every box is checked, diffvim is part of your team's DNA.

---

## 11. Anti-Patterns to Avoid

- **Don't** introduce raw options in the first week. Use presets only.
- **Don't** run `diffvim` without the C++ compute binary on files >500
  lines. The 3-second startup will sour users on the tool.
- **Don't** require a specific preset for everyone. Let each developer
  pick their own via `DIFFVIM_PRESET`.
- **Don't** use `--step-mode` for demos. It's for code review, not
  presentations.
- **Don't** forget to install the manpages (`man diffvim` should work
  out of the box).
- **Don't** skip the workshop. A 45-minute group session is worth
  weeks of solo trial-and-error.

---

## 12. Summary

The three things that matter most:

1. **Presets** — make the on-ramp trivial. Six use cases, one flag.
2. **External compute** — make it fast. `compute/bin/diffvim-compute-cpp`
   is the recommended default for real codebases.
3. **Editor integration** — make it stick. The vim plugin is the
   single biggest predictor of long-term adoption.

Everything else is gravy. Get those three right and your team will be
using diffvim daily within a month.

---

## See Also

- [Visual Guide](./VISUAL_GUIDE.md) — share this with newcomers
- [Presets](./src/presets.md) — the six built-in presets
- [Compute Tools](./src/compute.md) — external compute reference
- [Manpages](./man/) — install with `sudo cp man/*.1 /usr/local/share/man/man1/`
- [50 UX Improvements](./FOLLOW_IMPROVEMENTS.md) — what makes diffs
  easier to follow
- [AI Code Diffing](./AI_CODE_DIFFING.md) — 100 ways to make diffvim
  better for AI-generated code

## Change Log

| Date       | Change                                          |
| ---------- | ----------------------------------------------- |
| 2026-08-16 | Initial version. Covers diffvim 1.4.            |
| 2026-08-18 | Updated for the Phase A–C refactor: C++ only    |
|            | compute tool (with Perl fallback), removed      |
|            | `--tool` flag, removed Myers algorithm.         |
