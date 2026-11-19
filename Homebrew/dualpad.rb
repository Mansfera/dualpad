# Homebrew cask for DualPad. release.sh fills in the version and checksum
# and pushes the result to the tap repository as Casks/dualpad.rb.
cask "dualpad" do
  version "__VERSION__"
  sha256 "__SHA256__"

  url "https://github.com/Mansfera/dualpad/releases/download/v#{version}/DualPad-#{version}.dmg"
  name "DualPad"
  desc "Use the DualSense controller's touchpad as a Mac trackpad"
  homepage "https://github.com/Mansfera/dualpad"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "DualPad.app"

  # DualPad is ad-hoc signed, not notarized, so macOS would refuse to open a quarantined
  # download. Clearing the quarantine flag is what "Open Anyway" does.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/DualPad.app"]
  end

  uninstall quit: "com.mansfera.dualpad"

  zap trash: "~/Library/Preferences/com.mansfera.dualpad.plist"
end
