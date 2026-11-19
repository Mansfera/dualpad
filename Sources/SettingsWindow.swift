import AppKit
import SwiftUI

// Settings is a separate system window with toolbar tabs, like Lynx Battery's.

enum AppMenu {
    /// An LSUIElement app doesn't show its main menu, but ⌘, ⌘W and ⌘Q only work through it.
    static func installMainMenu() {
        let app = NSMenu(title: "DualPad")
        app.addItem(NSMenuItem(title: "Settings…", action: #selector(SettingsOpener.openSettings), keyEquivalent: ","))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: "Quit DualPad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let window = NSMenu(title: "Window")
        window.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let main = NSMenu()
        for submenu in [app, window] {
            let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }
}

final class SettingsWindow: NSObject {
    private var window: NSWindow?

    func show() {
        Settings.shared.syncLaunchAtLogin()
        let w = window ?? make()
        window = w
        // An LSUIElement app doesn't activate itself: without this the window opens behind others.
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettings()))
        tabs.addTabViewItem(tab("About", symbol: "info.circle", AboutSettings()))
        let w = NSWindow(contentViewController: tabs)
        w.styleMask = [.titled, .closable]
        w.toolbarStyle = .preference
        w.isReleasedWhenClosed = false
        w.center()
        w.setFrameAutosaveName("Settings")
        return w
    }

    private func tab<V: View>(_ label: String, symbol: String, _ view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = .preferredContentSize
        host.title = label
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

private struct SettingsPane<Content: View>: View {
    let height: CGFloat
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let pal = Palette(scheme: scheme)
        Form { content }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            .toggleStyle(.switch)
            .tint(pal.toggleTint)
            .font(Brand.text(13))
            .environment(\.palette, pal)
            .frame(width: 480, height: height)
    }
}

struct GeneralSettings: View {
    @ObservedObject var s = Settings.shared
    @ObservedObject var updates = UpdateChecker.shared

    var body: some View {
        SettingsPane(height: 380) {
            Section {
                Toggle("Open at login", isOn: $s.launchAtLogin)
                Toggle(isOn: $s.rightClickToggles) {
                    Text("Right-click to turn on or off")
                    Text("Right-clicking the menu bar icon turns the touchpad on or off instead of opening DualPad.")
                }
            }
            Section {
                Toggle(isOn: $s.updateCheck) {
                    Text("Check for updates")
                    Text("Asks GitHub for the latest release when DualPad opens and every 8 hours. It sends nothing about you or your Mac, and it's the only network request DualPad makes.")
                }
                LabeledContent {
                    Button(updates.checking ? "Checking…" : "Check Now") { updates.check() }
                        .disabled(!s.updateCheck || updates.checking)
                } label: {
                    Text("Version \(updates.current)")
                    Text(status)
                }
            } header: {
                Text("Updates").font(Brand.text(13, .semibold))
            }
        }
    }

    private var status: String {
        if let latest = updates.latest, UpdatePolicy.isNewer(latest.version, than: updates.current) {
            return updates.homebrew ? "\(latest.version) is out. Update with: \(UpdatePolicy.brewCommand)"
                                    : "\(latest.version) is out."
        }
        guard let checked = updates.lastChecked else { return "Not checked yet." }
        return "Up to date · checked \(checked.formatted(.relative(presentation: .named)))."
    }
}

struct AboutSettings: View {
    private func info(_ key: String) -> String { Bundle.main.object(forInfoDictionaryKey: key) as? String ?? "" }

    /// Underline: in secondary text, color alone isn't enough for a link to read as a link.
    private func link(_ title: String, _ url: String) -> AttributedString {
        var text = AttributedString(title)
        text.link = URL(string: url)
        text.underlineStyle = .single
        return text
    }

    var body: some View {
        SettingsPane(height: 270) {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DualPad").font(Brand.text(15, .semibold))
                        Text("Version \(info("CFBundleShortVersionString")) (\(info("CFBundleVersion")))")
                            .foregroundStyle(.secondary)
                        Text("© 2026 Designed & developed by")
                            .foregroundStyle(.secondary)
                        Text("\(link("Etherlynx Studio", "https://etherlynx.xyz/")) & \(link("Ihor Kharkholyuk", "https://kharkholy.uk"))")
                            .foregroundStyle(.secondary)
                        Text("Made with Claude").font(Brand.text(11)).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
            }
            Section {
                LabeledContent {
                    Button("Quit") { NSApp.terminate(nil) }
                } label: {
                    Text("Quit DualPad")
                    Text("The touchpad stops moving the pointer until you open it again.")
                }
            }
        }
    }
}
