# gitanim — animate code diffs as if a human were typing them

## What is this?

gitanim animates a code diff — it opens the old file and progressively
transforms it into the new file, character by character, as if a human
were typing the changes.

## Pipeline

```
<old> <new> → compute → postprocess → pace → animator → terminal animation
```

| Stage | Binary | Language | Purpose |
|-------|--------|----------|---------|
| compute | `compute/bin/diffvim-compute-cpp` | C++ | Patience diff → raw char ops |
| postprocess | `animator/bin/diffvim-postprocess` | C | Reorder ops, compute (line,col) positions |
| pace | `animator/bin/diffvim-pace` | C | Insert delays between ops |
| animator | `animator/bin/diffvim-animator-c` | C | Apply ops to buffer, render to terminal |

Each stage also has a Perl implementation (in `animator/perl/` and
`compute/perl/`) that produces identical output.

## Quick start

```bash
# Animate a diff in vim:
./diffvim old.py new.py

# Animate using the C animator (terminal):
./animator/diffvim-pipeline old.py new.py

# Debug the pipeline:
bash scripts/dv_debug.sh old.py new.py

# Run all tests:
bash tests/run_minimal_tests.sh        # 25 minimal cases
perl animator/tests/test_all_animators.pl   # animator unit tests
```

## Directory structure

| Directory | Contents |
|-----------|----------|
| `animator/` | Animator implementations (C + Perl) + tests + docs |
| `compute/` | Compute (diff) implementation (C++ + Perl fallback) |
| `DiffVim/` | Perl module for diff parsing |
| `autoload/` | Vimscript engine (sourced by the `diffvim` launcher) |
| `plugin/` | Vim plugin entry point |
| `scripts/` | Debugging, testing, and verification scripts |
| `tests/` | Test suites + minimal test cases |
| `examples/` | 42 old/new file pairs for testing |
| `docs/` | Documentation (DEBUGGING, FORMATS, PIPELINE, etc.) |
| `man/` | Man pages |
| `completion/` | Shell completions (bash, fish, zsh) |
| `packaging/` | Homebrew formula |

## Documentation

- [docs/DEBUGGING.md](docs/DEBUGGING.md) — How to debug the pipeline
- [docs/POSTPROCESS_TRANSFORMS.md](docs/POSTPROCESS_TRANSFORMS.md) — What the postprocess does
- [docs/FORMATS.md](docs/FORMATS.md) — Intermediary file formats
- [docs/PIPELINE.md](docs/PIPELINE.md) — Pipeline architecture
- [docs/VOCABULARY.md](docs/VOCABULARY.md) — Glossary

## Rebuilding after git pull

The compute binary is gitignored. After `git pull`:

```bash
make -C compute clean && make -C compute
```

If you see `# diffvim precomputed diff v1` in compute output, your binary
is stale.
