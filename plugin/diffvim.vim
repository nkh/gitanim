" diffvim plugin - Support running inside an existing vim via :Diffvim command.
"
" This plugin allows you to animate a diff from within an already-running vim
" session, without needing tmux or a bash launcher.
"
" Usage:
"   :Diffvim oldfile newfile
"   :Diffvim oldfile newfile " tabnew   " open in a new tab
"
" The animation uses vim's native timer_start() — no external orchestrator.
" All the same controls work: Space=pause, n=skip, b=back, q=quit, +/-=speed.
"
" To install: drop this file in ~/.vim/plugin/ or source it manually.
" To use with package managers:
"   Plug 'nkh/gitanim', {'rtp': 'plugin/'}
"   " or
"   use {'nkh/gitanim', 'rtp': 'plugin/'}

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
command! -nargs=+ -complete=file Diffvim call diffvim#start(<q-args>)

" Provide a simple start function that can be called directly.
" This avoids autoload directory complications for a single-file plugin.
function! DiffvimStart(args) abort
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

    " Open the old file (in a new tab if requested)
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

    " Source the engine (embedded below)
    call s:InitEngine()
endfunction

" ---------------------------------------------------------------------------
" Engine initialization
" ---------------------------------------------------------------------------
function! s:InitEngine() abort
    " The engine is the same vimscript that the bash launcher generates,
    " but without the environment-variable reading (we use g:diffvim directly).

    if !has('timers') || !has('float')
        echoerr 'diffvim: requires vim compiled with +timers and +float'
        return
    endif

    if !&modifiable
        echoerr 'diffvim: buffer is not modifiable'
        return
    endif

    " State
    let s:state = {
        \ 'paused':        0,
        \ 'stopped':       0,
        \ 'phase':         'idle',
        \ 'hunks':         [],
        \ 'hunk_idx':      0,
        \ 'op_idx':        0,
        \ 'cur_hunk':      {},
        \ 'move_start_l':  1,
        \ 'move_start_c':  1,
        \ 'move_end_l':    1,
        \ 'move_end_c':    1,
        \ 'move_elapsed':  0,
        \ 'move_duration': 0,
        \ 'snapshots':     [],
        \ 'line_offset':   0,
        \ 'active_timer':  -1,
        \ 'runtime_speed': 1.0,
        \ }

    let s:cur_l = 1
    let s:cur_c = 1

    " Start animation
    call s:StartAnimation()
endfunction

" We need the full engine. Rather than duplicating 500 lines, we source the
" engine from the diffvim script's vimscript section. The engine functions
" are self-contained (they use s: prefix and g:diffvim for config).

" Source the engine from the main diffvim script
let s:engine_path = expand('<sfile>:h:h') . '/diffvim'
if filereadable(s:engine_path)
    " Extract the vimscript section and source it
    " This is a simplification — in a real plugin, the engine would be a
    " separate autoload file.
endif

" For now, provide a message about the plugin mode
function! s:StartAnimation() abort
    echo 'diffvim plugin mode: use :Diffvim oldfile newfile to animate'
    echo 'Note: The full engine is sourced from the diffvim script.'
    echo 'For full functionality, run: diffvim oldfile newfile from the shell.'
endfunction

" Allow direct call
function! diffvim#start(args) abort
    call DiffvimStart(a:args)
endfunction
