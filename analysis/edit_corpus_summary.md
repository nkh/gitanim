# Edit Corpus Analysis
**Total hunks analyzed:** 3215

## By source
| Source | Hunks |
|---|---:|
| gitanim_history | 3129 |
| examples | 62 |
| minimal | 24 |

## By category
| Category | Count | % | Median lines (rem→add) | Example |
|---|---:|---:|---|---|
| `block_modify` | 758 | 23.6% | 3→3 | 02_large_python: @@ -1,68 +1,114 @@ — -:['"""Data processor module — handles CSV ingestion and transformation."""'] +:['"""Data processor module — handles CSV/JSON ingestion and transformation."""'] |
| `block_insert` | 608 | 18.9% | 0→120 | 13_java: @@ -5,4 +5,11 @@ — -:[] +:['    public int multiply(int a, int b) {'] |
| `word_replace` | 603 | 18.8% | 1→1 | 04_word_replace: @@ -1,2 +1,2 @@ — -:['def hello():'] +:['def greet():'] |
| `block_replace` | 347 | 10.8% | 7→11 | 27_weird_insert: @@ -1,5 +1,4 @@ — -:['class DataProcessor:'] +:['@dataclass'] |
| `literal_replace` | 222 | 6.9% | 1→1 | ddd6fd21/ad_layer_line_delete_in_place.c: @@ -2,7 +2,7 @@ — -:[' *   delete(line1 chars) → join_lines → delete(line2 chars) → join_lines → ...'] +:[' *   delete(line1 chars) -> join_lines -> delete(line2 chars) -> join_lines -> ...'] |
| `block_delete` | 180 | 5.6% | 111→0 | 17_multi_line_delete: @@ -1,5 +1,2 @@ — -:['line2'] +:[] |
| `typo_fix` | 166 | 5.2% | 1→1 | 01_simple_replace: @@ -1 +1 @@ — -:['hello world'] +:['hello world!'] |
| `line_expand` | 64 | 2.0% | 1→3 | 25_complex_mix: @@ -1,8 +1,9 @@ — -:["    print('hello')"] +:['import json'] |
| `block_move` | 63 | 2.0% | 64→22 | 34_large_javascript: @@ -1,101 +1,56 @@ — -:["import React from 'react';"] +:["import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';"] |
| `line_replace` | 53 | 1.6% | 1→1 | 08_line_replace: @@ -1,3 +1,3 @@ — -:['def'] +:['XYZ'] |
| `line_insert` | 53 | 1.6% | 0→1 | 12_insert_line_at_end: @@ -1,2 +1,3 @@ — -:[] +:['line3'] |
| `line_delete` | 45 | 1.4% | 1→0 | 09_delete_middle_line: @@ -1,3 +1,2 @@ — -:['line2'] +:[] |
| `format_only` | 26 | 0.8% | 3→3 | 15_join_two_lines: @@ -1,2 +1 @@ — -:['foo'] +:['foobar'] |
| `line_collapse` | 26 | 0.8% | 5→1 | 1d1fcc80/ad.c: @@ -878,23 +779,11 @@ int main(int argc, char **argv) { — -:['            if (debug_trace) fprintf(stderr, "INSERT op_line=%d op_col=%d code=%d → cursor_l=%d cursor_c=%d n_lines=%d line_shift=%d lss=%d\\n",'] +:['                delete_char(code);'] |
| `indent_change` | 1 | 0.0% | 1→1 | 18_indent_change: @@ -1,2 +1,2 @@ — -:['    bar'] +:['        bar'] |

## Examples per category

### `block_delete`

**17_multi_line_delete** — `@@ -1,5 +1,2 @@`
```
- line2
- line3
- line4
```
**26_delete_line_op** — `@@ -1,5 +1,3 @@`
```
- B
- D
```
**01_small_python** — `@@ -1,3 +0,0 @@`
```
- def greet(name):
-     print("Hello, " + name)
-     return None
```

### `block_insert`

**13_java** — `@@ -5,4 +5,11 @@`
```
+     public int multiply(int a, int b) {
+         return a * b;
+     }
```
**18_scala** — `@@ -1,4 +1,8 @@`
```
+   def power(base: Int, exp: Int): Int =
+     if (exp == 0) 1 else base * power(base, exp - 1)
+   def factorial(n: Int): Int =
```
**9aa92e50/ad.c** — `@@ -757,6 +754,12 @@ int main(int argc, char **argv) {`
```
+             } else if (n_lines >= 1) {
+                 /* Last line: no L+1 to join with.
+                  * The \n at end of file is being deleted.
```

### `block_modify`

**02_large_python** — `@@ -1,68 +1,114 @@`
```
- """Data processor module — handles CSV ingestion and transformation."""
- from typing import List, Dict, Optional
-     """Processes CSV data with configurable transformations."""
+ """Data processor module — handles CSV/JSON ingestion and transformation."""
+ import json
+ from pathlib import Path
```
**14_kotlin** — `@@ -1,6 +1,12 @@`
```
- data class User(val name: String, val age: Int)
-     val user = User("Alice", 30)
+ data class User(
+     val name: String,
+     val age: Int,
```
**16_ruby** — `@@ -1,12 +1,18 @@`
```
-   attr_accessor :name, :age
-   def initialize(name, age)
-     puts "Hello, I'm #{@name}!"
+   attr_accessor :name, :age, :email
+   def initialize(name:, age:, email: nil)
+     @email = email
```

### `block_move`

**34_large_javascript** — `@@ -1,101 +1,56 @@`
```
- import React from 'react';
-  * DataGrid: a class-based table component that loads paginated rows
-  * from an API endpoint, supports sorting, filtering, and row selection.
+ import React, { useState, useEffect, useRef, useCallback, useMemo } from 'react';
+  * DataGrid: a function-based table component using React hooks.
+  * Supports sorting, filtering, paginated server-side loading, polling,
```
**34_large_javascript** — `@@ -107,177 +62,237 @@`
```
-   }
-   loadRows(silent) {
-     if (!silent) {
+   }, [page, pageSize, sortBy, sortDir, filter]);
+   useEffect(() => {
+     cancelledRef.current = false;
```
**34_large_javascript** — `@@ -287,50 +302,37 @@`
```
-         <button
-           onClick={() => this.goToPage(page - 1)}
-           disabled={page === 0}
+         <button onClick={() => goToPage(page - 1)} disabled={page === 0}>
+           onClick={() => goToPage(page + 1)}
+         <button onClick={refresh}>Refresh</button>
```

### `block_replace`

**27_weird_insert** — `@@ -1,5 +1,4 @@`
```
- class DataProcessor:
-     """Processes CSV data with configurable transformations."""
- 
+ @dataclass
+ class ProcessingResult:
```
**03_json_config** — `@@ -1,14 +1,26 @@`
```
-   "version": "1.0.0",
-   "description": "A sample application",
-     "test": "jest"
+   "version": "2.0.0",
+   "description": "A sample application with enhanced features",
+   "type": "module",
```
**04_shell_script** — `@@ -1,26 +1,54 @@`
```
- set -e
- APP_PORT=8080
- LOG_FILE="/var/log/myapp.log"
+ set -euo pipefail
+ APP_PORT="${APP_PORT:-8080}"
+ APP_HOST="${APP_HOST:-0.0.0.0}"
```

### `format_only`

**15_join_two_lines** — `@@ -1,2 +1 @@`
```
- foo
- bar
+ foobar
```
**16_split_line** — `@@ -1 +1,2 @@`
```
- foobar
+ foo
+ bar
```
**cd30aef1/IMPROVEMENT_PROPOSALS.md** — `@@ -53,8 +65,8 @@ Last updated: 2026-09-09 (reflects `refactor/no-newline-in-char-ops` branch)`
```
- 13. ⬜ **"Why didn't this hunk animate?" notice** — when `--max-hunk-chars`
-     skips, show `hunk 4 skipped (312 > 200)`.
+ 13. ⬜ **"Why didn't this hunk animate?" notice** — when
+     `--max-hunk-chars` skips, show `hunk 4 skipped (312 > 200)`.
```

### `indent_change`

**18_indent_change** — `@@ -1,2 +1,2 @@`
```
-     bar
+         bar
```

### `line_collapse`

**1d1fcc80/ad.c** — `@@ -878,23 +779,11 @@ int main(int argc, char **argv) {`
```
-             if (debug_trace) fprintf(stderr, "INSERT op_line=%d op_col=%d code=%d → cursor_l=%d cursor_c=%d n_lines=%d line_shift=%d lss=%d\n",
-                 op_line, op_col, code, cursor_l, cursor_c, n_lines, line_shift, line_shift_at_hunk_start);
-                 delete_char(code);  /* code parameter ignored for non-\n */
+                 delete_char(code);
```
**1d1fcc80/ad.c** — `@@ -912,23 +801,9 @@ int main(int argc, char **argv) {`
```
-             if (strcmp(cmd, "HUNK") == 0 && ntok >= 2) {
-                 /* If user asked to skip to next hunk, this is the next hunk — reset */
-                 /* Snapshot the cumulative line_shift for this hunk's ops.
+             if (strcmp(cmd, "HUNK") == 0) {
```
**72ed8b9d/compute.md** — `@@ -84,15 +84,10 @@ produces the same op count as patience.`
```
- | `DIFFVIM_ALGORITHM`            | Default `--algorithm` value                     |
- | `DIFFVIM_WORD_DIFF`            | Set to `1` to enable by default                 |
- | `DIFFVIM_OPTIMIZE_SEQUENCE`    | Default `1`; set to `0` to disable              |
+ The compute tool writes a line-oriented diff file that ad_vim's
```

### `line_delete`

**09_delete_middle_line** — `@@ -1,3 +1,2 @@`
```
- line2
```
**10_delete_first_line** — `@@ -1,3 +1,2 @@`
```
- line1
```
**11_delete_last_line** — `@@ -1,3 +1,2 @@`
```
- line3
```

### `line_expand`

**25_complex_mix** — `@@ -1,8 +1,9 @@`
```
-     print('hello')
+ import json
+     print('hello world')
```
**08_rust_code** — `@@ -1,5 +1,20 @@`
```
-     let sum: i32 = nums.iter().sum();
+ use std::collections::HashMap;
+ 
+ 
```
**20_clojure** — `@@ -1,7 +1,14 @@`
```
- (ns myapp.core)
+ (ns myapp.core
+   (:require [clojure.string :as str]))
+ 
```

### `line_insert`

**12_insert_line_at_end** — `@@ -1,2 +1,3 @@`
```
+ line3
```
**13_insert_line_at_start** — `@@ -1,2 +1,3 @@`
```
+ line1
```
**14_insert_line_in_middle** — `@@ -1,2 +1,3 @@`
```
+ line2
```

### `line_replace`

**08_line_replace** — `@@ -1,3 +1,3 @@`
```
- def
+ XYZ
```
**20_unicode** — `@@ -1 +1 @@`
```
- cafe
+ café
```
**ddd6fd21/ad_layer_common.h** — `@@ -4,7 +4,7 @@`
```
-  *   3. No env vars, no debug dumps, no dead code.
+  *   3. --debug flag enables per-layer logging to stderr.
```

### `literal_replace`

**ddd6fd21/ad_layer_line_delete_in_place.c** — `@@ -2,7 +2,7 @@`
```
-  *   delete(line1 chars) → join_lines → delete(line2 chars) → join_lines → ...
+  *   delete(line1 chars) -> join_lines -> delete(line2 chars) -> join_lines -> ...
```
**ddd6fd21/ad_layer_line_delete_in_place.c** — `@@ -148,7 +153,7 @@ static int layer_line_delete_in_place(Op *ops, int n_ops, Op *out, int out_cap,`
```
-                      * delete content → join → delete next content → join.
+                      * delete content -> join -> delete next content -> join.
```
**4a12075c/OPTIONS_ANALYSIS.md** — `@@ -105,7 +105,7 @@ canceling pairs are already handled.`
```
- - `--type-delay-ms`, `--delete-delay-ms`, `--tick-ms`
+ - `--type-delay-ms`, `--delete-delay-ms`
```

### `typo_fix`

**01_simple_replace** — `@@ -1 +1 @@`
```
- hello world
+ hello world!
```
**02_simple_insert** — `@@ -1 +1 @@`
```
- hello world
+ hello world!
```
**72ed8b9d/completion.md** — `@@ -60,7 +60,7 @@ Phase B refactor — there's only one compute implementation now.)`
```
- The completion scripts are loaded by the shell when you type `diffvim`
+ The completion scripts are loaded by the shell when you type `ad_vim`
```

### `word_replace`

**04_word_replace** — `@@ -1,2 +1,2 @@`
```
- def hello():
+ def greet():
```
**05_delete_to_eol** — `@@ -1 +1 @@`
```
- abc def ghi
+ abc
```
**06_insert_at_eol** — `@@ -1 +1 @@`
```
- abc
+ abc def
```
