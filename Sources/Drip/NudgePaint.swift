import SwiftUI
import AppKit
import DripCore

struct TrailPoint { var p: CGPoint; var age: Double }

/// Samples the cursor while a cursor-trail nudge is up. NSEvent.mouseLocation needs no permission.
@MainActor
final class MouseTrail {
    static let shared = MouseTrail()
    private var samples: [(CGPoint, Date)] = []
    private var lastSample = Date.distantPast
    nonisolated static let lifetime: Double = 1.1

    func points(in frame: CGRect, now: Date) -> [TrailPoint] {
        if now.timeIntervalSince(lastSample) > 1 / 40 {
            let m = NSEvent.mouseLocation
            if samples.last.map({ hypot($0.0.x - m.x, $0.0.y - m.y) > 6 }) ?? true { samples.append((m, now)) }
            lastSample = now
        }
        samples.removeAll { now.timeIntervalSince($0.1) > Self.lifetime }
        return samples.compactMap { pt, when in
            guard frame.contains(pt) else { return nil }
            return TrailPoint(p: CGPoint(x: pt.x - frame.minX, y: frame.maxY - pt.y), age: now.timeIntervalSince(when))
        }
    }
}

extension SceneRenderer {
    // MARK: Dim

    func drawDim(_ ctx: inout GraphicsContext, _ size: CGSize, _ kind: HabitKind, _ fade: Double) {
        let w = size.width, h = size.height
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.ink.opacity((kind == .eyes ? 0.45 : 0.55) * fade)))
        var l = ctx
        l.opacity = fade
        switch kind {
        case .eyes:
            // Peep's spotlight: ring countdown + big timer, as in the design.
            let total = HabitKind.eyes.gagSeconds ?? 20
            let left = max(0, total - elapsed)
            let c = CGPoint(x: w * 0.36, y: h * 0.5)
            let r: CGFloat = 130
            let track = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            l.stroke(track, with: .color(Color(hex: 0x2a3d35)), lineWidth: 26)
            var arc = Path()
            arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * (left / total)), clockwise: false)
            l.stroke(arc, with: .color(Theme.sun), style: StrokeStyle(lineWidth: 26, lineCap: .round))
            if let peep = l.resolveSymbol(id: SceneSymbol.crew(.eyes)) { l.draw(peep, at: CGPoint(x: c.x, y: c.y + 10)) }
            let tx = w * 0.36 + r + 70
            l.draw(Text(String(format: "0:%02d", Int(left.rounded(.up)))).font(.display(110, .bold)).foregroundColor(Theme.sun),
                   at: CGPoint(x: tx, y: h * 0.40), anchor: .leading)
            l.draw(Text("Look at something\n20 feet away.").font(.display(42, .bold)).foregroundColor(.white),
                   at: CGPoint(x: tx, y: h * 0.53), anchor: .leading)
            l.draw(Text("A window, a plant, a coworker's suspiciously\nnice chair. Peep is looking with you.")
                    .font(.body(19)).foregroundColor(.white.opacity(0.75)),
                   at: CGPoint(x: tx, y: h * 0.63), anchor: .leading)
        case .posture:
            if let sprout = l.resolveSymbol(id: SceneSymbol.crew(.posture)) { l.draw(sprout, at: CGPoint(x: w / 2, y: h * 0.42)) }
            l.draw(Text("Sprout dimmed your screen.").font(.display(46, .bold)).foregroundColor(.white), at: CGPoint(x: w / 2, y: h * 0.58))
            l.draw(Text("Sit up straight and it brightens again.").font(.body(20)).foregroundColor(.white.opacity(0.8)),
                   at: CGPoint(x: w / 2, y: h * 0.64))
        default:
            if let who = l.resolveSymbol(id: SceneSymbol.crew(kind)) { l.draw(who, at: CGPoint(x: w / 2, y: h * 0.42)) }
            l.draw(Text(scene.line).font(.display(40, .bold)).foregroundColor(.white), at: CGPoint(x: w / 2, y: h * 0.58))
        }
    }

    // MARK: Walk-across

    func drawWalkAcross(_ ctx: inout GraphicsContext, _ size: CGSize, _ kind: HabitKind) {
        let w = size.width
        let groundY = size.height - 70
        let speed = 120.0
        let x = CGFloat((elapsed * speed).truncatingRemainder(dividingBy: Double(w + 360))) - 160
        let bob = CGFloat(abs(sin(t * 7))) * 7
        // Little legs (Stompy draws his own)
        if kind != .walk {
            let swing = sin(t * 7) * 0.5
            for (k, side) in [-1.0, 1.0].enumerated() {
                let hip = CGPoint(x: x + CGFloat(side) * 14, y: groundY - 18)
                let a = (k == 0 ? swing : -swing) + .pi / 2
                var leg = Path()
                leg.move(to: hip)
                leg.addLine(to: CGPoint(x: hip.x + CGFloat(cos(a)) * 22, y: hip.y + CGFloat(sin(a)) * 22))
                ctx.stroke(leg, with: .color(Theme.ink), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
        }
        if let who = ctx.resolveSymbol(id: SceneSymbol.crew(kind)) {
            ctx.draw(who, at: CGPoint(x: x, y: groundY - 70 - bob))
        }
        // Speech bubble pops in (with overshoot) a beat after each entrance
        let lapTime = Double(w + 360) / speed
        let lapE = elapsed.truncatingRemainder(dividingBy: lapTime)
        let pop = CGFloat(Ease.outBack(min(1, max(0, (lapE - 0.9) / 0.35)), 2.2))
        guard pop > 0.01 else { return }
        let text = ctx.resolve(Text(scene.line).font(.display(19, .semibold)).foregroundColor(Theme.ink))
        let ts = text.measure(in: CGSize(width: 340, height: 200))
        let anchor = CGPoint(x: x + 70, y: groundY - 200 - bob + ts.height + 26)
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.scaleBy(x: pop, y: pop)
        ctx.translateBy(x: -anchor.x, y: -anchor.y)
        let bubble = CGRect(x: x + 70, y: groundY - 200 - bob, width: ts.width + 36, height: ts.height + 26)
        let shape = Path(roundedRect: bubble, cornerRadius: 16)
        ctx.fill(shape.offsetBy(dx: 0, dy: 4), with: .color(Theme.ink))
        ctx.fill(shape, with: .color(.white))
        ctx.stroke(shape, with: .color(Theme.ink), lineWidth: 2.5)
        var tail = Path()
        tail.move(to: CGPoint(x: bubble.minX + 22, y: bubble.maxY - 1))
        tail.addLine(to: CGPoint(x: bubble.minX + 4, y: bubble.maxY + 18))
        tail.addLine(to: CGPoint(x: bubble.minX + 40, y: bubble.maxY - 1))
        ctx.fill(tail, with: .color(.white))
        ctx.stroke(tail, with: .color(Theme.ink), lineWidth: 2.5)
        ctx.draw(text, in: bubble.insetBy(dx: 18, dy: 13))
    }

    // MARK: Cursor trail

    func drawTrail(_ ctx: inout GraphicsContext, _ kind: HabitKind) {
        for (i, pt) in trail.enumerated() {
            let life = pt.age / MouseTrail.lifetime
            let a = max(0, 1 - life)
            var l = ctx
            l.opacity = a
            let p = pt.p
            switch kind {
            case .water:
                let r: CGFloat = 7 + CGFloat(rnd(i, 3)) * 5
                let y = p.y + 14 + CGFloat(pt.age * pt.age) * 260
                let rect = CGRect(x: p.x - r / 2, y: y, width: r, height: r / 0.76)
                l.fill(DropShape().path(in: rect), with: .color(Theme.aqua))
                l.stroke(DropShape().path(in: rect), with: .color(Theme.ink), lineWidth: 1.5)
            case .eyes:
                l.fill(Fx.starPath(center: CGPoint(x: p.x + 12, y: p.y + 12), radius: 9 * CGFloat(1 - life * 0.5), points: 4, inner: 0.3),
                       with: .color(Theme.sun))
            case .walk:
                let dy: CGFloat = i % 2 == 0 ? -6 : 6
                l.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y + 16 + dy, width: 10, height: 14)), with: .color(Theme.ink.opacity(0.7)))
            case .stretch:
                l.fill(Path(roundedRect: CGRect(x: p.x + 8, y: p.y + 8 + CGFloat(pt.age * 60), width: 7, height: 11), cornerRadius: 2),
                       with: .color(Fx.party[i % Fx.party.count]))
            case .posture:
                l.fill(Path(ellipseIn: CGRect(x: p.x + 8, y: p.y + 10 + CGFloat(pt.age * 80), width: 12, height: 7)), with: .color(Theme.leaf))
            case .breathe:
                let r = 6 + CGFloat(life) * 28
                l.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(Theme.lilac), lineWidth: 2.5)
            case .stand:
                l.draw(Text("↑").font(.display(18, .bold)).foregroundColor(Theme.orange),
                       at: CGPoint(x: p.x + 14, y: p.y + 10 - CGFloat(pt.age * 50)))
            }
        }
    }

    // MARK: New signature gags

    /// Puff's breathing: the screen edges swell in (4s) and out (6s) with a guide.
    func drawBreathing(_ ctx: inout GraphicsContext, _ size: CGSize, _ fade: Double) {
        let cycle = elapsed.truncatingRemainder(dividingBy: 10)
        let inhaling = cycle < 4
        let breath = inhaling ? Fx.easeInOut(cycle / 4) : 1 - Fx.easeInOut((cycle - 4) / 6)
        let edge = 60 + CGFloat(breath) * 220
        let rect = CGRect(origin: .zero, size: size)
        ctx.opacity = fade
        ctx.fill(Path(rect), with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.35), .init(color: Theme.lilac.opacity(0.55), location: 1)]),
            center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0,
            endRadius: max(size.width, size.height) * 0.75 - edge))
        if let puff = ctx.resolveSymbol(id: SceneSymbol.crew(.breathe)) {
            var l = ctx
            let s = 0.85 + 0.35 * breath
            l.translateBy(x: size.width / 2, y: size.height * 0.42)
            l.scaleBy(x: s, y: s)
            l.draw(puff, at: .zero)
        }
        let round = Int(elapsed / 10) + 1
        headline(&ctx, inhaling ? "Breathe in… \(4 - Int(cycle))" : "…and out \(6 - Int(cycle - 4))",
                 at: CGPoint(x: size.width / 2, y: size.height * 0.6), size: 56)
        ctx.draw(Text("Breath \(min(3, round)) of 3").font(.body(18)).foregroundColor(.white.opacity(0.85)),
                 at: CGPoint(x: size.width / 2, y: size.height * 0.66))
        ctx.opacity = 1
    }

    /// Pop keeps popping up from the bottom edge until you stand.
    func drawPopUp(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let hop = CGFloat(abs(sin(elapsed * 2.4)))
        let y = size.height + 40 - hop * 230
        if let pop = ctx.resolveSymbol(id: SceneSymbol.crew(.stand)) {
            var l = ctx
            l.translateBy(x: size.width / 2, y: y)
            l.rotate(by: .degrees(sin(elapsed * 4.8) * 8))
            l.draw(pop, at: .zero)
        }
        if hop > 0.75 {
            headline(&ctx, "Pop! Up you get.", at: CGPoint(x: size.width / 2, y: y - 120), size: 50)
        }
    }
}
