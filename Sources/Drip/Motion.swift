import SwiftUI
import AppKit

/// Shared motion switches: Reduce Motion, and whether the popover (the busiest surface) is on screen.
@MainActor
final class Motion: ObservableObject {
    static let shared = Motion()
    /// macOS "Reduce motion": idle choreography and big reveals turn into gentle fades.
    @Published private(set) var reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    @Published var popoverOpen = false
    /// Windows by id ("main", "onboarding") that are on screen and not fully covered.
    @Published var visibleWindows: Set<String> = []
    /// Offscreen snapshot rendering: skip entrances (their onAppear animations never run there).
    nonisolated(unsafe) static var snapshot = false

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in Motion.shared.reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        }
    }
}

private struct MotionPausedKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Pauses every character timeline below (e.g. the popover while it's closed).
    var motionPaused: Bool {
        get { self[MotionPausedKey.self] }
        set { self[MotionPausedKey.self] = newValue }
    }
}

/// Finds the NSWindow hosting a SwiftUI view (for converting view points to screen points).
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ v: NSView, context: Context) {
        DispatchQueue.main.async { if window !== v.window { window = v.window } }
    }
}

extension NSWindow {
    /// A point in the hosting view's SwiftUI global space → screen coordinates.
    func screenPoint(fromGlobal p: CGPoint) -> CGPoint? {
        guard let cv = contentView else { return nil }
        let local = cv.isFlipped ? p : CGPoint(x: p.x, y: cv.bounds.height - p.y)
        return convertPoint(toScreen: cv.convert(local, to: nil))
    }
}

/// Small easing / keyframe helpers shared by SwiftUI-side motion.
enum Ease {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func outBack(_ x: Double, _ s: Double = 1.7) -> Double {
        let p = clamp(x) - 1
        return 1 + (s + 1) * p * p * p + s * p * p
    }
    /// 0 → 1 → 0 bump over `x` in 0…1.
    static func bump(_ x: Double) -> Double { x <= 0 || x >= 1 ? 0 : sin(x * .pi) }
    static func smooth(_ x: Double) -> Double { let p = clamp(x); return p * p * (3 - 2 * p) }
}

// MARK: - Reusable motion views

/// Staggered entrance: rises and fades in `delay` after appearing.
struct Entrance: ViewModifier {
    var delay: Double
    var from: CGFloat = 18
    @State private var shown = false
    @ObservedObject private var motion = Motion.shared

    func body(content: Content) -> some View {
        let on = shown || Motion.snapshot
        return content
            .opacity(on ? 1 : 0)
            .offset(y: on || motion.reduced ? 0 : from)
            .scaleEffect(on || motion.reduced ? 1 : 0.96, anchor: .bottom)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func entrance(_ index: Int, step: Double = 0.045, base: Double = 0.05, from: CGFloat = 18) -> some View {
        modifier(Entrance(delay: base + Double(index) * step, from: from))
    }
}

/// A one-shot confetti/sparkle burst, replayed whenever `trigger` changes.
struct Burst: View {
    var trigger: Int
    var colors: [Color]
    var count = 26
    var power: CGFloat = 140
    @State private var start: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: start == nil)) { tl in
            Canvas { ctx, size in
                guard let start else { return }
                let e = tl.date.timeIntervalSince(start)
                guard e < 1.1 else { return }
                let o = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<count {
                    let a = Double(i) / Double(count) * 2 * .pi + rnd(i, trigger) * 0.6
                    let v = Double(power) * (0.55 + rnd(i, trigger + 1) * 0.6)
                    let x = o.x + CGFloat(cos(a) * v * e)
                    let y = o.y + CGFloat(sin(a) * v * e + 260 * e * e)
                    var l = ctx
                    l.opacity = max(0, 1 - e / 1.1)
                    l.translateBy(x: x, y: y)
                    l.rotate(by: .radians(e * 9 + Double(i)))
                    let w = 4 + CGFloat(rnd(i, trigger + 2)) * 4
                    if i % 3 == 0 {
                        l.fill(Fx.starPath(center: .zero, radius: w, points: 4, inner: 0.35), with: .color(colors[i % colors.count]))
                    } else {
                        l.fill(Path(roundedRect: CGRect(x: -w / 2, y: -w, width: w, height: w * 1.8), cornerRadius: 1.5),
                               with: .color(colors[i % colors.count]))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in if !Motion.shared.reduced { start = Date() } }
    }
}

/// Pauses a window's character timelines while it isn't visible.
struct PauseWhenHidden: ViewModifier {
    let id: String
    @ObservedObject private var motion = Motion.shared
    func body(content: Content) -> some View {
        content.environment(\.motionPaused, !motion.visibleWindows.contains(id))
    }
}
