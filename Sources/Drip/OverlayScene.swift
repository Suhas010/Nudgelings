import SwiftUI
import AppKit
import DripCore

struct Celebration: Equatable {
    var kind: HabitKind
    var start: Date
}

/// Everything a screen's overlay needs to draw one frame.
struct OverlayScene: Equatable {
    var presentation: Presentation?
    var mood: Mood = .hydrated
    var bottomLevel: Double?
    var celebration: Celebration?
    var gagStartedAt: Date?
    var water = Tween()
    /// What the character is saying (speech bubbles, dim captions).
    var line = ""

    static let painted: Set<NudgeType> = [.menuShow, .walkAcross, .cursorTrail, .dim, .gag]

    var kind: HabitKind? { presentation?.kind }
    var startedAt: Date { presentation?.attemptStartedAt ?? .distantPast }
    func has(_ t: NudgeType) -> Bool { presentation?.has(t) ?? false }

    /// Something click-through paints on this screen.
    var paints: Bool {
        guard let p = presentation, p.showing else { return false }
        return p.blocksScreen || p.types.contains(where: Self.painted.contains)
    }

    var needsOverlay: Bool { paints || celebration != nil }

    /// Only the menu-bar strip is drawn; don't redraw the whole screen for it.
    var drawsTopStripOnly: Bool {
        guard celebration == nil, let p = presentation else { return false }
        return p.types.filter(Self.painted.contains) == [.menuShow] && !p.blocksScreen
    }

    /// Drip's water gag rises through the show window: waves, then bubbles, then water, then fish.
    func waterTarget(at now: Date) -> Double {
        guard has(.gag), kind == .water else { return 0 }
        switch now.timeIntervalSince(startedAt) {
        case ..<20: return 0
        case ..<50: return 0.2
        default: return 0.35
        }
    }

    func floodLevel(at now: Date) -> Int {
        let e = now.timeIntervalSince(startedAt)
        return e < 10 ? 0 : e < 20 ? 1 : e < 50 ? 2 : 3
    }
}

@MainActor
final class OverlayStore: ObservableObject {
    @Published private(set) var scene = OverlayScene()

    func set(_ new: OverlayScene) {
        var next = new
        next.water = scene.water.retargeted(new.waterTarget(at: Date()), at: Date())
        if next != scene { scene = next }
    }
}

// MARK: - Root view per screen

struct OverlayRoot: View {
    @ObservedObject var store: OverlayStore
    let menuBarHeight: CGFloat
    /// The screen that hosts the takeover panel; other screens just dim while it's up.
    let isMain: Bool
    var screenFrame: CGRect = .zero

    var body: some View {
        let s = store.scene
        ZStack(alignment: .topLeading) {
            if s.kind == .eyes, s.has(.gag) || s.has(.dim) {
                FogView(scene: s)
            }
            if s.needsOverlay {
                SceneCanvas(scene: s, menuBarHeight: menuBarHeight, isMain: isMain, screenFrame: screenFrame)
                    .frame(height: s.drawsTopStripOnly ? menuBarHeight + 280 : nil)
            }
        }
        // Pin to the top: when only the menu-bar strip is drawn, the content is shorter than the screen.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
    }
}

/// The always-on hydration line along the bottom edge. Lives in its own 5pt panel; static, no timeline.
struct BottomWaterLine: View {
    @ObservedObject var store: OverlayStore
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.08))
                Rectangle()
                    .fill(LinearGradient(colors: [waterLight.opacity(0.9), waterDeep.opacity(0.9)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * max(0.02, store.scene.bottomLevel ?? 0))
            }
        }
    }
}

// MARK: - Frame renderer

struct SceneRenderer {
    let scene: OverlayScene
    let date: Date
    let menuBarHeight: CGFloat
    var isMain = true
    /// Recent cursor positions in this screen's coordinates, newest last.
    var trail: [TrailPoint] = []

    var t: Double { date.timeIntervalSinceReferenceDate }
    var elapsed: Double { date.timeIntervalSince(scene.startedAt) }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        if scene.paints, let kind = scene.kind { drawNudges(&ctx, size, kind) }
        if let c = scene.celebration { drawCelebration(&ctx, size, c) }
    }

    private func drawNudges(_ ctx: inout GraphicsContext, _ size: CGSize, _ kind: HabitKind) {
        let fadeIn = min(1, elapsed / 1.2)
        guard let p = scene.presentation else { return }
        if p.blocksScreen {
            // The takeover itself lives in a clickable panel on the main screen; others just go dark.
            if !isMain { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity(0.7 * fadeIn))) }
            return
        }
        if scene.has(.dim) { drawDim(&ctx, size, kind, fadeIn) }
        if scene.has(.gag) { drawGag(&ctx, size, kind, fadeIn) }
        if scene.has(.menuShow) || (scene.has(.gag) && kind == .water) { drawStrip(&ctx, size, kind: kind, intensity: fadeIn) }
        if scene.has(.walkAcross) { drawWalkAcross(&ctx, size, kind) }
        if scene.has(.cursorTrail) { drawTrail(&ctx, kind) }
    }

    private func drawGag(_ ctx: inout GraphicsContext, _ size: CGSize, _ kind: HabitKind, _ fadeIn: Double) {
        switch kind {
        case .water:
            let level = scene.floodLevel(at: date)
            if level >= 1 { WaterPaint.edgeBubbles(&ctx, size: size, top: menuBarHeight, t: t) }
            drawRisingWater(&ctx, size)
            let surface = size.height * (1 - CGFloat(scene.water.value(at: date)))
            if level >= 2 {
                WaterPaint.lightRays(&ctx, width: size.width, surface: surface, bottom: size.height, t: t)
                WaterPaint.seaweed(&ctx, width: size.width, surface: surface, bottom: size.height, t: t)
            }
            if level >= 3 {
                WaterPaint.fish(&ctx, size: size, surface: surface, t: t)
                WaterPaint.crab(&ctx, width: size.width, bottom: size.height, t: t)
            }
        case .eyes: drawFrost(&ctx, size)
        case .posture: drawPosture(&ctx, size, straighten: 0)
        case .stretch: drawJelly(&ctx, size, opacity: fadeIn)
        case .walk: drawFootprints(&ctx, size)
        case .breathe: drawBreathing(&ctx, size, fadeIn)
        case .stand: drawPopUp(&ctx, size)
        }
    }

    private func drawRisingWater(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let f = scene.water.value(at: date)
        guard f > 0.002 else { return }
        let surface = size.height * (1 - CGFloat(f))
        WaterPaint.body(&ctx, width: size.width, surface: surface, bottom: size.height, t: t)
    }

    // MARK: Signature gags

    func headline(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat = 54) {
        var layer = ctx
        layer.addFilter(.shadow(color: .black.opacity(0.45), radius: 10, y: 4))
        layer.draw(Text(text).font(.display(size, .bold)).foregroundColor(.white), at: p)
    }

    private func drawFrost(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let clear = eyesClearProgress
        let fade = min(1, date.timeIntervalSince(scene.startedAt) / 2) * (1 - clear)
        guard fade > 0 else { return }
        ctx.opacity = fade
        for i in 0..<140 {
            let x = CGFloat(rnd(i, 3)) * size.width, y = CGFloat(rnd(i, 4)) * size.height
            let r = CGFloat(2 + rnd(i, 5) * 10)
            ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(.white.opacity(0.25)))
        }
        let msg: String
        if let start = scene.gagStartedAt {
            let left = max(0, Int(HabitKind.eyes.gagSeconds!) - Int(date.timeIntervalSince(start)))
            msg = left > 0 ? "Look 20 feet away… \(left)" : "✨ Crystal clear ✨"
        } else {
            msg = "👀 Look 20 feet away"
        }
        headline(&ctx, msg, at: CGPoint(x: size.width / 2, y: size.height * 0.42), size: 64)
        ctx.opacity = 1
        if clear > 0 { drawWiper(&ctx, size, progress: clear) }
    }

    var eyesClearProgress: Double {
        guard let start = scene.gagStartedAt else { return 0 }
        return min(1, max(0, (date.timeIntervalSince(start) - HabitKind.eyes.gagSeconds!) / HabitKind.wiperSeconds))
    }

    private func drawWiper(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double) {
        let pivot = CGPoint(x: size.width / 2, y: size.height + 20)
        let angle = WiperMask.angle(progress)
        let len = size.height * 1.05
        let tip = CGPoint(x: pivot.x + cos(angle.radians) * len, y: pivot.y + sin(angle.radians) * len)
        var arm = Path(); arm.move(to: pivot); arm.addLine(to: tip)
        ctx.stroke(arm, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        ctx.stroke(arm, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    func drawPosture(_ ctx: inout GraphicsContext, _ size: CGSize, straighten: Double) {
        let tilt = 3.2 * (1 + 0.15 * sin(t * 1.5)) * (1 - straighten)
        var layer = ctx
        layer.translateBy(x: size.width / 2, y: size.height / 2)
        layer.rotate(by: .degrees(tilt))
        layer.translateBy(x: -size.width / 2, y: -size.height / 2)
        let frame = Path(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 18, dy: 18), cornerRadius: 26)
        layer.stroke(frame, with: .color(waterDeep.opacity(0.55)), lineWidth: 18)
        layer.stroke(frame, with: .color(.white.opacity(0.5)), lineWidth: 3)

        // Spirit level
        let vial = CGRect(x: size.width / 2 - 170, y: menuBarHeight + 40, width: 340, height: 50)
        layer.fill(Path(roundedRect: vial, cornerRadius: 25), with: .color(Color(red: 0.75, green: 1, blue: 0.4).opacity(0.85)))
        layer.stroke(Path(roundedRect: vial, cornerRadius: 25), with: .color(.black.opacity(0.4)), lineWidth: 3)
        for dx in [-28.0, 28.0] {
            var tick = Path()
            tick.move(to: CGPoint(x: vial.midX + dx, y: vial.minY + 6)); tick.addLine(to: CGPoint(x: vial.midX + dx, y: vial.maxY - 6))
            layer.stroke(tick, with: .color(.black.opacity(0.5)), lineWidth: 2)
        }
        let bubbleX = vial.midX + CGFloat(tilt / 3.2) * 120
        layer.fill(Path(ellipseIn: CGRect(x: bubbleX - 22, y: vial.midY - 15, width: 44, height: 30)), with: .color(.white.opacity(0.9)))
        if straighten == 0 {
            headline(&layer, "You're tilting! Sit up straight 🪑", at: CGPoint(x: size.width / 2, y: vial.maxY + 60), size: 44)
        }
    }

    private func drawJelly(_ ctx: inout GraphicsContext, _ size: CGSize, opacity: Double) {
        let inset: CGFloat = 16
        let r = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let perimeter = 2 * (r.width + r.height)
        var p = Path()
        var s: CGFloat = 0
        while s <= perimeter {
            let (pt, normal) = pointOnRect(r, s)
            let d = CGFloat(sin(Double(s) / 70 + t * 5) * 10 + sin(Double(s) / 23 - t * 3) * 4)
            let q = CGPoint(x: pt.x + normal.dx * d, y: pt.y + normal.dy * d)
            if s == 0 { p.move(to: q) } else { p.addLine(to: q) }
            s += 8
        }
        p.closeSubpath()
        ctx.opacity = opacity
        ctx.stroke(p, with: .color(waterLight.opacity(0.55)), lineWidth: 22)
        ctx.stroke(p, with: .color(.white.opacity(0.6)), lineWidth: 3)

        if let start = scene.gagStartedAt {
            let elapsed = date.timeIntervalSince(start)
            let poses = [("🙆", "Arms up, reach high"), ("🤸", "Lean left… now right"), ("🔄", "Slow neck rolls")]
            let i = min(poses.count - 1, Int(elapsed / 10))
            let left = max(0, Int(HabitKind.stretch.gagSeconds!) - Int(elapsed))
            let bounce = CGFloat(sin(t * 4)) * 14
            ctx.draw(Text(poses[i].0).font(.system(size: 160)), at: CGPoint(x: size.width / 2, y: size.height * 0.38 + bounce))
            headline(&ctx, "\(poses[i].1) · \(left)s", at: CGPoint(x: size.width / 2, y: size.height * 0.38 + 130), size: 48)
        } else {
            let pulse = 1 + 0.06 * sin(t * 5)
            headline(&ctx, "Stretch time 🙆", at: CGPoint(x: size.width / 2, y: size.height * 0.4), size: 64 * pulse)
        }
        ctx.opacity = 1
    }

    private func pointOnRect(_ r: CGRect, _ s: CGFloat) -> (CGPoint, CGVector) {
        var s = s
        if s < r.width { return (CGPoint(x: r.minX + s, y: r.minY), CGVector(dx: 0, dy: -1)) }
        s -= r.width
        if s < r.height { return (CGPoint(x: r.maxX, y: r.minY + s), CGVector(dx: 1, dy: 0)) }
        s -= r.height
        if s < r.width { return (CGPoint(x: r.maxX - s, y: r.maxY), CGVector(dx: 0, dy: 1)) }
        s -= r.width
        return (CGPoint(x: r.minX, y: r.maxY - min(s, r.height)), CGVector(dx: -1, dy: 0))
    }

    private func drawFootprints(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let steps = 9
        let stride = (size.width / 2 + 80) / CGFloat(steps)
        let cycle = Double(steps) * 0.42 + 2.5
        let local = (date.timeIntervalSince(scene.startedAt)).truncatingRemainder(dividingBy: cycle)
        for i in 0..<steps {
            let appear = Double(i) * 0.42
            guard local >= appear else { continue }
            let age = local - appear
            let alpha = max(0, 1 - age / 3.5)
            let x = size.width / 2 + CGFloat(i) * stride
            let y = size.height * 0.62 + (i % 2 == 0 ? -26 : 26)
            foot(&ctx, at: CGPoint(x: x, y: y), left: i % 2 == 0, alpha: alpha)
        }
        headline(&ctx, "Go for a walk. Follow me →", at: CGPoint(x: size.width / 2, y: size.height * 0.45), size: 52)
    }

    /// One bare footprint pointing right (drawn pointing up, then rotated).
    private func foot(_ ctx: inout GraphicsContext, at c: CGPoint, left: Bool, alpha: Double) {
        var l = ctx
        l.translateBy(x: c.x, y: c.y)
        l.rotate(by: .degrees(90))
        l.scaleBy(x: 1.3, y: 1.3)
        if left { l.scaleBy(x: -1, y: 1) }
        let ink = GraphicsContext.Shading.color(Color(red: 0.1, green: 0.2, blue: 0.35).opacity(0.7 * alpha))
        let rim = GraphicsContext.Shading.color(.white.opacity(0.85 * alpha))
        var sole = Path()
        sole.move(to: CGPoint(x: -2, y: -18))
        sole.addCurve(to: CGPoint(x: 12, y: 8), control1: CGPoint(x: 12, y: -18), control2: CGPoint(x: 14, y: -4))
        sole.addCurve(to: CGPoint(x: 6, y: 34), control1: CGPoint(x: 10, y: 18), control2: CGPoint(x: 12, y: 28))
        sole.addCurve(to: CGPoint(x: -8, y: 30), control1: CGPoint(x: 1, y: 42), control2: CGPoint(x: -9, y: 40))
        sole.addCurve(to: CGPoint(x: -4, y: 6), control1: CGPoint(x: -7, y: 22), control2: CGPoint(x: -1, y: 16))
        sole.addCurve(to: CGPoint(x: -2, y: -18), control1: CGPoint(x: -11, y: -4), control2: CGPoint(x: -12, y: -18))
        sole.closeSubpath()
        l.fill(sole, with: ink); l.stroke(sole, with: rim, lineWidth: 1.4)
        let toes: [(CGFloat, CGFloat, CGFloat)] = [(-6, -26, 5.5), (2, -28, 4), (8, -25.5, 3.4), (12.5, -21, 3), (15, -15.5, 2.6)]
        for (x, y, r) in toes {
            let toe = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.2))
            l.fill(toe, with: ink); l.stroke(toe, with: rim, lineWidth: 1.1)
        }
    }

}

// MARK: - Eyes fog (real behind-window blur)

struct FogView: View {
    let scene: OverlayScene
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
            let fadeIn = min(1, tl.date.timeIntervalSince(scene.startedAt) / 2)
            let clear = SceneRenderer(scene: scene, date: tl.date, menuBarHeight: 0).eyesClearProgress
            BehindWindowBlur()
                .opacity(fadeIn)
                .mask(WiperMask(progress: clear).fill(style: FillStyle(eoFill: true)))
        }
    }
}

/// Full rect minus the sector the wiper has swept.
struct WiperMask: Shape {
    var progress: Double
    static func angle(_ progress: Double) -> Angle { .degrees(-170 + 160 * progress) }

    func path(in r: CGRect) -> Path {
        if progress >= 1 { return Path() }
        var p = Path(r)
        guard progress > 0 else { return p }
        let pivot = CGPoint(x: r.midX, y: r.maxY + 20)
        p.move(to: pivot)
        p.addArc(center: pivot, radius: r.height * 1.2, startAngle: Self.angle(0), endAngle: Self.angle(progress), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .fullScreenUI
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
