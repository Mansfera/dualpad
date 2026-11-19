import AppKit

/// The menu bar icon: the app icon drawn small, a touchpad outline with a finger and its motion
/// trail. While the touchpad isn't driving the pointer, the circles fade out.
enum MenuIcon {
    static func image(working: Bool) -> NSImage {
        let size = NSSize(width: 22, height: 16)
        let image = NSImage(size: size, flipped: false) { _ in
            let pad = NSRect(x: 1.75, y: 3.25, width: 18.5, height: 9.5)
            let outline = NSBezierPath(roundedRect: pad, xRadius: 3.2, yRadius: 3.2)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            outline.stroke()
            // Same positions as finger.svg in the app icon, scaled to the pad.
            NSColor.black.withAlphaComponent(working ? 1 : 0.35).setFill()
            for (x, y, r) in [(14.6, 7.9, 2.1), (10.6, 6.3, 1.25), (7.6, 5.3, 0.85)] as [(CGFloat, CGFloat, CGFloat)] {
                NSBezierPath(ovalIn: NSRect(x: x - r, y: y - r, width: r * 2, height: r * 2)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = working ? "DualPad, on" : "DualPad, paused"
        return image
    }
}
