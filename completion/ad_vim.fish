# Fish completion for ad_vim / ad_tmux / ad_vim.pl
#
# Install:
#   cp completion/ad_vim.fish ~/.config/fish/completions/

# Options that don't take arguments
set -l ad_vim_flags \
    --multi \
    --replay \
    --dry-run \
    --sign-column \
    --git-blame \
    --step-mode \
    --no-startup-pause \
    --word-diff \
    --keep-dirty \
    --startup-feedback \
    --startup-pause \
    --no-vimrc \
    --no-log-timing \
    --debug \
    --version \
    --help \
    -h \
    -V

# Options that take arguments
set -l ad_vim_opts \
    --speed \
    --output \
    --context \
    --max-hunk-chars \
    --scroll \
    --git-rev \
    --language \
    --max-line-len \
    --precomputed \
    --delete-pacing \
    --delete-speed \
    --delete-threshold \
    --insert-pacing \
    --insert-speed \
    --pacing \
    --highlight \
    --highlight-color \
    --highlight-duration-ms \
    --dim-unchanged \
    --dim-unchanged-pct \
    --theme \
    --preset \
    --log-mode \
    --log-file \
    --diff

# Complete flags
for cmd in ad_vim ad_tmux ad_vim.pl
    complete -c $cmd -f -a "$ad_vim_flags"

    # Options with values
    complete -c $cmd -f -r -a "perl" -d "Diff parser" -n '__fish_seen_argument --parser -c $cmd'
    complete -c $cmd -f -r -a "zz zt zb none" -d "Scroll position" -n '__fish_seen_argument --scroll -c $cmd'
    # (algorithm removed — patience is the only algorithm)
    complete -c $cmd -f -r -a "char rapid-eol rapid-identical accel word instant" -d "Delete pacing" -n '__fish_seen_argument --delete-pacing -c $cmd'
    complete -c $cmd -f -r -a "slow normal fast instant" -d "Delete speed" -n '__fish_seen_argument --delete-speed -c $cmd'
    complete -c $cmd -f -r -a "char word accel" -d "Insert pacing" -n '__fish_seen_argument --insert-pacing -c $cmd'
    complete -c $cmd -f -r -a "slow normal fast" -d "Insert speed" -n '__fish_seen_argument --insert-speed -c $cmd'
    complete -c $cmd -f -r -a "uniform adaptive gaussian review" -d "Timing mode" -n '__fish_seen_argument --pacing -c $cmd'
    complete -c $cmd -f -r -a "none inline word hunk" -d "Highlight mode" -n '__fish_seen_argument --highlight -c $cmd'
    complete -c $cmd -f -r -a "dark light high-contrast" -d "Color theme" -n '__fish_seen_argument --theme -c $cmd'
    complete -c $cmd -f -r -a "fast-delete review demo ai-code custom" -d "Preset" -n '__fish_seen_argument --preset -c $cmd'
    complete -c $cmd -f -r -a "0.5 1 2 3 5" -d "Speed multiplier" -n '__fish_seen_argument --speed -c $cmd'

    # Options that take file paths
    for opt in --output --precomputed --log-file --diff
        complete -c $cmd -f -r -F -n "__fish_seen_argument $opt -c $cmd"
    end

    # Positional file arguments
    complete -c $cmd -f -F
end
