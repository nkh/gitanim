# Homebrew formula for ad_vim
# Install with: brew install ./packaging/ad_vim.rb
# Or: brew tap nkh/gitanim && brew install ad_vim
#
# This formula installs the ad toolkit + the ad_vim application:
#   - ad              (animator backend, C)
#   - ad_compute      (diff engine, C++)
#   - ad_postprocess  (layer orchestrator, bash)
#   - ad_pipeline     (full pipeline driver, bash)
#   - ad_layer_*      (postprocess layers, C)
#   - ad_vim          (vim application launcher, bash)
#   - ad_vim.pl       (Perl parallel launcher)

class AdVim < Formula
  desc "Animate a code diff as if a human were typing it"
  homepage "https://github.com/nkh/gitanim"
  url "https://github.com/nkh/gitanim/archive/refs/heads/main.zip"
  version "2.0.0"
  sha256 "placeholder"
  license "MIT"
  head "https://github.com/nkh/gitanim.git", branch: "main"

  depends_on "vim"
  depends_on "perl"

  def install
    # Build all binaries
    system "make"

    # Install binaries
    bin.install "bin/ad"             => "ad"
    bin.install "bin/ad_compute"     => "ad_compute"
    bin.install "bin/ad_layer_reorder"            => "ad_layer_reorder"
    bin.install "bin/ad_layer_overwrite"          => "ad_layer_overwrite"
    bin.install "bin/ad_layer_indent_last"        => "ad_layer_indent_last"
    bin.install "bin/ad_layer_line_delete_in_place" => "ad_layer_line_delete_in_place"
    bin.install "bin/ad_layer_pace"               => "ad_layer_pace"
    bin.install "bin/ad_layer_highlight"          => "ad_layer_highlight"
    bin.install "pipeline/bin/ad_postprocess"     => "ad_postprocess"
    bin.install "pipeline/bin/ad_pipeline"        => "ad_pipeline"

    # Install the vim application launcher
    bin.install "apps/vim/ad_vim"                 => "ad_vim"
    bin.install "apps/vim/ad_vim.pl"              => "ad_vim.pl"

    # Install the vim plugin
    (prefix/"plugin").install "apps/vim/plugin.vim"
    (prefix/"autoload"/"ad_vim").install Dir["apps/vim/autoload_diffvim/*"]

    # Install Perl fallbacks
    bin.install "diff_engine/perl/compute.pl"             => "ad_compute-perl"
    bin.install "animator/perl/ad.pl"                    => "ad-perl"
    bin.install "layers/perl/ad_layer_reorder.pl"        => "ad_layer_reorder-perl"
    bin.install "layers/perl/ad_layer_overwrite.pl"       => "ad_layer_overwrite-perl"
    bin.install "layers/perl/ad_layer_indent_last.pl"    => "ad_layer_indent_last-perl"
    bin.install "layers/perl/ad_layer_line_delete_in_place.pl" => "ad_layer_line_delete_in_place-perl"
    bin.install "layers/perl/ad_layer_pace.pl"            => "ad_layer_pace-perl"
    bin.install "layers/perl/ad_layer_highlight.pl"      => "ad_layer_highlight-perl"

    # Install helper scripts
    Dir["tools/bin/*.sh"].each do |script|
      bin.install script => File.basename(script, ".sh")
    end

    # Install man pages
    man1.install Dir["man/*.1"]

    # Install shell completions
    bash_completion.install "completion/ad_vim.bash" => "ad_vim"
    zsh_completion.install "completion/_ad_vim" => "_ad_vim"
    fish_completion.install "completion/ad_vim.fish"
  end

  test do
    # Test that the binaries run
    assert_match "ad", shell_output("#{bin}/ad --help 2>&1", 0)
    assert_match "ad_compute", shell_output("#{bin}/ad_compute --help 2>&1", 0)
  end
end
