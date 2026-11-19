import AppKit
import ApplicationServices
import Combine

/// Live finger positions for the touchpad picture. Separate from PadModel, so 60 updates a second
/// redraw only the picture, not the whole popover.
final class LivePad: ObservableObject {
    @Published var touches: [TouchPoint] = []
    @Published var pressed = false
}

/// Everything the popover shows, and the decision whether the touchpad drives the pointer right now.
final class PadModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case touchpad = "Touchpad"
        case apps = "Apps"
        var id: String { rawValue }
    }

    enum Gate: Equatable {
        case on
        case alwaysOn
        case off
        case ignored
        case game(String)
    }

    struct Controller: Equatable {
        let name: String
        let transport: String
        let model: String
        let serial: String?
        let connectedAt: Date
        let battery: Int?
        let charge: DualSenseReader.Charge
        /// Input reports per second, measured over the last second; nil until measured.
        let rate: Int?
        /// Minutes until empty, or until full while charging; nil until there's enough data.
        let minutesLeft: Int?
        let toFull: Bool
        /// How long a full charge lasts at the drain seen so far, in minutes.
        let fullChargeMinutes: Int?
        /// 10% steps still needed before the estimate appears.
        let stepsUntilEstimate: Int
    }

    struct FrontApp {
        let key: String
        let name: String
        let icon: NSImage?
    }

    /// `DUALPAD_DEMO=1 DualPad --render …`: neutral controller and app names for README screenshots.
    static let demo = ProcessInfo.processInfo.environment["DUALPAD_DEMO"] != nil

    @Published var tab: Tab = .touchpad
    @Published private(set) var controllers: [Controller] = []
    @Published private(set) var frontApp: FrontApp?
    @Published private(set) var gate: Gate = .on
    @Published private(set) var accessibility = AXIsProcessTrusted()
    let live = LivePad()
    let settings = Settings.shared

    /// Set by the app delegate: the popover is open, so the touchpad picture should update.
    var popoverShown = false {
        didSet {
            if popoverShown {
                checkAccessibility()
                updateControllers()
                // Battery and input rate refresh once a second, only while someone is looking.
                statsTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateControllers() }
                RunLoop.main.add(statsTimer!, forMode: .common)
            } else {
                statsTimer?.invalidate()
                statsTimer = nil
                live.touches = []
                live.pressed = false
            }
        }
    }
    /// Called when the menu bar icon should change.
    var onStateChange: (() -> Void)?

    /// The touchpad drives the pointer: on in this app, a controller is connected, and macOS allows it.
    var working: Bool { active && !controllers.isEmpty && accessibility }

    private let reader = DualSenseReader()
    private lazy var engine = TrackpadEngine(settings: settings)
    private var runningApp: NSRunningApplication?
    private var active = false
    private var lastPublish: TimeInterval = 0
    private var accessibilityTimer: Timer?
    private var statsTimer: Timer?
    /// Report count and time at the last rate sample, per controller (by object identity).
    private var rateSamples: [ObjectIdentifier: (count: Int, time: TimeInterval)] = [:]
    private var bag = Set<AnyCancellable>()

    func start() {
        reader.onFrame = { [weak self] frame in self?.handle(frame) }
        reader.onControllersChanged = { [weak self] in
            self?.updateControllers()
            self?.refresh()
        }
        let result = reader.start()
        if result != kIOReturnSuccess { NSLog("DualPad: IOHIDManagerOpen failed: 0x%08x", result) }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        if let app = NSWorkspace.shared.frontmostApplication { setFrontApp(app) }

        // Any setting can change the gate (ignore lists, game detection, the master switch).
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in DispatchQueue.main.async { self?.refresh() } }
            .store(in: &bag)
        checkAccessibility()
        refresh()
    }

    // MARK: Controllers

    private func updateControllers() {
        let now = ProcessInfo.processInfo.systemUptime
        var seen = Set<ObjectIdentifier>()
        let list = reader.controllers.map { c -> Controller in
            let id = ObjectIdentifier(c)
            seen.insert(id)
            var rate: Int?
            if let sample = rateSamples[id], now - sample.time > 0.5 {
                rate = Int((Double(c.reportCount - sample.count) / (now - sample.time)).rounded())
            }
            if rate != nil || rateSamples[id] == nil { rateSamples[id] = (c.reportCount, now) }
            let previous = controllers.first { $0.serial == c.serial && $0.connectedAt == c.connectedAt }
            let estimate = c.estimate(now: now)
            return Controller(name: Self.demo ? "DualSense Wireless Controller" : c.name,
                              transport: c.transport, model: c.model, serial: c.serial,
                              connectedAt: c.connectedAt, battery: c.battery, charge: c.charge,
                              rate: rate ?? previous?.rate,
                              minutesLeft: estimate.map { Int(($0.seconds / 60).rounded()) },
                              toFull: estimate?.toFull ?? false,
                              fullChargeMinutes: estimate?.fullChargeRuntime.map { Int(($0 / 60).rounded()) },
                              stepsUntilEstimate: c.stepsUntilEstimate)
        }
        rateSamples = rateSamples.filter { seen.contains($0.key) }
        if list != controllers { controllers = list }
    }

    // MARK: Input

    private func handle(_ frame: PadFrame) {
        if active { engine.process(frame) }
        guard popoverShown else { return }
        // About 60 updates a second for the picture, but every touch and click change right away.
        let changed = frame.touches.count != live.touches.count || frame.pressed != live.pressed
        if changed || frame.time - lastPublish > 1.0 / 60 {
            live.touches = frame.touches
            live.pressed = frame.pressed
            lastPublish = frame.time
        }
    }

    // MARK: Front app and gate

    @objc private func appActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        setFrontApp(app)
        refresh()
    }

    private func setFrontApp(_ app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        runningApp = app
        if Self.demo {
            let safari = "/Applications/Safari.app"
            frontApp = FrontApp(key: "com.apple.Safari", name: "Safari", icon: NSWorkspace.shared.icon(forFile: safari))
            return
        }
        frontApp = FrontApp(key: GameDetector.key(for: app), name: app.localizedName ?? "This app", icon: app.icon)
    }

    func refresh() {
        let newGate = computeGate()
        if newGate != gate { gate = newGate }
        let shouldBeActive = newGate == .on || newGate == .alwaysOn
        if shouldBeActive != active {
            engine.reset()
            active = shouldBeActive
        }
        onStateChange?()
    }

    private func computeGate() -> Gate {
        guard settings.enabled else { return .off }
        guard let app = runningApp, let key = frontApp?.key else { return .on }
        if settings.alwaysOnApps[key] != nil { return .alwaysOn }
        if settings.ignoredApps[key] != nil { return .ignored }
        if settings.autoDetectGames, let reason = GameDetector.detect(app) { return .game(reason) }
        return .on
    }

    // MARK: Actions

    func ignoreFrontApp() {
        guard let app = frontApp else { return }
        settings.alwaysOnApps[app.key] = nil
        settings.ignoredApps[app.key] = app.name
    }

    func useInFrontAppAnyway() {
        guard let app = frontApp else { return }
        settings.ignoredApps[app.key] = nil
        settings.alwaysOnApps[app.key] = app.name
    }

    /// Back to the default for the front app: no ignore, no override.
    func resetFrontApp() {
        guard let app = frontApp else { return }
        settings.ignoredApps[app.key] = nil
        settings.alwaysOnApps[app.key] = nil
    }

    func chooseAppsToIgnore() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose apps where the touchpad does nothing"
        panel.prompt = "Ignore"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundle = Bundle(url: url) else { continue }
            let key = bundle.bundleIdentifier ?? bundle.executableURL?.path ?? url.path
            settings.alwaysOnApps[key] = nil
            settings.ignoredApps[key] = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
    }

    /// The icon for an app in the ignore lists: by bundle id, or by path for apps without one.
    static func icon(forAppKey key: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: key) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        if key.hasPrefix("/") { return NSWorkspace.shared.icon(forFile: key) }
        return NSWorkspace.shared.icon(for: .application)
    }

    // MARK: Accessibility

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        checkAccessibility()
    }

    /// Polls every 2 seconds until macOS allows posting pointer events; there's no notification for it.
    private func checkAccessibility() {
        let trusted = AXIsProcessTrusted()
        if trusted != accessibility {
            accessibility = trusted
            onStateChange?()
        }
        guard !trusted, accessibilityTimer == nil else { return }
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.accessibilityTimer = nil
            self?.accessibility = true
            self?.onStateChange?()
        }
    }
}
