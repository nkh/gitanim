# ad_write_vimconfig.sh — Helper to write a vimscript-readable config file.
#
# Source this from a launcher (ad_vim, ad_vim.pl) after parsing CLI flags
# and sourcing the user/system config. It writes the final values of all
# animation variables to a temp file as vimscript `let` statements.
#
# The vimscript engine then reads this file via `:source` and gets every
# value as a vimscript variable — no env vars needed.
#
# Usage:
#   source packaging/ad_write_vimconfig.sh
#   ad_write_vimconfig /tmp/ad_config_$$
#   vim ... --cmd "let g:ad_config_file='/tmp/ad_config_$$'"
#   rm -f /tmp/ad_config_$$
#
# The temp file is vimscript (not bash) — it uses `let` statements so
# vim can `:source` it directly.

ad_write_vimconfig() {
    local out_file="$1"
    [[ -z "$out_file" ]] && return 1

    # Helper: write a string variable (quoted)
    _ad_vstr() {
        printf 'let g:ad_%s = "%s"\n' "$1" "$2"
    }
    # Helper: write a numeric variable (unquoted)
    _ad_vnum() {
        printf 'let g:ad_%s = %s\n' "$1" "${2:-0}"
    }
    # Helper: write a boolean variable (0 or 1)
    _ad_vbool() {
        local val="0"
        [[ "$2" == "1" || "$2" == "true" ]] && val="1"
        printf 'let g:ad_%s = %s\n' "$1" "$val"
    }

    {
        # ── Pacing ──────────────────────────────────────────────────
        _ad_vstr delete_pacing    "${DELETE_PACING:-word}"
        _ad_vstr insert_pacing    "${INSERT_PACING:-char}"
        _ad_vstr pacing           "${PACING:-uniform}"
        _ad_vstr delete_speed     "${DELETE_SPEED:-normal}"
        _ad_vstr insert_speed     "${INSERT_SPEED:-normal}"
        _ad_vnum delete_threshold "${DELETE_THRESHOLD:-3}"

        # ── Timing (ms) ─────────────────────────────────────────────
        _ad_vnum tick_ms           "${AD_TICK_MS:-16}"
        _ad_vnum type_delay_ms     "${AD_TYPE_DELAY_MS:-50}"
        _ad_vnum delete_delay_ms   "${AD_DELETE_DELAY_MS:-40}"
        _ad_vnum move_min_ms       "${AD_MOVE_MIN_MS:-200}"
        _ad_vnum move_max_ms       "${AD_MOVE_MAX_MS:-2000}"
        _ad_vnum move_ms_per_unit  "${AD_MOVE_MS_PER_UNIT:-1}"
        _ad_vnum hunk_pause_ms     "${AD_HUNK_PAUSE_MS:-250}"
        _ad_vnum word_pause_ms     "${AD_WORD_PAUSE_MS:-150}"

        # ── Layer chain ─────────────────────────────────────────────
        _ad_vbool indent_last          "${INDENT_LAST:-0}"
        _ad_vbool overwrite_mode       "${OVERWRITE_MODE:-0}"
        _ad_vbool line_delete_in_place  "${LINE_DELETE_IN_PLACE:-0}"

        # ── Animation behavior ──────────────────────────────────────
        _ad_vbool left_to_right    "${LEFT_TO_RIGHT:-0}"
        _ad_vnum speed_mult_x1000  "$(awk "BEGIN { printf \"%d\", (${SPEED:-1.0} * 1000) }")"
        _ad_vstr scroll            "${SCROLL:-zz}"
        _ad_vnum max_line_len      "${MAX_LINE_LEN:-10000}"
        _ad_vnum max_hunk_chars    "${MAX_HUNK_CHARS:-0}"

        # ── Cursor movement ──────────────────────────────────────────
        _ad_vnum cursor_glide_ms              "${CURSOR_GLIDE_MS:-0}"
        _ad_vbool cursor_glide_show_intermediate "${CURSOR_GLIDE_SHOW_INTERMEDIATE:-1}"
        _ad_vstr distance_speed               "${DISTANCE_SPEED:-off}"
        _ad_vnum distance_threshold           "${DISTANCE_THRESHOLD:-5}"
        _ad_vstr distance_fast_mult           "${DISTANCE_FAST_MULT:-2.0}"
        _ad_vstr distance_slow_mult           "${DISTANCE_SLOW_MULT:-0.5}"

        # ── Decoration ──────────────────────────────────────────────
        _ad_vstr highlight_mode       "${HIGHLIGHT_MODE:-none}"
        _ad_vnum highlight_duration_ms "${HIGHLIGHT_DURATION_MS:-200}"
        _ad_vbool dim_unchanged       "${DIM_UNCHANGED:-0}"
        _ad_vnum dim_unchanged_pct    "${DIM_UNCHANGED_PCT:-60}"
        _ad_vnum context_lines        "${CONTEXT_LINES:-0}"
        _ad_vbool fold_unchanged      "${FOLD_UNCHANGED:-0}"
        _ad_vbool sign_column         "${SIGN_COLUMN:-0}"
        _ad_vbool git_blame           "${GIT_BLAME:-0}"
        _ad_vstr highlight_color      "${HIGHLIGHT_COLOR:-DiffChange}"
        _ad_vnum highlight_min_chars  "${HIGHLIGHT_MIN_CHARS:-10}"

        # ── Accel delete ─────────────────────────────────────────────
        _ad_vbool accel_delete                "${ACCEL_DELETE:-0}"
        _ad_vnum accel_delete_start_ms        "${ACCEL_DELETE_START_MS:-80}"
        _ad_vnum accel_delete_min_ms          "${ACCEL_DELETE_MIN_MS:-15}"
        _ad_vstr accel_delete_accel           "${ACCEL_DELETE_ACCEL:-0.85}"

        # ── Block delete ─────────────────────────────────────────────
        _ad_vnum block_delete_size            "${BLOCK_DELETE_SIZE:-3}"
        _ad_vnum pause_before_delete_ms       "${PAUSE_BEFORE_DELETE_MS:-200}"
        _ad_vnum pause_after_delete_ms        "${PAUSE_AFTER_DELETE_MS:-200}"

        # ── Flash ───────────────────────────────────────────────────
        _ad_vnum flash_pause_ms      "${FLASH_PAUSE_MS:-400}"
        _ad_vnum flash_highlight_ms  "${FLASH_HIGHLIGHT_MS:-300}"

        # ── Pause after lines ───────────────────────────────────────
        _ad_vnum pause_after_lines     "${PAUSE_AFTER_LINES:-0}"
        _ad_vnum pause_after_threshold "${PAUSE_AFTER_THRESHOLD:-50}"
        _ad_vnum pause_after_ms        "${PAUSE_AFTER_MS:-500}"

        # ── Gaussian jitter ─────────────────────────────────────────
        _ad_vbool gaussian_jitter     "${GAUSSIAN_JITTER:-0}"
        _ad_vnum gaussian_jitter_pct  "${GAUSSIAN_JITTER_PCT:-20}"

        # ── Adaptive ────────────────────────────────────────────────
        _ad_vbool adaptive_mode       "${ADAPTIVE_MODE:-0}"
        _ad_vnum adaptive_start_ms    "${ADAPTIVE_START_MS:-80}"
        _ad_vnum adaptive_max_ms      "${ADAPTIVE_MAX_MS:-250}"
        _ad_vstr adaptive_accel       "${ADAPTIVE_ACCEL:-0.85}"
        _ad_vnum adaptive_pause_lines "${ADAPTIVE_PAUSE_LINES:-0}"
        _ad_vnum adaptive_pause_ms    "${ADAPTIVE_PAUSE_MS:-0}"
        _ad_vbool adaptive_timing     "${ADAPTIVE_TIMING:-0}"

        # ── Output ──────────────────────────────────────────────────
        _ad_vstr output_file   "${OUTPUT_FILE:-}"
        _ad_vstr snapshot_file "${SNAPSHOT_FILE:-}"
        _ad_vbool keep_dirty   "${KEEP_DIRTY:-0}"
        _ad_vstr timed_ops_file "${TIMED_OPS:-}"

        # ── Misc ────────────────────────────────────────────────────
        _ad_vstr theme       "${THEME:-}"
        _ad_vstr log_mode    "${LOG_MODE:-}"
        _ad_vstr log_file    "${LOG_FILE:-}"
        _ad_vbool debug_mode "${DEBUG_MODE:-0}"
        _ad_vbool no_vimrc   "${NO_VIMRC:-0}"
        _ad_vbool bell_on_error "${BELL_ON_ERROR:-0}"
        _ad_vbool diff_stat  "${DIFF_STAT:-0}"
        _ad_vbool diff_highlight "${DIFF_HIGHLIGHT:-0}"
    } > "$out_file"
}
