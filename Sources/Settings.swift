import Foundation
import ServiceManagement

/// User settings, stored in UserDefaults (com.mansfera.dualpad).
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// Slider ranges (multipliers). The sliders move on a log scale, so the slow end gets fine control.
    static let pointerSpeedRange = 0.1...1.5
    static let scrollSpeedRange = 0.25...2.5

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var autoDetectGames: Bool { didSet { d.set(autoDetectGames, forKey: "autoDetectGames") } }
    @Published var tapToClick: Bool { didSet { d.set(tapToClick, forKey: "tapToClick") } }
    @Published var naturalScrolling: Bool { didSet { d.set(naturalScrolling, forKey: "naturalScrolling") } }
    @Published var pointerSpeed: Double { didSet { d.set(pointerSpeed, forKey: "pointerSpeed") } }
    @Published var scrollSpeed: Double { didSet { d.set(scrollSpeed, forKey: "scrollSpeed") } }
    /// Right-clicking the menu bar icon turns the touchpad on or off instead of opening the popover.
    @Published var rightClickToggles: Bool { didSet { d.set(rightClickToggles, forKey: "rightClickToggles") } }
    /// Ask GitHub for new releases; the only network request DualPad makes.
    @Published var updateCheck: Bool { didSet { d.set(updateCheck, forKey: "updateCheck") } }
    /// App key (bundle id, or executable path for apps without one) → display name.
    @Published var ignoredApps: [String: String] { didSet { d.set(ignoredApps, forKey: "ignoredApps") } }
    /// Apps where the touchpad stays on even though they look like games.
    @Published var alwaysOnApps: [String: String] { didSet { d.set(alwaysOnApps, forKey: "alwaysOnApps") } }

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("DualPad: open at login — \(error.localizedDescription)")
                DispatchQueue.main.async { self.launchAtLogin = SMAppService.mainApp.status == .enabled }
            }
        }
    }

    /// Open at login may have been turned off in System Settings while the app was running.
    func syncLaunchAtLogin() {
        let on = SMAppService.mainApp.status == .enabled
        if launchAtLogin != on { launchAtLogin = on }
    }

    private init() {
        // Start with the Mac's own scroll direction ("Natural scrolling" in Trackpad settings).
        let systemNatural = d.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
        d.register(defaults: [
            "enabled": true,
            "autoDetectGames": true,
            "tapToClick": true,
            "naturalScrolling": systemNatural,
            "pointerSpeed": 0.5,
            "scrollSpeed": 1.0,
            "rightClickToggles": true,
            "updateCheck": true,
        ])
        updateCheck = d.bool(forKey: "updateCheck")
        enabled = d.bool(forKey: "enabled")
        autoDetectGames = d.bool(forKey: "autoDetectGames")
        tapToClick = d.bool(forKey: "tapToClick")
        naturalScrolling = d.bool(forKey: "naturalScrolling")
        pointerSpeed = d.double(forKey: "pointerSpeed")
        scrollSpeed = d.double(forKey: "scrollSpeed")
        rightClickToggles = d.bool(forKey: "rightClickToggles")
        ignoredApps = d.dictionary(forKey: "ignoredApps") as? [String: String] ?? [:]
        alwaysOnApps = d.dictionary(forKey: "alwaysOnApps") as? [String: String] ?? [:]
    }
}
