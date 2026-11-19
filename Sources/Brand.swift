import AppKit
import CoreText
import SwiftUI

// The same system as Lynx Battery (etherlynx.xyz): white background, Ink, a sky scene for the main
// block, white panels with a hairline border, Ink pills, Onest for text and Geist Mono for figures.

enum Brand {
    static let ink = Color(hex: 0x0E0E10)
    static let muted = Color(hex: 0x6A6F7C)
    static let mist = Color(hex: 0xB3BCCD)
    static let skyTop = Color(hex: 0xA9B3C6)
    static let skyMid = Color(hex: 0xC9D0DC)
    static let skyLow = Color(hex: 0xEEF0F3)
    /// Red is functional only: something needs your attention.
    static let signal = Color(hex: 0xE8271E)

    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom("Onest", size: size).weight(weight)
    }

    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom("Onest", size: size).weight(weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom("Geist Mono", size: size).weight(weight)
    }
}

/// Light and dark theme colors, the same tokens as Lynx Battery.
struct Palette {
    let scheme: ColorScheme
    var dark: Bool { scheme == .dark }
    var bg: Color { dark ? Color(hex: 0x101012) : .white }
    var panel: Color { dark ? Color(hex: 0x1A1A1D) : .white }
    var sunk: Color { dark ? Color(hex: 0x17171A) : Color(hex: 0xF1F3F7) }
    var fg: Color { dark ? .white : Brand.ink }
    var line: Color { dark ? .white.opacity(0.1) : Brand.ink.opacity(0.12) }
    var muted: Color { dark ? Color.white.opacity(0.55) : Brand.muted }
    /// An enabled switch: a white track in the dark theme would hide the white knob.
    var toggleTint: Color { dark ? Brand.mist : Brand.ink }

    /// Sky scene: a vertical sky gradient, in the dark theme a dark radial one.
    @ViewBuilder var stage: some View {
        if dark {
            RadialGradient(colors: [Color(hex: 0x2A2D35), Color(hex: 0x0E0E10)], center: .bottom, startRadius: 0, endRadius: 360)
        } else {
            LinearGradient(colors: [Brand.skyTop, Brand.skyMid, Brand.skyLow], startPoint: .top, endPoint: .bottom)
        }
    }
}

private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette(scheme: .light) }

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Surfaces

/// White panel with a hairline border (r 20), like cards on the site.
struct Panel<Content: View>: View {
    @Environment(\.palette) private var pal
    var padding: CGFloat = 14
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(pal.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(pal.line))
    }
}

/// Scene (r 28): the sky gradient, only for the main block of a tab.
struct Stage<Content: View>: View {
    @Environment(\.palette) private var pal
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(pal.stage.clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
    }
}

/// A scroll view that shrinks to its content, but never grows taller than the screen.
struct FitScroll<Content: View>: View {
    @ViewBuilder var content: Content
    static var maxHeight: CGFloat { max(300, (NSScreen.main?.visibleFrame.height ?? 800) - 170) }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) { content }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: Self.maxHeight)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Controls

/// Pill button from the site: Ink, white text, a white circle with a symbol on the right.
struct InkPill: View {
    let title: String
    var symbol: String = "arrow.right"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        // On a dark background the pill inverts: white with an Ink circle.
        let fill: Color = scheme == .dark ? .white : Brand.ink
        let ink: Color = scheme == .dark ? Brand.ink : .white
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(Brand.text(12, .medium))
                ZStack {
                    Circle().fill(ink)
                    Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(fill)
                }
                .frame(width: 22, height: 22)
            }
            .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 4)
            .background(fill, in: Capsule())
            .foregroundStyle(ink)
        }
        .buttonStyle(.plain)
    }
}

/// Setting row: a name, a one-sentence explanation and a switch.
struct Toggle2: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @Environment(\.palette) private var pal

    init(_ title: String, detail: String, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Brand.text(12.5, .medium))
                Text(detail).font(Brand.text(10.5)).foregroundStyle(pal.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(pal.toggleTint)
        }
    }
}

/// Small round button with a symbol on the sunk color, like the close button on Lynx's update banner.
struct RoundIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.palette) private var pal
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).foregroundStyle(pal.muted)
                .frame(width: 22, height: 22)
                .background(pal.sunk, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
