# Homebrew formula for the Zen AI Tidy helper. This repo doubles as its tap; the name has no
# "homebrew-" prefix, so it is tapped by URL:
#   brew tap SrujanPonnapalli/zen-ai-tidy https://github.com/SrujanPonnapalli/zen-ai-tidy
#   brew install tidy-helper
# Building from source on the user's Mac avoids needing Apple code signing/notarization.
class TidyHelper < Formula
  desc "On-device Apple Intelligence tab grouping for the Zen AI Tidy browser mod"
  homepage "https://github.com/SrujanPonnapalli/zen-ai-tidy"
  url "https://github.com/SrujanPonnapalli/zen-ai-tidy.git", tag: "v1.0.0"
  license "MIT"
  head "https://github.com/SrujanPonnapalli/zen-ai-tidy.git", branch: "main"

  depends_on xcode: ["26.0", :build]
  depends_on macos: :tahoe # Foundation Models needs macOS 26+
  depends_on arch: :arm64 # Apple Intelligence is Apple silicon only

  def install
    # Homebrew's build sandbox blocks swiftc's nested sandbox for the @Generable macro plugin.
    system "swiftc", "-O", "-disable-sandbox", "helper/main.swift", "-o", "tidy-helper"
    bin.install "tidy-helper"
  end

  test do
    # Exits 1 with "model unavailable" when Apple Intelligence is off, which is still a working binary.
    assert_match(/available/, shell_output("#{bin}/tidy-helper --check 2>&1 || true"))
  end
end
