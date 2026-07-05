import SwiftUI
import AppKit
import CoreText
import DripCore

/// Nudgelings look: toy-like, chunky ink outlines, hard drop shadows, Fredoka + Nunito.
enum Theme {
    static let ink = Color(hex: 0x10231d)
    static let aqua = Color(hex: 0x5cc8e0)
    static let aquaDeep = Color(hex: 0x3fb3cf)
    static let leaf = Color(hex: 0x6fcf6f)
    static let sun = Color(hex: 0xeed35a)
    static let coral = Color(hex: 0xef8f7a)
    static let lilac = Color(hex: 0xb79be6)
    static let sprout = Color(hex: 0x9fdc8a)
    static let orange = Color(hex: 0xf5a55a)

    // Adaptive surfaces (light ↔ dark), matching the design's paired screens.
    static let paper = Color(light: 0xfbfdfb, dark: 0x1d2e27)
    static let canvas = Color(light: 0xeef1ef, dark: 0x10231d)
    static let raised = Color(light: 0xffffff, dark: 0x2a3d35)
    static let text = Color(light: 0x10231d, dark: 0xeef1ef)
    static let muted = Color(light: 0x5b6e67, dark: 0x9fb5ac)
    static let line = Color(light: 0xcfd9d4, dark: 0x3f524b)
    static let outline = Color(light: 0x10231d, dark: 0x0b1813)

    /// Selected pills: dark in light mode, light in dark mode (so they never vanish into the background).
    static let inverse = Color(light: 0x10231d, dark: 0xeef1ef)
    static let inverseText = Color(light: 0xffffff, dark: 0x10231d)

    static let stroke: CGFloat = 2.5
}

extension HabitKind {
    var color: Color {
        switch self {
        case .water: Theme.aqua
        case .eyes: Theme.sun
        case .walk: Theme.leaf
        case .stretch: Theme.coral
        case .posture: Theme.sprout
        case .breathe: Theme.lilac
        case .stand: Theme.orange
        }
    }

    /// Readable text/icon colour for this character on app surfaces (≥4.5:1 in both modes).
    /// The pastel `color` is for fills only — sun or sprout text on white is unreadable.
    var accent: Color {
        switch self {
        case .water: Color(light: 0x0b6f86, dark: 0x5cc8e0)
        case .eyes: Color(light: 0x7a5c00, dark: 0xeed35a)
        case .walk: Color(light: 0x1f7a33, dark: 0x6fcf6f)
        case .stretch: Color(light: 0xb23f28, dark: 0xef8f7a)
        case .posture: Color(light: 0x3b7a23, dark: 0x9fdc8a)
        case .breathe: Color(light: 0x6a44b8, dark: 0xb79be6)
        case .stand: Color(light: 0xa8520c, dark: 0xf5a55a)
        }
    }

    /// Pale card fill for this character (light mode), deep tint in dark mode.
    var wash: Color {
        switch self {
        case .water: Color(light: 0xdff4f8, dark: 0x1f3f45)
        case .eyes: Color(light: 0xfbf3d2, dark: 0x3d3a22)
        case .walk: Color(light: 0xe3f5df, dark: 0x234027)
        case .stretch: Color(light: 0xfbe6e0, dark: 0x45302b)
        case .posture: Color(light: 0xeaf6e3, dark: 0x2a3f27)
        case .breathe: Color(light: 0xefe8fb, dark: 0x352c45)
        case .stand: Color(light: 0xfdeedd, dark: 0x45351f)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255, opacity: alpha)
    }

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }
}

// MARK: - Fonts

enum Fonts {
    /// Registers the bundled Fredoka + Nunito (OFL). Looks in the app bundle, then the source tree for dev runs.
    static func register() {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
            URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Resources/Fonts"),
        ].compactMap { $0 }
        for dir in candidates {
            let urls = ["Fredoka.ttf", "Nunito.ttf"].map { dir.appendingPathComponent($0) }
            guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else { continue }
            CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
            return
        }
    }
}

extension Font {
    /// Rounded display face for headings and buttons.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .custom("Fredoka", size: size).weight(weight)
    }
    /// Friendly body face.
    static func body(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .custom("Nunito", size: size).weight(weight)
    }
}

// MARK: - Toy surfaces

/// Chunky card: fill, ink outline, hard drop shadow.
struct ToyCard: ViewModifier {
    var fill: Color = Theme.raised
    var radius: CGFloat = 16
    var shadow: CGFloat = 4
    var dashed = false

    func body(content: Content) -> some View {
        // Each .background sits behind everything before it: fill first, then the hard shadow under it.
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.outline)
                    .offset(y: shadow)
                    .opacity(dashed ? 0 : 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(dashed ? Theme.line : Theme.outline,
                                  style: StrokeStyle(lineWidth: dashed ? 2 : Theme.stroke, dash: dashed ? [6, 5] : []))
            )
    }
}

extension View {
    func toyCard(_ fill: Color = Theme.raised, radius: CGFloat = 16, shadow: CGFloat = 4, dashed: Bool = false) -> some View {
        modifier(ToyCard(fill: fill, radius: radius, shadow: shadow, dashed: dashed))
    }
}

/// The design's buttons: filled, outlined in ink, with a hard shadow that squashes on press.
struct ToyButton: ButtonStyle {
    var fill: Color = Theme.leaf
    var textColor: Color = Theme.ink
    var size: CGFloat = 14
    var wide = false

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.display(size, .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, size * 1.1)
            .padding(.vertical, size * 0.6)
            .frame(maxWidth: wide ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(fill))
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.outline).offset(y: pressed ? 1 : 3.5))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.outline, lineWidth: Theme.stroke))
            .offset(y: pressed ? 2.5 : 0)
            .contentShape(Rectangle())
            .handCursor()
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: pressed)
    }
}

/// Pill-shaped segmented chip.
struct ChipStyle: ButtonStyle {
    var selected: Bool
    var tint: Color = Theme.leaf
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.display(12.5, .semibold))
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(selected ? tint : Color.clear))
            .overlay(Capsule().strokeBorder(selected ? Theme.outline : Theme.muted.opacity(0.45), lineWidth: selected ? 2 : 1.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .contentShape(Capsule())
            .handCursor()
    }
}

/// Chunky ink-outlined switch, as in the crew list.
struct ToySwitch: ToggleStyle {
    var tint: Color = Theme.ink
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? tint : Theme.line.opacity(0.6))
                Circle().fill(.white).overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2)).padding(3)
            }
            .frame(width: 44, height: 26)
            .overlay(Capsule().strokeBorder(Theme.outline, lineWidth: 2))
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

// MARK: - Pointer

/// Pointing-hand cursor over anything clickable.
struct HandCursor: ViewModifier {
    @State private var pushed = false
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content
                .onHover { inside in
                    if inside, !pushed { NSCursor.pointingHand.push(); pushed = true }
                    if !inside, pushed { NSCursor.pop(); pushed = false }
                }
                .onDisappear { if pushed { NSCursor.pop(); pushed = false } }
        }
    }
}

extension View {
    func handCursor() -> some View { modifier(HandCursor()) }
}
