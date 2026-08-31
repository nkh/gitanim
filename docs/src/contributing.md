# Contributing to `ad`

*Created:* `8475573` (2026-08-28 15:39:59 +0000)
*Last updated:* `7b9e449` (2026-08-28 18:57:44 +0000)
*Repo HEAD:* `96d0693aca20` (2026-08-31 01:49:17 +0000)


Thanks for your interest in improving `ad`! This document explains the development workflow.

## Quick start

```bash
git clone https://github.com/nkh/gitanim.git
cd gitanim
make            # builds all binaries into bin/
make test       # runs all tests
```

## Project layout

```
ad/
├── bin/                  # build output (gitignored)
├── diff_engine/          # the diff LCS/Hirschberg engine (C++ + Perl)
├── layers/               # postprocess layer plugins (C + Perl twins)
│   ├── c/
│   ├── perl/
│   └── tests/            # one test file per layer (TDD)
├── animator/             # the animator backend
├── pipeline/         # the orchestrator + pipeline driver
├── apps/vim/             # ad_vim — the vim application
├── scripts/            # helper scripts (ad_debug, ad_snapshot, etc.)
├── tests/                # cross-cutting tests + examples
├── docs/                 # mdBook documentation
├── man/                  # manpages
└── completion/           # shell completions
```

## How CI works

Three workflows run on every push and PR:

1. **build-and-test.yml** — builds with `make`, runs all tests via `make test-*` targets.
2. **lint.yml** — runs `shellcheck` on every `.sh`, `perl -c` on every `.pl`, `gcc -fsyntax-only` on every `.c`.
3. **docs.yml** — builds the mdBook on changes to `docs/**`.

A fourth workflow, **release.yml**, runs on git tags `v*` and creates a GitHub Release with a tarball.

To run CI locally:

```bash
make test       # mirrors build-and-test.yml
make docs       # mirrors docs.yml (requires mdbook installed)
```

## Adding a new layer (TDD workflow)

Layers are the postprocess plugins — they transform V2 TSV op streams. Each layer lives at `layers/c/ad_layer_<name>.c` (C) and `layers/perl/ad_layer_<name>.pl` (Perl twin).

### Step 1: Write the test first

Create `layers/tests/test_<name>.pl`. The test should:

- Feed a known V2 TSV input (commit a `<name>_in.tsv` fixture if needed).
- Assert specific V2 TSV output.
- Assert the layer is invokable standalone (`bin/ad_layer_<name> < in > out; exit 0`).
- Assert C/Perl parity (if you implement both).

Look at `layers/tests/test_reorder.pl` for a template.

### Step 2: Run the test (it should fail — red)

```bash
perl layers/tests/test_<name>.pl
```

### Step 3: Implement the layer

Create `layers/c/ad_layer_<name>.c` (and `layers/perl/ad_layer_<name>.pl` for the twin). The layer must:

- Read V2 TSV from stdin.
- Write V2 TSV to stdout.
- Exit 0 on success.

See `docs/src/plugin-layers.md` for the full plugin contract.

### Step 4: Add Makefile entries

Add a build rule and test target in `Makefile`:

```makefile
bin/ad_layer_<name>: layers/c/ad_layer_<name>.c layers/tests/test_<name>.pl
	$(CC) $(CFLAGS) -I layers/c -o $@ layers/c/ad_layer_<name>.c

test-layer-<name>: bin/ad_layer_<name>
	@perl layers/tests/test_<name>.pl
```

Add `test-layer-<name>` to the `test-layers` aggregate target.

### Step 5: Run the test (it should pass — green)

```bash
make test-layer-<name>
```

### Step 6: Commit

The commit MUST include both the test file and the implementation. CI will block merge if the test is missing or failing.

## Adding a new feature to an existing layer

1. Add a test case to `layers/tests/test_<name>.pl` that exercises the new feature.
2. Run the test — it should fail.
3. Implement the feature in `layers/c/ad_layer_<name>.c` and `layers/perl/ad_layer_<name>.pl`.
4. Run the test — it should pass.
5. Verify C/Perl parity (the test does this automatically).

## Running specific tests

```bash
make test-layers              # all 6 layer tests
make test-layer-reorder       # just one layer
make test-minimal             # 25 end-to-end minimal cases
make test-l2r                 # 35 l2r algorithm tests
make test-property            # 50 property-based random tests
make test-layers-discovery    # 9 plugin-contract tests
```

## Previewing the docs locally

```bash
# Install mdbook (one-time):
curl -sSL https://github.com/rust-lang/mdBook/releases/latest/download/mdbook-x86_64-unknown-linux-gnu.tar.gz \
  | tar xz -C /usr/local/bin

# Serve the docs (live reload):
cd docs && mdbook serve
# Open http://localhost:3000
```

## Coding standards

- **C**: `-Wall -Wextra -Werror` (enforced by Makefile). Include `ad_layer_common.h` for shared types.
- **Perl**: `use strict; use warnings;` always. UTF-8 stdin/stdout.
- **Bash**: `set -euo pipefail` at the top. Quote all variable expansions.
- **Tests**: one test file per layer. Data-driven where possible (iterate examples).

## Commit messages

Follow the existing style:

```
Phase N: <short description>

<longer description, wrapped at 72 cols>
```

Use `Phase N:` for multi-commit refactors so the progression is visible.

## Questions?

Open an issue at https://github.com/nkh/gitanim/issues.
