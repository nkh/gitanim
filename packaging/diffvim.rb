# Homebrew formula for diffvim
# Install with: brew install ./packaging/diffvim.rb
# Or: brew tap nkh/gitanim && brew install diffvim
#
# This formula installs all three diffvim implementations:
#   - diffvim       (Bash + Vimscript, no tmux needed)
#   - diffvim-tmux  (Bash + tmux)
#   - diffvim.pl    (Perl + tmux, pure-Perl LCS parser)

class Diffvim < Formula
  desc "Animate a code diff in vim as if a human were typing it"
  homepage "https://github.com/nkh/gitanim"
  url "https://github.com/nkh/gitanim/archive/refs/heads/main.zip"
  version "1.3.0"
  sha256 "placeholder"
  license "MIT"
  head "https://github.com/nkh/gitanim.git", branch: "main"

  depends_on "vim"
  depends_on "tmux"
  depends_on "perl"

  def install
    # Install the three main scripts
    bin.install "diffvim"
    bin.install "diffvim-tmux"
    bin.install "diffvim.pl"

    # Install the Perl module (pure-Perl LCS parser)
    (lib/"perl5"/"DiffVim"/"Parser").install "DiffVim/Parser/Perl.pm"

    # Install the vim plugin
    (prefix/"plugin").install "plugin/diffvim.vim"
    (prefix/"autoload"/"diffvim").install "autoload/diffvim/engine.vim"

    # Install the man pages
    man1.install Dir["man/*.1"]

    # Install shell completions
    bash_completion.install "completion/diffvim.bash" => "diffvim"
    zsh_completion.install "completion/_diffvim" => "_diffvim"
    fish_completion.install "completion/diffvim.fish"

    # Install the set_config helper
    bin.install "set_config" => "diffvim-set-config"
  end

  test do
    # Test that the scripts run
    assert_match "diffvim", shell_output("#{bin}/diffvim --version 2>&1", 0)
    assert_match "diffvim", shell_output("#{bin}/diffvim-tmux --help 2>&1", 0)
    assert_match "diffvim", shell_output("perl #{bin}/diffvim.pl --version 2>&1", 0)
  end
end
