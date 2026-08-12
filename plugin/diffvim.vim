" diffvim plugin - Support running inside an existing vim via :Diffvim command.
"
" This plugin allows you to animate a diff from within an already-running vim
" session, without needing tmux or a bash launcher.
"
" Usage:
"   :Diffvim oldfile newfile          Animate diff between two files
"   :Diffvim oldfile newfile tabnew   Open in a new tab
"   :Diffvim oldfile newfile vsplit   Open in a vertical split
"
"   :DiffvimCommit [commit]           VimDiff current buffer against a commit
"                                     If no commit given, prompts for one.
"                                     Uses the current buffer's file path.
"
"   :DiffvimPick                      Pick a commit from a list with preview
"                                     Requires fzf (recommended) or forgit.
"                                     Shows commit list with diff preview,
"                                     then animates the selected commit's
"                                     changes to the current file.
"
" The animation uses vim's native timer_start() — no external orchestrator.
" All the same controls work: Space=pause, n=skip, b=back, q=quit, +/-=speed.
"
" To install: drop this file (and the autoload/ directory) in your vim runtimepath.
" Or with a package manager:
"   Plug 'nkh/gitanim', {'rtp': '.'}
"
" Configuration:
"   let g:diffvim = {'type_delay_ms': 50, 'scroll': 'zz', ...}
"   See :help diffvim-configuration or docs/CONFIGURATION.md
"
" Dependencies:
"   :DiffvimCommit — requires git
"   :DiffvimPick   — requires git + fzf (recommended) or forgit

if exists('g:loaded_diffvim_plugin')
    finish
endif
let g:loaded_diffvim_plugin = 1

" Configuration: allow g:diffvim in vimrc to set defaults
if !exists('g:diffvim')
    let g:diffvim = {}
endif

" Default config (merged with user's g:diffvim)
let s:default_config = {
    \ 'type_delay_ms':    get(g:diffvim, 'type_delay_ms',    50),
    \ 'delete_delay_ms':  get(g:diffvim, 'delete_delay_ms',  40),
    \ 'move_min_ms':      get(g:diffvim, 'move_min_ms',      250),
    \ 'move_max_ms':      get(g:diffvim, 'move_max_ms',      1600),
    \ 'move_ms_per_unit': get(g:diffvim, 'move_ms_per_unit', 6),
    \ 'hunk_pause_ms':    get(g:diffvim, 'hunk_pause_ms',    250),
    \ 'tick_ms':          get(g:diffvim, 'tick_ms',          16),
    \ 'word_pause_ms':    get(g:diffvim, 'word_pause_ms',    150),
    \ 'scroll':           get(g:diffvim, 'scroll',           'zz'),
    \ 'max_hunk_chars':   get(g:diffvim, 'max_hunk_chars',   0),
    \ 'max_word_chars':   get(g:diffvim, 'max_word_chars',   0),
    \ 'output_file':      get(g:diffvim, 'output_file',      ''),
    \ 'commit_picker':    get(g:diffvim, 'commit_picker',    'auto'),
    \ }

" Merge user config over defaults
let g:diffvim = extend(s:default_config, g:diffvim)

" ===========================================================================
" Commands
" ===========================================================================

" :Diffvim — animate diff between two files
command! -nargs=+ -complete=file Diffvim call s:DiffvimStart(<q-args>)

" :DiffvimCommit — VimDiff current buffer against a git commit
" Usage:
"   :DiffvimCommit              Prompt for commit hash
"   :DiffvimCommit HEAD         Use HEAD
"   :DiffvimCommit HEAD~3       Use HEAD~3
"   :DiffvimCommit abc123       Use specific commit
command! -nargs=? DiffvimCommit call s:DiffvimCommit(<q-args>)

" :DiffvimPick — pick a commit from a list with preview, then animate
" Requires fzf or forgit. Shows a commit browser with diff preview.
command! -nargs=0 DiffvimPick call s:DiffvimPick()

" ===========================================================================
" :Diffvim — animate diff between two files
" ===========================================================================

function! s:DiffvimStart(args) abort
    let l:parts = split(a:args, '\s\+')
    if len(l:parts) < 2
        echoerr 'Diffvim: requires oldfile and newfile'
        return
    endif
    let l:old_file = l:parts[0]
    let l:new_file = l:parts[1]
    let l:extra = len(l:parts) > 2 ? join(l:parts[2:], ' ') : ''

    if !filereadable(l:old_file)
        echoerr 'Diffvim: cannot read old file: ' . l:old_file
        return
    endif
    if !filereadable(l:new_file)
        echoerr 'Diffvim: cannot read new file: ' . l:new_file
        return
    endif

    let l:old_file = fnamemodify(l:old_file, ':p')
    let l:new_file = fnamemodify(l:new_file, ':p')

    if l:extra =~? 'tab\|tabnew'
        tabnew
    elseif l:extra =~? 'split\|new'
        new
    elseif l:extra =~? 'vsplit\|vnew'
        vnew
    endif

    execute 'edit ' . fnameescape(l:old_file)
    let g:diffvim_new_file = l:new_file

    call s:SourceEngine()
    call diffvim#engine#Start()
endfunction

" ===========================================================================
" :DiffvimCommit — VimDiff current buffer against a git commit
" ===========================================================================

function! s:DiffvimCommit(commit) abort
    " Get the current buffer's file path (relative to git root)
    let l:file = expand('%:p')
    if empty(l:file)
        echoerr 'DiffvimCommit: current buffer has no file path'
        return
    endif

    " Check we're in a git repo
    let l:git_root = systemlist('git rev-parse --show-toplevel 2>/dev/null')
    if empty(l:git_root) || v:shell_error != 0
        echoerr 'DiffvimCommit: not in a git repository'
        return
    endif
    let l:git_root = l:git_root[0]

    " Get the file path relative to git root
    let l:rel_file = fnamemodify(l:file, ':.')
    " Handle files outside git root
    if l:rel_file =~ '^\.\./'
        let l:rel_file = substitute(l:file, l:git_root . '/', '', '')
    endif

    " Prompt for commit if not given
    let l:commit = a:commit
    if empty(l:commit)
        " Show recent commits as suggestions
        let l:commits = systemlist(
            \ 'git log --oneline -20 -- "' . shellescape(l:rel_file) . '" 2>/dev/null')
        if empty(l:commits)
            echoerr 'DiffvimCommit: no commits found for ' . l:rel_file
            return
        endif

        " Display the commits
        echo "--- Recent commits for " . l:rel_file . " ---"
        for l:line in l:commits
            echo l:line
        endfor
        echo ""
        let l:commit = input('Enter commit (hash, HEAD, HEAD~3, etc): ')
        if empty(l:commit)
            echo "\nCancelled."
            return
        endif
    endif

    " Validate the commit exists
    let l:valid = system('git cat-file -t ' . shellescape(l:commit) . ' 2>/dev/null')
    if l:valid !~# 'commit'
        echoerr 'DiffvimCommit: invalid commit: ' . l:commit
        return
    endif

    " Extract the file content at that commit to a temp file
    let l:temp = tempname()
    let l:cmd = 'git show ' . shellescape(l:commit) . ':' . shellescape(l:rel_file)
    \          . ' > ' . shellescape(l:temp) . ' 2>/dev/null'
    call system(l:cmd)

    if v:shell_error != 0
        echoerr 'DiffvimCommit: file does not exist at commit ' . l:commit
        return
    endif

    " Save current buffer (so the working copy is up to date)
    if &modified
        let l:save = input('Buffer modified. Save before diff? (y/n): ')
        if l:save =~? '^y'
            write
        endif
    endif

    " The current buffer is the "new" version; the temp file is the "old"
    " Animate from old (commit) to new (working copy)
    let l:new_file = expand('%:p')

    " Reload the buffer to make sure it's fresh
    edit!

    " Run the diffvim animation
    let g:diffvim_new_file = l:new_file
    execute 'edit ' . fnameescape(l:temp)
    call s:SourceEngine()
    call diffvim#engine#Start()

    " Clean up temp file when done (set a flag for the engine to handle)
    let g:diffvim_temp_file = l:temp
    augroup diffvim_cleanup_temp
        autocmd!
        autocmd VimLeave * call delete(g:diffvim_temp_file)
    augroup END
endfunction

" ===========================================================================
" :DiffvimPick — pick a commit from a list with preview (fzf/forgit)
" ===========================================================================

function! s:DiffvimPick() abort
    " Get the current buffer's file path
    let l:file = expand('%:p')
    if empty(l:file)
        echoerr 'DiffvimPick: current buffer has no file path'
        return
    endif

    " Check we're in a git repo
    let l:git_check = system('git rev-parse --is-inside-work-tree 2>/dev/null')
    if l:git_check !~# 'true'
        echoerr 'DiffvimPick: not in a git repository'
        return
    endif

    let l:rel_file = fnellescape(fnamemodify(l:file, ':.'))

    " Determine which picker to use
    let l:picker = get(g:diffvim, 'commit_picker', 'auto')

    if l:picker ==# 'auto'
        if exists('*fzf#run')
            let l:picker = 'fzf'
        elseif executable('fzf')
            let l:picker = 'fzf-cli'
        elseif executable('forgit')
            let l:picker = 'forgit'
        else
            let l:picker = 'builtin'
        endif
    endif

    if l:picker ==# 'fzf'
        call s:PickWithFzfAPI(l:rel_file)
    elseif l:picker ==# 'fzf-cli'
        call s:PickWithFzfCLI(l:rel_file)
    elseif l:picker ==# 'forgit'
        call s:PickWithForgit(l:rel_file)
    else
        call s:PickWithBuiltin(l:rel_file)
    endif
endfunction

" --- fzf vim API (if fzf.vim is installed) ---

function! s:PickWithFzfAPI(rel_file) abort
    " Get commits that touched this file
    let l:cmd = 'git log --format="%H %h %s (%cr)" -- ' . shellescape(a:rel_file)
    let l:commits = systemlist(l:cmd . ' 2>/dev/null')

    if empty(l:commits)
        echoerr 'DiffvimPick: no commits found for ' . a:rel_file
        return
    endif

    " Build preview command: show the diff for the selected commit
    let l:preview_cmd = 'git show --stat --patch --color=always {1} -- ' . shellescape(a:rel_file)

    call fzf#run({
        \ 'source': l:commits,
        \ 'sink': function('s:OnCommitPicked', [a:rel_file]),
        \ 'options': '--reverse --expect=enter --prompt="Select commit> " '
        \          . '--preview="' . l:preview_cmd . '" '
        \          . '--preview-window=right:60%:wrap '
        \          . '--header="ENTER: animate diff from this commit to working copy"',
        \ 'down': '60%',
        \ })
endfunction

" --- fzf CLI (if fzf binary is available but not fzf.vim) ---

function! s:PickWithFzfCLI(rel_file) abort
    let l:cmd = 'git log --format="%H %h %s (%cr)" -- ' . shellescape(a:rel_file)
    let l:preview = 'git show --stat --patch --color=always {1} -- ' . shellescape(a:rel_file)

    " Use fzf with preview
    let l:fzf_cmd = l:cmd . ' | fzf --reverse --prompt="Select commit> "'
        \ . ' --preview="' . l:preview . '"'
        \ . ' --preview-window=right:60%:wrap'
        \ . ' --header="ENTER: animate diff from this commit to working copy"'
        \ . ' --expect=enter'

    " Run in a terminal buffer
    let l:output = systemlist(l:fzf_cmd . ' 2>/dev/null')

    if empty(l:output) || (len(l:output) == 1 && empty(l:output[0]))
        echo 'DiffvimPick: cancelled'
        return
    endif

    " fzf --expect=enter outputs: first line = key pressed, second line = selection
    if len(l:output) >= 2
        let l:selection = l:output[1]
    else
        let l:selection = l:output[0]
    endif

    if !empty(l:selection)
        let l:commit = split(l:selection)[0]  " First field is the full hash
        call s:AnimateFromCommit(a:rel_file, l:commit)
    endif
endfunction

" --- forgit (if forgit is installed) ---

function! s:PickWithForgit(rel_file) abort
    " forgit_show shows a commit with diff preview
    " We use it to let the user pick a commit, then animate
    echo 'DiffvimPick: launching forgit_show to pick a commit...'
    echo 'Select a commit, then run :DiffvimCommit <hash>'

    " forgit doesn't have a programmatic "pick and return" interface,
    " so we fall back to the builtin picker for the actual selection
    call s:PickWithBuiltin(a:rel_file)
endfunction

" --- Builtin picker (no dependencies) ---

function! s:PickWithBuiltin(rel_file) abort
    " Get commits with oneline format
    let l:cmd = 'git log --oneline -30 -- ' . shellescape(a:rel_file)
    let l:commits = systemlist(l:cmd . ' 2>/dev/null')

    if empty(l:commits)
        echoerr 'DiffvimPick: no commits found for ' . a:rel_file
        return
    endif

    " Build a menu
    let l:choices = []
    for l:line in l:commits
        call add(l:choices, l:line)
    endfor

    " Show a preview popup or use inputlist
    echo "--- Commits for " . a:rel_file . " ---"
    echo ""
    let l:i = 1
    for l:choice in l:choices
        echo printf('%2d. %s', l:i, l:choice)
        let l:i += 1
    endfor
    echo ""
    echo "  p. Preview a commit's diff"
    echo "  q. Cancel"
    echo ""

    let l:sel = input('Select commit number (or p to preview, q to cancel): ')
    if empty(l:sel) || l:sel ==# 'q'
        echo "\nCancelled."
        return
    endif

    if l:sel ==# 'p'
        " Preview mode: let user enter a commit hash to preview
        let l:preview_commit = input('Enter commit to preview (hash/HEAD~N): ')
        if !empty(l:preview_commit)
            echo "\n"
            " Show the diff for this commit
            let l:diff = systemlist(
                \ 'git show --stat --patch --color=always '
                \ . shellescape(l:preview_commit) . ' -- ' . shellescape(a:rel_file)
                \ . ' 2>/dev/null')
            " Open in a new buffer
            new
            setlocal buftype=nofile bufhidden=delete noswapfile
            call setline(1, l:diff)
            setfiletype diff
            echo "Press :q to close, then :DiffvimCommit " . l:preview_commit . " to animate"
        endif
        return
    endif

    " Parse selection
    let l:num = str2nr(l:sel)
    if l:num < 1 || l:num > len(l:choices)
        echoerr 'DiffvimPick: invalid selection'
        return
    endif

    " Extract commit hash from the selected line
    let l:line = l:choices[l:num - 1]
    let l:commit = split(l:line)[0]

    call s:AnimateFromCommit(a:rel_file, l:commit)
endfunction

" ===========================================================================
" Shared: animate from a selected commit
" ===========================================================================

function! s:OnCommitPicked(rel_file, selection) abort
    " Called by fzf#run's sink
    if empty(a:selection)
        return
    endif
    let l:commit = split(a:selection)[0]
    call s:AnimateFromCommit(a:rel_file, l:commit)
endfunction

function! s:AnimateFromCommit(rel_file, commit) abort
    " Validate the commit
    let l:valid = system('git cat-file -t ' . shellescape(a:commit) . ' 2>/dev/null')
    if l:valid !~# 'commit'
        echoerr 'DiffvimPick: invalid commit: ' . a:commit
        return
    endif

    " Extract file content at the commit to a temp file
    let l:temp = tempname()
    let l:cmd = 'git show ' . shellescape(a:commit) . ':' . shellescape(a:rel_file)
    \          . ' > ' . shellescape(l:temp) . ' 2>/dev/null'
    call system(l:cmd)

    if v:shell_error != 0
        echoerr 'DiffvimPick: file does not exist at commit ' . a:commit
        return
    endif

    " The current buffer (working copy) is the "new" version
    let l:new_file = expand('%:p')

    " Save if modified
    if &modified
        let l:save = input('Buffer modified. Save before diff? (y/n): ')
        if l:save =~? '^y'
            write
        endif
    endif

    " Reload to get fresh working copy
    edit!

    " Animate from old (commit version) to new (working copy)
    let g:diffvim_new_file = l:new_file
    execute 'edit ' . fnameescape(l:temp)

    " Show commit info
    let l:info = systemlist('git log --oneline -1 ' . shellescape(a:commit))
    if !empty(l:info)
        echo 'diffvim: animating from ' . a:commit . ' — ' . l:info[0]
    endif

    call s:SourceEngine()
    call diffvim#engine#Start()

    " Clean up temp file on exit
    let g:diffvim_temp_file = l:temp
    augroup diffvim_cleanup_temp
        autocmd!
        autocmd VimLeave * call delete(g:diffvim_temp_file)
    augroup END
endfunction

" ===========================================================================
" Helper: source the diffvim engine
" ===========================================================================

function! s:SourceEngine() abort
    let l:engine_path = findfile('autoload/diffvim/engine.vim', &runtimepath)
    if empty(l:engine_path)
        let l:engine_path = expand('<sfile>:h:h') . '/autoload/diffvim/engine.vim'
    endif

    if !filereadable(l:engine_path)
        echoerr 'Diffvim: cannot find engine file at ' . l:engine_path
        echoerr 'Make sure the autoload/diffvim/engine.vim file is installed.'
        return 0
    endif

    execute 'source ' . fnameescape(l:engine_path)
    return 1
endfunction

" ===========================================================================
" Help
" ===========================================================================

function! s:ShowHelp() abort
    echo 'diffvim commands:'
    echo '  :Diffvim oldfile newfile       Animate diff between two files'
    echo '  :DiffvimCommit [commit]        VimDiff current buffer against a commit'
    echo '  :DiffvimPick                   Pick a commit from a list with preview'
    echo ''
    echo 'Controls during animation:'
    echo '  Space=pause  n=skip  b=back  q=quit  +/-=speed  f=fold  ?=help'
endfunction

command! -nargs=0 DiffvimHelp call s:ShowHelp()
