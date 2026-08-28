# tests/examples/

The canonical end-to-end test corpus. 36 old/new file pairs covering
26 languages: Python, Go, Rust, C, TypeScript, Java, JavaScript, Ruby,
PHP, Swift, Scala, Clojure, Haskell, R, SQL, YAML, TOML, JSON, XML,
HTML, CSS, Shell, Dockerfile, Makefile, Markdown, Lua, Perl, Elixir,
Kotlin, C#, plus "large" variants for stress-testing.

## Usage

    bash tests/run_all_examples.sh

Each pair is run through the full pipeline:

    ad_compute → ad_postprocess → ad_layer_pace → ad

The final buffer is compared against `new.<ext>`. 36/36 should pass.

## Adding a new example

Create a directory `tests/examples/NN_name/` with `old.<ext>` and
`new.<ext>` files. The test runner auto-discovers them.
