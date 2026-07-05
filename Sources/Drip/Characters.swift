import SwiftUI
import AppKit
import DripCore

/// How a Nudgeling is feeling.
enum Expression: Hashable {
    case calm, happy, sleepy, worried, sad, cheer
}

extension Mood {
    /// Drip's face follows hydration.
    var expression: Expression {
        switch self {
        case .hydrated: .happy
        case .thirsty: .worried
        case .parched: .sad
        }
    }
}

/// Everything that moves on a character in one frame.
struct Pose {
    /// Where the eyes point, each axis −1…1 (screen-down is +y).
    var look = CGVector.zero
    /// 0 = open, 1 = shut.
    var blink: Double = 0
    /// Peep's pupil size.
    var pupil: Double = 1
    var legLift: (Double, Double) = (0, 0)
    var ear: Double = 0
    var leaf: Double = 0

    static let rest = Pose()
}

/// One of the seven crew members, drawn in the toy style (ink outline + hard shadow).
/// Frames are square; each body sits on the bottom edge.
///
/// When `animated`, a character is alive: it breathes, blinks on its own rhythm, glances around,
/// follows the cursor with its eyes, performs a signature idle quirk, and hops when hovered or bumped.
struct CharacterView: View {
    let kind: HabitKind
    var expression: Expression = .calm
    var size: CGFloat = 48
    /// Alive (idle motion, blinking, cursor-following eyes, hover hop). Off for snapshots, icons and share cards.
    var animated = false
    var shadow = true
    /// Override the body colour (e.g. a white Drip on an aqua takeover).
    var tint: Color?
    /// Change this to make the character hop and grin (e.g. when a habit is completed).
    var bump = 0

    @Environment(\.motionPaused) private var paused
    @ObservedObject private var motion = Motion.shared
    @State private var reactStart: Date?
    @State private var window: NSWindow?

    var body: some View {
        if animated {
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: size < 60 ? 1 / 20 : 1 / 30, paused: paused)) { tl in
                    let frame = geo.frame(in: .global)
                    live(tl.date, center: CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            .frame(width: size, height: size)
            .background { if !Motion.snapshot { WindowReader(window: $window) } }
            .onHover { inside in if inside { react() } }
            .onChange(of: bump) { _, _ in react() }
        } else {
            canvas(expression, .rest)
                .frame(width: size, height: size)
        }
    }

    private func react() {
        guard !motion.reduced else { return }
        if let r = reactStart, Date().timeIntervalSince(r) < 0.6 { return }
        reactStart = Date()
    }

    // MARK: Choreography

    private var seed: Double { Double(HabitKind.allCases.firstIndex(of: kind) ?? 0) * 1.37 }

    private struct Frame {
        var expr: Expression, pose: Pose, sx: Double, sy: Double, dy: CGFloat, rot: Double, t: Double
    }

    private func live(_ date: Date, center: CGPoint) -> some View {
        let f = frame(date, center: center)
        return ZStack {
            canvas(f.expr, f.pose)
                .scaleEffect(x: f.sx, y: f.sy, anchor: .bottom)
                .rotationEffect(.degrees(f.rot), anchor: .bottom)
                .offset(y: f.dy)
            if expression == .sleepy && !motion.reduced { zzz(f.t) }
        }
    }

    private func frame(_ date: Date, center: CGPoint) -> Frame {
        let t = date.timeIntervalSinceReferenceDate + seed * 3
        let reduced = motion.reduced
        var pose = Pose()
        pose.blink = blinkAmount(t)
        pose.look = look(t, center: center)

        // Signature quirk: every ~8s for ~1.2s
        let qCycle = 7.6 + seed * 0.4
        let q = (t.truncatingRemainder(dividingBy: qCycle)) / 1.2   // 0…1 during the quirk
        let inQuirk = !reduced && q < 1
        var sx = 1.0, sy = 1.0, dy: CGFloat = 0, rot = 0.0

        // Breathing squash (Puff breathes deeper)
        if !reduced {
            let depth = kind == .breathe ? 0.06 : 0.03
            let b = sin(t * (kind == .breathe ? 1.3 : 2.4)) * depth
            sx += b; sy -= b
        }
        if inQuirk {
            switch kind {
            case .water:     // jelly jiggle
                let j = sin(q * .pi * 7) * (1 - q) * 0.09
                sx += j; sy -= j
            case .eyes:      // pupil dilates, eye widens
                pose.pupil = 1 + Ease.bump(q) * 0.45
            case .walk:      // foot tap
                pose.legLift = (Ease.bump(min(1, q * 2)), Ease.bump(max(0, q * 2 - 1)))
            case .stretch:   // ear wiggle
                pose.ear = sin(q * .pi * 6) * (1 - q) * 0.45
            case .posture:   // proud straighten
                sy += Ease.bump(q) * 0.06
            case .breathe:   // big inflate
                let i = Ease.bump(q) * 0.1
                sx += i; sy += i * 0.6
            case .stand:     // little hop
                dy = -CGFloat(Ease.bump(q)) * size * 0.14
            }
        }
        if kind == .posture, !reduced { pose.leaf = sin(t * 1.6) * 0.35 }

        // Hover / bump reaction: hop, squash on landing, grin
        var expr = expression
        if let r = reactStart {
            let e = date.timeIntervalSince(r)
            if e < 0.75 {
                let hop = e < 0.42 ? Ease.bump(e / 0.42) : 0
                dy -= CGFloat(hop) * size * 0.22
                let land = e >= 0.42 ? Ease.bump((e - 0.42) / 0.33) : Ease.bump(min(1, e / 0.08)) * 0.5
                sx += land * 0.14; sy -= land * 0.12
                rot = sin(e * 18) * (1 - e / 0.75) * 6
                if expression != .sleepy && expression != .sad { expr = .cheer }
            }
        }

        return Frame(expr: expr, pose: pose, sx: sx, sy: sy, dy: dy, rot: rot, t: t)
    }

    /// Natural blinking: each character on its own rhythm, with the odd double-blink.
    private func blinkAmount(_ t: Double) -> Double {
        let period = 4.3
        let k = floor(t / period)
        let local = t - k * period
        let at = 0.6 + rnd(Int(k), 11) * 2.8
        func tri(_ x: Double) -> Double { x < 0 || x > 0.15 ? 0 : 1 - abs(x / 0.075 - 1) }
        var b = tri(local - at)
        if rnd(Int(k), 12) < 0.28 { b = max(b, tri(local - at - 0.24)) }
        return b
    }

    /// Eyes follow the cursor when it's near; otherwise they glance around on their own.
    private func look(_ t: Double, center: CGPoint) -> CGVector {
        if let window, let c = window.screenPoint(fromGlobal: center) {
            let m = NSEvent.mouseLocation
            let dx = m.x - c.x, dy = c.y - m.y
            let d = hypot(dx, dy)
            if d < 900, d > 1 {
                let k = min(1, d / 220)
                return CGVector(dx: dx / d * k, dy: dy / d * k)
            }
        }
        guard !motion.reduced else { return .zero }
        let seg = 2.3
        let j = floor(t / seg)
        func target(_ j: Double) -> CGVector {
            rnd(Int(j), 21) < 0.35 ? .zero
                : CGVector(dx: (rnd(Int(j), 22) - 0.5) * 2, dy: (rnd(Int(j), 23) - 0.5) * 1.2)
        }
        let a = target(j - 1), b = target(j)
        let p = Ease.smooth((t - j * seg) / 0.18)   // quick saccade, then hold
        return CGVector(dx: a.dx + (b.dx - a.dx) * p, dy: a.dy + (b.dy - a.dy) * p)
    }

    private func zzz(_ t: Double) -> some View {
        Canvas { ctx, sz in
            for i in 0..<3 {
                let p = ((t * 0.35) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                let x = sz.width * (0.72 + CGFloat(p) * 0.25) + CGFloat(sin(p * 6 + Double(i))) * 3
                let y = sz.height * (0.35 - CGFloat(p) * 0.4)
                var l = ctx
                l.opacity = Ease.bump(p)
                l.draw(Text("z").font(.display(max(7, sz.width * (0.16 + CGFloat(p) * 0.12)), .bold)).foregroundColor(Theme.muted),
                       at: CGPoint(x: x, y: y))
            }
        }
        .allowsHitTesting(false)
    }

    private func canvas(_ expr: Expression, _ pose: Pose) -> some View {
        Canvas { ctx, sz in
            CharacterPainter(kind: kind, expression: expr, pose: pose, shadow: shadow, tint: tint).draw(&ctx, sz)
        }
    }
}

/// Draws a character into any GraphicsContext (also used by the overlay canvas).
struct CharacterPainter {
    let kind: HabitKind
    var expression: Expression = .calm
    var pose = Pose.rest
    var shadow = true
    var tint: Color?

    init(kind: HabitKind, expression: Expression = .calm, pose: Pose = .rest, blink: Bool = false,
         shadow: Bool = true, tint: Color? = nil) {
        self.kind = kind; self.expression = expression; self.pose = pose
        if blink { self.pose.blink = 1 }
        self.shadow = shadow; self.tint = tint
    }

    func draw(_ ctx: inout GraphicsContext, _ sz: CGSize) {
        let s = min(sz.width, sz.height)
        let lw = max(1.4, s * 0.05)
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let body = bodyPath(s, sz)
        if shadow { ctx.fill(body.offsetBy(dx: 0, dy: s * 0.06), with: ink) }
        ctx.fill(body, with: .color(tint ?? kind.color))
        let b = body.boundingRect
        ctx.fill(Path(ellipseIn: CGRect(x: b.minX + b.width * 0.18, y: b.minY + b.height * 0.12,
                                        width: b.width * 0.22, height: b.height * 0.14)),
                 with: .color(.white.opacity(0.45)))
        ctx.stroke(body, with: ink, lineWidth: lw)
        extras(&ctx, s, b, lw)
        face(&ctx, s, b, lw)
    }

    private func bodyPath(_ s: CGFloat, _ sz: CGSize) -> Path {
        let cx = sz.width / 2, bottom = sz.height - s * 0.1
        switch kind {
        case .water:   // egg-drop
            let w = s * 0.62, h = s * 0.78
            let r = CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h)
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + h * 0.62),
                       control1: CGPoint(x: r.midX + w * 0.28, y: r.minY + h * 0.05),
                       control2: CGPoint(x: r.maxX, y: r.minY + h * 0.35))
            p.addCurve(to: CGPoint(x: r.midX, y: r.maxY),
                       control1: CGPoint(x: r.maxX, y: r.minY + h * 0.88), control2: CGPoint(x: r.midX + w * 0.3, y: r.maxY))
            p.addCurve(to: CGPoint(x: r.minX, y: r.minY + h * 0.62),
                       control1: CGPoint(x: r.midX - w * 0.3, y: r.maxY), control2: CGPoint(x: r.minX, y: r.minY + h * 0.88))
            p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                       control1: CGPoint(x: r.minX, y: r.minY + h * 0.35), control2: CGPoint(x: r.midX - w * 0.28, y: r.minY + h * 0.05))
            p.closeSubpath()
            return p
        case .eyes:
            let d = s * 0.74
            return Path(ellipseIn: CGRect(x: cx - d / 2, y: bottom - d, width: d, height: d))
        case .walk:
            let w = s * 0.66, h = s * 0.58
            return Path(roundedRect: CGRect(x: cx - w / 2, y: bottom - h - s * 0.1, width: w, height: h), cornerRadius: s * 0.13)
        case .stretch:
            let w = s * 0.4, h = s * 0.8
            return Path(roundedRect: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h), cornerRadius: w / 2)
        case .posture:
            let w = s * 0.42, h = s * 0.66
            return Path(roundedRect: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h), cornerRadius: w / 2)
        case .breathe:
            let w = s * 0.82, h = s * 0.46
            return Path(ellipseIn: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h))
        case .stand:
            let w = s * 0.62, h = s * 0.62
            return Path(roundedRect: CGRect(x: cx - w / 2, y: bottom - h, width: w, height: h), cornerRadius: s * 0.12)
        }
    }

    private func extras(_ ctx: inout GraphicsContext, _ s: CGFloat, _ b: CGRect, _ lw: CGFloat) {
        let ink = GraphicsContext.Shading.color(Theme.ink)
        switch kind {
        case .walk:
            for (i, dx) in [-0.2, 0.2].enumerated() {
                // A tap is a small forward kick: the foot swings out and up a little.
                let lift = CGFloat(i == 0 ? pose.legLift.0 : pose.legLift.1)
                var leg = Path()
                leg.move(to: CGPoint(x: b.midX + b.width * dx, y: b.maxY))
                leg.addLine(to: CGPoint(x: b.midX + b.width * dx * 1.25 + lift * s * 0.08 * (dx > 0 ? 1 : -1),
                                        y: b.maxY + s * 0.1 - lift * s * 0.035))
                ctx.stroke(leg, with: ink, style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
            }
        case .stretch:
            for side in [-1.0, 1.0] {
                var l = ctx
                let base = CGPoint(x: b.midX + CGFloat(side) * b.width * 0.36, y: b.minY + b.width * 0.35)
                l.translateBy(x: base.x, y: base.y)
                l.rotate(by: .radians(pose.ear * side))
                var ear = Path()
                ear.move(to: .zero)
                ear.addQuadCurve(to: CGPoint(x: CGFloat(side) * s * 0.07, y: b.minY - s * 0.02 - base.y),
                                 control: CGPoint(x: CGFloat(side) * s * 0.12, y: -s * 0.05))
                l.stroke(ear, with: .color(tint ?? kind.color), style: StrokeStyle(lineWidth: lw * 2.6, lineCap: .round))
                l.stroke(ear, with: ink, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
            }
        case .posture:
            var stem = Path()
            stem.move(to: CGPoint(x: b.midX, y: b.minY))
            stem.addLine(to: CGPoint(x: b.midX, y: b.minY - s * 0.08))
            ctx.stroke(stem, with: ink, style: StrokeStyle(lineWidth: lw, lineCap: .round))
            var l = ctx
            l.translateBy(x: b.midX, y: b.minY - s * 0.08)
            l.rotate(by: .radians(pose.leaf))
            let leaf = Path(ellipseIn: CGRect(x: 0, y: -s * 0.05, width: s * 0.14, height: s * 0.08))
            l.fill(leaf, with: .color(Theme.leaf))
            l.stroke(leaf, with: ink, lineWidth: lw * 0.8)
        default: break
        }
    }

    private func face(_ ctx: inout GraphicsContext, _ s: CGFloat, _ b: CGRect, _ lw: CGFloat) {
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let open = 1 - pose.blink
        if kind == .eyes {
            // Peep is one big eye.
            let c = CGPoint(x: b.midX, y: b.midY)
            let r = b.width * 0.34
            if expression == .sleepy || open < 0.15 {
                var lid = Path()
                lid.move(to: CGPoint(x: c.x - r, y: c.y)); lid.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x, y: c.y + r * 0.6))
                ctx.stroke(lid, with: ink, style: StrokeStyle(lineWidth: lw * 1.2, lineCap: .round))
                return
            }
            let eyeRect = CGRect(x: c.x - r, y: c.y - r * CGFloat(open), width: r * 2, height: r * 2 * CGFloat(open))
            let eye = Path(ellipseIn: eyeRect)
            ctx.fill(eye, with: .color(.white))
            var inner = ctx
            inner.clip(to: eye)
            let pr = r * (expression == .worried ? 0.42 : 0.55) * CGFloat(pose.pupil)
            let pc = CGPoint(x: c.x + CGFloat(pose.look.dx) * r * 0.38, y: c.y + CGFloat(pose.look.dy) * r * 0.38)
            inner.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)), with: ink)
            inner.fill(Path(ellipseIn: CGRect(x: pc.x + pr * 0.1, y: pc.y - pr * 0.7, width: pr * 0.5, height: pr * 0.5)), with: .color(.white))
            ctx.stroke(eye, with: ink, lineWidth: lw)
            return
        }

        let eyeY = b.minY + b.height * (kind == .breathe ? 0.45 : (kind == .water ? 0.55 : 0.42))
        let dx = min(b.width * 0.16, s * 0.1)
        let er = max(1.3, s * 0.045)
        let shift = CGPoint(x: CGFloat(pose.look.dx) * er * 0.9, y: CGFloat(pose.look.dy) * er * 0.6)
        let closed = expression == .sleepy || open < 0.2 || (kind == .breathe && expression == .calm)
        for side in [-1.0, 1.0] {
            let c = CGPoint(x: b.midX + CGFloat(side) * dx + shift.x, y: eyeY + shift.y)
            if closed {
                var l = Path()
                l.move(to: CGPoint(x: c.x - er * 1.2, y: c.y)); l.addLine(to: CGPoint(x: c.x + er * 1.2, y: c.y))
                ctx.stroke(l, with: ink, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
            } else if expression == .sad {
                var x = Path()
                x.move(to: CGPoint(x: c.x - er, y: c.y - er)); x.addLine(to: CGPoint(x: c.x + er, y: c.y + er))
                x.move(to: CGPoint(x: c.x + er, y: c.y - er)); x.addLine(to: CGPoint(x: c.x - er, y: c.y + er))
                ctx.stroke(x, with: ink, style: StrokeStyle(lineWidth: lw * 0.8, lineCap: .round))
            } else if expression == .cheer {
                // ^ ^ happy eyes
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - er * 1.1, y: c.y + er * 0.4))
                arc.addQuadCurve(to: CGPoint(x: c.x + er * 1.1, y: c.y + er * 0.4), control: CGPoint(x: c.x, y: c.y - er * 1.3))
                ctx.stroke(arc, with: ink, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
            } else {
                let h = er * 2.3 * CGFloat(open)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - er, y: c.y - h / 2, width: er * 2, height: h)), with: ink)
            }
        }

        let my = eyeY + s * 0.1
        var mouth = Path()
        switch expression {
        case .happy, .cheer:
            mouth.move(to: CGPoint(x: b.midX - dx * 0.8, y: my))
            mouth.addQuadCurve(to: CGPoint(x: b.midX + dx * 0.8, y: my), control: CGPoint(x: b.midX, y: my + s * (expression == .cheer ? 0.12 : 0.07)))
            if expression == .cheer { mouth.closeSubpath(); ctx.fill(mouth, with: ink) } else {
                ctx.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
            }
        case .worried:
            let o = Path(ellipseIn: CGRect(x: b.midX - s * 0.035, y: my - s * 0.01, width: s * 0.07, height: s * 0.07))
            ctx.stroke(o, with: ink, lineWidth: lw * 0.8)
        case .sad:
            mouth.move(to: CGPoint(x: b.midX - dx * 0.7, y: my + s * 0.04))
            mouth.addQuadCurve(to: CGPoint(x: b.midX + dx * 0.7, y: my + s * 0.04), control: CGPoint(x: b.midX, y: my - s * 0.02))
            ctx.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: lw * 0.9, lineCap: .round))
        case .calm, .sleepy:
            break
        }
        if kind == .stretch && expression == .calm {
            let o = Path(ellipseIn: CGRect(x: b.midX - s * 0.04, y: my - s * 0.02, width: s * 0.08, height: s * 0.09))
            ctx.fill(o, with: .color(.white)); ctx.stroke(o, with: ink, lineWidth: lw * 0.8)
        }
    }
}

/// The whole crew in a row (onboarding, about).
/// With `parade`, they drop in one by one, land with a squash, then wave on their own rhythm.
struct CrewRow: View {
    var kinds: [HabitKind] = HabitKind.allCases
    var size: CGFloat = 56
    var animated = true
    var parade = false
    @State private var landed = false
    @ObservedObject private var motion = Motion.shared

    var body: some View {
        HStack(alignment: .bottom, spacing: -size * 0.12) {
            ForEach(Array(kinds.enumerated()), id: \.element) { i, k in
                CharacterView(kind: k, expression: .happy, size: size, animated: animated)
                    .offset(y: parade && !landed && !motion.reduced ? -size * 3.5 : 0)
                    .opacity(parade && !landed ? 0 : 1)
                    .animation(.spring(response: 0.55, dampingFraction: 0.55).delay(0.12 + Double(i) * 0.09), value: landed)
            }
        }
        .onAppear { if parade { landed = true } }
    }
}
