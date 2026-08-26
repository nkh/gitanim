# docs/

Documentation for the diffvim project.

## Debugging

- `DEBUGGING.md` — Full debugging guide. How to run each pipeline stage
  separately, what to look for, common errors and their causes.
- `POSTPROCESS_TRANSFORMS.md` — Every transformation the postprocess
  applies, with examples. Clearly marks always-on vs option-dependent.

## Architecture

- `PIPELINE.md` — Pipeline architecture and stage descriptions.
- `ARCHITECTURE.md` — High-level architecture.
- `ARCHITECTURE_DIAGRAMS.md` — ASCII architecture diagrams.
- `ARCHITECTURE_ANALYSIS.md` — Architecture analysis.
- `ANIMATOR_REQUIREMENTS.md` — Animator requirements spec.

## Formats

- `FORMATS.md` — Intermediary file formats (raw, post-processed, timed).
- `VOCABULARY.md` — Glossary of terms.

## Options

- `OPTIONS_OVERVIEW.md` — Overview of all options.
- `OPTION_ANALYSIS.md` — Analysis of individual options.
- `OPTIONS_ANALYSIS.md` — Detailed options analysis.
- `OPTION_COMBINATIONS.md` — Option combination examples.

## Guides

- `ADOPTION_GUIDE.md` — How to adopt diffvim in your workflow.
- `CONFIGURATION.md` — Configuration guide.
- `CONTROLS.md` — Keyboard controls during animation.
- `DEVELOPER_GUIDE.md` — Guide for developers.
- `MULTI_FILE.md` — Multi-file animation.
- `PARALLEL_COMPUTE.md` — Parallel computation.
- `VISUAL_GUIDE.md` — Visual guide.
- `FAQ.md` — Frequently asked questions.

## Other

- `NEXT_SESSION.md` — Handoff doc for the next session.
- `USER_REQUESTS.md` — User requests and responses.
- `100_IMPROVEMENTS.md` — 100 improvement ideas.
- `DIFF_STUDY.md` — Diff algorithm study.
- `DIFF_TOOL_REPLACEMENT.md` — Replacing diff tools.
- `POST_PROCESSING.md` — Post-processing notes.
- `AI_CODE_DIFFING.md` — AI code diffing.
- `FOLLOW_IMPROVEMENTS.md` — Follow improvements.
- `NON_CHAR_OPTIONS.md` — Non-character options.
- `PICKER.md` — Commit picker.
- `API_REFERENCE.md` — API reference.
- `TESTING.md` — Testing guide.
- `presentation.html` — HTML presentation.

## mdBook (`src/`)

The `src/` subdirectory contains mdBook chapters. Build with:
```bash
mdbook build docs/src/
```

## Related

- `../DEBUGGING.md` — Quick link to the debugging guide
- `../scripts/dv_debug.sh` — The debugging tool
- `../tests/minimal/` — Minimal test cases for debugging
