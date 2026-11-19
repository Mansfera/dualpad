import AppKit
import SwiftUI

@main
enum Main {
    static let openNotification = Notification.Name("com.mansfera.dualpad.open")

    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--dump") { Dump.run(); return }
        if arguments.contains("--scan") { scanApplications(); return }
        if let index = arguments.firstIndex(of: "--render"), index + 1 < arguments.count {
            Render.run(to: arguments[index + 1])
            return
        }

        // A second launch (Finder, Spotlight) opens the popover of the running copy instead.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id)
               .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            DistributedNotificationCenter.default().postNotificationName(
                openNotification, object: nil, userInfo: nil, deliverImmediately: true)
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    /// `DualPad --scan`: lists which installed apps the touchpad would pause in.
    private static func scanApplications() {
        let folders = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for name in names.sorted() where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name)
                let bundle = Bundle(url: url)
                let reason = GameDetector.detect(bundleID: bundle?.bundleIdentifier, bundleURL: url,
                                                 executableURL: bundle?.executableURL)
                print(reason.map { "  PAUSED  \(name) — \($0)" } ?? "  on      \(name)")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, SettingsOpener {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private let model = PadModel()
    private lazy var settingsWindow = SettingsWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Brand.registerFonts()
        AppMenu.installMainMenu()

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        let host = NSHostingController(rootView: PopoverView(model: model))
        host.sizingOptions = .preferredContentSize // the popover follows the content height when switching tabs
        popover.contentViewController = host

        model.onStateChange = { [weak self] in self?.updateIcon() }
        model.start()
        UpdateChecker.shared.start()
        updateIcon()

        DistributedNotificationCenter.default().addObserver(forName: Main.openNotification, object: nil, queue: .main) { [weak self] note in
            if let tab = (note.object as? String).flatMap(PadModel.Tab.init(rawValue:)) { self?.model.tab = tab }
            self?.showPopover()
        }

        // First run, or access lost after an update: show why nothing happens yet.
        if !model.accessibility {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showPopover() }
        }
    }

    // Not in the Dock: opening the app again from Finder or Spotlight shows the popover.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    @objc func openSettings() {
        popover.performClose(nil)
        settingsWindow.show()
    }

    func popoverWillShow(_ notification: Notification) { model.popoverShown = true }
    func popoverDidClose(_ notification: Notification) { model.popoverShown = false }

    private func updateIcon() {
        guard let button = item?.button else { return }
        button.image = MenuIcon.image(working: model.working)
        button.toolTip = model.working ? "DualPad · On in \(model.frontApp?.name ?? "this app")" : "DualPad · Paused"
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp, Settings.shared.rightClickToggles {
            Settings.shared.enabled.toggle()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
}
