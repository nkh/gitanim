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
    --rapid-eol-min-chars

# Complete flags
for cmd in diffvim diffvim-tmux diffvim.pl
    complete -c $cmd -f -a "$diffvim_flags"

    # Options with values
    complete -c $cmd -f -r -a "perl diff2html" -d "Diff parser" -n '__fish_seen_argument --parser -c $cmd'
    complete -c $cmd -f -r -a "zz zt zb none" -d "Scroll position" -n '__fish_seen_argument --scroll -c $cmd'
    complete -c $cmd -f -r -a "0.5 1 2 3 5" -d "Speed multiplier" -n '__fish_seen_argument --speed -c $cmd'

    # Options that take file paths
    for opt in --output
        complete -c $cmd -f -r -F -n "__fish_seen_argument $opt -c $cmd"
    end

    # Positional file arguments
    complete -c $cmd -f -F
end
