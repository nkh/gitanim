#!/bin/bash
# Bash completion for diffvim / diffvim-tmux / diffvim.pl
#
# Install:
#   sudo cp completion/diffvim.bash /etc/bash_completion.d/diffvim
#   # or
#   source completion/diffvim.bash

_diffvim_complete() {
    local cur prev opts
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Options that take arguments
    case "$prev" in
        --parser)
            COMPREPLY=( $(compgen -W "perl diff2html" -- "$cur") )
            return 0
            ;;
        --scroll)
            COMPREPLY=( $(compgen -W "zz zt zb none" -- "$cur") )
            return 0
            ;;
        --speed)
            COMPREPLY=( $(compgen -W "0.5 1 2 3 5" -- "$cur") )
            return 0
            ;;
        --output|--from|--to|--git-rev|--max-hunk-chars|--max-word-chars|--word-pause-ms|--context|--max-line-len|--rapid-eol-delay-ms|--rapid-eol-min-chars)
            # File path or value
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
    esac

    # Options
    if [[ "$cur" == --* ]]; then
        opts="--parser --speed --output --context --max-hunk-chars --max-word-chars
              --word-pause-ms --scroll --multi --replay --from --to --git-rev
              --no-tmux --dry-run --sign-column --git-blame --step-mode
              --max-line-len --adaptive-timing --word-diff
              --rapid-eol-delete --no-rapid-eol-delete --rapid-eol-delay-ms --rapid-eol-min-chars
              --keep-dirty --version --help"
        COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
        return 0
    fi

    # File paths
    COMPREPLY=( $(compgen -f -- "$cur") )
}
complete -F _diffvim_complete diffvim
complete -F _diffvim_complete diffvim-tmux
complete -F _diffvim_complete diffvim.pl
