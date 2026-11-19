import Foundation

// Pure update-check logic: versions, parsing the GitHub response, and when to show the banner.
// Foundation only, so Tests/update-policy.sh builds it without the rest of the app.

/// A version like 1.10.0: compares numbers, not strings, so 1.10.0 > 1.9.0.
struct AppVersion: Comparable, CustomStringConvertible {
    let parts: [Int]
    /// Has a suffix like "-beta": a prerelease, never offered.
    let prerelease: Bool

    /// "v1.2.3", "1.2", "1.2.3-beta.1", "1.2.3+build". Anything else: nil.
    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        var pre = false
        if let dash = s.firstIndex(of: "-") { pre = true; s = String(s[..<dash]) }
        let numbers = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !numbers.isEmpty, numbers.count <= 4, numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        parts = numbers.map { $0! }
        prerelease = pre
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    /// 1.2 == 1.2.0. A prerelease is lower than the release of the same version.
    static func < (a: AppVersion, b: AppVersion) -> Bool {
        for i in 0..<max(a.parts.count, b.parts.count) {
            let x = i < a.parts.count ? a.parts[i] : 0, y = i < b.parts.count ? b.parts[i] : 0
            if x != y { return x < y }
        }
        return a.prerelease && !b.prerelease
    }

    static func == (a: AppVersion, b: AppVersion) -> Bool { !(a < b) && !(b < a) }
}

/// A release on GitHub.
struct ReleaseInfo: Codable, Equatable {
    var version: String // without "v": 1.2.0
    var tag: String     // as on GitHub: v1.2.0
    var url: URL        // release page
    var dmgURL: URL?
}

enum UpdatePolicy {
    static let owner = "Mansfera"
    static let repo = "dualpad"
    static let cask = "mansfera/tap/dualpad"
    static var latestURL: URL { URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")! }
    static var brewCommand: String { "brew upgrade --cask \(cask)" }
    /// How often to ask GitHub. Without a token the limit is 60 requests an hour per IP; this makes about 3 a day.
    static let interval: TimeInterval = 8 * 3600

    /// Newer than the current version. Prereleases and versions that don't parse: no.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let l = AppVersion(latest), !l.prerelease, let c = AppVersion(current) else { return false }
        return l > c
    }

    /// The popover banner: checking is on, the release is newer, and it wasn't dismissed.
    static func showBanner(_ release: ReleaseInfo?, current: String, checkOn: Bool, dismissed: String?) -> Bool {
        guard checkOn, let release, isNewer(release.version, than: current) else { return false }
        return dismissed.map { AppVersion($0) != AppVersion(release.version) } ?? true
    }

    static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = UpdatePolicy.interval) -> Bool {
        guard let last = lastCheck, last <= now else { return true } // the clock went back: check too
        return now.timeIntervalSince(last) >= interval
    }

    /// The /releases/latest response. Drafts and prereleases are rejected.
    static func parse(_ data: Data) -> ReleaseInfo? {
        struct Asset: Decodable { let name: String; let browser_download_url: URL }
        struct Release: Decodable {
            let tag_name: String
            let html_url: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
        }
        guard let r = try? JSONDecoder().decode(Release.self, from: data),
              r.draft != true, r.prerelease != true,
              let version = AppVersion(r.tag_name), !version.prerelease else { return nil }
        let dmg = r.assets?.first { $0.name.hasSuffix(".dmg") }
        return ReleaseInfo(version: version.description, tag: r.tag_name, url: r.html_url, dmgURL: dmg?.browser_download_url)
    }

    static let caskrooms = ["/opt/homebrew/Caskroom/dualpad", "/usr/local/Caskroom/dualpad"]

    /// Installed with the cask: updating outside brew would leave brew thinking the old version is installed.
    static func isHomebrewInstall(caskrooms: [String] = caskrooms,
                                  exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> Bool {
        caskrooms.contains(where: exists)
    }
}
