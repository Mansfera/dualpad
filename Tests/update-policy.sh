#!/bin/bash
# Checks version comparison, GitHub response parsing and when the update banner shows.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/update-policy-test
cat > build/update-policy-test/main.swift <<'EOF'
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "  ok    " : "  FAIL  ") + what)
    if !ok { failures += 1 }
}

check(UpdatePolicy.isNewer("1.10.0", than: "1.9.0"), "1.10.0 is newer than 1.9.0")
check(UpdatePolicy.isNewer("v1.0.1", than: "1.0"), "v1.0.1 is newer than 1.0")
check(!UpdatePolicy.isNewer("1.0.0", than: "1.0"), "1.0.0 is the same as 1.0")
check(!UpdatePolicy.isNewer("2.0.0-beta.1", than: "1.0.0"), "prereleases are never offered")
check(!UpdatePolicy.isNewer("banana", than: "1.0.0"), "a tag that isn't a version is ignored")

let json = """
{"tag_name":"v1.2.0","html_url":"https://github.com/Mansfera/dualpad/releases/tag/v1.2.0","draft":false,"prerelease":false,
 "assets":[{"name":"DualPad-1.2.0.dmg","browser_download_url":"https://github.com/Mansfera/dualpad/releases/download/v1.2.0/DualPad-1.2.0.dmg"}]}
"""
let release = UpdatePolicy.parse(Data(json.utf8))
check(release?.version == "1.2.0" && release?.tag == "v1.2.0", "parses the version from the tag")
check(release?.dmgURL?.lastPathComponent == "DualPad-1.2.0.dmg", "finds the DMG")
let pre = json.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
check(UpdatePolicy.parse(Data(pre.utf8)) == nil, "rejects a prerelease")

check(UpdatePolicy.showBanner(release, current: "1.0.0", checkOn: true, dismissed: nil), "banner for a newer release")
check(!UpdatePolicy.showBanner(release, current: "1.2.0", checkOn: true, dismissed: nil), "no banner when up to date")
check(!UpdatePolicy.showBanner(release, current: "1.0.0", checkOn: false, dismissed: nil), "no banner with checks off")
check(!UpdatePolicy.showBanner(release, current: "1.0.0", checkOn: true, dismissed: "1.2.0"), "no banner once dismissed")
check(UpdatePolicy.showBanner(release, current: "1.0.0", checkOn: true, dismissed: "1.1.0"), "banner again for the next version")

let now = Date()
check(UpdatePolicy.isDue(lastCheck: nil, now: now), "due when never checked")
check(!UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-3600), now: now), "not due an hour later")
check(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(-9 * 3600), now: now), "due 9 hours later")
check(UpdatePolicy.isDue(lastCheck: now.addingTimeInterval(3600), now: now), "due when the clock went back")

check(UpdatePolicy.isHomebrewInstall(exists: { $0 == "/opt/homebrew/Caskroom/dualpad" }), "detects a Homebrew install")
check(!UpdatePolicy.isHomebrewInstall(exists: { _ in false }), "no Caskroom: not Homebrew")

print(failures == 0 ? "All passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
EOF
swiftc -swift-version 5 Sources/UpdatePolicy.swift build/update-policy-test/main.swift -o build/update-policy-test/run
build/update-policy-test/run
