# completion/

Shell completions for `ad_vim`.

## Contents

- `ad_vim.bash` — bash completion
- `ad_vim.fish` — fish completion
- `_ad_vim` — zsh completion

## Installation

    make install-comp    # installs to $(PREFIX)/share/bash-completion/completions/

Or manually:

    cp completion/ad_vim.bash /etc/bash_completion.d/ad_vim
    cp completion/_ad_vim /usr/local/share/zsh/site-functions/
    cp completion/ad_vim.fish ~/.config/fish/completions/
