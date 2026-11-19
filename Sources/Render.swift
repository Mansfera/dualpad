import AppKit
import SwiftUI

/// `DualPad --render <folder>`: draws the popover tabs in light and dark into PNGs, for checking the
/// design without opening the menu bar. Renders inside this process, so it needs no screen recording.
enum Render {
    static func run(to folder: String) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        Brand.registerFonts()
        let model = PadModel()
        model.start()
        UpdateChecker.shared.check() // with SIMULATE_VERSION, the update banner shows up in the render
        // Let the controller connect and the stats measure a second of input.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        model.popoverShown = true
        RunLoop.main.run(until: Date().addingTimeInterval(2.2))
        if let folder = Optional(folder) {
            for (name, working) in [("menubar-on", true), ("menubar-paused", false)] {
                let icon = MenuIcon.image(working: working)
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 88, pixelsHigh: 64, bitsPerSample: 8,
                                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                NSColor.white.setFill()
                NSRect(x: 0, y: 0, width: 88, height: 64).fill()
                icon.draw(in: NSRect(x: 0, y: 0, width: 88, height: 64))
                NSGraphicsContext.restoreGraphicsState()
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: URL(fileURLWithPath: folder).appendingPathComponent("\(name).png"))
            }
        }
        for tab in PadModel.Tab.allCases {
            model.tab = tab
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let view = NSHostingView(rootView: PopoverView(model: model))
                view.appearance = NSAppearance(named: appearance)
                let size = view.fittingSize
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = view
                view.frame = NSRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let url = URL(fileURLWithPath: folder).appendingPathComponent("\(tab.rawValue.lowercased())-\(name).png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                print(url.path)
            }
        }
    }
}
