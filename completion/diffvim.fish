# Fish completion for diffvim / diffvim-tmux / diffvim.pl
#
# Install:
#   cp completion/diffvim.fish ~/.config/fish/completions/

# Options that don't take arguments
set -l diffvim_flags \
    --multi \
    --replay \
    --no-tmux \
    --dry-run \
    --sign-column \
    --git-blame \
    --step-mode \
    --adaptive-timing \
    --word-diff \
    --rapid-eol-delete \
    --no-rapid-eol-delete \
    --keep-dirty \
    --highlight-word \
    --highlight-inline \
    --highlight-hunk \
    --dim-unchanged \
    --fold-unchanged \
    --delete-end-first \
    --delete-end-first-smart \
    --overwrite \
    --adaptive-word-delete \
    --accel-delete \
    --rapid-identical-chars \
    --word-accel \
    --optimize-sequence \
    --no-optimize-sequence \
    --left-to-right \
    --no-left-to-right \
    --semantic-cleanup \
    --indent-aware \
    --auto-precompute \
    --startup-feedback \
    --no-vimrc \
    --no-log-timing \
    --version \
    --help \
    -h \
    -V

# Options that take arguments
set -l diffvim_opts \
    --parser \
    --speed \
    --output \
    --context \
    --max-hunk-chars \
    --max-word-chars \
    --word-pause-ms \
    --scroll \
    --from \
    --to \
    --git-rev \
    --max-line-len \
    --rapid-eol-delay-ms \
    --rapid-eol-min-chars \
    --highlight-word-color \
    --highlight-word-duration-ms \
    --highlight-word-min-chars \
    --highlight-inline-duration-ms \
    --dim-unchanged-pct \
    --delete-end-first-delay-ms \
    --delete-end-first-highlight-ms \
    --adaptive-word-delete-threshold \
    --adaptive-word-delete-start-chars \
    --adaptive-word-delete-start-ms \
    --adaptive-word-delete-min-ms \
    --adaptive-word-delete-accel \
    --adaptive-word-delete-word-pause-ms \
    --accel-delete-start-ms \
    --accel-delete-min-ms \
    --accel-delete-accel \
    --rapid-identical-min \
    --rapid-identical-accel \
    --word-accel-delete-pct \
    --word-end-pause-ms \
    --line-change-pause-ms \
    --pause-after-lines \
    --pause-after-ms \
    --pause-after-threshold \
    --pause-after-delete-ms \
    --algorithm \
    --preset \
    --precomputed \
    --diff \
    --theme \
    --debug

# Complete flags
for cmd in diffvim diffvim-tmux diffvim.pl
    complete -c $cmd -f -a "$diffvim_flags"

    # Options with values
    complete -c $cmd -f -r -a "perl" -d "Diff parser" -n '__fish_seen_argument --parser -c $cmd'
    complete -c $cmd -f -r -a "zz zt zb none" -d "Scroll position" -n '__fish_seen_argument --scroll -c $cmd'
    complete -c $cmd -f -r -a "0.5 1 2 3 5" -d "Speed multiplier" -n '__fish_seen_argument --speed -c $cmd'

    # Options that take file paths
    for opt in --output
        complete -c $cmd -f -r -F -n "__fish_seen_argument $opt -c $cmd"
    end

    # Positional file arguments
    complete -c $cmd -f -F
end
