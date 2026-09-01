" ad_ops_syntax.vim — syntax highlighting for ad op TSV files
"
" Standalone — no plugins, no filetype autodetection needed.
" Load with: vim -S ad_ops_syntax.vim opfile.tsv
"
" Or add to ~/.vim/syntax/ and use :set filetype=ad_ops
"
" Color scheme:
"   Comments (#...)          → Comment  (gray)
"   Op types (keep/delete/…)  → Type     (green)
"   HUNK / HUNK_END           → Statement (yellow)
"   \n ops (code 10)          → Special  (magenta)
"   Numbers (line, col, code) → Number   (cyan)
"   Char repr ('a')           → String   (red)
"   delay ops                 → PreProc  (purple)

" Clear existing syntax
syntax clear

" ── Comments ──────────────────────────────────────────────────────
" Lines starting with # (after optional whitespace)
syn match adOpsComment "^\s*#.*$"

" ── Op types (first column) ──────────────────────────────────────
syn match adOpsKeep    "^keep\t"
syn match adOpsDelete  "^delete\t"
syn match adOpsInsert  "^insert\t"
syn match adOpsOverwrite "^overwrite_insert\t"

" ── HUNK / HUNK_END ──────────────────────────────────────────────
syn match adOpsHunk    "^HUNK\t"
syn match adOpsHunkEnd "^HUNK_END$"

" ── delay ops ────────────────────────────────────────────────────
syn match adOpsDelay   "^delay\t"

" ── snapshot ops (used by tests) ─────────────────────────────────
syn match adOpsSnapshot "^snapshot\t"

" ── decoration ops (highlight, dim, fold, sign, marker) ──────────
syn match adOpsHighlight "^highlight\t"
syn match adOpsDim       "^dim\t"
syn match adOpsFold      "^fold\t"
syn match adOpsSign      "^sign\t"
syn match adOpsMarker    "^marker\t"

" ── \n ops (code 10) — highlight the whole line differently ─────
" Match lines where the 4th field (code) is 10
syn match adOpsNewline "^\(keep\|delete\|insert\|overwrite_insert\)\t\d\+\t\d\+\t10\t"

" ── Numbers (line, col, code — the 2nd, 3rd, 4th fields) ────────
" Match tab-delimited numbers
syn match adOpsNumber "\t\d\+"

" ── Char repr (last column) ──────────────────────────────────────
" Single chars in quotes: 'a', '\n', etc.
syn match adOpsChar "'[^']*'"
" Special: \n, \t, \r, space (without quotes)
syn match adOpsCharSpecial "\\\\n\|\\\\t\|\\\\r\|\<space\>"

" ── Highlight links ──────────────────────────────────────────────
hi link adOpsComment       Comment
hi link adOpsKeep          Type
hi link adOpsDelete        Type
hi link adOpsInsert        Type
hi link adOpsOverwrite     Type
hi link adOpsHunk          Statement
hi link adOpsHunkEnd       Statement
hi link adOpsDelay         PreProc
hi link adOpsSnapshot      PreProc
hi link adOpsHighlight     PreProc
hi link adOpsDim           PreProc
hi link adOpsFold          PreProc
hi link adOpsSign          PreProc
hi link adOpsMarker        PreProc
hi link adOpsNewline       Special
hi link adOpsNumber        Number
hi link adOpsChar          String
hi link adOpsCharSpecial   Special

" ── Optional: set filetype for buffer ────────────────────────────
" This helps if user wants to use :setfiletype later
let b:current_syntax = "ad_ops"
