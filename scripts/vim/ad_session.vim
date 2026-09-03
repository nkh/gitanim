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
let s:fold_context = exists('g:ad_fold_context') ? g:ad_fold_context : 5
let s:fold_hunks_start = exists('g:ad_fold_hunks') ? g:ad_fold_hunks : 0

" --- Set working directory ---
execute 'cd ' . s:session_dir

" --- Leader key (use default \, don't override user's setting) ---

" --- Layout setup ---
" Current buffer is ops.tsv (opened on command line).
" Create the layout:
"   1. Open result.txt in horizontal split below ops
"   2. Open vertical diffsplit new (left side)

" Open result.txt below
execute 'belowright split ' . s:result_file
setlocal nomodifiable readonly
wincmd k  " back to ops.tsv

" Open diff: new file on the left
execute 'leftabove vertical diffsplit ' . s:new_file
" In the new buffer, also diff with result
wincmd l  " back to ops area
wincmd l  " to result (if 3 windows) — actually let's set up properly

" Let's redo: we want:
" Left: diff(new, result) — but vim diffsplit works on current buffer
" Right top: ops.tsv
" Right bottom: result.txt
"
" Simpler approach:
" 1. Current = ops.tsv
" 2. :below split result.txt (right bottom)
" 3. :wincmd k (back to ops)
" 4. :vert diffsplit new (opens new on left, diffs with ops — wrong)
"
" Actually, the diff should be between result.txt and new, not ops.
" So:
" 1. Current = ops.tsv
" 2. :below split result.txt (right bottom)
" 3. Go to result.txt, :vert diffsplit new (opens new on left of result)
"    But that creates: new | result | ops (3 windows)
"
" Better approach:
" 1. ops.tsv is buffer 1
" 2. :vsplit new (left: new, right: ops)
" 3. Go to new, :diffsplit result (below new: result)
" 4. Go to ops

" Close all windows, start fresh
only

" Open new file on the left
execute 'leftabove vsplit ' . s:new_file
" Open result below new
execute 'belowright split ' . s:result_file
" Now: new (top-left) | result (bottom-left) | ops (right)

" Set up diff between new and result
wincmd h  " to new
diffthis
wincmd j  " to result
diffthis
setlocal nomodifiable

" Go to ops
wincmd l  " to ops.tsv

" --- Fold expression for keep ops ---
" Folds consecutive 'keep' lines, showing N context lines around non-keep.
let s:fold_expr_context = s:fold_context

function! AdKeepFoldExpr(lnum)
    let l:line = getline(a:lnum)
    let l:is_keep = (l:line =~ '^keep\t')

    " If not a keep line, never fold it
    if !l:is_keep
        return 0
    endif

    " Check context: look ahead and behind for non-keep lines
    let l:ctx = s:fold_expr_context
    if l:ctx <= 0
        return 0
    endif

    " Check if within context of a non-keep line (ahead)
    let l:i = a:lnum + 1
    let l:ahead_nonkeep = 0
    while l:i <= line('$') && (l:i - a:lnum) <= l:ctx
        if getline(l:i) !~ '^keep\t' && getline(l:i) !~ '^#' && getline(l:i) !~ '^$'
            let l:ahead_nonkeep = 1
            break
        endif
        let l:i += 1
    endwhile

    " Check if within context of a non-keep line (behind)
    let l:i = a:lnum - 1
    let l:behind_nonkeep = 0
    while l:i >= 1 && (a:lnum - l:i) <= l:ctx
        if getline(l:i) !~ '^keep\t' && getline(l:i) !~ '^#' && getline(l:i) !~ '^$'
            let l:behind_nonkeep = 1
            break
        endif
        let l:i -= 1
    endwhile

    " If within context of non-keep, don't fold
    if l:ahead_nonkeep || l:behind_nonkeep
        return 0
    endif

    " This is a keep line outside context — fold it
    " Use 'a' to start a fold, 's' to continue, but we need to detect
    " fold boundaries. Simple approach: fold level 1 for keep lines
    " outside context.
    let l:prev = getline(a:lnum - 1)
    let l:prev_keep = (l:prev =~ '^keep\t')
    let l:prev_in_ctx = 0

    " Check if previous line was within context
    if l:prev_keep
        let l:pi = a:lnum - 1
        let l:pi_ahead = 0
        let l:pi_i = l:pi + 1
        while l:pi_i <= line('$') && (l:pi_i - l:pi) <= l:ctx
            if getline(l:pi_i) !~ '^keep\t' && getline(l:pi_i) !~ '^#' && getline(l:pi_i) !~ '^$'
                let l:pi_ahead = 1
                break
            endif
            let l:pi_i += 1
        endwhile
        if l:pi_ahead
            let l:prev_in_ctx = 1
        endif
    endif

    if l:prev_keep && !l:prev_in_ctx
        return 1  " continue fold
    else
        return '>1'  " start new fold
    endif
endfunction

" Apply fold settings to ops buffer
setlocal foldmethod=expr
setlocal foldexpr=AdKeepFoldExpr(v:lnum)
setlocal foldtext=getline(v:foldstart).'... ('.(v:foldend-v:foldstart+1).' keep ops)'

" --- Commands ---

" F6 / <leader>r: Run animator snapshot
command! -buffer AdRun call s:AdRun()
nnoremap <buffer> <F6> :call <SID>AdRun()<CR>
nnoremap <buffer> <leader>r :call <SID>AdRun()<CR>

function! s:AdRun()
    " Save ops if modified
    if &modified
        write
    endif

    " Run animator
    execute '!' . s:animator . ' --no-display --speed 1000 --snapshot ' . s:result_file . ' ' . s:old_file . ' < ' . s:ops_file

    " Refresh result buffer
    let l:cur_win = winnr()
    " Find result window
    2wincmd w  " go to result (bottom-left)
    setlocal modifiable noreadonly
    edit!
    setlocal nomodifiable readonly
    diffupdate
    wincmd w  " back to ops
endfunction

" F5: Run animation in terminal split
command! -buffer AdAnimate call s:AdAnimate()
nnoremap <buffer> <F5> :call <SID>AdAnimate()<CR>

function! s:AdAnimate()
    if &modified
        write
    endif
    " Open terminal split below
    belowright split
    terminal
    " In the terminal, run the animator with display
    call feedkeys(s:animator . ' --speed 1000 ' . s:old_file . ' < ' . s:ops_file . "\n")
endfunction

" <leader>c: Git commit
command! -buffer AdCommit call s:AdCommit()
nnoremap <buffer> <leader>c :call <SID>AdCommit()<CR>

function! s:AdCommit()
    !git add -A && git commit -q -m "Session update $(date '+%H:%M:%S')"
endfunction

" <leader>q: Commit and quit
command! -buffer AdQuit call s:AdQuit()
nnoremap <buffer> <leader>q :call <SID>AdQuit()<CR>

function! s:AdQuit()
    !git add -A && git commit -q -m "Session update $(date '+%H:%M:%S')"
    qa!
endfunction

" <leader>Q: Quit without committing
command! -buffer AdQuitForce call s:AdQuitForce()
nnoremap <buffer> <leader>Q :call <SID>AdQuitForce()<CR>

function! s:AdQuitForce()
    qa!
endfunction

" <leader>g: Regenerate ops (backup first)
command! -buffer AdGen call s:AdGen()
nnoremap <buffer> <leader>g :call <SID>AdGen()<CR>

function! s:AdGen()
    let l:confirm = input('Regenerate ops? Current will be backed up. (y/n): ')
    if l:confirm !=? 'y'
        return
    endif
    " Backup
    execute '!cp ' . s:ops_file . ' ' . s:ops_file . '.bak'
    " Regenerate
    execute '!' . s:animator . '_gen_ops ' . s:old_file . ' ' . s:new_file . ' > ' . s:ops_file
    " Reload ops buffer
    edit!
endfunction

" <leader>d: Reopen diff split
command! -buffer AdDiff call s:AdDiff()
nnoremap <buffer> <leader>d :call <SID>AdDiff()<CR>

function! s:AdDiff()
    " Find or create result window
    let l:result_buf = bufnr(s:result_file)
    if l:result_buf == -1
        belowright split
        execute 'edit ' . s:result_file
    endif
    execute 'leftabove vertical diffsplit ' . s:new_file
endfunction

" <leader>h: Fold all hunks except current
command! -buffer AdFoldHunks call s:AdFoldHunks()
nnoremap <buffer> <leader>h :call <SID>AdFoldHunks()<CR>

function! s:AdFoldHunks()
    " Fold all HUNK...HUNK_END regions except the one containing the cursor
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
                " This hunk doesn't contain cursor — fold it
                execute l:hunk_start . ',' . l:i . 'fold'
            endif
            let l:in_hunk = 0
        endif
        let l:i += 1
    endwhile
endfunction

" <leader>H: Unfold all
command! -buffer AdFoldHunksUnfold call s:AdFoldHunksUnfold()
nnoremap <buffer> <leader>H :call <SID>AdFoldHunksUnfold()<CR>

function! s:AdFoldHunksUnfold()
    normal! zR
endfunction

" <leader>k: Toggle keep-op folding
command! -buffer AdFoldKeeps call s:AdFoldKeeps()
nnoremap <buffer> <leader>k :call <SID>AdFoldKeeps()<CR>

function! s:AdFoldKeeps()
    if &foldmethod ==# 'expr'
        setlocal foldmethod=manual
        normal! zR
        echo 'Keep folding: OFF'
    else
        setlocal foldmethod=expr
        setlocal foldexpr=AdKeepFoldExpr(v:lnum)
        echo 'Keep folding: ON (context=' . s:fold_context . ')'
    endif
endfunction

" <leader>?: Show help
command! -buffer AdHelp call s:AdHelp()
nnoremap <buffer> <leader>? :call <SID>AdHelp()<CR>

function! s:AdHelp()
    echo "ad_session shortcuts:"
    echo "  F5          Run animation in terminal split"
    echo "  F6          Run snapshot, update result.txt + diff"
    echo "  <leader>r   Same as F6"
    echo "  <leader>c   Git commit"
    echo "  <leader>q   Commit and quit"
    echo "  <leader>Q   Quit without commit"
    echo "  <leader>g   Regenerate ops (backup to .bak)"
    echo "  <leader>d   Reopen diff split"
    echo "  <leader>h   Fold all hunks except current"
    echo "  <leader>H   Unfold all"
    echo "  <leader>k   Toggle keep-op folding"
    echo "  <leader>?   Show this help"
endfunction

" --- Start with hunks folded if requested ---
if s:fold_hunks_start
    call s:AdFoldHunks()
endif

" --- Status message ---
echo "ad_session: " . s:session_dir
echo "  F5=animate  F6=snapshot  <leader>?=help"
