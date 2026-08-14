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
    \ 'semantic_cleanup':   !empty($DIFFVIM_SEMANTIC_CLEANUP) ? 1 : 0,
    \ 'indent_aware':       !empty($DIFFVIM_INDENT_AWARE)     ? 1 : 0,
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
    \ 'no_startup_pause':   !empty($DIFFVIM_NO_STARTUP_PAUSE) ? 1 : 0,
    \ 'startup_pause':      !empty($DIFFVIM_STARTUP_PAUSE)    ? 1 : 0,
    \ 'adaptive_mode':     !empty($DIFFVIM_ADAPTIVE_MODE)   ? 1 : 0,
    \ 'adaptive_start_ms': !empty($DIFFVIM_ADAPTIVE_START_MS) ? str2nr($DIFFVIM_ADAPTIVE_START_MS) : 80,
    \ 'adaptive_max_ms':   !empty($DIFFVIM_ADAPTIVE_MAX_MS)   ? str2nr($DIFFVIM_ADAPTIVE_MAX_MS)   : 30,
    \ 'adaptive_accel':    !empty($DIFFVIM_ADAPTIVE_ACCEL)    ? str2nr($DIFFVIM_ADAPTIVE_ACCEL) * 1.0 / 100.0 : 0.92,
    \ 'adaptive_pause_lines': !empty($DIFFVIM_ADAPTIVE_PAUSE_LINES) ? str2nr($DIFFVIM_ADAPTIVE_PAUSE_LINES) : 15,
    \ 'adaptive_pause_ms': !empty($DIFFVIM_ADAPTIVE_PAUSE_MS) ? str2nr($DIFFVIM_ADAPTIVE_PAUSE_MS) : 500,
    \ 'rapid_eol_delete':   !empty($DIFFVIM_RAPID_EOL_DELETE)  ? 1 : 0,
    \ 'rapid_eol_delay_ms': !empty($DIFFVIM_RAPID_EOL_DELAY_MS) ? str2nr($DIFFVIM_RAPID_EOL_DELAY_MS) : 80,
    \ 'rapid_eol_min_chars':!empty($DIFFVIM_RAPID_EOL_MIN_CHARS) ? str2nr($DIFFVIM_RAPID_EOL_MIN_CHARS) : 3,
    \ 'keep_dirty':         !empty($DIFFVIM_KEEP_DIRTY)        ? 1 : 0,
    \ 'precomputed':        !empty($DIFFVIM_PRECOMPUTED)       ? $DIFFVIM_PRECOMPUTED             : '',
    \ 'highlight_word':      !empty($DIFFVIM_HIGHLIGHT_WORD)            ? 1 : 0,
    \ 'highlight_word_color':!empty($DIFFVIM_HIGHLIGHT_WORD_COLOR)      ? $DIFFVIM_HIGHLIGHT_WORD_COLOR            : 'Search',
    \ 'highlight_word_duration': !empty($DIFFVIM_HIGHLIGHT_WORD_DURATION_MS) ? str2nr($DIFFVIM_HIGHLIGHT_WORD_DURATION_MS) : 300,
    \ 'highlight_word_min_chars': !empty($DIFFVIM_HIGHLIGHT_WORD_MIN_CHARS) ? str2nr($DIFFVIM_HIGHLIGHT_WORD_MIN_CHARS) : 2,
    \ 'accel_delete':       !empty($DIFFVIM_ACCEL_DELETE)        ? 1 : 0,
    \ 'accel_delete_start_ms': !empty($DIFFVIM_ACCEL_DELETE_START_MS) ? str2nr($DIFFVIM_ACCEL_DELETE_START_MS) : 80,
    \ 'accel_delete_min_ms':!empty($DIFFVIM_ACCEL_DELETE_MIN_MS) ? str2nr($DIFFVIM_ACCEL_DELETE_MIN_MS) : 10,
    \ 'accel_delete_accel': !empty($DIFFVIM_ACCEL_DELETE_ACCEL)  ? str2nr($DIFFVIM_ACCEL_DELETE_ACCEL) * 1.0 / 100.0 : 0.85,
    \ 'overwrite_mode':     !empty($DIFFVIM_OVERWRITE_MODE)      ? 1 : 0,
    \ 'delete_end_first':   !empty($DIFFVIM_DELETE_END_FIRST)    ? 1 : 0,
    \ 'delete_end_first_delay_ms': !empty($DIFFVIM_DELETE_END_FIRST_DELAY_MS) ? str2nr($DIFFVIM_DELETE_END_FIRST_DELAY_MS) : 100,
    \ 'startup_feedback':   !empty($DIFFVIM_STARTUP_FEEDBACK)    ? 1 : 0,
    \ 'inline_highlight':   !empty($DIFFVIM_INLINE_HIGHLIGHT)    ? 1 : 0,
    \ 'inline_highlight_duration': !empty($DIFFVIM_INLINE_HIGHLIGHT_DURATION_MS) ? str2nr($DIFFVIM_INLINE_HIGHLIGHT_DURATION_MS) : 200,
    \ 'gaussian_jitter':    !empty($DIFFVIM_GAUSSIAN_JITTER)     ? 1 : 0,
    \ 'gaussian_jitter_pct':!empty($DIFFVIM_GAUSSIAN_JITTER_PCT) ? str2nr($DIFFVIM_GAUSSIAN_JITTER_PCT) : 20,
    \ 'dim_unchanged':      !empty($DIFFVIM_DIM_UNCHANGED)       ? 1 : 0,
    \ 'dim_unchanged_pct':  !empty($DIFFVIM_DIM_UNCHANGED_PCT)   ? str2nr($DIFFVIM_DIM_UNCHANGED_PCT) : 60,
    \ 'pause_after_lines':  !empty($DIFFVIM_PAUSE_AFTER_LINES)   ? str2nr($DIFFVIM_PAUSE_AFTER_LINES) : 0,
    \ 'pause_after_threshold': !empty($DIFFVIM_PAUSE_AFTER_THRESHOLD) ? str2nr($DIFFVIM_PAUSE_AFTER_THRESHOLD) : 50,
    \ 'pause_after_ms':     !empty($DIFFVIM_PAUSE_AFTER_MS)      ? str2nr($DIFFVIM_PAUSE_AFTER_MS) : 500,
    \ 'pause_before_delete_ms': !empty($DIFFVIM_PAUSE_BEFORE_DELETE_MS) ? str2nr($DIFFVIM_PAUSE_BEFORE_DELETE_MS) : 200,
    \ 'pause_after_delete_ms': !empty($DIFFVIM_PAUSE_AFTER_DELETE_MS) ? str2nr($DIFFVIM_PAUSE_AFTER_DELETE_MS) : 200,
    \ 'block_delete_size':  !empty($DIFFVIM_BLOCK_DELETE_SIZE)   ? str2nr($DIFFVIM_BLOCK_DELETE_SIZE) : 3,
    \ 'theme':              !empty($DIFFVIM_THEME)              ? $DIFFVIM_THEME                   : '',
    \ 'optimize_sequence':  !empty($DIFFVIM_OPTIMIZE_SEQUENCE)  ? 1 : 1,
    \ 'log_mode':           !empty($DIFFVIM_LOG_MODE)           ? $DIFFVIM_LOG_MODE                : '',
    \ 'log_file':           !empty($DIFFVIM_LOG_FILE)           ? $DIFFVIM_LOG_FILE                : 'diffvim.log',
    \ 'left_to_right':      empty($DIFFVIM_LEFT_TO_RIGHT)       ? 1 : ($DIFFVIM_LEFT_TO_RIGHT ==# '0' ? 0 : 1),
    \ 'adaptive_word_delete': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE) ? 1 : 0,
    \ 'adaptive_word_delete_start_chars': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE_START_CHARS) ? str2nr($DIFFVIM_ADAPTIVE_WORD_DELETE_START_CHARS) : 3,
    \ 'adaptive_word_delete_start_ms': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE_START_MS) ? str2nr($DIFFVIM_ADAPTIVE_WORD_DELETE_START_MS) : 80,
    \ 'adaptive_word_delete_min_ms': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE_MIN_MS) ? str2nr($DIFFVIM_ADAPTIVE_WORD_DELETE_MIN_MS) : 15,
    \ 'adaptive_word_delete_accel': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE_ACCEL) ? str2nr($DIFFVIM_ADAPTIVE_WORD_DELETE_ACCEL) * 1.0 / 100.0 : 0.85,
    \ 'adaptive_word_delete_word_pause_ms': !empty($DIFFVIM_ADAPTIVE_WORD_DELETE_WORD_PAUSE_MS) ? str2nr($DIFFVIM_ADAPTIVE_WORD_DELETE_WORD_PAUSE_MS) : 100,
    \ 'rapid_identical_chars': !empty($DIFFVIM_RAPID_IDENTICAL_CHARS) ? 1 : 0,
    \ 'rapid_identical_min': !empty($DIFFVIM_RAPID_IDENTICAL_MIN) ? str2nr($DIFFVIM_RAPID_IDENTICAL_MIN) : 5,
    \ 'rapid_identical_accel': !empty($DIFFVIM_RAPID_IDENTICAL_ACCEL) ? str2nr($DIFFVIM_RAPID_IDENTICAL_ACCEL) * 1.0 / 100.0 : 0.5,
    \ 'word_accel':          !empty($DIFFVIM_WORD_ACCEL)           ? 1 : 0,
    \ 'word_accel_delete_pct': !empty($DIFFVIM_WORD_ACCEL_DELETE_PCT) ? str2nr($DIFFVIM_WORD_ACCEL_DELETE_PCT) : 20,
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
    \ 'adaptive_delay': 0,
    \ 'adaptive_lines_done': 0,
    \ 'accel_delete_delay': 0,
    \ 'accel_delete_count': 0,
    \ 'accel_delete_total': 0,
    \ 'pause_after_count': 0,
    \ 'awd_phase': 0,
    \ 'awd_delay': 0,
    \ 'awd_word_count': 0,
    \ 'word_accel_idx': 0,
    \ 'word_accel_total': 0,
    \ 'word_accel_base_delay': 0,
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

" Word-level diff: splits text into word tokens (non-space runs and
" whitespace runs), runs LCS at the token level, then expands back to
" char ops. Produces more natural typing patterns than char-level LCS
" because consecutive chars within a word are grouped.
function! s:WordDiff(a, b) abort
    let l:a = s:SplitWords(a:a)
    let l:b = s:SplitWords(a:b)
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
    " Backtrack at token level, collecting (op_type, token) pairs in reverse.
    let l:token_ops = []
    let l:i = l:na
    let l:j = l:nb
    while l:i > 0 || l:j > 0
        if l:i > 0 && l:j > 0 && l:a[l:i - 1] ==# l:b[l:j - 1]
            call add(l:token_ops, ['keep', l:a[l:i - 1]])
            let l:i -= 1
            let l:j -= 1
        elseif l:j > 0 && (l:i == 0 || l:dp[l:i][l:j - 1] >= l:dp[l:i - 1][l:j])
            call add(l:token_ops, ['insert', l:b[l:j - 1]])
            let l:j -= 1
        else
            call add(l:token_ops, ['delete', l:a[l:i - 1]])
            let l:i -= 1
        endif
    endwhile
    " Reverse to get forward order, THEN expand each token to char ops.
    " This ensures chars within each token are in the correct order.
    call reverse(l:token_ops)
    let l:ops = []
    for l:top in l:token_ops
        for l:ch in split(l:top[1], '\zs')
            call add(l:ops, [l:top[0], l:ch])
        endfor
    endfor
    return l:ops
endfunction

" Split text into word tokens: maximal runs of non-space chars and
" maximal runs of whitespace. E.g. "hello world" -> ["hello", " ", "world"].
function! s:SplitWords(text) abort
    return split(a:text, '\(\S\+\|\s\+\)\zs')
endfunction

" Semantic cleanup: merge adjacent delete+insert (or insert+delete) pairs
" that cancel out (same char code) into a single keep op. Reduces
" unnecessary typing noise.
function! s:SemanticCleanup(ops) abort
    if len(a:ops) < 2 | return a:ops | endif
    let l:result = []
    let l:i = 0
    while l:i < len(a:ops)
        if l:i + 1 < len(a:ops)
            let l:op1 = a:ops[l:i]
            let l:op2 = a:ops[l:i + 1]
            " delete X followed by insert X → keep X
            if l:op1[0] ==# 'delete' && l:op2[0] ==# 'insert' && l:op1[1] ==# l:op2[1]
                call add(l:result, ['keep', l:op1[1]])
                let l:i += 2
                continue
            endif
            " insert X followed by delete X → keep X
            if l:op1[0] ==# 'insert' && l:op2[0] ==# 'delete' && l:op1[1] ==# l:op2[1]
                call add(l:result, ['keep', l:op1[1]])
                let l:i += 2
                continue
            endif
        endif
        call add(l:result, a:ops[l:i])
        let l:i += 1
    endwhile
    return l:result
endfunction

" Normalize indentation: strip leading whitespace from a line.
" Used by --indent-aware so lines that differ only in indentation are
" treated as "keep" at the line level.
function! s:NormalizeIndent(line) abort
    return substitute(a:line, '^[ \t]*', '', '')
endfunction

" Load precomputed hunks from a file produced by the external compute tools
" (compute/c, compute/cpp, compute/rust, compute/go).
"
" Format:
"   # diffvim precomputed diff v1
"   # hunk_count N
"   HUNK target del ins end_ins end_del
"   keep|delete|insert <code>
"   ...
"
" Returns a list of hunk dictionaries, same structure as s:BuildHunks.
function! s:LoadPrecomputed(path) abort
    if !filereadable(a:path)
        echoerr 'diffvim: cannot read precomputed file: ' . a:path
        return []
    endif
    let l:lines = readfile(a:path)
    let l:hunks = []
    let l:cur_hunk = {}
    let l:cur_ops = []
    for l:line in l:lines
        " Skip comments and blank lines
        if l:line =~# '^#' || l:line =~# '^\s*$'
            continue
        endif
        if l:line =~# '^HUNK '
            " Save previous hunk if any
            if !empty(l:cur_hunk)
                let l:cur_hunk.char_ops = l:cur_ops
                call add(l:hunks, l:cur_hunk)
            endif
            let l:parts = split(l:line)
            let l:cur_hunk = {
                \ 'target_line_old': str2nr(l:parts[1]),
                \ 'deleted_count':   str2nr(l:parts[2]),
                \ 'inserted_count':  str2nr(l:parts[3]),
                \ 'is_end_insert':   str2nr(l:parts[4]),
                \ 'is_end_delete':   str2nr(l:parts[5]),
                \ 'old_text':        '',
                \ 'new_text':        '',
                \ }
            let l:cur_ops = []
        else
            " Char op: "keep|delete|insert <code>"
            let l:parts = split(l:line)
            if len(l:parts) >= 2
                let l:code = str2nr(l:parts[1])
                let l:ch = l:code == 10 ? "\n" : nr2char(l:code, 1)
                call add(l:cur_ops, [l:parts[0], l:ch])
            endif
        endif
    endfor
    " Save last hunk
    if !empty(l:cur_hunk)
        let l:cur_hunk.char_ops = l:cur_ops
        call add(l:hunks, l:cur_hunk)
    endif
    echo 'diffvim: loaded ' . len(l:hunks) . ' precomputed hunk(s) from ' . a:path
    return l:hunks
endfunction

" Overwrite transform: when a delete run is immediately followed by an
" insert run (the classic "replace word X with word Y" pattern), transform
" the ops so that:
"   - If the replacement is SHORTER: overwrite min(len) chars (delete+insert
"     pairs become keep+insert), then delete the extra old chars.
"   - If the replacement is SAME LENGTH: all delete+insert pairs become
"     keep (pure overwrite, no deletion needed).
"   - If the replacement is LONGER: overwrite the old word (delete+insert
"     pairs become keep+insert), then insert the remainder.
"
" This produces a more natural "typing over" effect instead of
" "delete everything, then type everything".
"
" The transform scans for patterns: [delete D1..Dn] [insert I1..Im]
" and rewrites them. It only applies when both runs are non-empty and
" consist of non-space, non-newline chars (word tokens).
function! s:OverwriteTransform(ops) abort
    let l:result = []
    let l:i = 0
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] ==# 'delete' && l:op[1] !=# "\n" && l:op[1] !=# ' '
            " Collect the delete run (non-space, non-newline only)
            let l:del_run = []
            while l:i < len(a:ops) && a:ops[l:i][0] ==# 'delete'
                \ && a:ops[l:i][1] !=# "\n" && a:ops[l:i][1] !=# ' '
                call add(l:del_run, a:ops[l:i])
                let l:i += 1
            endwhile
            " Check if followed by an insert run
            if !empty(l:del_run) && l:i < len(a:ops) && a:ops[l:i][0] ==# 'insert'
                \ && a:ops[l:i][1] !=# "\n" && a:ops[l:i][1] !=# ' '
                let l:ins_run = []
                while l:i < len(a:ops) && a:ops[l:i][0] ==# 'insert'
                    \ && a:ops[l:i][1] !=# "\n" && a:ops[l:i][1] !=# ' '
                    call add(l:ins_run, a:ops[l:i])
                    let l:i += 1
                endwhile
                if !empty(l:ins_run)
                    let l:del_len = len(l:del_run)
                    let l:ins_len = len(l:ins_run)
                    let l:min_len = min([l:del_len, l:ins_len])
                    " Emit delete+insert pairs for the overlap (overwrite)
                    for l:j in range(l:min_len)
                        call add(l:result, l:del_run[l:j])
                        call add(l:result, l:ins_run[l:j])
                    endfor
                    " Remainder
                    if l:del_len > l:min_len
                        for l:j in range(l:min_len, l:del_len - 1)
                            call add(l:result, l:del_run[l:j])
                        endfor
                    elseif l:ins_len > l:min_len
                        for l:j in range(l:min_len, l:ins_len - 1)
                            call add(l:result, l:ins_run[l:j])
                        endfor
                    endif
                else
                    " No insert run — keep deletes as-is
                    for l:d in l:del_run
                        call add(l:result, l:d)
                    endfor
                endif
            else
                " No following insert run — keep deletes as-is
                for l:d in l:del_run
                    call add(l:result, l:d)
                endfor
            endif
        else
            " Not a word-delete or delete with newline/space — pass through
            call add(l:result, l:op)
            let l:i += 1
        endif
    endwhile
    return l:result
endfunction

" Delete-end-first: when a line has both inserts and trailing deletes
" (deletes that extend to end of line), move the trailing deletes BEFORE
" the inserts. This makes the animation: "delete end of line, pause, then
" insert new text" which is more natural than "insert, then delete end".
"
" Detects patterns: [insert I1..In] [delete D1..Dm] where the deletes
" extend to end of line (next op is keep-\n or end of ops), and reorders
" to: [delete D1..Dm] [pause marker] [insert I1..In].
"
" The pause is implemented as a special op ['pause_end_first', delay]
" that ProcessCharOp recognizes and uses to schedule a delay.
function! s:DeleteEndFirst(ops) abort
    let l:result = []
    let l:i = 0
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] ==# 'insert'
            " Collect the insert run
            let l:ins_start = l:i
            while l:i < len(a:ops) && a:ops[l:i][0] ==# 'insert'
                call add(l:result, a:ops[l:i])
                let l:i += 1
            endwhile
            " Check if followed by a trailing-EOL delete run
            if l:i < len(a:ops) && a:ops[l:i][0] ==# 'delete'
                let l:del_start = l:i
                while l:i < len(a:ops) && a:ops[l:i][0] ==# 'delete'
                    let l:i += 1
                endwhile
                " Check if the delete run extends to EOL
                let l:at_eol = 0
                if l:i >= len(a:ops)
                    let l:at_eol = 1
                elseif a:ops[l:i][0] ==# 'keep' && a:ops[l:i][1] ==# "\n"
                    let l:at_eol = 1
                endif
                if l:at_eol
                    " Move the deletes before the inserts.
                    " Remove the inserts we just added, add deletes first,
                    " then pause marker, then inserts.
                    let l:ins_count = l:i - l:ins_start - (l:i - l:del_start)
                    " Actually, let's just rebuild this segment properly.
                    " We added (del_start - ins_start) inserts to result.
                    " Remove them.
                    let l:ins_run = []
                    let l:to_remove = l:del_start - l:ins_start
                    while len(l:result) > 0 && l:to_remove > 0
                        call add(l:ins_run, remove(l:result, -1))
                        let l:to_remove -= 1
                    endwhile
                    call reverse(l:ins_run)
                    " Collect the delete run
                    let l:del_run = []
                    let l:j = l:del_start
                    while l:j < l:i
                        call add(l:del_run, a:ops[l:j])
                        let l:j += 1
                    endwhile
                    " Emit: deletes, pause marker, inserts
                    for l:d in l:del_run
                        call add(l:result, l:d)
                    endfor
                    call add(l:result, ['pause_end_first', g:diffvim.delete_end_first_delay_ms])
                    for l:ins in l:ins_run
                        call add(l:result, l:ins)
                    endfor
                else
                    " Not at EOL — emit the deletes normally
                    let l:j = l:del_start
                    while l:j < l:i
                        call add(l:result, a:ops[l:j])
                        let l:j += 1
                    endwhile
                endif
            endif
        else
            call add(l:result, l:op)
            let l:i += 1
        endif
    endwhile
    return l:result
endfunction

" Op-sequence post-processing: optimize the char_ops sequence to eliminate
" erratic back-and-forth cursor movement.
"
" The standard LCS diff can produce interleaved sequences like:
"   del 'a', ins 'x', del 'b', ins 'y', del 'c', ins 'z'
" which causes the cursor to jump between delete and insert positions.
" This is visually confusing and inefficient.
"
" Optimization passes:
" 1. Consolidate: group consecutive deletes and inserts so all deletes
"    come before all inserts within a "change region":
"    del a, ins x, del b, ins y → del a, del b, ins x, ins y
" 2. Coalesce: merge adjacent same-type ops that are separated only by
"    keep-ops on whitespace (the cursor doesn't need to move for whitespace).
" 3. Line-coherent: ensure ops within a single line are grouped together,
"    preventing cross-line interleaving.
"
" Research basis: "The Magic of LCS" (Hunt & McIlroy) notes that the
" standard backtrack can produce non-optimal visual sequences. The
" "patience diff" algorithm (Bram Cohen) produces more human-readable
" diffs by anchoring on unique lines. This post-processor applies similar
" principles at the char level.
"
" Enable with --optimize-sequence (default: on, use --no-optimize-sequence to disable)
function! s:OptimizeSequence(ops) abort
    if len(a:ops) < 4 | return a:ops | endif

    " Pass 1: Consolidate interleaved delete/insert pairs.
    " Scan for patterns: del X, ins Y, del Z, ins W → del X, del Z, ins Y, ins W
    " Only consolidate when the ops are within the same line (no newlines).
    let l:result = []
    let l:i = 0
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] ==# 'delete' || l:op[0] ==# 'insert'
            " Check if this op is a newline — if so, just emit and advance
            if l:op[1] ==# "\n"
                call add(l:result, l:op)
                let l:i += 1
                continue
            endif
            " Collect a run of interleaved deletes and inserts (no newlines)
            let l:del_run = []
            let l:ins_run = []
            while l:i < len(a:ops)
                let l:cur = a:ops[l:i]
                if l:cur[0] !=# 'delete' && l:cur[0] !=# 'insert'
                    break
                endif
                if l:cur[1] ==# "\n"
                    break
                endif
                if l:cur[0] ==# 'delete'
                    call add(l:del_run, l:cur)
                else
                    call add(l:ins_run, l:cur)
                endif
                let l:i += 1
            endwhile
            " If we found interleaved ops (both del and ins), consolidate:
            " all deletes first, then all inserts.
            if !empty(l:del_run) && !empty(l:ins_run)
                for l:d in l:del_run
                    call add(l:result, l:d)
                endfor
                for l:ins in l:ins_run
                    call add(l:result, l:ins)
                endfor
            else
                " Not interleaved — keep as-is
                for l:d in l:del_run
                    call add(l:result, l:d)
                endfor
                for l:ins in l:ins_run
                    call add(l:result, l:ins)
                endfor
            endif
        else
            call add(l:result, l:op)
            let l:i += 1
        endif
    endwhile

    return l:result
endfunction

" Left-to-right ordering: ensures that within each line, all delete and
" insert operations go from left to right, never jumping around.
"
" The standard LCS can produce ops that jump back and forth (e.g., delete
" at col 5, insert at col 3, delete at col 8). This function groups ops
" by line (delimited by newlines) and within each line, sorts them so
" deletes come before inserts, and within each type, by position.
"
" When --left-to-right is on, this is applied as a post-processing pass
" after OptimizeSequence.
function! s:LeftToRight(ops) abort
    let l:result = []
    let l:line_ops = []
    let l:i = 0
    let l:col = 1
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] ==# 'keep' && l:op[1] ==# "\n"
            " End of line — sort accumulated line_ops and flush
            call extend(l:result, s:SortLineOps(l:line_ops))
            call add(l:result, l:op)
            let l:line_ops = []
            let l:col = 1
        elseif l:op[0] ==# 'delete' && l:op[1] ==# "\n"
            " End of line via delete — sort and flush
            call extend(l:result, s:SortLineOps(l:line_ops))
            call add(l:result, l:op)
            let l:line_ops = []
            let l:col = 1
        elseif l:op[0] ==# 'insert' && l:op[1] ==# "\n"
            " End of line via insert — sort and flush
            call extend(l:result, s:SortLineOps(l:line_ops))
            call add(l:result, l:op)
            let l:line_ops = []
            let l:col = 1
        else
            " Track position and accumulate
            call add(l:line_ops, [l:op, l:col])
            if l:op[0] ==# 'keep' || l:op[0] ==# 'insert'
                let l:col += 1
            endif
        endif
        let l:i += 1
    endwhile
    " Flush remaining
    call extend(l:result, s:SortLineOps(l:line_ops))
    return l:result
endfunction

" Sort line ops: all deletes first (by position, left to right),
" then all inserts (by position, left to right).
function! s:SortLineOps(line_ops) abort
    if len(a:line_ops) <= 1
        let l:result = []
        for l:item in a:line_ops
            call add(l:result, l:item[0])
        endfor
        return l:result
    endif
    " Separate into keeps, deletes, inserts
    let l:keeps = []
    let l:dels = []
    let l:ins = []
    for l:item in a:line_ops
        if l:item[0][0] ==# 'keep'
            call add(l:keeps, l:item)
        elseif l:item[0][0] ==# 'delete'
            call add(l:dels, l:item)
        else
            call add(l:ins, l:item)
        endif
    endfor
    " Sort deletes: non-whitespace first (by position, left to right),
    " then whitespace deletes last. Whitespace = space (32) or tab (9).
    " This ensures the user sees content being deleted first, not indentation.
    let l:dels_nonws = []
    let l:dels_ws = []
    for l:item in l:dels
        if l:item[0][1] ==# ' ' || l:item[0][1] ==# "\t"
            call add(l:dels_ws, l:item)
        else
            call add(l:dels_nonws, l:item)
        endif
    endfor
    call sort(l:dels_nonws, {a, b -> a[1] - b[1]})
    call sort(l:dels_ws, {a, b -> a[1] - b[1]})
    let l:dels = l:dels_nonws + l:dels_ws
    " Sort inserts by position (ascending = left to right)
    call sort(l:ins, {a, b -> a[1] - b[1]})
    " Emit: keeps first, then deletes (non-ws then ws), then inserts
    let l:result = []
    for l:item in l:keeps
        call add(l:result, l:item[0])
    endfor
    for l:item in l:dels
        call add(l:result, l:item[0])
    endfor
    for l:item in l:ins
        call add(l:result, l:item[0])
    endfor
    return l:result
endfunction

" Group line-level ops into hunks, then compute char-level diff per hunk.
function! s:BuildHunks() abort
    " If --precomputed FILE was given, load hunks from that file instead of
    " computing the diff in vimscript. The file format is:
    "   # diffvim precomputed diff v1
    "   # hunk_count N
    "   HUNK target del ins end_ins end_del
    "   keep|delete|insert <code>
    "   ...
    " This is produced by the tools in compute/ (C, C++, Rust, Go).
    if !empty(g:diffvim.precomputed)
        return s:LoadPrecomputed(g:diffvim.precomputed)
    endif

    let l:old_lines = getline(1, '$')
    if empty(l:old_lines)
        let l:old_lines = ['']
    endif
    let l:new_lines = readfile(g:diffvim_new_file)
    if empty(l:new_lines)
        let l:new_lines = ['']
    endif

    " --indent-aware: normalize indentation before line-level diff so lines
    " that differ only in indentation are treated as "keep" at line level.
    " The indent change is then handled at the char level.
    if g:diffvim.indent_aware
        let l:old_norm = map(copy(l:old_lines), 's:NormalizeIndent(v:val)')
        let l:new_norm = map(copy(l:new_lines), 's:NormalizeIndent(v:val)')
        let l:line_ops = s:LineDiff(l:old_norm, l:new_norm)
        " Fix up a_idx/b_idx to point into the ORIGINAL lines (not normalized),
        " since BuildHunks reads from l:old_lines/l:new_lines.
        " The indices are the same (normalization doesn't change line count),
        " so we can use them directly.
    else
        let l:line_ops = s:LineDiff(l:old_lines, l:new_lines)
    endif

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

        " --word-diff: use word-level LCS instead of char-level for more
        " natural typing patterns (consecutive chars within a word are grouped).
        if g:diffvim.word_diff
            let l:h.char_ops = s:WordDiff(l:h.old_text, l:h.new_text)
        else
            let l:h.char_ops = s:CharDiff(l:h.old_text, l:h.new_text)
        endif
        " --semantic-cleanup: merge adjacent delete+insert pairs that cancel
        " out, reducing unnecessary typing noise.
        if g:diffvim.semantic_cleanup
            let l:h.char_ops = s:SemanticCleanup(l:h.char_ops)
        endif
        " --optimize-sequence: consolidate interleaved delete/insert ops to
        " eliminate erratic back-and-forth cursor movement. Default: on.
        if g:diffvim.optimize_sequence
            let l:h.char_ops = s:OptimizeSequence(l:h.char_ops)
        endif
        " --left-to-right: sort ops within each line so deletes and inserts
        " go from left to right, never jumping around.
        if g:diffvim.left_to_right
            let l:h.char_ops = s:LeftToRight(l:h.char_ops)
        endif
        " --overwrite: transform delete+insert pairs into overwrite-then-
        " insert-remainder or overwrite-then-delete-extra. When a word is
        " replaced, overwrite the old word in place instead of delete-all
        " then insert-all. Shorter replacement = overwrite + delete extra;
        " same length = overwrite only; longer = overwrite + insert remainder.
        if g:diffvim.overwrite_mode
            let l:h.char_ops = s:OverwriteTransform(l:h.char_ops)
        endif
        " --delete-end-first: when a line has both inserts and end-of-line
        " deletes, move the end-deletes before the inserts (with a short
        " pause) so the viewer sees the tail disappear first.
        if g:diffvim.delete_end_first
            let l:h.char_ops = s:DeleteEndFirst(l:h.char_ops)
        endif
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
        " By default, mark the buffer as not modified so ':q' quits cleanly.
        " Use --keep-dirty to leave the buffer modified (then ':q!' is required).
        if !g:diffvim.keep_dirty
            set nomodified
        endif
        if g:diffvim.keep_dirty
            echo 'diffvim: animation complete (' . len(s:state.hunks) . ' hunk(s) applied) — buffer modified, use :q! to quit'
        else
            echo 'diffvim: animation complete (' . len(s:state.hunks) . ' hunk(s) applied) — :q to quit'
        endif
        return
    endif
    call s:SaveSnapshot()
    call s:UpdateProgress()
    let l:hunk = s:state.hunks[s:state.hunk_idx]
    let l:target_line = l:hunk.target_line_old + s:state.line_offset

    " Set cur_hunk NOW — needed by ApplyHunkInstantly and ProcessCharOp
    let s:state.cur_hunk = l:hunk

    " Reset adaptive state for this hunk
    let s:state.adaptive_delay = 0
    let s:state.adaptive_lines_done = 0

    " Save the current cursor position as the START of the glide.
    " This is the key fix: previously, the cursor was moved to the target
    " BEFORE setting up the glide, so move_start == move_end and there
    " was no visible scrolling. Now we save the old position, set the
    " new target, and let MoveStep glide from old to new.
    let l:old_cur_l = s:cur_l
    let l:old_cur_c = s:cur_c

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
    " Do NOT call PlaceCursor here — let MoveStep handle the scrolling.
    " PlaceCursor would jump the cursor instantly, defeating the glide.
    " Exception: for instant-apply paths (max-hunk-chars), we need the
    " cursor positioned immediately.

    " Check --max-hunk-chars: if hunk has too many changed chars, apply instantly
    if g:diffvim.max_hunk_chars > 0
        let l:changed = 0
        for l:op in l:hunk.char_ops
            if l:op[0] !=# 'keep'
                let l:changed += 1
            endif
        endfor
        if l:changed > g:diffvim.max_hunk_chars
            call s:PlaceCursor()
            echo 'diffvim: hunk ' . (s:state.hunk_idx + 1) . ' has ' . l:changed . ' changed chars (> ' . g:diffvim.max_hunk_chars . '), applying instantly'
            call s:ApplyHunkInstantly()
            return
        endif
    endif

    " --git-blame: echo git blame for the target line of this hunk.
    if g:diffvim.git_blame
        call s:ShowGitBlame(l:target_line)
    endif

    " --highlight-hunk: visually highlight ALL lines that will change.
    " Highlight from target_line to target_line + max(deleted, inserted) - 1.
    " This ensures both deleted and inserted lines are highlighted.
    if g:diffvim.highlight_hunk
        let l:changed = 0
        for l:op in l:hunk.char_ops
            if l:op[0] !=# 'keep'
                let l:changed += 1
            endif
        endfor
        if l:changed >= g:diffvim.highlight_min_chars
            let l:start_line = l:target_line
            " Highlight max(deleted_count, inserted_count) lines so we
            " cover both the old lines being removed and the new lines
            " being added. This prevents whole blocks from disappearing
            " without highlight.
            let l:line_span = l:hunk.deleted_count
            if l:hunk.inserted_count > l:line_span
                let l:line_span = l:hunk.inserted_count
            endif
            if l:line_span < 1 | let l:line_span = 1 | endif
            let l:end_line = l:target_line + l:line_span - 1
            if l:start_line < 1 | let l:start_line = 1 | endif
            if l:end_line < 1 | let l:end_line = 1 | endif
            if l:end_line > line('$') | let l:end_line = line('$') | endif
            call s:HighlightHunk(l:start_line, l:end_line)
            " Schedule highlight clear after the duration
            call timer_start(g:diffvim.highlight_duration, function('s:ClearHighlight'))
        endif
    endif

    " Set up the move (cursor glide from old position to new target)
    let s:state.move_start_l = l:old_cur_l
    let s:state.move_start_c = l:old_cur_c
    let s:state.move_end_l = s:cur_l
    let s:state.move_end_c = s:cur_c
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
    " During the glide, move the cursor AND scroll the viewport so the
    " user sees smooth scrolling instead of a jump at the end.
    " The scroll follows the cursor with the configured scroll mode (zz/zt/zb).
    call cursor(l:cur_l, l:cur_c)
    " Scroll the viewport to follow the cursor during the glide.
    " This is the key fix: previously the viewport only scrolled at the
    " end of the glide (in PlaceCursor), causing a jarring jump. Now
    " it scrolls smoothly at each intermediate step.
    if g:diffvim.scroll ==# 'zz'
        normal! zz
    elseif g:diffvim.scroll ==# 'zt'
        normal! zt
    elseif g:diffvim.scroll ==# 'zb'
        normal! zb
    endif
    redraw
    call s:ScheduleNext(float2nr(g:diffvim.tick_ms / s:state.runtime_speed))
endfunction

function! s:ProcessCharOp() abort
    let l:hunk = s:state.cur_hunk
    if s:state.op_idx >= len(l:hunk.char_ops)
        " Hunk finished — in adaptive mode, pause at end of hunk
        let s:state.line_offset += (l:hunk.inserted_count - l:hunk.deleted_count)
        let s:state.hunk_idx += 1
        let s:state.phase = 'idle'
        if g:diffvim.adaptive_mode
            let s:state.paused = 1
            echo 'diffvim: hunk complete — paused (Space=resume, n=next)'
            call s:UpdateProgress()
            return
        endif
        call s:ScheduleNext(float2nr(g:diffvim.hunk_pause_ms / s:state.runtime_speed))
        return
    endif
    let l:op = l:hunk.char_ops[s:state.op_idx]

    " --max-word-chars: if a contiguous sequence of modified (non-space)
    " characters is LONGER than max_word_chars, apply the whole sequence
    " in one shot with a pause, so the user can read the change.
    if g:diffvim.max_word_chars > 0 && (l:op[0] ==# 'insert' || l:op[0] ==# 'delete')
        let l:word_len = s:LookaheadWordLength(l:hunk.char_ops, s:state.op_idx)
        if l:word_len > g:diffvim.max_word_chars
            call s:ApplyWordInstantly(l:hunk.char_ops, s:state.op_idx, l:word_len)
            let s:state.op_idx += l:word_len
            call s:ScheduleNext(float2nr(g:diffvim.word_pause_ms / s:state.runtime_speed))
            return
        endif
    endif

    " --word-accel: when inserting/deleting a word char by char, start slowly
    " and accelerate, then pause slightly. Total time with acceleration + pause
    " equals uniform char-by-char time. Deletion is word_accel_delete_pct%
    " faster by default (configurable).
    if g:diffvim.word_accel && (l:op[0] ==# 'insert' || l:op[0] ==# 'delete')
            \ && l:op[1] !=# "\n" && l:op[1] !=# ' ' && l:op[1] !=# "\t"
        " Check if we're starting a new word run
        if s:state.word_accel_total == 0
            let l:run_len = s:LookaheadSameTypeRun(l:hunk.char_ops, s:state.op_idx)
            if l:run_len >= 2
                let s:state.word_accel_total = l:run_len
                let s:state.word_accel_idx = 0
                " Compute base delay: for inserts, use type_delay_ms;
                " for deletes, use delete_delay_ms * (1 - delete_pct/100)
                if l:op[0] ==# 'insert'
                    let s:state.word_accel_base_delay = g:diffvim.type_delay_ms
                else
                    let l:reduction = g:diffvim.word_accel_delete_pct / 100.0
                    let s:state.word_accel_base_delay = float2nr(g:diffvim.delete_delay_ms * (1.0 - l:reduction))
                endif
            endif
        endif
        " If we're in a word acceleration run
        if s:state.word_accel_total > 0
            " Apply the op
            if l:op[0] ==# 'insert'
                call s:InsertCharAtCursor(l:op[1])
                call s:InlineHighlight(s:cur_l, s:cur_c, 'insert')
            else
                call s:DeleteCharAtCursor()
                call s:InlineHighlight(s:cur_l, s:cur_c, 'delete')
            endif
            redraw
            if g:diffvim.sign_column
                call s:PlaceSign(l:op[0] ==# 'insert' ? 'dv_add' : 'dv_del', s:cur_l)
            endif
            let s:state.op_idx += 1
            let s:state.word_accel_idx += 1
            " Compute accelerating delay: start at 2x base, decrease to 0.5x
            " The profile is: delay = base * (2.0 - 1.5 * progress)
            " where progress = idx / total. So first char = 2x, last char = 0.5x.
            " Total = sum(base * (2 - 1.5*k/N)) for k=0..N-1
            "       = base * (2N - 1.5*(N-1)/2) ≈ base * N * 1.25
            " We want total = base * N, so scale by 1/1.25 = 0.8
            let l:progress = s:state.word_accel_idx * 1.0 / s:state.word_accel_total
            let l:delay = s:state.word_accel_base_delay * (2.0 - 1.5 * l:progress) * 0.8
            if l:delay < 1 | let l:delay = 1 | endif
            let l:delay = s:GaussianJitter(float2nr(l:delay))
            " Check if word is done
            if s:state.word_accel_idx >= s:state.word_accel_total
                let l:word_total = s:state.word_accel_total
                let s:state.word_accel_total = 0
                let s:state.word_accel_idx = 0
                " Short pause after the word (10% of total word time)
                let l:pause = float2nr(s:state.word_accel_base_delay * l:word_total * 0.1)
                if l:pause < 10 | let l:pause = 10 | endif
                call s:ScheduleNext(l:pause)
                return
            endif
            call s:ScheduleNext(l:delay)
            return
        endif
    else
        " Reset word accel state when we hit a non-word op
        let s:state.word_accel_total = 0
        let s:state.word_accel_idx = 0
    endif

    " --word-diff: batch contiguous delete/insert runs (non-space, non-newline)
    " so they appear as instant word operations instead of char-by-char.
    " This is the key fix: --word-diff was only changing how the diff is
    " computed (token-level LCS), but the animation still did one char at
    " a time. Now we batch word runs.
    if g:diffvim.word_diff && (l:op[0] ==# 'insert' || l:op[0] ==# 'delete')
        let l:run_len = s:LookaheadSameTypeRun(l:hunk.char_ops, s:state.op_idx)
        if l:run_len >= 2
            call s:ApplyWordInstantly(l:hunk.char_ops, s:state.op_idx, l:run_len)
            let s:state.op_idx += l:run_len
            call s:ScheduleNext(float2nr(g:diffvim.word_pause_ms / s:state.runtime_speed))
            return
        endif
    endif

    let l:delay = 0
    if l:op[0] ==# 'keep'
        call s:AdvanceForKeepChar(l:op[1])
        redraw
        let l:delay = 1

        " --adaptive mode: count lines, pause periodically
        if g:diffvim.adaptive_mode && l:op[1] ==# "\n"
            let s:state.adaptive_lines_done += 1
            if s:state.adaptive_lines_done >= g:diffvim.adaptive_pause_lines
                let s:state.adaptive_lines_done = 0
                let s:state.paused = 1
                call s:UpdateProgress()
                echo 'diffvim: adaptive pause — press Space to continue'
                call s:ScheduleNext(g:diffvim.adaptive_pause_ms)
                return
            endif
        endif

        " --pause-after-lines: pause every N lines in large hunks
        if g:diffvim.pause_after_lines > 0 && l:op[1] ==# "\n"
            if s:state.cur_hunk.deleted_count + s:state.cur_hunk.inserted_count >= g:diffvim.pause_after_threshold
                let s:state.pause_after_count += 1
                if s:state.pause_after_count >= g:diffvim.pause_after_lines
                    let s:state.pause_after_count = 0
                    let s:state.paused = 1
                    call s:UpdateProgress()
                    echo 'diffvim: pause-after-lines — press Space to continue'
                    call s:ScheduleNext(g:diffvim.pause_after_ms)
                    return
                endif
            endif
        endif
    elseif l:op[0] ==# 'delete'
        " --highlight-word: highlight the word at cursor before deleting.
        if g:diffvim.highlight_word
            let l:run_len = s:LookaheadSameTypeRun(l:hunk.char_ops, s:state.op_idx)
            call s:HighlightCurrentWord('delete', l:run_len)
        endif
        " --rapid-identical-chars: accelerate deletion of identical char runs
        " like "---------------------------" rapidly. Each char deleted with
        " exponentially decreasing delay (accel^count).
        if g:diffvim.rapid_identical_chars
            let l:ident_count = s:LookaheadIdenticalChars(l:hunk.char_ops, s:state.op_idx)
            if l:ident_count > 0
                " Delete one char, schedule next with rapidly decreasing delay
                call s:DeleteCharAtCursor()
                call s:InlineHighlight(s:cur_l, s:cur_c, 'delete')
                redraw
                let s:state.op_idx += 1
                if g:diffvim.sign_column
                    call s:PlaceSign('dv_del', s:cur_l)
                endif
                " Compute rapidly accelerating delay
                let l:delay = float2nr(g:diffvim.delete_delay_ms)
                let l:ident_progress = 0
                " Track how many identical chars we have deleted in this run
                " by checking how many identical chars are left
                let l:remaining = s:LookaheadIdenticalChars(l:hunk.char_ops, s:state.op_idx)
                if l:remaining > 0
                    let l:ident_progress = l:ident_count - l:remaining
                    let l:delay = float2nr(g:diffvim.delete_delay_ms * pow(g:diffvim.rapid_identical_accel, l:ident_progress))
                    if l:delay < 1 | let l:delay = 1 | endif
                endif
                let l:delay = s:GaussianJitter(l:delay)
                call s:ScheduleNext(l:delay)
                return
            endif
        endif
        " --adaptive-word-delete: word-by-word line deletion with acceleration.
        " Each line: few chars slow → word by word (accelerating) → rest rapid.
        if g:diffvim.adaptive_word_delete
            let l:ml_count = s:LookaheadMultiLineDelete(l:hunk.char_ops, s:state.op_idx)
            if l:ml_count >= 2
                if s:state.accel_delete_count == 0
                    let s:state.accel_delete_total = l:ml_count
                endif
                call s:ProcessAdaptiveWordDelete(l:hunk, l:ml_count)
                return
            endif
        endif
        " --accel-delete: accelerated block-based multi-line deletion.
        " Deletes in blocks of block_delete_size lines, with accel/decel
        " and pause before/after.
        if g:diffvim.accel_delete
            let l:ml_count = s:LookaheadMultiLineDelete(l:hunk.char_ops, s:state.op_idx)
            if l:ml_count >= 2
                " Initialize accel state at the start of the run
                if s:state.accel_delete_count == 0
                    let s:state.accel_delete_total = l:ml_count
                    let s:state.accel_delete_delay = 0
                endif
                call s:ProcessBlockDelete(l:hunk, l:ml_count)
                return
            endif
        endif
        " --rapid-eol-delete: if a run of deletes extends to end of line
        " (or cursor is already past end of line), apply them in one rapid shot.
        if g:diffvim.rapid_eol_delete
            let l:rapid_count = s:LookaheadEOLDelete(l:hunk.char_ops, s:state.op_idx)
            if l:rapid_count >= g:diffvim.rapid_eol_min_chars
                for l:i in range(l:rapid_count)
                    call s:DeleteCharAtCursor()
                endfor
                redraw
                let s:state.op_idx += l:rapid_count
                if g:diffvim.sign_column
                    call s:PlaceSign('dv_del', s:cur_l)
                endif
                let l:delay = float2nr(g:diffvim.rapid_eol_delay_ms / s:state.runtime_speed)
                let l:delay = s:GaussianJitter(l:delay)
                call s:ScheduleNext(l:delay)
                return
            endif
        endif
        call s:DeleteCharAtCursor()
        " Inline highlight for deleted char
        call s:InlineHighlight(s:cur_l, s:cur_c, 'delete')
        redraw
        if g:diffvim.adaptive_mode
            let l:delay = float2nr(s:state.adaptive_delay)
        else
            let l:delay = float2nr(g:diffvim.delete_delay_ms / s:state.runtime_speed)
        endif
        if g:diffvim.adaptive_timing
            let l:complex = s:ComputeComplexity(l:hunk.char_ops, s:state.op_idx)
            let l:delay = float2nr(l:delay * (1.0 + l:complex * 0.5))
        endif
        let l:delay = s:GaussianJitter(l:delay)
        if g:diffvim.sign_column
            call s:PlaceSign('dv_del', s:cur_l)
        endif
    elseif l:op[0] ==# 'insert'
        " --highlight-word: highlight the word at cursor before inserting.
        if g:diffvim.highlight_word
            let l:run_len = s:LookaheadSameTypeRun(l:hunk.char_ops, s:state.op_idx)
            call s:HighlightCurrentWord('insert', l:run_len)
        endif
        call s:InsertCharAtCursor(l:op[1])
        " Inline highlight for freshly typed char
        call s:InlineHighlight(s:cur_l, s:cur_c, 'insert')
        redraw
        if g:diffvim.adaptive_mode
            let l:delay = float2nr(s:state.adaptive_delay)
        else
            let l:delay = float2nr(g:diffvim.type_delay_ms / s:state.runtime_speed)
        endif
        if g:diffvim.adaptive_timing
            let l:complex = s:ComputeComplexity(l:hunk.char_ops, s:state.op_idx)
            let l:delay = float2nr(l:delay * (1.0 + l:complex * 0.5))
        endif
        let l:delay = s:GaussianJitter(l:delay)
        if g:diffvim.sign_column
            call s:PlaceSign('dv_add', s:cur_l)
        endif
    elseif l:op[0] ==# 'pause_end_first'
        " --delete-end-first: pause marker between delete-end and insert.
        " No buffer change, just a delay.
        redraw
        let l:delay = float2nr(l:op[1])
        let s:state.op_idx += 1
        call s:ScheduleNext(l:delay)
        return
    endif

    " --adaptive mode: accelerate (decrease delay) after each op
    if g:diffvim.adaptive_mode && l:op[0] !=# 'keep'
        if s:state.adaptive_delay <= 0
            let s:state.adaptive_delay = g:diffvim.adaptive_start_ms
        else
            let s:state.adaptive_delay = s:state.adaptive_delay * g:diffvim.adaptive_accel
            if s:state.adaptive_delay < g:diffvim.adaptive_max_ms
                let s:state.adaptive_delay = g:diffvim.adaptive_max_ms
            endif
        endif
    endif

    let s:state.op_idx += 1
    call s:ScheduleNext(l:delay)
endfunction

" Look ahead from op_idx to count consecutive delete ops that extend to the
" end of the current line. A delete run "extends to EOL" when any of these
" is true:
"   1. The cursor is already past the end of the line (col > len(line)) —
"      every subsequent delete is "after the cursor".
"   2. The op after the delete run is a 'keep' whose char is "\n" — the
"      deletes consume the trailing text of the current line.
"   3. The delete run reaches the end of char_ops — the deletes consume
"      the rest of the hunk's old text.
" Returns the count of deletes to apply rapidly (0 if not a trailing-EOL run
" or below the min threshold).
function! s:LookaheadEOLDelete(ops, start) abort
    if !g:diffvim.rapid_eol_delete | return 0 | endif
    let l:i = a:start
    let l:count = 0
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] ==# 'delete'
            let l:count += 1
            let l:i += 1
        else
            break
        endif
    endwhile
    if l:count == 0 | return 0 | endif
    " Condition 1: cursor is past end of line — all subsequent deletes are
    " "text after the cursor".
    let l:line = getline(s:cur_l)
    let l:at_eol = s:cur_c > len(l:line)
    if l:at_eol
        return l:count
    endif
    " Condition 2 & 3: deletes extend to end of line / end of ops.
    if l:i >= len(a:ops)
        return l:count
    endif
    let l:next_op = a:ops[l:i]
    if l:next_op[0] ==# 'keep' && l:next_op[1] ==# "\n"
        return l:count
    endif
    return 0
endfunction

" Look ahead from op_idx to count contiguous ops of the SAME type as the op
" at op_idx. Stops at the first op of a different type, or at a newline, or
" at end of ops. Used by --highlight-word to know how long the upcoming
" change run is, so it can decide whether to highlight.
" Returns at least 1 (the op at op_idx itself, if it's not a keep/newline).
function! s:LookaheadSameTypeRun(ops, start) abort
    if a:start >= len(a:ops) | return 0 | endif
    let l:first_type = a:ops[a:start][0]
    if l:first_type ==# 'keep' | return 0 | endif
    let l:count = 0
    let l:i = a:start
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] !=# l:first_type | break | endif
        " Stop at newline — that's a line boundary, not part of the word.
        if l:op[1] ==# "\n" | break | endif
        let l:count += 1
        let l:i += 1
    endwhile
    return l:count
endfunction

" Look ahead for a run of identical characters being deleted.
" Returns the count if >= min_threshold, 0 otherwise.
" Used for --rapid-identical-chars: accelerate deletion of sequences
" like "---------------------------" or "=====" rapidly.
function! s:LookaheadIdenticalChars(ops, start) abort
    if !g:diffvim.rapid_identical_chars | return 0 | endif
    if a:start >= len(a:ops) | return 0 | endif
    let l:first_op = a:ops[a:start]
    if l:first_op[0] !=# 'delete' | return 0 | endif
    let l:first_char = l:first_op[1]
    if l:first_char ==# "\n" || l:first_char ==# ' ' || l:first_char ==# "\t" | return 0 | endif
    let l:count = 0
    let l:i = a:start
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] !=# 'delete' | break | endif
        if l:op[1] !=# l:first_char | break | endif
        let l:count += 1
        let l:i += 1
    endwhile
    if l:count >= g:diffvim.rapid_identical_min
        return l:count
    endif
    return 0
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

" --- Accelerated multi-line deletion --------------------------------------
" When --accel-delete is on, multi-line deletions start slow, accelerate to
" a max speed, then decelerate near the end. This prevents large blocks
" from vanishing in one shot while still being fast enough to not bore the
" viewer.
"
" The acceleration uses a triangle profile:
"   - Phase 1 (accelerate): delay = start_ms * accel^count, decreasing
"   - Phase 2 (cruise):     delay = min_ms (max speed)
"   - Phase 3 (decelerate): symmetric to phase 1, starting when we're
"     close to the end of the delete run
"
" Returns the delay in ms for the current delete op.
function! s:ComputeAccelDeleteDelay() abort
    let l:count = s:state.accel_delete_count
    let l:total = s:state.accel_delete_total
    let l:remaining = l:total - l:count
    " Deceleration phase: last 30% of the run, mirror the acceleration
    if l:remaining < l:total * 0.3 && l:remaining > 0
        let l:phase = l:remaining
        let l:delay = g:diffvim.accel_delete_min_ms
        let l:i = 0
        while l:i < l:phase
            let l:delay = l:delay / g:diffvim.accel_delete_accel
            if l:delay > g:diffvim.accel_delete_start_ms
                let l:delay = g:diffvim.accel_delete_start_ms
            endif
            let l:i += 1
        endwhile
        return float2nr(l:delay)
    endif
    " Acceleration phase
    let l:delay = s:state.accel_delete_delay
    if l:delay <= 0
        let l:delay = g:diffvim.accel_delete_start_ms
    else
        let l:delay = l:delay * g:diffvim.accel_delete_accel
        if l:delay < g:diffvim.accel_delete_min_ms
            let l:delay = g:diffvim.accel_delete_min_ms
        endif
    endif
    let s:state.accel_delete_delay = l:delay
    return float2nr(l:delay)
endfunction

" Block-based multi-line deletion: deletes in blocks of N chars (where N
" is block_delete_size * average_line_length), with a pause between blocks.
" The pause starts at pause_before_delete_ms, accelerates, then decelerates.
"
" This is called from ProcessCharOp when --accel-delete is on and a multi-
" line delete run is detected. It deletes one block at a time and schedules
" the next block with a computed delay.
"
" State tracking:
"   s:state.accel_delete_count  — chars deleted so far in this run
"   s:state.accel_delete_total  — total chars to delete in this run
"   s:state.accel_delete_delay  — current delay (for acceleration)
"   s:state.accel_delete_block  — chars deleted in current block
function! s:ProcessBlockDelete(hunk, total_count) abort
    let l:block_size = g:diffvim.block_delete_size

    " On the first block of a multi-line delete run, advance the cursor
    " past leading whitespace so the viewer sees deletion starting at the
    " first non-space character, not at a random indent position.
    if s:state.accel_delete_count == 0
        let l:skipped = 0
        while s:state.op_idx + l:skipped < len(a:hunk.char_ops)
            let l:op = a:hunk.char_ops[s:state.op_idx + l:skipped]
            if l:op[0] ==# 'delete' && (l:op[1] ==# ' ' || l:op[1] ==# "\t")
                " Skip leading whitespace deletes — advance cursor past them
                call s:AdvanceForKeepChar(l:op[1])
                let l:skipped += 1
            else
                break
            endif
        endwhile
        if l:skipped > 0
            let s:state.op_idx += l:skipped
            let s:state.accel_delete_count += l:skipped
            let s:state.accel_delete_total = a:total_count
            redraw
        endif
    endif

    " Find how many chars to delete for block_size lines.
    let l:chars_to_delete = 0
    let l:lines_in_block = 0
    let l:op_idx = s:state.op_idx
    while l:op_idx < len(a:hunk.char_ops) && l:lines_in_block < l:block_size
        let l:op = a:hunk.char_ops[l:op_idx]
        if l:op[0] !=# 'delete' | break | endif
        let l:chars_to_delete += 1
        if l:op[1] ==# "\n"
            let l:lines_in_block += 1
        endif
        let l:op_idx += 1
    endwhile
    if l:chars_to_delete == 0
        let l:chars_to_delete = 1
    endif

    " Delete the block
    for l:i in range(l:chars_to_delete)
        call s:DeleteCharAtCursor()
    endfor
    redraw
    let s:state.op_idx += l:chars_to_delete
    let s:state.accel_delete_count += l:chars_to_delete

    if g:diffvim.sign_column
        call s:PlaceSign('dv_del', s:cur_l)
    endif

    " Compute delay for this block
    let l:remaining = a:total_count - s:state.accel_delete_count
    if l:remaining <= 0
        " Done — reset and pause after
        let s:state.accel_delete_count = 0
        let s:state.accel_delete_delay = 0
        let s:state.accel_delete_total = 0
        let l:delay = g:diffvim.pause_after_delete_ms
    else
        " Compute accel/decel delay
        let l:delay = s:ComputeAccelDeleteDelay()
        " First block uses pause_before_delete_ms
        if s:state.accel_delete_count == l:chars_to_delete
            let l:delay = g:diffvim.pause_before_delete_ms
        endif
    endif
    let l:delay = s:GaussianJitter(l:delay)
    call s:ScheduleNext(l:delay)
endfunction

" Adaptive word-by-word line deletion.
"
" When --adaptive-word-delete is on and a multi-line delete run is detected,
" each line is deleted in 3 phases:
"   Phase 1 (start): delete the first N chars slowly (start_chars chars
"     at start_ms delay each). Lets the user see what is being deleted.
"   Phase 2 (word-by-word): delete word by word. Each word (non-space run)
"     is deleted instantly, followed by a pause. The pause accelerates:
"     word_pause_ms * accel^word_count (decreasing). After each word,
"     word_pause_ms delay.
"   Phase 3 (rest): delete remaining chars (spaces, last partial word)
"     rapidly at min_ms delay.
"
" State tracking:
"   s:state.awd_phase: 0=not started, 1=start chars, 2=word-by-word, 3=rest
"   s:state.awd_delay: current delay for acceleration
"   s:state.awd_word_count: words deleted so far
function! s:ProcessAdaptiveWordDelete(hunk, total_count) abort
    " Skip leading whitespace (advance cursor past indent)
    if s:state.awd_phase == 0
        let l:skipped = 0
        while s:state.op_idx + l:skipped < len(a:hunk.char_ops)
            let l:op = a:hunk.char_ops[s:state.op_idx + l:skipped]
            if l:op[0] ==# 'delete' && (l:op[1] ==# ' ' || l:op[1] ==# "\t")
                call s:AdvanceForKeepChar(l:op[1])
                let l:skipped += 1
            else
                break
            endif
        endwhile
        if l:skipped > 0
            let s:state.op_idx += l:skipped
            let s:state.accel_delete_count += l:skipped
            redraw
        endif
        let s:state.awd_phase = 1
    endif

    " Count remaining delete ops on the current line (until newline or end)
    let l:line_remaining = 0
    let l:op_idx = s:state.op_idx
    while l:op_idx < len(a:hunk.char_ops)
        let l:op = a:hunk.char_ops[l:op_idx]
        if l:op[0] !=# 'delete' | break | endif
        if l:op[1] ==# "\n" | break | endif
        let l:line_remaining += 1
        let l:op_idx += 1
    endwhile

    if l:line_remaining == 0
        " Line done — delete the newline and move to next line
        if s:state.op_idx < len(a:hunk.char_ops)
            let l:op = a:hunk.char_ops[s:state.op_idx]
            if l:op[0] ==# 'delete'
                call s:DeleteCharAtCursor()
                let s:state.op_idx += 1
                let s:state.accel_delete_count += 1
                redraw
            endif
        endif
        " Reset for next line
        let s:state.awd_phase = 0
        let s:state.awd_delay = 0
        let s:state.awd_word_count = 0
        " Check if done
        if s:state.accel_delete_count >= a:total_count
            let s:state.accel_delete_count = 0
            let s:state.accel_delete_total = 0
            let l:delay = g:diffvim.pause_after_delete_ms
        else
            let l:delay = g:diffvim.adaptive_word_delete_word_pause_ms
        endif
        let l:delay = s:GaussianJitter(l:delay)
        call s:ScheduleNext(l:delay)
        return
    endif

    " Phase 1: delete start_chars one by one, slowly
    if s:state.awd_phase == 1
        let l:start_chars = g:diffvim.adaptive_word_delete_start_chars
        if l:line_remaining <= l:start_chars
            " Line is short — go straight to rest phase
            let s:state.awd_phase = 3
        else
            call s:DeleteCharAtCursor()
            redraw
            let s:state.op_idx += 1
            let s:state.accel_delete_count += 1
            " Count how many start chars we have deleted in this line
            let l:phase1_count = 0
            let l:check_idx = s:state.op_idx - 1
            while l:check_idx >= 0
                let l:check_op = a:hunk.char_ops[l:check_idx]
                if l:check_op[0] ==# 'delete' && l:check_op[1] !=# "\n" && l:check_op[1] !=# ' ' && l:check_op[1] !=# "\t"
                    let l:phase1_count += 1
                    let l:check_idx -= 1
                else
                    break
                endif
            endwhile
            if l:phase1_count >= l:start_chars
                let s:state.awd_phase = 2
                let s:state.awd_delay = g:diffvim.adaptive_word_delete_start_ms
            endif
            let l:delay = s:GaussianJitter(g:diffvim.adaptive_word_delete_start_ms)
            call s:ScheduleNext(l:delay)
            return
        endif
    endif

    " Phase 2: word-by-word deletion with acceleration
    if s:state.awd_phase == 2
        " Find the next word boundary: count non-space chars until space or end
        let l:word_len = 0
        let l:op_idx2 = s:state.op_idx
        while l:op_idx2 < len(a:hunk.char_ops)
            let l:op = a:hunk.char_ops[l:op_idx2]
            if l:op[0] !=# 'delete' | break | endif
            if l:op[1] ==# "\n" | break | endif
            if l:op[1] ==# ' ' || l:op[1] ==# "\t" | break | endif
            let l:word_len += 1
            let l:op_idx2 += 1
        endwhile

        if l:word_len == 0
            " No more words — go to rest phase
            let s:state.awd_phase = 3
        else
            " Delete the whole word instantly
            for l:i in range(l:word_len)
                call s:DeleteCharAtCursor()
            endfor
            redraw
            let s:state.op_idx += l:word_len
            let s:state.accel_delete_count += l:word_len
            let s:state.awd_word_count += 1
            " Compute accelerating delay
            let l:delay = s:state.awd_delay
            if l:delay <= 0
                let l:delay = g:diffvim.adaptive_word_delete_start_ms
            else
                let l:delay = l:delay * g:diffvim.adaptive_word_delete_accel
                if l:delay < g:diffvim.adaptive_word_delete_min_ms
                    let l:delay = g:diffvim.adaptive_word_delete_min_ms
                endif
            endif
            let s:state.awd_delay = l:delay
            let l:delay = s:GaussianJitter(float2nr(l:delay))
            if g:diffvim.sign_column
                call s:PlaceSign('dv_del', s:cur_l)
            endif
            call s:ScheduleNext(l:delay)
            return
        endif
    endif

    " Phase 3: delete rest rapidly
    if s:state.awd_phase == 3
        call s:DeleteCharAtCursor()
        redraw
        let s:state.op_idx += 1
        let s:state.accel_delete_count += 1
        let l:delay = s:GaussianJitter(g:diffvim.adaptive_word_delete_min_ms)
        call s:ScheduleNext(l:delay)
        return
    endif
endfunction

" Look ahead to count consecutive delete ops that span whole lines (i.e.,
" the deletes include newlines). Returns the count, or 0 if not a multi-
" line delete run.
function! s:LookaheadMultiLineDelete(ops, start) abort
    let l:i = a:start
    let l:count = 0
    let l:has_newline = 0
    while l:i < len(a:ops)
        let l:op = a:ops[l:i]
        if l:op[0] !=# 'delete' | break | endif
        if l:op[1] ==# "\n" | let l:has_newline = 1 | endif
        let l:count += 1
        let l:i += 1
    endwhile
    " Only treat as multi-line if it spans at least 2 lines and has newlines
    if l:has_newline && l:count >= 2
        return l:count
    endif
    return 0
endfunction

" --- Gaussian jitter ------------------------------------------------------
" Add random variation to a delay for human-like typing.
" Uses a simple Box-Muller transform approximation.
function! s:GaussianJitter(delay_ms) abort
    if !g:diffvim.gaussian_jitter | return a:delay_ms | endif
    let l:pct = g:diffvim.gaussian_jitter_pct
    let l:range = a:delay_ms * l:pct / 100.0
    " Simple approximation: average of two uniforms ~ triangular, close enough
    let l:u1 = rand() * 1.0 / 0x7fffffff
    let l:u2 = rand() * 1.0 / 0x7fffffff
    let l:jitter = (l:u1 + l:u2 - 1.0) * l:range
    let l:result = a:delay_ms + l:jitter
    if l:result < 1 | let l:result = 1 | endif
    return float2nr(l:result)
endfunction

" --- Inline char highlight ------------------------------------------------
" Highlight freshly typed/deleted chars for a short duration.
" Each highlight has its own ID and its own timer. When the timer fires,
" only that specific highlight is cleared. This lets multiple highlights
" coexist and fade independently, so the user can see a trail of recent
" changes instead of only the latest one.
let s:inline_highlights = []  " list of [match_id, timer_id]

function! s:InlineHighlight(line, col, type) abort
    if !g:diffvim.inline_highlight | return | endif
    let l:color = a:type ==# 'insert' ? 'DiffAdd' : 'DiffDelete'
    let l:pos = [[a:line, a:col, 1]]
    let l:match_id = matchaddpos(l:color, l:pos)
    " Schedule this specific highlight to be cleared after the duration
    let l:timer_id = timer_start(
        \ g:diffvim.inline_highlight_duration,
        \ function('s:ClearOneInlineHighlight', [l:match_id]))
    call add(s:inline_highlights, [l:match_id, l:timer_id])
    " Clean up old cleared entries
    call filter(s:inline_highlights, 'v:val[0] != -1')
    " Limit to 50 concurrent highlights to avoid performance issues
    while len(s:inline_highlights) > 50
        let l:old = remove(s:inline_highlights, 0)
        try | call matchdelete(l:old[0]) | catch | endtry
        if l:old[1] != -1
            call timer_stop(l:old[1])
        endif
    endwhile
endfunction

function! s:ClearOneInlineHighlight(match_id, ...) abort
    try | call matchdelete(a:match_id) | catch | endtry
    " Mark as cleared in the list
    for l:h in s:inline_highlights
        if l:h[0] == a:match_id
            let l:h[0] = -1
            let l:h[1] = -1
        endif
    endfor
endfunction

function! s:ClearInlineHighlight(...) abort
    for l:h in s:inline_highlights
        try | call matchdelete(l:h[0]) | catch | endtry
        if l:h[1] != -1
            call timer_stop(l:h[1])
        endif
    endfor
    let s:inline_highlights = []
endfunction

" --- Dim unchanged lines --------------------------------------------------
let s:dim_match_ids = []

function! s:SetupDimUnchanged() abort
    if !g:diffvim.dim_unchanged | return | endif
    call s:ClearDimUnchanged()
    " Define a dim highlight group. The percentage controls how dim:
    " higher = more dim (more gray). We map pct to a ctermfg color:
    " 0-20: color 7 (light gray), 21-40: color 8 (dark gray),
    " 41-60: color 240, 61-80: color 242, 81-100: color 245.
    " For gui, we use a gray hex value interpolated from the pct.
    let l:pct = g:diffvim.dim_unchanged_pct
    let l:cterm = 8
    if l:pct <= 20
        let l:cterm = 7
    elseif l:pct <= 40
        let l:cterm = 8
    elseif l:pct <= 60
        let l:cterm = 240
    elseif l:pct <= 80
        let l:cterm = 242
    else
        let l:cterm = 245
    endif
    " For gui, interpolate gray: 0% = normal, 100% = gray80
    let l:gray_val = float2nr(80 + (255 - 80) * (100 - l:pct) / 100)
    let l:hex = printf('#%02x%02x%02x', l:gray_val, l:gray_val, l:gray_val)
    execute 'highlight diffvimDimUnchanged ctermfg=' . l:cterm . ' guifg=' . l:hex
    " Find all unchanged lines (lines not in any hunk) and dim them
    let l:changed_lines = {}
    for l:h in s:state.hunks
        let l:start = l:h.target_line_old
        " Also include inserted lines in the changed set
        let l:end = l:start + l:h.deleted_count
        if l:h.inserted_count > l:h.deleted_count
            let l:end = l:start + l:h.inserted_count
        endif
        if l:end < l:start | let l:end = l:start | endif
        for l:l in range(l:start, l:end)
            let l:changed_lines[l:l] = 1
        endfor
    endfor
    let l:positions = []
    for l:l in range(1, line('$'))
        if !has_key(l:changed_lines, l:l)
            call add(l:positions, [l:l])
        endif
    endfor
    " Batch in groups of 8 (matchaddpos limit)
    let l:batch = []
    for l:pos in l:positions
        call add(l:batch, l:pos)
        if len(l:batch) == 8
            let l:id = matchaddpos('diffvimDimUnchanged', l:batch)
            call add(s:dim_match_ids, l:id)
            let l:batch = []
        endif
    endfor
    if !empty(l:batch)
        let l:id = matchaddpos('diffvimDimUnchanged', l:batch)
        call add(s:dim_match_ids, l:id)
    endif
    redraw
endfunction

function! s:ClearDimUnchanged(...) abort
    for l:id in s:dim_match_ids
        try | call matchdelete(l:id) | catch | endtry
    endfor
    let s:dim_match_ids = []
endfunction

" --- Startup feedback -----------------------------------------------------
function! s:ShowStartupFeedback(msg) abort
    if !g:diffvim.startup_feedback | return | endif
    echo a:msg
    redraw
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
" Git blame cache — pre-compute blame for all lines at startup instead of
" shelling out per hunk (which blocks the animation timer).
let s:blame_cache = {}

function! s:LoadBlameCache() abort
    let s:blame_cache = {}
    if !g:diffvim.git_blame | return | endif
    let l:file = expand('%:p')
    if empty(l:file) | return | endif
    " Run git blame once for the entire file. This is much faster than
    " per-line calls during animation.
    let l:cmd = 'git blame -- ' . shellescape(l:file) . ' 2>/dev/null'
    let l:result = systemlist(l:cmd)
    if v:shell_error != 0 || empty(l:result) | return | endif
    " Parse "hash (author date line) content" format into a per-line cache.
    let l:line_num = 1
    for l:line in l:result
        " git blame output: ^hash (Author Name 2024-01-15 12:34:56 +0000 1) content
        " or: hash (Author Name 2024-01-15 12:34:56 +0000 1) content
        let l:blame = substitute(l:line, '^\^', '', '')
        let s:blame_cache[l:line_num] = l:blame
        let l:line_num += 1
    endfor
endfunction

function! s:ShowGitBlame(line) abort
    " Use the pre-computed blame cache if available.
    if has_key(s:blame_cache, a:line)
        echo 'diffvim blame: ' . s:blame_cache[a:line]
        return
    endif
    " Fallback: if cache miss (e.g., line beyond file), shell out.
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

" Word highlighting (--highlight-word): highlight the word at the cursor
" position before a delete or insert op touches it. Finer-grained than
" --highlight-hunk: shows exactly which token is about to change.
"
" A "word" here is the maximal run of non-whitespace characters that
" contains the cursor. If the cursor is on whitespace, no highlight is
" applied (there's no word to highlight).
let s:word_highlight_ids = []
let s:word_highlight_timer = -1

function! s:ClearWordHighlight(...) abort
    for l:id in s:word_highlight_ids
        try
            call matchdelete(l:id)
        catch
        endtry
    endfor
    let s:word_highlight_ids = []
    if s:word_highlight_timer != -1
        call timer_stop(s:word_highlight_timer)
        let s:word_highlight_timer = -1
    endif
    redraw
endfunction

" Highlight the word at the current cursor position (s:cur_l, s:cur_c).
" The word is the maximal run of non-whitespace chars containing the cursor.
" If the upcoming op is a delete/insert of length >= min_chars, the word is
" highlighted for `duration` ms. Returns 1 if a highlight was applied.
function! s:HighlightCurrentWord(op_type, op_count) abort
    if !g:diffvim.highlight_word | return 0 | endif
    " Only highlight for delete/insert ops, not keep.
    if a:op_type !=# 'delete' && a:op_type !=# 'insert' | return 0 | endif
    " Don't highlight if the change is too small.
    if a:op_count < g:diffvim.highlight_word_min_chars | return 0 | endif
    " Don't highlight newlines (no word to show).
    let l:line = getline(s:cur_l)
    let l:line_len = len(l:line)
    if l:line_len == 0 | return 0 | endif
    " Clamp cursor column to the line.
    let l:c = s:cur_c
    if l:c < 1 | let l:c = 1 | endif
    if l:c > l:line_len | let l:c = l:line_len | endif
    " If cursor is on whitespace, no word to highlight.
    let l:ch_at = l:line[l:c - 1]
    if l:ch_at ==# ' ' || l:ch_at ==# "\t" | return 0 | endif
    " Find word start: walk left while non-whitespace.
    let l:start_c = l:c
    while l:start_c > 1 && l:line[l:start_c - 2] !=# ' ' && l:line[l:start_c - 2] !=# "\t"
        let l:start_c -= 1
    endwhile
    " Find word end: walk right while non-whitespace.
    let l:end_c = l:c
    while l:end_c < l:line_len && l:line[l:end_c] !=# ' ' && l:line[l:end_c] !=# "\t"
        let l:end_c += 1
    endwhile
    " matchaddpos uses [line, col, length] form.
    let l:word_len = l:end_c - l:start_c + 1
    if l:word_len < g:diffvim.highlight_word_min_chars | return 0 | endif
    call s:ClearWordHighlight()
    let l:pos = [[s:cur_l, l:start_c, l:word_len]]
    let l:id = matchaddpos(g:diffvim.highlight_word_color, l:pos)
    call add(s:word_highlight_ids, l:id)
    redraw
    " Schedule clear after the configured duration.
    let s:word_highlight_timer = timer_start(
        \ g:diffvim.highlight_word_duration,
        \ function('s:ClearWordHighlight'))
    return 1
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

    " If between hunks (idle), jump to the next hunk target and apply it
    if s:state.phase ==# 'idle'
        " Start the next hunk to position cursor and set cur_hunk
        let l:hunk = s:state.hunks[s:state.hunk_idx]
        let s:state.cur_hunk = l:hunk
        let l:target_line = l:hunk.target_line_old + s:state.line_offset
        if l:hunk.is_end_insert && l:target_line > line('$')
            let s:cur_l = line('$') | let s:cur_c = len(getline(line('$'))) + 1
        elseif l:hunk.is_end_delete
            let l:prev = l:target_line - 1
            if l:prev < 1 | let l:prev = 1 | endif
            if l:prev > line('$') | let l:prev = line('$') | endif
            let s:cur_l = l:prev | let s:cur_c = len(getline(l:prev)) + 1
        else
            let l:tl = l:target_line
            if l:tl < 1 | let l:tl = 1 | endif
            if l:tl > line('$') | let l:tl = line('$') | endif
            let s:cur_l = l:tl | let s:cur_c = 1
        endif
        call s:PlaceCursor()
        let s:state.op_idx = 0
        let s:state.phase = 'typing'
    endif

    " If moving, jump to end of move first
    if s:state.phase ==# 'moving'
        let s:cur_l = s:state.move_end_l
        let s:cur_c = s:state.move_end_c
        call s:PlaceCursor()
        let s:state.phase = 'typing'
        let s:state.op_idx = 0
    endif

    " Apply all remaining char_ops in this hunk instantly
    if s:state.phase ==# 'typing'
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

    " PAUSE after applying — user must press Space or n to continue
    let s:state.paused = 1
    echo 'diffvim: hunk applied — paused (Space=resume, n=next hunk, b=back)'
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
    " By default, mark the buffer as not modified so ':q' quits cleanly.
    " Use --keep-dirty to leave the buffer modified (then ':q!' is required).
    if !g:diffvim.keep_dirty
        set nomodified
    endif
    silent! nunmap <buffer> <Space>
    silent! nunmap <buffer> n
    silent! nunmap <buffer> b
    silent! nunmap <buffer> q
    silent! nunmap <buffer> ?
    silent! nunmap <buffer> +
    silent! nunmap <buffer> -
    silent! nunmap <buffer> =
    if g:diffvim.keep_dirty
        echo 'diffvim: animation stopped. Buffer is modified — use :q! to quit.'
    else
        echo 'diffvim: animation stopped. Buffer left in current state — :q to quit.'
    endif
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

" --- Multi-file navigation ------------------------------------------------

let s:file_pairs = []
let s:cur_file_idx = 0

function! s:SetFilePairs(pairs) abort
    let s:file_pairs = a:pairs
    let s:cur_file_idx = 0
endfunction

function! s:NextFile() abort
    if empty(s:file_pairs)
        echo 'diffvim: no multi-file pairs'
        return
    endif
    if s:cur_file_idx >= len(s:file_pairs) - 1
        echo 'diffvim: already at last file'
        return
    endif
    " Apply all remaining hunks instantly
    call s:StopTimer()
    while s:state.phase !=# 'done' && !s:state.stopped
        if s:state.phase ==# 'idle'
            call s:StartNextHunk()
        elseif s:state.phase ==# 'moving'
            let s:cur_l = s:state.move_end_l
            let s:cur_c = s:state.move_end_c
            call s:PlaceCursor()
            let s:state.phase = 'typing'
            let s:state.op_idx = 0
        elseif s:state.phase ==# 'typing'
            call s:ApplyHunkInstantly()
        endif
    endwhile
    " Load next file
    let s:cur_file_idx += 1
    let l:pair = s:file_pairs[s:cur_file_idx]
    let l:old = l:pair[0]
    let l:new = l:pair[1]
    " Edit the new old file
    execute 'edit! ' . l:old
    let g:diffvim_new_file = l:new
    call s:StartAnimation()
    echo 'diffvim: file ' . (s:cur_file_idx + 1) . '/' . len(s:file_pairs)
endfunction

function! s:PrevFile() abort
    if empty(s:file_pairs)
        echo 'diffvim: no multi-file pairs'
        return
    endif
    if s:cur_file_idx <= 0
        echo 'diffvim: already at first file'
        return
    endif
    call s:StopTimer()
    let s:cur_file_idx -= 1
    let l:pair = s:file_pairs[s:cur_file_idx]
    let l:old = l:pair[0]
    let l:new = l:pair[1]
    execute 'edit! ' . l:old
    let g:diffvim_new_file = l:new
    call s:StartAnimation()
    echo 'diffvim: file ' . (s:cur_file_idx + 1) . '/' . len(s:file_pairs)
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
nnoremap <buffer> <silent> ]       :call <SID>NextFile()<CR>
nnoremap <buffer> <silent> [       :call <SID>PrevFile()<CR>

" --- Autostart -------------------------------------------------------------

function! s:StartAnimation() abort
    " Set up syntax highlighting for the file
    call s:SetupSyntax()
    " Pre-compute git blame cache if --git-blame is enabled (batch, not per-hunk)
    call s:LoadBlameCache()
    " Startup feedback: show progress during diff computation
    call s:ShowStartupFeedback('diffvim: computing diff...')
    " Compute the diff.
    let s:state.hunks = s:BuildHunks()
    call s:ShowStartupFeedback('diffvim: ' . len(s:state.hunks) . ' hunk(s) found')
    if empty(s:state.hunks)
        echo 'diffvim: files are identical, nothing to animate'
        return
    endif
    " --dim-unchanged: dim unchanged anchor lines
    call s:SetupDimUnchanged()
    " --sign-column: define signs for add/delete/modify.
    if g:diffvim.sign_column
        sign define dv_add text=+ texthl=DiffAdd
        sign define dv_del text=- texthl=DiffDelete
        sign define dv_mod text=* texthl=DiffChange
    endif
    let s:state.hunk_idx = 0
    let s:state.line_offset = 0
    let s:state.phase = 'idle'
    let s:state.stopped = 0
    let s:state.paused = g:diffvim.step_mode ? 1 : 0
    let s:cur_l = line('.')
    let s:cur_c = col('.')
    " Show config and help ONLY if --startup-pause is explicitly requested.
    " Default: no startup messages, start animating immediately.
    if g:diffvim.startup_pause
        call s:ShowConfig()
        call s:ShowHelp()
        call s:ScheduleNext(300)
    else
        " Silent startup: just start the animation after a minimal tick
        " so vim has time to render the buffer.
        if g:diffvim.step_mode
            echo 'diffvim: step mode — press Space to advance'
        endif
        call s:ScheduleNext(50)
    endif
endfunction

" Set up syntax highlighting based on --language option or auto-detection.
function! s:SetupSyntax() abort
    let l:lang = $DIFFVIM_LANGUAGE
    if empty(l:lang) || l:lang ==# 'auto'
        let l:ext = fnamemodify(expand('%'), ':e')
        let l:lang = s:DetectFiletype(l:ext)
    endif
    if !empty(l:lang)
        " Set filetype — this triggers syntax highlighting automatically
        " because 'syntax enable' was called in the mini vimrc.
        " Using setfiletype avoids re-triggering the filetype autocommand
        " group (which may not exist with -u NONE).
        let &l:filetype = l:lang
        " Also set syntax directly as a fallback
        let &l:syntax = l:lang
    endif
endfunction

" Detect vim filetype from file extension.
function! s:DetectFiletype(ext) abort
    let l:ft_map = {
        \ 'py': 'python', 'pyw': 'python',
        \ 'js': 'javascript', 'mjs': 'javascript', 'cjs': 'javascript',
        \ 'ts': 'typescript', 'tsx': 'typescript',
        \ 'java': 'java',
        \ 'kt': 'kotlin', 'kts': 'kotlin',
        \ 'swift': 'swift',
        \ 'rb': 'ruby',
        \ 'php': 'php',
        \ 'scala': 'scala', 'sbt': 'scala',
        \ 'ex': 'elixir', 'exs': 'elixir',
        \ 'clj': 'clojure', 'cljs': 'clojure', 'cljc': 'clojure',
        \ 'hs': 'haskell',
        \ 'lua': 'lua',
        \ 'pl': 'perl', 'pm': 'perl',
        \ 'r': 'r', 'R': 'r',
        \ 'sql': 'sql',
        \ 'go': 'go',
        \ 'rs': 'rust',
        \ 'c': 'c', 'h': 'c',
        \ 'cpp': 'cpp', 'cc': 'cpp', 'cxx': 'cpp', 'hpp': 'cpp',
        \ 'cs': 'cs',
        \ 'sh': 'sh', 'bash': 'sh', 'zsh': 'sh',
        \ 'json': 'json',
        \ 'yaml': 'yaml', 'yml': 'yaml',
        \ 'xml': 'xml',
        \ 'html': 'html', 'htm': 'html',
        \ 'css': 'css',
        \ 'toml': 'toml',
        \ 'md': 'markdown', 'markdown': 'markdown',
        \ 'txt': 'text',
        \ 'vim': 'vim',
        \ 'ml': 'ocaml', 'mli': 'ocaml',
        \ 'dart': 'dart',
        \ 'groovy': 'groovy', 'gradle': 'groovy',
        \ 'dockerfile': 'dockerfile',
        \ 'makefile': 'make', 'mk': 'make',
        \ }
    return get(l:ft_map, a:ext, '')
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
    if g:diffvim.rapid_eol_delete
        let l:msg .= '  rapid_eol=on(' . g:diffvim.rapid_eol_delay_ms . 'ms,' . g:diffvim.rapid_eol_min_chars . '+)'
    else
        let l:msg .= '  rapid_eol=off'
    endif
    if g:diffvim.keep_dirty
        let l:msg .= '  keep_dirty=on(:q!)'
    else
        let l:msg .= '  keep_dirty=off(:q)'
    endif
    if g:diffvim.highlight_word
        let l:msg .= '  highlight_word=on(' . g:diffvim.highlight_word_color . ',' . g:diffvim.highlight_word_duration . 'ms)'
    endif
    echo l:msg
endfunction


" Public entry point
function! diffvim#engine#Start() abort
    call s:StartAnimation()
endfunction
