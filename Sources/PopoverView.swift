import SwiftUI

// Built like Lynx Battery's popover: pill tabs and a gear on top, one sky Stage per tab for the main
// block, white Panels with a hairline border for settings, Ink pills for actions.

struct PopoverView: View {
    @ObservedObject var model: PadModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme: scheme)
        VStack(alignment: .leading, spacing: 10) {
            TopBar(model: model)
            UpdateBanner(updates: UpdateChecker.shared)
            FitScroll {
                Group {
                    switch model.tab {
                    case .touchpad: TouchpadTab(model: model)
                    case .apps: AppsTab(model: model)
                    }
                }
                .padding(.bottom, 2)
            }
        }
        .padding(12)
        .frame(width: 360)
        .background(pal.bg)
        .foregroundStyle(pal.fg)
        .environment(\.palette, pal)
        .font(Brand.text(12))
    }
}

/// Opens the Settings window; the action goes up the responder chain to the app delegate.
@objc protocol SettingsOpener { func openSettings() }

struct TopBar: View {
    @ObservedObject var model: PadModel
    @Environment(\.palette) private var pal

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PadModel.Tab.allCases) { tab in
                let on = model.tab == tab
                Button { model.tab = tab } label: {
                    Text(tab.rawValue)
                        .font(Brand.text(12.5, .medium))
                        .padding(.horizontal, 13).padding(.vertical, 7)
                        .background(on ? pal.fg : .clear, in: Capsule())
                        .foregroundStyle(on ? pal.bg : pal.muted)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { NSApp.sendAction(#selector(SettingsOpener.openSettings), to: nil, from: nil) } label: {
                ZStack {
                    Circle().fill(pal.fg)
                    Image(systemName: "gearshape.fill").font(.system(size: 13)).foregroundStyle(pal.bg)
                }
                .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Settings")
            .accessibilityLabel("Settings")
        }
    }
}

/// A new version on GitHub, above the tabs so it shows on either. The cross hides it until the next version.
struct UpdateBanner: View {
    @ObservedObject var updates: UpdateChecker
    @ObservedObject private var settings = Settings.shared
    @Environment(\.palette) private var pal
    @State private var copied = false

    var body: some View {
        if let release = updates.available {
            Panel {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DualPad \(release.version) is out").font(Brand.text(12.5, .medium))
                        Text(updates.homebrew ? "Installed with Homebrew: update with brew so it keeps track."
                                              : "You have \(updates.current).")
                            .font(Brand.text(10.5)).foregroundStyle(pal.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { NSWorkspace.shared.open(release.url) }
                    .help("Open the release page")
                    Spacer()
                    if updates.homebrew {
                        InkPill(title: copied ? "Copied" : "Copy brew command", symbol: copied ? "checkmark" : "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(UpdatePolicy.brewCommand, forType: .string)
                            copied = true
                        }
                        .help(UpdatePolicy.brewCommand)
                    } else {
                        InkPill(title: "Download", symbol: "arrow.down") {
                            NSWorkspace.shared.open(release.dmgURL ?? release.url)
                        }
                    }
                    RoundIconButton(symbol: "xmark", help: "Hide until the next version") { updates.dismissBanner() }
                }
            }
        }
    }
}

// MARK: - Touchpad

struct TouchpadTab: View {
    @ObservedObject var model: PadModel
    @ObservedObject private var s = Settings.shared
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(spacing: 10) {
            HeroStage(model: model)
            if let controller = model.controllers.first {
                ControllerStats(controller: controller)
            }
            Panel {
                VStack(spacing: 14) {
                    SpeedSlider(title: "Pointer speed", value: $s.pointerSpeed, range: Settings.pointerSpeedRange)
                    Divider().overlay(pal.line)
                    SpeedSlider(title: "Scroll speed", value: $s.scrollSpeed, range: Settings.scrollSpeedRange)
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle2("Tap to click", detail: "Tap the pad to click, tap with two fingers to right-click.",
                            isOn: $s.tapToClick)
                    Divider().overlay(pal.line)
                    Toggle2("Natural scrolling", detail: "Content follows your fingers, like on a Mac trackpad.",
                            isOn: $s.naturalScrolling)
                }
            }
            Text("Press the pad to click, press with two fingers to right-click. Two fingers scroll.")
                .font(Brand.text(10.5)).foregroundStyle(pal.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
}

struct HeroStage: View {
    @ObservedObject var model: PadModel
    @ObservedObject private var s = Settings.shared
    @Environment(\.palette) private var pal

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Touchpad").font(Brand.text(11, .medium)).foregroundStyle(pal.fg.opacity(0.6))
                        Text(word).font(Brand.display(44)).tracking(-1.6)
                            .foregroundStyle(needsAttention ? Brand.signal : pal.fg)
                            .contentTransition(.opacity)
                    }
                    Spacer()
                    Toggle("", isOn: $s.enabled).labelsHidden().toggleStyle(.switch).tint(pal.toggleTint)
                        .help("Turn the touchpad on or off")
                }
                PadPicture(live: model.live, connected: !model.controllers.isEmpty, dimmed: !model.working)
                VStack(alignment: .leading, spacing: 4) {
                    Text(line).font(Brand.text(13, .medium)).foregroundStyle(pal.fg.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    if let controller = model.controllers.first {
                        Text(controller.name).font(Brand.text(11)).foregroundStyle(pal.fg.opacity(0.5))
                    }
                }
                if !model.accessibility {
                    InkPill(title: "Allow access", symbol: "lock.open.fill") { model.requestAccessibility() }
                }
            }
        }
    }

    private var needsAttention: Bool { !model.accessibility }

    private var appName: String { model.frontApp?.name ?? "this app" }

    private var word: String {
        if !model.accessibility { return "No access" }
        if model.controllers.isEmpty { return "Waiting" }
        switch model.gate {
        case .off: return "Off"
        case .on, .alwaysOn: return "On"
        case .ignored, .game: return "Paused"
        }
    }

    private var line: String {
        if !model.accessibility {
            return "macOS needs you to allow DualPad under Accessibility before it can move the pointer."
        }
        if model.controllers.isEmpty { return "Connect a DualSense over USB or Bluetooth." }
        switch model.gate {
        case .off: return "The pad does nothing until you turn it back on."
        case .on: return "Working in \(appName)."
        case .alwaysOn: return "Working in \(appName), even though it looks like a game."
        case .ignored: return "You ignore it in \(appName)."
        case .game(let reason): return "\(appName) looks like a game (\(reason)), so it gets the controller to itself."
        }
    }
}

/// The DualSense touchpad as a dot matrix: dots light up under each finger, and the whole pad
/// gets darker while it's pressed in. Coordinates are the pad's own (1920 × 1080).
struct PadPicture: View {
    @ObservedObject var live: LivePad
    let connected: Bool
    let dimmed: Bool
    @Environment(\.palette) private var pal
    private let cols = 30, rows = 11

    var body: some View {
        Canvas { ctx, size in
            let stepX = size.width / CGFloat(cols), stepY = size.height / CGFloat(rows)
            let dot = min(stepX, stepY) * 0.36
            let fingers = live.touches.map { CGPoint(x: $0.x / 1919 * size.width, y: $0.y / 1079 * size.height) }
            let reach = stepX * 2.4
            let base = live.pressed ? 0.2 : 0.09
            for c in 0..<cols {
                for r in 0..<rows {
                    let center = CGPoint(x: (CGFloat(c) + 0.5) * stepX, y: (CGFloat(r) + 0.5) * stepY)
                    let distance = fingers.map { hypot($0.x - center.x, $0.y - center.y) }.min() ?? .infinity
                    let glow = max(0, 1 - distance / reach)
                    let d = dot * (1 + 0.7 * glow)
                    let opacity = (base + (1 - base) * glow) * (dimmed ? 0.6 : 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)),
                             with: .color(pal.fg.opacity(opacity)))
                }
            }
        }
        .frame(height: 112)
        .padding(10)
        .background(pal.fg.opacity(live.pressed ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.fg.opacity(0.18)))
        .overlay {
            if live.touches.isEmpty {
                Text(connected ? "Touch the pad" : "No controller")
                    .font(Brand.mono(10, .medium)).foregroundStyle(pal.fg.opacity(0.5))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The connected controller as a 2 × 2 grid of figures with hairline dividers, like Lynx Battery's stats row.
struct ControllerStats: View {
    let controller: PadModel.Controller
    @Environment(\.palette) private var pal

    var body: some View {
        Panel(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Stat(value: controller.battery.map { "\($0)%" } ?? "—", caption: batteryCaption,
                         color: batteryColor)
                    Divider().overlay(pal.line)
                    Stat(value: controller.minutesLeft.map(Self.duration) ?? "—", caption: timeCaption, size: 22)
                        .help("The controller reports its level in 10% steps only, so the estimate starts after two steps and is rough.")
                }
                Divider().overlay(pal.line)
                HStack(spacing: 0) {
                    Stat(value: controller.transport, caption: connectedCaption, size: 20)
                        .help([controller.model, controller.serial].compactMap { $0 }.joined(separator: " · "))
                    Divider().overlay(pal.line)
                    Stat(value: controller.rate.map { "\($0) Hz" } ?? "—", caption: "Input reports a second")
                }
            }
        }
    }

    private var batteryCaption: String {
        switch controller.charge {
        case .unknown: return "Battery · waiting for a report"
        case .onBattery: return "Battery · not charging"
        case .charging: return "Battery · charging"
        case .full: return "Battery · fully charged"
        case .error: return "Battery · charging error"
        }
    }

    private var batteryColor: Color? {
        switch controller.charge {
        case .charging, .full: return Color(nsColor: .systemGreen)
        case .error: return Brand.signal
        default: return (controller.battery ?? 100) <= 20 ? Brand.signal : nil
        }
    }

    private var timeCaption: String {
        if controller.minutesLeft != nil {
            if controller.toFull { return "Until full" }
            return controller.fullChargeMinutes.map { "Left · a full charge lasts ≈ \(Self.duration($0))" } ?? "Left"
        }
        switch controller.charge {
        case .full: return "Unplug it to start counting"
        case .error, .unknown: return "Time left"
        case .onBattery, .charging:
            let percent = controller.stepsUntilEstimate * 10
            return controller.charge == .charging
                ? "Until full shows after about \(percent)% more charge"
                : "Time left shows after about \(percent)% of use"
        }
    }

    private var connectedCaption: String {
        let minutes = Int(Date().timeIntervalSince(controller.connectedAt) / 60)
        if minutes < 1 { return "Connected just now" }
        return "Connected for \(Self.duration(minutes))"
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    struct Stat: View {
        let value: String
        let caption: String
        var color: Color? = nil
        var size: CGFloat = 28
        var monoCaption = false
        @Environment(\.palette) private var pal

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(value).font(Brand.display(size)).tracking(size > 24 ? -0.8 : -0.4).monospacedDigit()
                    .foregroundStyle(color ?? pal.fg)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(height: 30, alignment: .bottomLeading)
                Text(caption).font(monoCaption ? Brand.mono(10, .regular) : Brand.text(10.5))
                    .foregroundStyle(pal.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}

/// A Slow…Fast slider on a log scale, with the multiplier in mono like Lynx's figures.
struct SpeedSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(Brand.text(12.5, .medium))
                Spacer()
                Text(String(format: "%.2f×", value)).font(Brand.mono(10.5, .semibold)).foregroundStyle(pal.muted)
                    .monospacedDigit()
            }
            Slider(value: Binding(get: { log2(value) }, set: { value = pow(2, $0) }),
                   in: log2(range.lowerBound)...log2(range.upperBound))
                .tint(pal.fg)
                .controlSize(.small)
                .accessibilityLabel(title)
            HStack {
                Text("Slow")
                Spacer()
                Text("Fast")
            }
            .font(Brand.mono(9.5, .medium)).foregroundStyle(pal.fg.opacity(0.6))
        }
    }
}

// MARK: - Apps

struct AppsTab: View {
    @ObservedObject var model: PadModel
    @ObservedObject private var s = Settings.shared
    @Environment(\.palette) private var pal

    var body: some View {
        VStack(spacing: 10) {
            FrontAppStage(model: model)
            Panel {
                Toggle2("Pause in games",
                        detail: "Steam, Unity, Unreal, SDL and Wine games, apps that read the controller themselves, and game streaming like GeForce NOW.",
                        isOn: $s.autoDetectGames)
            }
            AppList(title: "Ignored", empty: "Apps you ignore show up here.", apps: s.ignoredApps,
                    remove: { s.ignoredApps[$0] = nil }, add: { model.chooseAppsToIgnore() })
            if !s.alwaysOnApps.isEmpty {
                AppList(title: "Always on", empty: "", apps: s.alwaysOnApps,
                        remove: { s.alwaysOnApps[$0] = nil }, add: nil)
            }
        }
    }
}

struct FrontAppStage: View {
    @ObservedObject var model: PadModel
    @Environment(\.palette) private var pal

    var body: some View {
        Stage {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    if let icon = model.frontApp?.icon {
                        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.frontApp?.name ?? "No app").font(Brand.display(22)).tracking(-0.6).lineLimit(1)
                        Text(status).font(Brand.text(11.5)).foregroundStyle(pal.fg.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if model.frontApp != nil { action }
            }
        }
    }

    private var status: String {
        switch model.gate {
        case .on: return "The touchpad works here."
        case .alwaysOn: return "Always on here, even though it looks like a game."
        case .off: return "The touchpad is turned off everywhere."
        case .ignored: return "Ignored: the touchpad does nothing here."
        case .game(let reason): return "Paused: looks like a game (\(reason))."
        }
    }

    @ViewBuilder private var action: some View {
        switch model.gate {
        case .on: InkPill(title: "Ignore this app", symbol: "hand.raised.fill") { model.ignoreFrontApp() }
        case .ignored: InkPill(title: "Stop ignoring", symbol: "arrow.uturn.left") { model.resetFrontApp() }
        case .game: InkPill(title: "Use here anyway", symbol: "hand.point.up.left.fill") { model.useInFrontAppAnyway() }
        case .alwaysOn: InkPill(title: "Pause here again", symbol: "arrow.uturn.left") { model.resetFrontApp() }
        case .off: EmptyView()
        }
    }
}

/// A list of apps with their icons, each with a button to take it off the list.
struct AppList: View {
    let title: String
    let empty: String
    let apps: [String: String]
    let remove: (String) -> Void
    let add: (() -> Void)?
    @Environment(\.palette) private var pal

    var body: some View {
        let sorted = apps.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        Panel(padding: 4) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(title).font(Brand.text(11, .medium)).foregroundStyle(pal.muted)
                    Spacer()
                    if let add {
                        Button(action: add) {
                            Label("Add app", systemImage: "plus").font(Brand.text(11, .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                if sorted.isEmpty {
                    Text(empty).font(Brand.text(11)).foregroundStyle(pal.muted)
                        .padding(.horizontal, 10).padding(.bottom, 10)
                }
                ForEach(sorted, id: \.key) { key, name in
                    AppListRow(key: key, name: name) { remove(key) }
                }
            }
        }
    }
}

struct AppListRow: View {
    let key: String
    let name: String
    let remove: () -> Void
    @Environment(\.palette) private var pal
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: PadModel.icon(forAppKey: key)).resizable().frame(width: 20, height: 20)
            Text(name).font(Brand.text(12.5, .medium)).lineLimit(1)
            Spacer(minLength: 8)
            RoundIconButton(symbol: "xmark", help: "Remove \(name)", action: remove)
                .opacity(hover ? 1 : 0.6)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(pal.fg.opacity(hover ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { hover = $0 }
    }
}
