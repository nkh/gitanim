" diffvim.vim - animation engine, sourced by the diffvim bash launcher.
" Expects g:diffvim_new_file to be set to the absolute path of the new file.

" Ensure nocompatible mode — required for backslash line continuation.
" The system vimrc (/etc/vim/vimrc) may set 'compatible' which breaks it.
set nocp

if !exists('g:diffvim_new_file')
    echoerr 'diffvim: g:diffvim_new_file not set'
    finish
endif

if !has('timers') || !has('float')
    echoerr 'diffvim: requires vim compiled with +timers and +float'
    finish
endif

if !filereadable(g:diffvim_new_file)
    echoerr 'diffvim: cannot read new file: ' . g:diffvim_new_file
    finish
endif

if !&modifiable
    echoerr 'diffvim: buffer is not modifiable'
    finish
endif

" --- Configuration ---------------------------------------------------------
" Tunables. Priority (highest wins):
"   1. g:diffvim dictionary in vimrc (set before launching diffvim)
"   2. DIFFVIM_* environment variables
"   3. Built-in defaults
"
" In Vimscript, $NAME accesses environment variables.  empty($NAME) is true
" when the var is unset or empty.  str2nr() converts the string to a number.
let g:diffvim = extend({
    \ 'type_delay_ms':      !empty($DIFFVIM_TYPE_DELAY_MS)    ? str2nr($DIFFVIM_TYPE_DELAY_MS)    : 50,
    \ 'delete_delay_ms':    !empty($DIFFVIM_DELETE_DELAY_MS)  ? str2nr($DIFFVIM_DELETE_DELAY_MS)  : 40,
    \ 'move_min_ms':        !empty($DIFFVIM_MOVE_MIN_MS)      ? str2nr($DIFFVIM_MOVE_MIN_MS)      : 250,
    \ 'move_max_ms':        !empty($DIFFVIM_MOVE_MAX_MS)      ? str2nr($DIFFVIM_MOVE_MAX_MS)      : 1600,
    \ 'move_ms_per_unit':   !empty($DIFFVIM_MOVE_MS_PER_UNIT) ? str2nr($DIFFVIM_MOVE_MS_PER_UNIT) : 6,
    \ 'hunk_pause_ms':      !empty($DIFFVIM_HUNK_PAUSE_MS)    ? str2nr($DIFFVIM_HUNK_PAUSE_MS)    : 250,
    \ 'tick_ms':            !empty($DIFFVIM_TICK_MS)          ? str2nr($DIFFVIM_TICK_MS)          : 16,
    \ 'word_pause_ms':      !empty($DIFFVIM_WORD_PAUSE_MS)    ? str2nr($DIFFVIM_WORD_PAUSE_MS)    : 150,
    \ 'scroll':             !empty($DIFFVIM_SCROLL)           ? $DIFFVIM_SCROLL                   : 'zz',
    \ 'max_hunk_chars':     !empty($DIFFVIM_MAX_HUNK_CHARS)   ? str2nr($DIFFVIM_MAX_HUNK_CHARS)   : 0,
    \ 'max_word_chars':     !empty($DIFFVIM_MAX_WORD_CHARS)   ? str2nr($DIFFVIM_MAX_WORD_CHARS)   : 0,
    \ 'output_file':        !empty($DIFFVIM_OUTPUT)           ? $DIFFVIM_OUTPUT                   : '',
    \ 'word_diff':          !empty($DIFFVIM_WORD_DIFF)        ? 1 : 0,
    \ 'step_mode':          !empty($DIFFVIM_STEP_MODE)        ? 1 : 0,
    \ 'adaptive_timing':    !empty($DIFFVIM_ADAPTIVE_TIMING)  ? 1 : 0,
    \ 'sign_column':        !empty($DIFFVIM_SIGN_COLUMN)      ? 1 : 0,
    \ 'git_blame':          !empty($DIFFVIM_GIT_BLAME)        ? 1 : 0,
    \ 'highlight_hunk':     !empty($DIFFVIM_HIGHLIGHT_HUNK)   ? 1 : 0,
    \ 'highlight_color':    !empty($DIFFVIM_HIGHLIGHT_COLOR)  ? $DIFFVIM_HIGHLIGHT_COLOR          : 'DiffChange',
    \ 'highlight_duration': !empty($DIFFVIM_HIGHLIGHT_DURATION_MS) ? str2nr($DIFFVIM_HIGHLIGHT_DURATION_MS) : 1000,
    \ 'highlight_min_chars':!empty($DIFFVIM_HIGHLIGHT_MIN_CHARS)   ? str2nr($DIFFVIM_HIGHLIGHT_MIN_CHARS)  : 10,
    \ 'max_line_len':       !empty($DIFFVIM_MAX_LINE_LEN)     ? str2nr($DIFFVIM_MAX_LINE_LEN)    : 0,
    \ 'fold_unchanged':     !empty($DIFFVIM_FOLD_UNCHANGED)   ? 1 : 0,
    \ }, get(g:, 'diffvim', {}))
"   type_delay_ms      - delay between typed characters
"   delete_delay_ms    - delay between deleted characters
"   move_min_ms        - minimum cursor-glide duration
"   move_max_ms        - maximum cursor-glide duration
"   move_ms_per_unit   - ms per unit of distance, capped by max
"   hunk_pause_ms      - pause between hunks
"   tick_ms            - animation frame interval (~60fps)

" --- State -----------------------------------------------------------------

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

" --- Diff: LCS at line level and char level -------------------------------

" Line-level LCS diff. a:a, a:b are lists of strings.
" Returns a list of ops in forward order:
"   ['keep',   old_idx, new_idx]
"   ['delete', old_idx]
"   ['insert', new_idx]
function! s:LineDiff(a, b) abort
    let l:na = len(a:a)
    let l:nb = len(a:b)
    let l:dp = []
    let l:i = 0
    while l:i <= l:na
        call add(l:dp, repeat([0], l:nb + 1))
        let l:i += 1
    endwhile
    let l:i = 1
    while l:i <= l:na
        let l:j = 1
        while l:j <= l:nb
            if a:a[l:i - 1] ==# a:b[l:j - 1]
                let l:dp[l:i][l:j] = l:dp[l:i - 1][l:j - 1] + 1
            else
                let l:dp[l:i][l:j] = max([l:dp[l:i - 1][l:j], l:dp[l:i][l:j - 1]])
            endif
            let l:j += 1
        endwhile
        let l:i += 1
    endwhile
    let l:ops = []
    let l:i = l:na
    let l:j = l:nb
    while l:i > 0 || l:j > 0
        if l:i > 0 && l:j > 0 && a:a[l:i - 1] ==# a:b[l:j - 1]
            call add(l:ops, ['keep', l:i - 1, l:j - 1])
            let l:i -= 1
            let l:j -= 1
        elseif l:j > 0 && (l:i == 0 || l:dp[l:i][l:j - 1] >= l:dp[l:i - 1][l:j])
            call add(l:ops, ['insert', l:j - 1])
            let l:j -= 1
        else
            call add(l:ops, ['delete', l:i - 1])
            let l:i -= 1
        endif
    endwhile
    return reverse(l:ops)
endfunction

" Character-level LCS diff between two strings (treating \n as a regular char).
" Returns a list of ops in forward order:
"   ['keep',   ch]
"   ['delete', ch]
"   ['insert', ch]
function! s:CharDiff(a, b) abort
    let l:a = split(a:a, '\zs')
    let l:b = split(a:b, '\zs')
    let l:na = len(l:a)
    let l:nb = len(l:b)
    let l:dp = []
    let l:i = 0
    while l:i <= l:na
        call add(l:dp, repeat([0], l:nb + 1))
        let l:i += 1
    endwhile
    let l:i = 1
    while l:i <= l:na
        let l:j = 1
        while l:j <= l:nb
            if l:a[l:i - 1] ==# l:b[l:j - 1]
                let l:dp[l:i][l:j] = l:dp[l:i - 1][l:j - 1] + 1
            else
                let l:dp[l:i][l:j] = max([l:dp[l:i - 1][l:j], l:dp[l:i][l:j - 1]])
            endif
            let l:j += 1
        endwhile
        let l:i += 1
    endwhile
    let l:ops = []
    let l:i = l:na
    let l:j = l:nb
    while l:i > 0 || l:j > 0
        if l:i > 0 && l:j > 0 && l:a[l:i - 1] ==# l:b[l:j - 1]
            call add(l:ops, ['keep', l:a[l:i - 1]])
            let l:i -= 1
            let l:j -= 1
        elseif l:j > 0 && (l:i == 0 || l:dp[l:i][l:j - 1] >= l:dp[l:i - 1][l:j])
            call add(l:ops, ['insert', l:b[l:j - 1]])
            let l:j -= 1
        else
            call add(l:ops, ['delete', l:a[l:i - 1]])
            let l:i -= 1
        endif
    endwhile
    return reverse(l:ops)
endfunction

" Group line-level ops into hunks, then compute char-level diff per hunk.
function! s:BuildHunks() abort
    let l:old_lines = getline(1, '$')
    if empty(l:old_lines)
        let l:old_lines = ['']
    endif
    let l:new_lines = readfile(g:diffvim_new_file)
    if empty(l:new_lines)
        let l:new_lines = ['']
    endif

    let l:line_ops = s:LineDiff(l:old_lines, l:new_lines)

    let l:hunks = []
    let l:cur_ops = []
    let l:cur_target = 1
    let l:old_pos = 1   " 1-indexed position in OLD file we're currently at

    for l:op in l:line_ops
        if l:op[0] ==# 'keep'
            if !empty(l:cur_ops)
                call add(l:hunks, {'target_line_old': l:cur_target, 'ops': l:cur_ops})
                let l:cur_ops = []
            endif
            let l:old_pos = l:op[1] + 2   " past the kept line (0-idx + 2 = next 1-idx line)
        elseif l:op[0] ==# 'delete'
            if empty(l:cur_ops)
                let l:cur_target = l:old_pos
            endif
            call add(l:cur_ops, l:op)
            let l:old_pos = l:op[1] + 2
        elseif l:op[0] ==# 'insert'
            if empty(l:cur_ops)
                let l:cur_target = l:old_pos
            endif
            call add(l:cur_ops, l:op)
            " inserts don't advance OLD position
        endif
    endfor
    if !empty(l:cur_ops)
        call add(l:hunks, {'target_line_old': l:cur_target, 'ops': l:cur_ops})
    endif

    " For each hunk, compute char-level diff between deleted and inserted text.
    " Pure insertions need a trailing '\n' (or leading, for end-of-file) so the
    " new content becomes separate line(s) rather than getting merged into the
    " adjacent line.  Hunks with deletions don't need this — the line structure
    " around the deleted lines already provides the separator.
    let l:old_line_count = len(l:old_lines)
    for l:h in l:hunks
        let l:deleted = []
        let l:inserted = []
        for l:op in l:h.ops
            if l:op[0] ==# 'delete'
                call add(l:deleted, l:old_lines[l:op[1]])
            else
                call add(l:inserted, l:new_lines[l:op[1]])
            endif
        endfor

        if empty(l:deleted)
            " Pure insertion.
            let l:h.old_text = ""
            if l:h.target_line_old > l:old_line_count
                " Insertion past the last old line: prepend '\n' so the new
                " content starts on a fresh line after the current last line.
                let l:h.new_text = "\n" . join(l:inserted, "\n")
                let l:h.is_end_insert = 1
            else
                " Insertion at start/middle: append '\n' so the new content
                " ends with a line break, pushing the existing line down.
                let l:h.new_text = join(l:inserted, "\n") . "\n"
                let l:h.is_end_insert = 0
            endif
            let l:h.is_end_delete = 0
        elseif empty(l:inserted)
            " Pure deletion.  Need to also remove a '\n' so the line vanishes
            " entirely (otherwise we'd leave an empty line behind).
            let l:last_deleted_idx = -1
            for l:op in l:h.ops
                if l:op[0] ==# 'delete' && l:op[1] > l:last_deleted_idx
                    let l:last_deleted_idx = l:op[1]
                endif
            endfor
            if l:last_deleted_idx >= 0 && l:last_deleted_idx == l:old_line_count - 1
                " Deleted block includes the last old line: prepend '\n' and
                " position cursor at end of the previous line so the join
                " collapses the trailing empty line.
                let l:h.old_text = "\n" . join(l:deleted, "\n")
                let l:h.is_end_delete = 1
            else
                " Middle deletion: append '\n' to also eat the line break
                " after the deleted block.
                let l:h.old_text = join(l:deleted, "\n") . "\n"
                let l:h.is_end_delete = 0
            endif
            let l:h.new_text = ""
            let l:h.is_end_insert = 0
        else
            let l:h.old_text = join(l:deleted, "\n")
            let l:h.new_text = join(l:inserted, "\n")
            let l:h.is_end_insert = 0
            let l:h.is_end_delete = 0
        endif

        let l:h.char_ops = s:CharDiff(l:h.old_text, l:h.new_text)
        let l:h.deleted_count = len(l:deleted)
        let l:h.inserted_count = len(l:inserted)
    endfor

    return l:hunks
endfunction

" --- Easing and movement ---------------------------------------------------

" Ease in-out cubic.
function! s:EaseInOut(t) abort
    if a:t < 0.5
        return 4.0 * a:t * a:t * a:t
    else
        let l:f = -2.0 * a:t + 2.0
        return 1.0 - (l:f * l:f * l:f) / 2.0
    endif
endfunction

function! s:ComputeMoveDuration(start_l, start_c, end_l, end_c) abort
    let l:dl = abs(a:end_l - a:start_l)
    let l:dc = abs(a:end_c - a:start_c)
    let l:dist = l:dl * 80 + l:dc   " weight lines much more than columns
    let l:dur = l:dist * g:diffvim.move_ms_per_unit
    if l:dur < g:diffvim.move_min_ms
        let l:dur = g:diffvim.move_min_ms
    endif
    if l:dur > g:diffvim.move_max_ms
        let l:dur = g:diffvim.move_max_ms
    endif
    return l:dur
endfunction

" --- Buffer primitives (no insert mode needed, no user input disruption) ---
"
" We track the logical cursor position in s:cur_l / s:cur_c because vim's
" real cursor (in normal mode) cannot sit past the last char of a line
" (col is clamped to len(line)).  Several diff operations need to advance
" the cursor to col len+1 (e.g. after keeping the last char of a line, the
" next insert must go at the end).  Tracking position ourselves lets us
" reason about that "past-end" state while the visible cursor sits on the
" last char.

let s:cur_l = 1
let s:cur_c = 1

" Move vim's visible cursor to the tracked logical position (clamped).
function! s:PlaceCursor() abort
    let l:ll = s:cur_l
    let l:lc = s:cur_c
    if l:ll < 1 | let l:ll = 1 | endif
    if l:ll > line('$') | let l:ll = line('$') | endif
    let l:line = getline(l:ll)
    let l:len = len(l:line)
    let l:actual = l:lc
    if l:actual > l:len + 1 | let l:actual = l:len + 1 | endif
    if l:actual < 1 | let l:actual = 1 | endif
    call cursor(l:ll, l:actual)
    " Scroll cursor to center/top/bottom if configured
    if g:diffvim.scroll ==# 'zz'
        normal! zz
    elseif g:diffvim.scroll ==# 'zt'
        normal! zt
    elseif g:diffvim.scroll ==# 'zb'
        normal! zb
    endif
endfunction

function! s:InsertCharAtCursor(ch) abort
    let l:l = s:cur_l
    let l:c = s:cur_c
    let l:line = getline(l:l)
    let l:before = strpart(l:line, 0, l:c - 1)
    let l:after  = strpart(l:line, l:c - 1)
    if a:ch ==# "\n"
        call setline(l:l, l:before)
        call append(l:l, l:after)
        let s:cur_l = l:l + 1
        let s:cur_c = 1
    else
        call setline(l:l, l:before . a:ch . l:after)
        let s:cur_c = l:c + strlen(a:ch)
    endif
    call s:PlaceCursor()
endfunction

function! s:DeleteCharAtCursor() abort
    let l:l = s:cur_l
    let l:c = s:cur_c
    let l:line = getline(l:l)
    let l:line_len = len(l:line)
    if l:c > l:line_len
        " past end -> join with next line (delete the newline)
        if l:l < line('$')
            let l:next = getline(l:l + 1)
            call setline(l:l, l:line . l:next)
            execute (l:l + 1) . 'delete _'
            " logical cursor stays at same col on the joined line
        endif
    else
        let l:before = strpart(l:line, 0, l:c - 1)
        let l:after  = strpart(l:line, l:c)
        call setline(l:l, l:before . l:after)
        " logical cursor stays at same col
    endif
    call s:PlaceCursor()
endfunction

" Advance logical cursor for a 'keep' char (no buffer change).
function! s:AdvanceForKeepChar(ch) abort
    if a:ch ==# "\n"
        let s:cur_l += 1
        if s:cur_l > line('$')
            let s:cur_l = line('$')
        endif
        let s:cur_c = 1
    else
        let s:cur_c += strlen(a:ch)
    endif
    call s:PlaceCursor()
endfunction

" --- Snapshots for the 'back' control -------------------------------------

function! s:SaveSnapshot() abort
    call add(s:state.snapshots, {
        \ 'lines':       getline(1, '$'),
        \ 'cursor_l':    line('.'),
        \ 'cursor_c':    col('.'),
        \ 'hunk_idx':    s:state.hunk_idx,
        \ 'line_offset': s:state.line_offset,
        \ })
endfunction

function! s:RestoreSnapshot(idx) abort
    if a:idx < 0 || a:idx >= len(s:state.snapshots)
        return
    endif
    let l:snap = s:state.snapshots[a:idx]
    " Clear buffer (always leaves one empty line).
    silent %delete _
    if !empty(l:snap.lines)
        call setline(1, l:snap.lines)
    endif
    call cursor(l:snap.cursor_l, l:snap.cursor_c)
    let s:state.line_offset = l:snap.line_offset
    " Drop any later snapshots (we're branching the timeline).
    let s:state.snapshots = s:state.snapshots[:a:idx]
endfunction

" --- Timer plumbing --------------------------------------------------------

function! s:ScheduleNext(delay_ms) abort
    if s:state.stopped | return | endif
    if s:state.active_timer != -1
        call timer_stop(s:state.active_timer)
    endif
    let s:state.active_timer = timer_start(a:delay_ms, function('s:Tick'))
endfunction

function! s:StopTimer() abort
    if s:state.active_timer != -1
        call timer_stop(s:state.active_timer)
        let s:state.active_timer = -1
    endif
endfunction

" --- Animation phases ------------------------------------------------------

function! s:Tick(timer) abort
    if s:state.stopped | return | endif
    if s:state.paused
        call s:ScheduleNext(50)
        return
    endif
    if s:state.phase ==# 'idle'
        call s:StartNextHunk()
    elseif s:state.phase ==# 'moving'
        call s:MoveStep()
    elseif s:state.phase ==# 'typing'
        call s:ProcessCharOp()
    elseif s:state.phase ==# 'done'
        return
    endif
endfunction

function! s:StartNextHunk() abort
    if s:state.hunk_idx >= len(s:state.hunks)
        let s:state.phase = 'done'
        " If --output was specified, write the buffer and quit
        if !empty(g:diffvim.output_file)
            execute 'w! ' . g:diffvim.output_file
            echo 'diffvim: result written to ' . g:diffvim.output_file
            qa!
        endif
        echo 'diffvim: animation complete (' . len(s:state.hunks) . ' hunk(s) applied)'
        return
    endif
    call s:SaveSnapshot()
    call s:UpdateProgress()
    let l:hunk = s:state.hunks[s:state.hunk_idx]
    let l:target_line = l:hunk.target_line_old + s:state.line_offset

    " Set cur_hunk NOW — needed by ApplyHunkInstantly and ProcessCharOp
    let s:state.cur_hunk = l:hunk

    " Position cursor at the hunk target BEFORE any processing
    " (including max-hunk-chars instant apply)
    if l:hunk.is_end_insert && l:target_line > line('$')
        let s:cur_l = line('$')
        let s:cur_c = len(getline(line('$'))) + 1
    elseif l:hunk.is_end_delete
        let l:prev = l:target_line - 1
        if l:prev < 1 | let l:prev = 1 | endif
        if l:prev > line('$') | let l:prev = line('$') | endif
        let s:cur_l = l:prev
        let s:cur_c = len(getline(l:prev)) + 1
    else
        let l:tl = l:target_line
        if l:tl < 1 | let l:tl = 1 | endif
        if l:tl > line('$') | let l:tl = line('$') | endif
        let s:cur_l = l:tl
        let s:cur_c = 1
    endif
    call s:PlaceCursor()

    " Check --max-hunk-chars: if hunk has too many changed chars, apply instantly
    if g:diffvim.max_hunk_chars > 0
        let l:changed = 0
        for l:op in l:hunk.char_ops
            if l:op[0] !=# 'keep'
                let l:changed += 1
            endif
        endfor
        if l:changed > g:diffvim.max_hunk_chars
            echo 'diffvim: hunk ' . (s:state.hunk_idx + 1) . ' has ' . l:changed . ' changed chars (> ' . g:diffvim.max_hunk_chars . '), applying instantly'
            call s:ApplyHunkInstantly()
            return
        endif
    endif

    " --git-blame: echo git blame for the target line of this hunk.
    if g:diffvim.git_blame
        call s:ShowGitBlame(l:target_line)
    endif

    " --highlight-hunk: visually highlight the hunk region before animating
    if g:diffvim.highlight_hunk
        let l:changed = 0
        for l:op in l:hunk.char_ops
            if l:op[0] !=# 'keep'
                let l:changed += 1
            endif
        endfor
        if l:changed >= g:diffvim.highlight_min_chars
            let l:start_line = l:target_line
            let l:end_line = l:target_line + l:hunk.deleted_count - 1
            if l:hunk.deleted_count == 0
                let l:end_line = l:start_line
            endif
            if l:start_line < 1 | let l:start_line = 1 | endif
            if l:end_line < 1 | let l:end_line = 1 | endif
            call s:HighlightHunk(l:start_line, l:end_line)
            " Schedule highlight clear after the duration
            call timer_start(g:diffvim.highlight_duration, function('s:ClearHighlight'))
        endif
    endif

    " Set up the move (cursor glide to target)
    let s:state.move_end_l = s:cur_l
    let s:state.move_end_c = s:cur_c
    let s:state.move_start_l = s:cur_l
    let s:state.move_start_c = s:cur_c
    let s:state.move_elapsed = 0
    let s:state.move_duration = s:ComputeMoveDuration(
        \ s:state.move_start_l, s:state.move_start_c,
        \ s:state.move_end_l,   s:state.move_end_c)
    let s:state.phase = 'moving'
    call s:ScheduleNext(float2nr(g:diffvim.tick_ms / s:state.runtime_speed))
endfunction

" Apply all remaining char ops in the current hunk instantly (no animation).
function! s:ApplyHunkInstantly() abort
    let l:hunk = s:state.cur_hunk
    let l:ops = l:hunk.char_ops
    for l:op in l:ops
        if l:op[0] ==# 'keep'
            call s:AdvanceForKeepChar(l:op[1])
        elseif l:op[0] ==# 'delete'
            call s:DeleteCharAtCursor()
        elseif l:op[0] ==# 'insert'
            call s:InsertCharAtCursor(l:op[1])
        endif
    endfor
    redraw
    let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
    let s:state.hunk_idx += 1
    let s:state.phase = 'idle'
    call s:ScheduleNext(g:diffvim.hunk_pause_ms)
endfunction

" Update the status line with progress info.
function! s:UpdateProgress() abort
    let l:total = len(s:state.hunks)
    let l:current = s:state.hunk_idx + 1
    if l:current > l:total | let l:current = l:total | endif
    let l:pct = l:total > 0 ? float2nr(l:current * 100 / l:total) : 100
    let l:msg = 'diffvim: hunk ' . l:current . '/' . l:total . ' (' . l:pct . '%)'
    if abs(s:state.runtime_speed - 1.0) > 0.01
        let l:msg .= ' | speed ' . printf('%.1f', s:state.runtime_speed) . 'x'
    endif
    if s:state.paused
        let l:msg .= ' | PAUSED'
    endif
    echo l:msg
endfunction

function! s:MoveStep() abort
    let s:state.move_elapsed += float2nr(g:diffvim.tick_ms / s:state.runtime_speed)
    let l:t = s:state.move_elapsed * 1.0 / s:state.move_duration
    if l:t >= 1.0
        let s:cur_l = s:state.move_end_l
        let s:cur_c = s:state.move_end_c
        call s:PlaceCursor()
        let s:state.phase = 'typing'
        let s:state.op_idx = 0
        call s:ScheduleNext(float2nr(g:diffvim.hunk_pause_ms / s:state.runtime_speed))
        return
    endif
    let l:eased = s:EaseInOut(l:t)
    let l:cur_l = float2nr(round(s:state.move_start_l
        \ + (s:state.move_end_l - s:state.move_start_l) * l:eased))
    let l:cur_c = float2nr(round(s:state.move_start_c
        \ + (s:state.move_end_c - s:state.move_start_c) * l:eased))
    if l:cur_l < 1 | let l:cur_l = 1 | endif
    if l:cur_c < 1 | let l:cur_c = 1 | endif
    if l:cur_l > line('$') | let l:cur_l = line('$') | endif
    " During the glide, show the visible cursor at intermediate positions.
    call cursor(l:cur_l, l:cur_c)
    redraw
    call s:ScheduleNext(float2nr(g:diffvim.tick_ms / s:state.runtime_speed))
endfunction

function! s:ProcessCharOp() abort
    let l:hunk = s:state.cur_hunk
    if s:state.op_idx >= len(l:hunk.char_ops)
        " Hunk finished.
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
        let s:state.phase = 'idle'
        call s:ScheduleNext(float2nr(g:diffvim.hunk_pause_ms / s:state.runtime_speed))
        return
    endif
    let l:op = l:hunk.char_ops[s:state.op_idx]

    " --max-word-chars: if a contiguous sequence of modified (non-space)
    " characters is LONGER than max_word_chars, apply the whole sequence
    " in one shot with a pause, so the user can read the change.
    " Sequences <= max_word_chars are animated character by character.
    if g:diffvim.max_word_chars > 0 && (l:op[0] ==# 'insert' || l:op[0] ==# 'delete')
        let l:word_len = s:LookaheadWordLength(l:hunk.char_ops, s:state.op_idx)
        if l:word_len > g:diffvim.max_word_chars
            call s:ApplyWordInstantly(l:hunk.char_ops, s:state.op_idx, l:word_len)
            let s:state.op_idx += l:word_len
            call s:ScheduleNext(float2nr(g:diffvim.word_pause_ms / s:state.runtime_speed))
            return
        endif
    endif

    let l:delay = 0
    if l:op[0] ==# 'keep'
        call s:AdvanceForKeepChar(l:op[1])
        redraw
        let l:delay = 1   " skip keeps as fast as possible
    elseif l:op[0] ==# 'delete'
        call s:DeleteCharAtCursor()
        redraw
        let l:delay = float2nr(g:diffvim.delete_delay_ms / s:state.runtime_speed)
        if g:diffvim.adaptive_timing
            let l:complex = s:ComputeComplexity(l:hunk.char_ops, s:state.op_idx)
            let l:delay = float2nr(l:delay * (1.0 + l:complex * 0.5))
        endif
        if g:diffvim.sign_column
            call s:PlaceSign('dv_del', s:cur_l)
        endif
    elseif l:op[0] ==# 'insert'
        call s:InsertCharAtCursor(l:op[1])
        redraw
        let l:delay = float2nr(g:diffvim.type_delay_ms / s:state.runtime_speed)
        if g:diffvim.adaptive_timing
            let l:complex = s:ComputeComplexity(l:hunk.char_ops, s:state.op_idx)
            let l:delay = float2nr(l:delay * (1.0 + l:complex * 0.5))
        endif
        if g:diffvim.sign_column
            call s:PlaceSign('dv_add', s:cur_l)
        endif
    endif
    let s:state.op_idx += 1
    call s:ScheduleNext(l:delay)
endfunction

" Look ahead from op_idx to find a "word": contiguous insert or delete ops
" (not mixed) where chars are non-space, terminated by a space or op change.
" Returns the length of the word (0 if not a word boundary).
function! s:LookaheadWordLength(ops, start) abort
    let l:first_type = a:ops[a:start][0]
    if l:first_type ==# 'keep' | return 0 | endif
    let l:len = 0
    let l:i = a:start
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] !=# l:first_type | break | endif
        let l:code = char2nr(l:op[1])
        " Newline (10) or space (32) terminates a word
        if l:op[1] ==# "\n" || l:op[1] ==# ' ' | break | endif
        let l:len += 1
        let l:i += 1
    endwhile
    " Word must be terminated by space/newline/keep/end to be a "word"
    let l:end_idx = a:start + l:len
    if l:end_idx < len(a:ops)
        let l:next_op = a:ops[l:end_idx]
        if l:next_op[0] ==# 'keep' || l:next_op[1] ==# "\n" || l:next_op[1] ==# ' '
            return l:len
        endif
    else
        return l:len  " End of ops
    endif
    return 0  " Not terminated properly
endfunction

" Apply a word (contiguous insert or delete) instantly.
function! s:ApplyWordInstantly(ops, start, len) abort
    let l:first_type = a:ops[a:start][0]
    let l:i = a:start
    while l:i < a:start + a:len
        let l:op = a:ops[l:i]
        if l:first_type ==# 'insert'
            call s:InsertCharAtCursor(l:op[1])
        elseif l:first_type ==# 'delete'
            call s:DeleteCharAtCursor()
        endif
        let l:i += 1
    endwhile
    redraw
endfunction

" --- Adaptive timing and sign-column helpers ------------------------------

" Count non-keep ops in a ±10 window around idx (for --adaptive-timing).
function! s:ComputeComplexity(ops, idx) abort
    let l:start = a:idx - 10
    if l:start < 0 | let l:start = 0 | endif
    let l:end = a:idx + 10
    if l:end >= len(a:ops) | let l:end = len(a:ops) - 1 | endif
    let l:count = 0
    let l:i = l:start
    while l:i <= l:end
        if a:ops[l:i][0] !=# 'keep'
            let l:count += 1
        endif
        let l:i += 1
    endwhile
    return l:count
endfunction

" Sign placement (for --sign-column). Uses an incrementing ID per buffer.
let s:sign_next_id = 100

function! s:PlaceSign(name, line) abort
    if a:line < 1 || a:line > line('$') | return | endif
    execute 'sign place ' . s:sign_next_id . ' line=' . a:line
        \ . ' name=' . a:name . ' buffer=' . bufnr('')
    let s:sign_next_id += 1
    if s:sign_next_id > 99990
        let s:sign_next_id = 100
    endif
endfunction

" Run git blame on a given line and echo the result (for --git-blame).
function! s:ShowGitBlame(line) abort
    let l:file = expand('%:p')
    if empty(l:file) | return | endif
    let l:cmd = 'git blame -L ' . a:line . ',' . a:line . ' -- ' . shellescape(l:file) . ' 2>/dev/null'
    let l:result = system(l:cmd)
    if !empty(l:result) && v:shell_error == 0
        echo 'diffvim blame: ' . substitute(l:result, '\n\+$', '', '')
    endif
endfunction

" Hunk highlighting — highlight a line range before animating it.
let s:highlight_ids = []

function! s:HighlightHunk(start_line, end_line) abort
    call s:ClearHighlight()
    let l:positions = []
    for l:l in range(a:start_line, a:end_line)
        call add(l:positions, [l:l])
    endfor
    " matchaddpos handles up to 8 positions per call; batch if needed
    let l:batch = []
    for l:pos in l:positions
        call add(l:batch, l:pos)
        if len(l:batch) == 8
            let l:id = matchaddpos(g:diffvim.highlight_color, l:batch)
            call add(s:highlight_ids, l:id)
            let l:batch = []
        endif
    endfor
    if !empty(l:batch)
        let l:id = matchaddpos(g:diffvim.highlight_color, l:batch)
        call add(s:highlight_ids, l:id)
    endif
    redraw
endfunction

function! s:ClearHighlight(...) abort
    for l:id in s:highlight_ids
        try
            call matchdelete(l:id)
        catch
        endtry
    endfor
    let s:highlight_ids = []
    redraw
endfunction

" --- User controls ---------------------------------------------------------

function! s:TogglePause() abort
    if s:state.stopped || s:state.phase ==# 'done'
        echo 'diffvim: nothing to pause'
        return
    endif
    " --step-mode: Space advances one step instead of toggling pause.
    " The animation starts paused; each Space press advances one op.
    if g:diffvim.step_mode
        if s:state.phase ==# 'typing' && !empty(s:state.cur_hunk)
            call s:ProcessCharOp()
        elseif s:state.phase ==# 'moving'
            " Jump to end of move and enter typing phase.
            let s:cur_l = s:state.move_end_l
            let s:cur_c = s:state.move_end_c
            call s:PlaceCursor()
            let s:state.phase = 'typing'
            let s:state.op_idx = 0
            redraw
        elseif s:state.phase ==# 'idle'
            call s:StartNextHunk()
        endif
        return
    endif
    let s:state.paused = !s:state.paused
    call s:UpdateProgress()
endfunction

function! s:SkipCurrent() abort
    if s:state.stopped | return | endif
    if s:state.phase ==# 'done'
        echo 'diffvim: already done'
        return
    endif
    call s:StopTimer()
    let s:state.paused = 0
    if s:state.phase ==# 'idle'
        " Between hunks: just immediately kick off the next.
        call s:ScheduleNext(1)
        echo 'diffvim: skip'
        return
    endif
    if s:state.phase ==# 'moving'
        " Jump straight to the move endpoint.
        let s:cur_l = s:state.move_end_l
        let s:cur_c = s:state.move_end_c
        call s:PlaceCursor()
        let s:state.phase = 'typing'
        let s:state.op_idx = 0
    endif
    if s:state.phase ==# 'typing'
        " Apply remaining char_ops instantly.
        let l:hunk = s:state.cur_hunk
        while s:state.op_idx < len(l:hunk.char_ops)
            let l:op = l:hunk.char_ops[s:state.op_idx]
            if l:op[0] ==# 'keep'
                call s:AdvanceForKeepChar(l:op[1])
            elseif l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
            elseif l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
            endif
            let s:state.op_idx += 1
        endwhile
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
        let s:state.phase = 'idle'
    endif
    redraw
    call s:UpdateProgress()
    call s:ScheduleNext(g:diffvim.hunk_pause_ms)
endfunction

function! s:Back() abort
    if s:state.stopped | return | endif
    call s:StopTimer()
    let s:state.paused = 0
    if s:state.hunk_idx > 0
        let s:state.hunk_idx -= 1
    elseif s:state.hunk_idx == 0 && !empty(s:state.snapshots)
        " Already at the first hunk; just rewind to its start.
    endif
    if !empty(s:state.snapshots)
        let l:target = min([s:state.hunk_idx, len(s:state.snapshots) - 1])
        call s:RestoreSnapshot(l:target)
        let s:cur_l = s:state.snapshots[l:target].cursor_l
        let s:cur_c = s:state.snapshots[l:target].cursor_c
        call s:PlaceCursor()
    endif
    let s:state.phase = 'idle'
    let s:state.op_idx = 0
    redraw
    call s:UpdateProgress()
    call s:ScheduleNext(g:diffvim.hunk_pause_ms)
endfunction

function! s:Quit() abort
    call s:StopTimer()
    let s:state.stopped = 1
    let s:state.paused = 0
    " If --output was specified, write the buffer before stopping
    if !empty(g:diffvim.output_file)
        execute 'w! ' . g:diffvim.output_file
        echo 'diffvim: result written to ' . g:diffvim.output_file
    endif
    silent! nunmap <buffer> <Space>
    silent! nunmap <buffer> n
    silent! nunmap <buffer> b
    silent! nunmap <buffer> q
    silent! nunmap <buffer> ?
    silent! nunmap <buffer> +
    silent! nunmap <buffer> -
    silent! nunmap <buffer> =
    echo 'diffvim: animation stopped. Buffer left in current state.'
endfunction

function! s:ShowHelp() abort
    echo 'diffvim: hunk ' . (s:state.hunk_idx + 1) . '/' . len(s:state.hunks)
        \ . '  | Space=pause  n=next  b=back  q=quit  +/-=speed  ?=help'
endfunction

" Speed up: multiply runtime_speed by 1.5
function! s:SpeedUp() abort
    let s:state.runtime_speed = s:state.runtime_speed * 1.5
    echo 'diffvim: speed ' . printf('%.1f', s:state.runtime_speed) . 'x'
endfunction

" Slow down: divide runtime_speed by 1.5
function! s:SlowDown() abort
    let s:state.runtime_speed = s:state.runtime_speed / 1.5
    echo 'diffvim: speed ' . printf('%.1f', s:state.runtime_speed) . 'x'
endfunction

" Reset speed to 1.0
function! s:ResetSpeed() abort
    let s:state.runtime_speed = 1.0
    echo 'diffvim: speed reset to 1.0x'
endfunction

" --- Mappings --------------------------------------------------------------

nnoremap <buffer> <silent> <Space> :call <SID>TogglePause()<CR>
nnoremap <buffer> <silent> n       :call <SID>SkipCurrent()<CR>
nnoremap <buffer> <silent> b       :call <SID>Back()<CR>
nnoremap <buffer> <silent> q       :call <SID>Quit()<CR>
nnoremap <buffer> <silent> ?       :call <SID>ShowHelp()<CR>
nnoremap <buffer> <silent> +       :call <SID>SpeedUp()<CR>
nnoremap <buffer> <silent> -       :call <SID>SlowDown()<CR>
nnoremap <buffer> <silent> =       :call <SID>ResetSpeed()<CR>

" --- Autostart -------------------------------------------------------------

function! s:StartAnimation() abort
    let s:state.hunks = s:BuildHunks()
    if empty(s:state.hunks)
        echo 'diffvim: files are identical, nothing to animate'
        return
    endif
    " --sign-column: define signs for add/delete/modify.
    if g:diffvim.sign_column
        sign define dv_add text=+ texthl=DiffAdd
        sign define dv_del text=- texthl=DiffDelete
        sign define dv_mod text=* texthl=DiffChange
    endif
    " --step-mode: start paused so the user can step through with Space.
    if g:diffvim.step_mode
        let s:state.paused = 1
        echo 'diffvim: step mode active — press Space to advance one op'
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'idle'
    let s:state.stopped = 0
    let s:state.paused = g:diffvim.step_mode ? 1 : 0
    let s:cur_l = line('.')
    let s:cur_c = col('.')
    call s:ShowConfig()
    call s:ShowHelp()
    call s:ScheduleNext(300)   " brief pause so the user can see the original
endfunction

" Print the active configuration so the user can verify env vars are read.
function! s:ShowConfig() abort
    let l:msg = 'diffvim config:'
        \ . '  tick=' . g:diffvim.tick_ms . 'ms'
        \ . '  type=' . g:diffvim.type_delay_ms . 'ms'
        \ . '  del=' . g:diffvim.delete_delay_ms . 'ms'
        \ . '  move=' . g:diffvim.move_min_ms . '-' . g:diffvim.move_max_ms . 'ms'
        \ . '  hunk_pause=' . g:diffvim.hunk_pause_ms . 'ms'
    if g:diffvim.scroll !=# 'none'
        let l:msg .= '  scroll=' . g:diffvim.scroll
    endif
    if g:diffvim.max_hunk_chars > 0
        let l:msg .= '  max_hunk=' . g:diffvim.max_hunk_chars
    endif
    if g:diffvim.max_word_chars > 0
        let l:msg .= '  max_word=' . g:diffvim.max_word_chars
    endif
    if !empty(g:diffvim.output_file)
        let l:msg .= '  output=' . g:diffvim.output_file
    endif
    if g:diffvim.word_diff
        let l:msg .= '  word_diff=on'
    endif
    if g:diffvim.step_mode
        let l:msg .= '  step_mode=on'
    endif
    if g:diffvim.adaptive_timing
        let l:msg .= '  adaptive_timing=on'
    endif
    if g:diffvim.sign_column
        let l:msg .= '  sign_column=on'
    endif
    if g:diffvim.git_blame
        let l:msg .= '  git_blame=on'
    endif
    if g:diffvim.max_line_len > 0
        let l:msg .= '  max_line_len=' . g:diffvim.max_line_len
    endif
    echo l:msg
endfunction


" Public entry point — called by the :Diffvim command in plugin/diffvim.vim
function! diffvim#engine#Start() abort
    call s:StartAnimation()
endfunction
