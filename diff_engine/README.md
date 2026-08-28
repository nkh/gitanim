# compute/

Stage 1 of the diffvim pipeline. Computes the diff between old and new
files, produces raw character-level ops.

## Pipeline context

```
COMPUTE → postprocess → pace → animator
```

## Files

- `cpp/ad_compute.cpp` — C++ implementation (the only compute tool)
- `perl/compute_builtin.pl` — Perl fallback (produces identical output)
- `Makefile` — Builds `bin/ad_compute`
- `README.md` — Detailed compute documentation
- `PARALLELISM.md` — Parallelism notes

## Binary

`bin/ad_compute` — the compiled C++ binary.

**NOTE:** `bin/` is gitignored! After `git pull`, you must rebuild:
```bash
make -C compute clean && make -C compute
```

If you see `# diffvim precomputed diff v1` in the output, your binary
is stale (the v2 format has been the default since the refactor).

## Usage

```bash
./bin/ad_compute old.py new.py raw_ops.txt
```

Output format (v2 TSV):
```
# diffvim raw diff v2
# algorithm patience
HUNK	<target>	<del>	<ins>	<end_ins>	<end_del>
keep	<line>	<col>	<code>	<char_repr>
delete	<line>	<col>	<code>	<char_repr>
insert	<line>	<col>	<code>	<char_repr>
HUNK_END
```

## Algorithm

Patience diff (anchored on unique common lines, with LCS fallback for
ranges with no anchors). Produces char-level ops within each hunk.

Myers was removed in the refactor. LCS is available as `--algorithm lcs`
but Patience is the default.

## Related

- `../animator/` — Stages 2-4 (postprocess, pace, animator)
- `../docs/DEBUGGING.md` — How to debug the pipeline
- `../scripts/dv_debug.sh` — Run all stages and inspect output
