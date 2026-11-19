import AppKit

/// Guesses whether an app reads the controller itself, so the touchpad should leave it alone.
/// Returns a short reason, or nil when the app doesn't look like a game.
enum GameDetector {
    private static var cache: [String: String?] = [:]

    /// Game streaming and remote play apps, which pass the controller through.
    private static let knownBundleIDs: [String: String] = [
        "com.nvidia.gfnpc.mall": "GeForce NOW",
        "com.moonlight-stream.Moonlight": "game streaming",
        "com.valvesoftware.steamlink": "Steam Link",
        "com.playstation.RemotePlay": "PS Remote Play",
        "com.chiaki-ng.chiaki-ng": "PS Remote Play",
        "com.openemu.OpenEmu": "emulator",
    ]

    /// File and folder names inside an app bundle that give away a game engine or controller library.
    private static let markers: [(String, String)] = [
        ("unityplayer", "Unity game"),
        ("gameassembly", "Unity game"),
        ("il2cpp", "Unity game"),
        ("libsdl2", "uses SDL"),
        ("sdl2.framework", "uses SDL"),
        ("libsdl3", "uses SDL"),
        ("sdl3.framework", "uses SDL"),
        ("steam_api", "Steam game"),
        ("libgodot", "Godot game"),
        ("ue4", "Unreal Engine game"),
        ("ue5", "Unreal Engine game"),
    ]

    static func key(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.executableURL?.path ?? app.localizedName ?? "pid \(app.processIdentifier)"
    }

    static func detect(_ app: NSRunningApplication) -> String? {
        let key = key(for: app)
        if let cached = cache[key] { return cached }
        let reason = compute(app)
        cache[key] = reason
        return reason
    }

    private static func compute(_ app: NSRunningApplication) -> String? {
        detect(bundleID: app.bundleIdentifier, bundleURL: app.bundleURL, executableURL: app.executableURL)
    }

    static func detect(bundleID: String?, bundleURL: URL?, executableURL: URL?) -> String? {
        if let id = bundleID, let reason = knownBundleIDs[id] { return reason }
        let executable = executableURL?.path.lowercased() ?? ""
        if executable.contains("/steamapps/common/") { return "Steam game" }
        if executable.contains("wine") || executable.contains("crossover") { return "Windows game (Wine)" }

        guard let bundleURL else { return nil }
        // Not the "Games" App Store category: launchers and mouse-driven games use it too.
        let info = Bundle(url: bundleURL)?.infoDictionary ?? [:]
        if info["GCSupportsControllerUserInteraction"] as? Bool == true || info["GCSupportedGameControllers"] != nil {
            return "declares game controller support"
        }

        let contents = bundleURL.appendingPathComponent("Contents")
        let folders = ["", "Frameworks", "MacOS", "PlugIns", "Resources", "Resources/Data"]
        for folder in folders {
            let url = folder.isEmpty ? contents : contents.appendingPathComponent(folder)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { continue }
            for name in names.map({ $0.lowercased() }) {
                for (marker, reason) in markers where name.hasPrefix(marker) || name.contains(marker + ".") {
                    return reason
                }
            }
        }
        return nil
    }
}
