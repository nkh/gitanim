" diffvim plugin - Support running inside an existing vim via :Diffvim command.
"
" This plugin allows you to animate a diff from within an already-running vim
" session, without needing tmux or a bash launcher.
"
" Usage:
"   :Diffvim oldfile newfile
"   :Diffvim oldfile newfile tabnew     " open in a new tab
"   :Diffvim oldfile newfile vsplit     " open in a vertical split
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
    \ 'type_delay_ms':    get(g:diffvim, 'type_delay_ms',    35),
    \ 'delete_delay_ms':  get(g:diffvim, 'delete_delay_ms',  25),
    \ 'move_min_ms':      get(g:diffvim, 'move_min_ms',      200),
    \ 'move_max_ms':      get(g:diffvim, 'move_max_ms',      1400),
    \ 'move_ms_per_unit': get(g:diffvim, 'move_ms_per_unit', 6),
    \ 'hunk_pause_ms':    get(g:diffvim, 'hunk_pause_ms',    180),
    \ 'tick_ms':          get(g:diffvim, 'tick_ms',          16),
    \ 'word_pause_ms':    get(g:diffvim, 'word_pause_ms',    150),
    \ 'scroll':           get(g:diffvim, 'scroll',           'none'),
    \ 'max_hunk_chars':   get(g:diffvim, 'max_hunk_chars',   0),
    \ 'max_word_chars':   get(g:diffvim, 'max_word_chars',   0),
    \ 'output_file':      get(g:diffvim, 'output_file',      ''),
    \ }

" Merge user config over defaults
let g:diffvim = extend(s:default_config, g:diffvim)

" ---------------------------------------------------------------------------
" :Diffvim command
" ---------------------------------------------------------------------------
command! -nargs=+ -complete=file Diffvim call s:DiffvimStart(<q-args>)

function! s:DiffvimStart(args) abort
    " Parse args: "oldfile newfile" or "oldfile newfile tabnew"
    let l:parts = split(a:args, '\s\+')
    if len(l:parts) < 2
        echoerr 'Diffvim: requires oldfile and newfile'
        return
    endif
    let l:old_file = l:parts[0]
    let l:new_file = l:parts[1]
    let l:extra = len(l:parts) > 2 ? join(l:parts[2:], ' ') : ''

    " Validate files
    if !filereadable(l:old_file)
        echoerr 'Diffvim: cannot read old file: ' . l:old_file
        return
    endif
    if !filereadable(l:new_file)
        echoerr 'Diffvim: cannot read new file: ' . l:new_file
        return
    endif

    " Resolve absolute paths
    let l:old_file = fnamemodify(l:old_file, ':p')
    let l:new_file = fnamemodify(l:new_file, ':p')

    " Open the old file (in a new tab/split if requested)
    if l:extra =~? 'tab\|tabnew'
        tabnew
    elseif l:extra =~? 'split\|new'
        new
    elseif l:extra =~? 'vsplit\|vnew'
        vnew
    endif

    execute 'edit ' . fnameescape(l:old_file)

    " Set up the diffvim engine
    let g:diffvim_new_file = l:new_file

    " Source the engine — it defines s: functions and starts the animation
    let l:engine_path = findfile('autoload/diffvim/engine.vim', &runtimepath)
    if empty(l:engine_path)
        " Try relative to this plugin file
        let l:engine_path = expand('<sfile>:h:h') . '/autoload/diffvim/engine.vim'
    endif

    if !filereadable(l:engine_path)
        echoerr 'Diffvim: cannot find engine file at ' . l:engine_path
        echoerr 'Make sure the autoload/diffvim/engine.vim file is installed.'
        return
    endif

    " Source the engine — it uses s: prefix (script-local) so each source
    " creates a fresh namespace. The engine's StartAnimation will run.
    execute 'source ' . fnameescape(l:engine_path)

    " The engine defines s:StartAnimation and calls it via autocmd VimEnter.
    " But since we're already past VimEnter, we need to call it directly.
    " The engine defines diffvim#engine#Start() as a public wrapper.
    call diffvim#engine#Start()
endfunction
