" diffvim.vim — Vim plugin entry point for diffvim.
"
" This plugin provides the :DiffVim command which animates a code diff
" as if a human were typing it. It's a thin wrapper around the `diffvim`
" bash launcher.
"
" Installation:
"   1. Using a plugin manager (vim-plug, packer, etc.):
"      Plug 'nkh/gitanim'
"      " or
"      use 'nkh/gitanim'
"
"   2. Manual installation:
"      Copy plugin/diffvim.vim to ~/.vim/plugin/
"      Copy autoload/diffvim/ to ~/.vim/autoload/diffvim/
"      Build the C tools: make
"      Ensure diffvim is in your PATH (or set g:diffvim_binary)
"
" Configuration:
"   let g:diffvim_binary = '/path/to/diffvim'  " Override launcher path
"   let g:diffvim_defaults = {'speed': 1.0}   " Default options
"
" Usage:
"   :DiffVim old.py new.py
"   :DiffVim --speed 2 old.py new.py
"   :DiffVim --highlight inline old.py new.py

if exists('g:loaded_diffvim')
    finish
endif
let g:loaded_diffvim = 1

" Default configuration
let g:diffvim = extend({
    \ 'binary': '',
    \ 'defaults': {},
    \ }, get(g:, 'diffvim', {}))

" Find the diffvim launcher
function! s:find_diffvim() abort
    if !empty(g:diffvim.binary) && executable(g:diffvim.binary)
        return g:diffvim.binary
    endif
    if executable('diffvim')
        return 'diffvim'
    endif
    " Try common install locations
    for path in ['/usr/local/bin/diffvim',
                \ expand('~/.local/bin/diffvim'),
                \ expand('~/.vim/bundle/gitanim/diffvim'),
                \ expand('~/.config/nvim/plugged/gitanim/diffvim')]
        if executable(path)
            return path
        endif
    endfor
    return ''
endfunction

" :DiffVim command
command! -nargs=+ -complete=file DiffVim call diffvim#run(<f-args>)

" Main entry point
function! diffvim#run(...) abort
    let l:binary = s:find_diffvim()
    if empty(l:binary)
        echoerr 'diffvim: launcher not found. Install with: make install'
        echoerr '  Or set g:diffvim_binary to the full path'
        return
    endif

    " Build command line
    let l:args = join(map(copy(a:000), 'shellescape(v:val)'), ' ')

    " Add defaults from g:diffvim.defaults
    let l:default_args = ''
    for [l:key, l:val] in items(get(g:diffvim, 'defaults', {}))
        let l:default_args .= ' --' . l:key . ' ' . shellescape(string(l:val))
    endfor

    " Run in a terminal buffer (neovim) or ! command (vim)
    if has('terminal')
        " Neovim or vim with +terminal
        execute 'terminal ' . l:binary . ' --no-vimrc' . l:default_args . ' ' . l:args
    else
        " Fallback: run in a split
        execute '!' . l:binary . ' --no-vimrc' . l:default_args . ' ' . l:args
    endif
endfunction

" Helper: animate current file vs a target
function! diffvim#animate(target) abort
    let l:current = expand('%:p')
    call diffvim#run(l:current, a:target)
endfunction

" Helper: animate git diff for current file
function! diffvim#git(rev) abort
    let l:current = expand('%:p')
    let l:binary = s:find_diffvim()
    if empty(l:binary)
        echoerr 'diffvim: launcher not found'
        return
    endif
    let l:cmd = l:binary . ' --git-rev ' . a:rev . ' ' . shellescape(l:current)
    if has('terminal')
        execute 'terminal ' . l:cmd
    else
        execute '!' . l:cmd
    endif
endfunction

" Commands for convenience
command! -nargs=1 -complete=file DiffVimTo call diffvim#animate(<q-args>)
command! -nargs=1 DiffVimGit call diffvim#git(<q-args>)
