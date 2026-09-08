" ad_ops_syntax.vim — syntax highlighting for ad op TSV files
"
" Standalone — no plugins, no filetype autodetection needed.
" Load with: vim -S ad_ops_syntax.vim opfile.tsv
"
" Or add to ~/.vim/syntax/ and use :set filetype=ad_ops
"
" Color scheme (distinct colors per op type):
"   Comments (#...)           → Comment      (gray italic)
"   keep                       → Type         (green)
"   delete                     → red bg, white text
"   insert                     → green bg, black text
"   overwrite_insert           → yellow bg, black text
"   HUNK / HUNK_END            → Statement    (yellow bold)
"   \n ops (code 10)           → magenta bg, white text
"   delay                      → PreProc      (purple)
"   Numbers (line, col, code)  → Number       (cyan)
"   Char repr ('a')            → String       (red)
"   snapshot                   → Special      (orange)
"   highlight/dim/fold/sign/marker → PreProc  (purple)

" Clear existing syntax
syntax clear

" ── Comments ──────────────────────────────────────────────────────
syn match adOpsComment "^\s*#.*$"

" ── Op types (first column) — distinct colors ────────────────────
syn match adOpsKeep           "^keep\t"
syn match adOpsDelete         "^delete\t"
syn match adOpsInsert         "^insert\t"
syn match adOpsOverwrite      "^overwrite_insert\t"
syn match adOpsKeepLine       "^keep_line\t"
syn match adOpsJoinLines      "^join_lines\t"
syn match adOpsSplitLine      "^split_line\t"
syn match adOpsDeleteLine     "^delete_line\t"
syn match adOpsInsertLine     "^insert_line\t"

" ── HUNK / HUNK_END ──────────────────────────────────────────────
syn match adOpsHunk           "^HUNK\t"
syn match adOpsHunkEnd        "^HUNK_END$"

" ── delay ops ────────────────────────────────────────────────────
syn match adOpsDelay          "^delay\t"

" ── snapshot ops (used by tests) ─────────────────────────────────
syn match adOpsSnapshot       "^snapshot\t"

" ── decoration ops (highlight, dim, fold, sign, marker) ──────────
syn match adOpsHighlight      "^highlight\t"
syn match adOpsDim            "^dim\t"
syn match adOpsFold           "^fold\t"
syn match adOpsSign           "^sign\t"
syn match adOpsMarker         "^marker\t"

" ── glide ops ────────────────────────────────────────────────────
syn match adOpsGlide          "^glide\t"

" ── \n ops (code 10) — highlight the whole line differently ─────
" Match lines where the 4th field (code) is 10
" Old \n-specific match removed — \n is no longer a char op
" (replaced by keep_line/join_lines/split_line)

" ── Numbers (line, col, code — the 2nd, 3rd, 4th fields) ────────
syn match adOpsNumber         "\t\d\+"

" ── Char repr (last column) ──────────────────────────────────────
" Single chars in quotes: 'a', '\n', etc.
syn match adOpsChar           "'[^']*'"
" Special: \n, \t, \r, space (without quotes)
syn match adOpsCharSpecial    "\\\\n\|\\\\t\|\\\\r\|\<space\>"

" ── Highlight links ──────────────────────────────────────────────
" Comments
hi link adOpsComment          Comment

" Op types — distinct foreground colors
hi link adOpsKeep             Type
hi link adOpsOverwrite        Type

" delete: red background, white text
hi adOpsDelete      ctermfg=white ctermbg=red    guifg=white guibg=red

" insert: green background, black text
hi adOpsInsert      ctermfg=black ctermbg=green  guifg=black guibg=green

" HUNK / HUNK_END — bold yellow
hi adOpsHunk        ctermfg=yellow cterm=bold    guifg=yellow gui=bold
hi adOpsHunkEnd     ctermfg=yellow cterm=bold    guifg=yellow gui=bold

" delay — purple
hi link adOpsDelay            PreProc

" snapshot — orange (Special)
hi link adOpsSnapshot         Special

" decoration ops — purple
hi link adOpsHighlight        PreProc
hi link adOpsDim              PreProc
hi link adOpsFold             PreProc
hi link adOpsSign             PreProc
hi link adOpsMarker           PreProc
hi link adOpsGlide            PreProc

" \n ops — magenta background, white text
hi adOpsKeepLine     ctermfg=green guifg=green
hi adOpsJoinLines    ctermfg=yellow ctermbg=darkred guifg=yellow guibg=darkred
hi adOpsSplitLine    ctermfg=yellow ctermbg=darkgreen guifg=yellow guibg=darkgreen

" Numbers — cyan
hi link adOpsNumber          Number

" Char repr — red string
hi link adOpsChar            String
hi link adOpsCharSpecial     Special

" ── Optional: set filetype for buffer ────────────────────────────
let b:current_syntax = "ad_ops"
