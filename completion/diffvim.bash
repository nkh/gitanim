#!/usr/bin/env bash
# Bash completion for diffvim / diffvim-tmux / diffvim.pl
#
# Install:
#   cp completion/diffvim.bash /etc/bash_completion.d/diffvim
# or:
#   cp completion/diffvim.bash ~/.bash_completion.d/diffvim

_diffvim() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Options that take arguments
    case "$prev" in
        --parser)
            COMPREPLY=( $(compgen -W "perl" -- "$cur") )
            return 0
            ;;
        --scroll)
            COMPREPLY=( $(compgen -W "zz zt zb none" -- "$cur") )
            return 0
            ;;
        --delete-pacing)
            COMPREPLY=( $(compgen -W "char rapid-eol rapid-identical accel word instant" -- "$cur") )
            return 0
            ;;
        --delete-speed)
            COMPREPLY=( $(compgen -W "slow normal fast instant" -- "$cur") )
            return 0
            ;;
        --insert-pacing)
            COMPREPLY=( $(compgen -W "char word accel" -- "$cur") )
            return 0
            ;;
        --insert-speed)
            COMPREPLY=( $(compgen -W "slow normal fast" -- "$cur") )
            return 0
            ;;
        --pacing)
            COMPREPLY=( $(compgen -W "uniform adaptive gaussian review" -- "$cur") )
            return 0
            ;;
        --highlight)
            COMPREPLY=( $(compgen -W "none inline word hunk" -- "$cur") )
            return 0
            ;;
        --theme|-t)
            COMPREPLY=( $(compgen -W "dark light high-contrast" -- "$cur") )
            return 0
            ;;
        --preset|-p)
            COMPREPLY=( $(compgen -W "fast-delete review demo ai-code custom" -- "$cur") )
            return 0
            ;;
        --log-mode)
            COMPREPLY=( $(compgen -W "1 2" -- "$cur") )
            return 0
            ;;
        --output|-o|--precomputed|--log-file|--diff|--language)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    # Options
    if [[ "$cur" == --* ]]; then
        opts="--speed -s --output -o --context -c --max-hunk-chars --scroll
              --multi -m --replay -r --git-rev -R --version -V --dry-run -d
              --word-diff -w --step-mode --no-startup-pause --language
              --sign-column --git-blame -g --max-line-len --keep-dirty
              --no-vimrc -N --precomputed --startup-pause --startup-feedback -F
              --delete-pacing --delete-speed --delete-threshold
              --insert-pacing --insert-speed --pacing --highlight
              --highlight-color --highlight-duration-ms
              --dim-unchanged -D --dim-unchanged-pct
              --theme -t --preset -p --log-mode --log-file --no-log-timing
              --diff --debug --help -h"
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # File paths
    COMPREPLY=( $(compgen -f -- "$cur") )
}

complete -F _diffvim diffvim
complete -F _diffvim diffvim-tmux
complete -F _diffvim diffvim.pl
