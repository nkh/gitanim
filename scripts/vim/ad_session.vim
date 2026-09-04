" ad_session.vim — Vim setup for ad_session (vim-only op debugger).
"
" Loaded after ad_ops_syntax.vim. Sets up:
"   - Split layout: diff (left) | ops+result (right)
"   - F5: run animation in terminal split
"   - F6: run animator snapshot, update result, refresh diff
"   - Leader shortcuts for commit, quit, generate, fold, etc.
"   - Fold expressions for keep ops and hunks
"   - Help system (<leader>?)

" --- Check required variables ---
if !exists('g:ad_session_dir')
    echoerr 'ad_session.vim: g:ad_session_dir not set'
    finish
endif

" --- Variables ---
let s:session_dir = g:ad_session_dir
let s:old_file = exists('g:ad_old_file') ? g:ad_old_file : 'old'
let s:new_file = exists('g:ad_new_file') ? g:ad_new_file : 'new'
let s:ops_file = exists('g:ad_ops_file') ? g:ad_ops_file : 'ops.tsv'
let s:result_file = exists('g:ad_result_file') ? g:ad_result_file : 'result.txt'
let s:animator = exists('g:ad_animator') ? g:ad_animator : 'ad'
let s:gen_ops = exists('g:ad_gen_ops') ? g:ad_gen_ops : 'ad_gen_ops'
let s:fold_context = exists('g:ad_fold_context') ? g:ad_fold_context : 5
let s:fold_hunks_start = exists('g:ad_fold_hunks') ? g:ad_fold_hunks : 0
let s:annotate = exists('g:ad_annotate') ? g:ad_annotate : 0
let s:layer_file = exists('g:ad_layer_file') && g:ad_layer_file != '' ? g:ad_layer_file : ''

" --- Set working directory ---
execute 'cd ' . s:session_dir

" --- Leader key (use default \, don't override user's setting) ---

" --- Layout setup ---
" Layout:
"   Left: new file (diff with result)
"   Right top: ops.tsv
"   Right bottom: result.txt

" Close all windows, start fresh
only

" Open new file on the left
execute 'leftabove vsplit ' . s:new_file
" Open result below new
execute 'belowright split ' . s:result_file

" Set up diff between new and result
wincmd h  " to new
diffthis
wincmd j  " to result
diffthis
setlocal nomodifiable readonly

" Go to ops
wincmd l  " to ops.tsv

" --- Fold settings for ops buffer ---
" O(N) fold: pre-compute fold regions on BufReadPost, use manual folds.
" The O(N²) foldexpr was replaced because it froze on large op files.
function! s:AdSetupFolds()
    " Clear existing folds
    normal! zE
    let l:ctx = s:fold_context
    if l:ctx <= 0
        return
    endif
    " Walk lines, find runs of keep ops outside context of non-keep ops
    let l:start = 0
    let l:i = 1
    let l:n = line('$')
    while l:i <= l:n
        let l:line = getline(l:i)
        let l:is_keep = (l:line =~ '^keep\t')
        let l:is_meta = (l:line =~ '^#' || l:line == '' || l:line =~ '^HUNK' || l:line =~ '^HUNK_END' || l:line =~ '^delay' || l:line =~ '^EOF')
        if !l:is_keep && !l:is_meta
            " Non-keep op — check if there's a foldable run before it
            if l:start > 0
                " Don't fold the last l:ctx lines (context)
                let l:fold_end = l:i - l:ctx - 1
                if l:fold_end > l:start
                    execute l:start . ',' . l:fold_end . 'fold'
                endif
            endif
            let l:start = 0
            " Also check ahead for context
            let l:ahead = l:i + 1
            let l:ahead_end = min([l:i + l:ctx, l:n])
        elseif l:is_keep
            if l:start == 0
                " Check if this keep is outside context of any non-keep op
                let l:in_context = 0
                " Check behind
                let l:b = max([1, l:i - l:ctx])
                for l:j in range(l:b, l:i - 1)
                    let l:bl = getline(l:j)
                    if l:bl !~ '^keep\t' && l:bl !~ '^#' && l:bl != '' && l:bl !~ '^HUNK' && l:bl !~ '^HUNK_END' && l:bl !~ '^delay' && l:bl !~ '^EOF'
                        let l:in_context = 1
                        break
                    endif
                endfor
                " Check ahead
                if !l:in_context
                    let l:a = min([l:i + l:ctx, l:n])
                    for l:j in range(l:i + 1, l:a)
                        let l:al = getline(l:j)
                        if l:al !~ '^keep\t' && l:al !~ '^#' && l:al != '' && l:al !~ '^HUNK' && l:al !~ '^HUNK_END' && l:al !~ '^delay' && l:al !~ '^EOF'
                            let l:in_context = 1
                            break
                        endif
                    endfor
                endif
                if !l:in_context
                    let l:start = l:i
                endif
            endif
        endif
        let l:i += 1
    endwhile
    " Fold trailing keep run
    if l:start > 0
        let l:fold_end = l:n - l:ctx
        if l:fold_end > l:start
            execute l:start . ',' . l:fold_end . 'fold'
        endif
    endif
endfunction

" Apply folds after buffer is loaded
augroup AdSessionFolds
    autocmd! * <buffer>
    autocmd BufReadPost <buffer> call s:AdSetupFolds()
augroup END

" Call once now (for already-loaded buffer)
call s:AdSetupFolds()

" Custom fold text
function! s:AdFoldText()
    let l:line = getline(v:foldstart)
    let l:count = v:foldend - v:foldstart + 1
    return '+' . l:line . '... (' . l:count . ' keep ops)'
endfunction
setlocal foldtext=s:AdFoldText()

" --- Commands and mappings ---
" Mappings are global (not buffer-local) so they work in any window.

" Find and switch to the ops buffer
function! s:AdGoToOps()
    let l:buf = bufnr(s:ops_file)
    if l:buf == -1 | return 0 | endif
    for l:w in range(1, winnr('$'))
        if winbufnr(l:w) == l:buf
            execute l:w . 'wincmd w'
            return 1
        endif
    endfor
    execute 'buffer ' . l:buf
    return 1
endfunction

" Find and switch to the result buffer
function! s:AdGoToResult()
    let l:buf = bufnr(s:result_file)
    if l:buf == -1 | return 0 | endif
    for l:w in range(1, winnr('$'))
        if winbufnr(l:w) == l:buf
            execute l:w . 'wincmd w'
            return 1
        endif
    endfor
    return 0
endfunction

" F6 / <leader>r: Run animator snapshot
command! AdRun call s:AdRun()
nnoremap <F6> :call <SID>AdRun()<CR>
nnoremap <leader>r :call <SID>AdRun()<CR>

function! s:AdRun()
    let l:ops_buf = bufnr(s:ops_file)
    if l:ops_buf != -1 && getbufvar(l:ops_buf, '&modified')
        call s:AdGoToOps()
        write
    endif
    let l:cmd = s:animator . ' --no-display --speed 1000 --snapshot ' . s:result_file . ' ' . s:old_file . ' < ' . s:ops_file
    call system(l:cmd)
    if v:shell_error != 0
        echohl ErrorMsg | echo 'AdRun: animator failed (exit ' . v:shell_error . ')' | echohl None
        return
    endif
    let l:result_buf = bufnr(s:result_file)
    if l:result_buf != -1
        call s:AdGoToResult()
        setlocal modifiable noreadonly
        edit!
        setlocal nomodifiable readonly
        diffupdate
    endif
    call s:AdGoToOps()
    echo 'AdRun: done'
endfunction

" F5: Run animation in terminal split
command! AdAnimate call s:AdAnimate()
nnoremap <F5> :call <SID>AdAnimate()<CR>

function! s:AdAnimate()
    let l:ops_buf = bufnr(s:ops_file)
    if l:ops_buf != -1 && getbufvar(l:ops_buf, '&modified')
        call s:AdGoToOps()
        write
    endif
    call s:AdGoToOps()
    belowright split
    let l:cmd = s:animator . ' --speed 1000 ' . s:old_file . ' < ' . s:ops_file
    call term_start(l:cmd, {'curwin': 1})
endfunction

" <leader>c: Git commit
command! AdCommit call s:AdCommit()
nnoremap <leader>c :call <SID>AdCommit()<CR>

function! s:AdCommit()
    call system('git add -A && git commit -q -m "Session update"')
    if v:shell_error == 0
        echo 'AdCommit: committed'
    else
        echo 'AdCommit: nothing to commit'
    endif
endfunction

" <leader>q: Commit and quit
command! AdQuit call s:AdQuit()
nnoremap <leader>q :call <SID>AdQuit()<CR>

function! s:AdQuit()
    call system('git add -A && git commit -q -m "Session update"')
    qa!
endfunction

" <leader>Q: Quit without committing
command! AdQuitForce call s:AdQuitForce()
nnoremap <leader>Q :call <SID>AdQuitForce()<CR>

function! s:AdQuitForce()
    qa!
endfunction

" <leader>g: Regenerate ops (backup first)
let s:ad_auto_gen = 0

command! AdGen call s:AdGen()
nnoremap <leader>g :let s:ad_auto_gen=0<CR>:call <SID>AdGen()<CR>
nnoremap <leader>L :let s:ad_auto_gen=0<CR>:call <SID>AdGen()<CR>

function! s:AdGen()
    if !s:ad_auto_gen
        let l:confirm = input('Regenerate ops? Current will be backed up. (y/n): ')
        if l:confirm !=? 'y' | return | endif
    endif
    call system('cp ' . s:ops_file . ' ' . s:ops_file . '.bak')
    if s:layer_file != '' && filereadable(s:layer_file)
        let l:layers = s:ParseLayerFile(s:layer_file)
        let l:cmd = s:gen_ops . ' ' . s:old_file . ' ' . s:new_file
        for l:layer in l:layers
            let l:cmd .= ' --ad-layer=' . l:layer
        endfor
        if s:annotate
            let l:cmd .= ' --annotate'
        endif
        call system(l:cmd . ' > ' . s:ops_file)
    else
        let l:gen_cmd = s:gen_ops . ' ' . s:old_file . ' ' . s:new_file
        if s:annotate
            let l:gen_cmd .= ' --annotate'
        endif
        call system(l:gen_cmd . ' > ' . s:ops_file)
    endif
    let l:ops_buf = bufnr(s:ops_file)
    if l:ops_buf != -1
        call s:AdGoToOps()
        edit!
        call s:AdSetupFolds()
    endif
    echo 'AdGen: regenerated'
endfunction

" Parse layer group file (first non-comment line = active group)
function! s:ParseLayerFile(file)
    let l:lines = readfile(a:file)
    let l:active_group = ''
    let l:first_seen = 0
    let l:in_group = 0
    let l:found = 0
    let l:layers = []
    for l:line in l:lines
        if l:line =~ '^\s*#' | continue | endif
        let l:line = substitute(l:line, '^\s\+', '', '')
        let l:line = substitute(l:line, '\s\+$', '', '')
        if l:line == ''
            if l:in_group && l:found | break | endif
            let l:in_group = 0
            continue
        endif
        if !l:first_seen
            let l:first_seen = 1
            let l:active_group = l:line
            continue
        endif
        if !l:in_group
            let l:in_group = 1
            let l:found = (l:line == l:active_group) ? 1 : 0
            continue
        endif
        if l:found | call add(l:layers, l:line) | endif
    endfor
    return l:layers
endfunction

" Auto-regenerate ops when layers.txt is saved (no prompt)
if s:layer_file != ''
    execute 'autocmd BufWritePost ' . s:layer_file . ' let s:ad_auto_gen=1 | call s:AdGen() | let s:ad_auto_gen=0'
endif

" <leader>d: Reopen diff split
command! AdDiff call s:AdDiff()
nnoremap <leader>d :call <SID>AdDiff()<CR>

function! s:AdDiff()
    let l:result_buf = bufnr(s:result_file)
    if l:result_buf == -1
        call s:AdGoToOps()
        belowright split
        execute 'edit ' . s:result_file
    else
        call s:AdGoToResult()
    endif
    execute 'leftabove vertical diffsplit ' . s:new_file
endfunction

" <leader>h: Fold all hunks except current
command! AdFoldHunks call s:AdFoldHunks()
nnoremap <leader>h :call <SID>AdFoldHunks()<CR>

function! s:AdFoldHunks()
    if bufname('%') !=# s:ops_file | call s:AdGoToOps() | endif
    let l:cur_line = line('.')
    let l:in_hunk = 0
    let l:hunk_start = 0
    let l:i = 1
    while l:i <= line('$')
        let l:line = getline(l:i)
        if l:line =~ '^HUNK\t'
            let l:hunk_start = l:i
            let l:in_hunk = 1
        elseif l:line =~ '^HUNK_END'
            if l:in_hunk && (l:cur_line < l:hunk_start || l:cur_line > l:i)
                execute l:hunk_start . ',' . l:i . 'fold'
            endif
            let l:in_hunk = 0
        endif
        let l:i += 1
    endwhile
endfunction

" <leader>H: Unfold all
command! AdFoldHunksUnfold call s:AdFoldHunksUnfold()
nnoremap <leader>H :call <SID>AdFoldHunksUnfold()<CR>

function! s:AdFoldHunksUnfold()
    if bufname('%') !=# s:ops_file | call s:AdGoToOps() | endif
    normal! zR
endfunction

" <leader>k: Toggle keep-op folding
command! AdFoldKeeps call s:AdFoldKeeps()
nnoremap <leader>k :call <SID>AdFoldKeeps()<CR>

function! s:AdFoldKeeps()
    if bufname('%') !=# s:ops_file | call s:AdGoToOps() | endif
    let l:has_folds = 0
    for l:i in range(1, line('$'))
        if foldclosed(l:i) != -1
            let l:has_folds = 1
            break
        endif
    endfor
    if l:has_folds
        normal! zR
        echo 'Keep folding: OFF'
    else
        call s:AdSetupFolds()
        echo 'Keep folding: ON (context=' . s:fold_context . ')'
    endif
endfunction


" <leader>a: Toggle annotations (show/hide # old: / # new: comments)
command! AdToggleAnnotate call s:AdToggleAnnotate()
nnoremap <leader>a :call <SID>AdToggleAnnotate()<CR>

function! s:AdToggleAnnotate()
    let s:annotate = !s:annotate
    if s:annotate
        echo 'Annotations: ON (will be added on next AdGen)'
    else
        echo 'Annotations: OFF (will be removed on next AdGen)'
    endif
    " Regenerate ops with new setting
    let s:ad_auto_gen = 1
    call s:AdGen()
    let s:ad_auto_gen = 0
endfunction

" <leader>?: Show help
command! AdHelp call s:AdHelp()
nnoremap <leader>? :call <SID>AdHelp()<CR>

function! s:AdHelp()
    echo "ad_session shortcuts:"
    echo "  F5          Run animation in terminal split"
    echo "  F6          Run snapshot, update result.txt + diff"
    echo "  <leader>r   Same as F6"
    echo "  <leader>c   Git commit"
    echo "  <leader>q   Commit and quit"
    echo "  <leader>Q   Quit without commit"
    echo "  <leader>g   Regenerate ops from layers (backup to .bak)"
    echo "  <leader>L   Same as <leader>g"
    echo "  <leader>d   Reopen diff split"
    echo "  <leader>h   Fold all hunks except current"
    echo "  <leader>H   Unfold all"
    echo "  <leader>k   Toggle keep-op folding"
    echo "  <leader>a   Toggle annotations (# old: / # new:)"
    echo "  <leader>?   Show this help"
    if s:layer_file != ''
        echo ""
        echo "  Layer file: " . s:layer_file . " (first line = active group)"
        echo "  Saving layers.txt auto-regenerates ops (no prompt)"
    endif
endfunction

" --- Start with hunks folded if requested ---
if s:fold_hunks_start
    call s:AdFoldHunks()
endif

" --- Status message ---
echo "ad_session: " . s:session_dir
echo "  F5=animate  F6=snapshot  <leader>?=help"
