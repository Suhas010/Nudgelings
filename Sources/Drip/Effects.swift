import SwiftUI
import DripCore

/// Symbols the scene canvas can stamp (real SwiftUI views, resolved once per frame).
enum SceneSymbol: Hashable { case hero, walker, crew(HabitKind), mini(HabitKind) }

/// The animated overlay: one Canvas driven by a timeline, with Drip available as a symbol.
struct SceneCanvas: View {
    let scene: OverlayScene
    let menuBarHeight: CGFloat
    var isMain = true
    /// This screen's frame in global coordinates (for the cursor trail).
    var screenFrame: CGRect = .zero
    /// Freeze time (snapshots); nil = live.
    var fixedDate: Date?

    var body: some View {
        if let fixedDate {
            canvas(fixedDate)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 24)) { tl in canvas(tl.date) }
        }
    }

    private func canvas(_ date: Date) -> some View {
        Canvas { ctx, size in
            let trail = scene.has(.cursorTrail) && fixedDate == nil
                ? MouseTrail.shared.points(in: screenFrame, now: date) : []
            SceneRenderer(scene: scene, date: date, menuBarHeight: menuBarHeight, isMain: isMain, trail: trail).draw(&ctx, size)
        } symbols: {
            CharacterView(kind: .water, expression: .cheer, size: 300).tag(SceneSymbol.hero)
            CharacterView(kind: .walk, expression: .happy, size: max(18, menuBarHeight * 0.9), shadow: false).tag(SceneSymbol.walker)
            ForEach(HabitKind.allCases) { k in
                CharacterView(kind: k, expression: k == .water ? scene.mood.expression : .happy, size: 150).tag(SceneSymbol.crew(k))
            }
            CharacterView(kind: .stand, expression: .happy, size: max(18, menuBarHeight * 0.9), shadow: false).tag(SceneSymbol.mini(.stand))
        }
    }
}

extension Celebration {
    var duration: TimeInterval { kind == .water ? 3.3 : 2.6 }
}

// MARK: - Shared motion helpers

enum Fx {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    static func easeIn(_ x: Double) -> Double { pow(clamp(x), 3) }
    static func easeInOut(_ x: Double) -> Double {
        let p = clamp(x)
        return p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }
    /// Springy 0 → 1 with overshoot; `t` in seconds.
    static func spring(_ t: Double) -> Double { t <= 0 ? 0 : 1 - exp(-6 * t) * cos(13 * t) }

    static let party: [Color] = [
        Color(red: 1, green: 0.35, blue: 0.45), Color(red: 1, green: 0.78, blue: 0.2), Color(red: 0.3, green: 0.85, blue: 0.5),
        Color(red: 0.35, green: 0.7, blue: 1), Color(red: 0.7, green: 0.45, blue: 1), .white,
    ]
    static let gold: [Color] = [Color(red: 1, green: 0.84, blue: 0.3), Color(red: 1, green: 0.7, blue: 0.15), .white]

    static func popText(_ ctx: inout GraphicsContext, _ text: String, at p: CGPoint, size: CGFloat,
                        localTime: Double, fade: Double) {
        let s = spring(localTime * 1.5)
        guard s > 0.01, fade > 0 else { return }
        var l = ctx
        l.opacity = fade
        l.translateBy(x: p.x, y: p.y)
        l.scaleBy(x: s, y: s)
        l.addFilter(.shadow(color: .black.opacity(0.45), radius: 14, y: 6))
        l.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
        l.draw(Text(text).font(.display(size, .bold)).foregroundColor(.white), at: .zero)
    }

    /// Paper confetti shot from `origin`, arcing under gravity with a 3D flutter.
    static func confetti(_ ctx: inout GraphicsContext, origin: CGPoint, elapsed e: Double, count: Int,
                         speed: ClosedRange<Double>, spread: Double, colors: [Color], salt: Int, fade: Double) {
        guard e > 0, fade > 0 else { return }
        for i in 0..<count {
            let ang = -Double.pi / 2 + (rnd(i, salt) - 0.5) * spread
            let v = speed.lowerBound + rnd(i, salt + 1) * (speed.upperBound - speed.lowerBound)
            let drag = 1 - min(0.6, e * 0.35)
            let x = origin.x + CGFloat(cos(ang) * v * e * drag + sin(e * 3 + Double(i)) * 12)
            let y = origin.y + CGFloat(sin(ang) * v * e * drag + 0.5 * 1100 * e * e)
            var l = ctx
            l.opacity = fade
            l.translateBy(x: x, y: y)
            l.rotate(by: .radians(e * (4 + rnd(i, salt + 2) * 8) + Double(i)))
            l.scaleBy(x: 1, y: CGFloat(cos(e * 7 + Double(i))))
            let w = 7 + CGFloat(rnd(i, salt + 3)) * 7
            l.fill(Path(roundedRect: CGRect(x: -w / 2, y: -w * 0.8, width: w, height: w * 1.6), cornerRadius: 2),
                   with: .color(colors[i % colors.count]))
        }
    }

    /// Pieces falling from the top edge.
    static func rain(_ ctx: inout GraphicsContext, width: CGFloat, elapsed e: Double, count: Int, colors: [Color],
                     salt: Int, fade: Double, stars: Bool = false) {
        for i in 0..<count {
            let delay = rnd(i, salt) * 0.8
            let tt = e - delay
            guard tt > 0 else { continue }
            let x = CGFloat(rnd(i, salt + 1)) * width + CGFloat(sin(tt * 3 + Double(i))) * 20
            let y = -30 + CGFloat(tt * (380 + rnd(i, salt + 2) * 420))
            var l = ctx
            l.opacity = fade
            l.translateBy(x: x, y: y)
            l.rotate(by: .radians(tt * 5 + Double(i)))
            let r = 7 + CGFloat(rnd(i, salt + 3)) * 9
            let shape = stars ? starPath(center: .zero, radius: r)
                              : Path(roundedRect: CGRect(x: -r / 2, y: -r, width: r, height: r * 1.6), cornerRadius: 2)
            l.fill(shape, with: .color(colors[i % colors.count]))
        }
    }

    static func starPath(center c: CGPoint, radius r: CGFloat, points: Int = 5, inner: CGFloat = 0.45) -> Path {
        var p = Path()
        for k in 0..<(points * 2) {
            let a = Double(k) * .pi / Double(points) - .pi / 2
            let rr = k % 2 == 0 ? r : r * inner
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    static func rings(_ ctx: inout GraphicsContext, center: CGPoint, elapsed e: Double, count: Int,
                      color: Color, speed: Double = 900, fade: Double) {
        for k in 0..<count {
            let tt = e - Double(k) * 0.22
            guard tt > 0 else { continue }
            let r = CGFloat(tt * speed)
            let a = max(0, 1 - tt / 1.4) * fade
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                       with: .color(color.opacity(0.55 * a)), lineWidth: CGFloat(10 * (1 - tt / 1.6)).clamped(1, 10))
        }
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(hi, Swift.max(lo, self)) }
}

// MARK: - Menu-bar strips (a different show per habit)

extension SceneRenderer {
    func drawStrip(_ ctx: inout GraphicsContext, _ size: CGSize, kind: HabitKind, intensity: Double) {
        let h = menuBarHeight, w = size.width
        switch kind {
        case .water:
            WaterPaint.menuBarWaves(&ctx, width: w, height: h, t: t, intensity: intensity)
            WaterPaint.menuDrips(&ctx, width: w, top: h, t: t, intensity: intensity)
        case .eyes: eyesStrip(&ctx, w, h, intensity)
        case .posture: postureStrip(&ctx, w, h, intensity)
        case .stretch: stretchStrip(&ctx, w, h, intensity)
        case .walk: walkStrip(&ctx, w, h, intensity)
        case .breathe: breatheStrip(&ctx, w, h, intensity)
        case .stand: standStrip(&ctx, w, h, intensity)
        }
    }

    private func tintBand(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ kind: HabitKind, _ a: Double) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .linearGradient(Gradient(colors: [kind.color.opacity(0.18 * a), kind.color.opacity(0.38 * a)]),
                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
    }

    /// Cartoon eyes peeking along the menu bar, looking around and blinking.
    private func eyesStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        tintBand(&ctx, w, h, .eyes, a)
        let ew = h * 0.62, eh = h * 0.7
        var i = 0
        var x: CGFloat = 70
        ctx.opacity = a
        while x < w - 40 {
            let cycle = 3.4
            let local = (t + rnd(i, 11) * cycle).truncatingRemainder(dividingBy: cycle)
            let open = local < 0.16 ? abs(local / 0.08 - 1) : 1
            let look = CGFloat(sin(t * 1.1 + Double(i) * 0.9))
            for side in [-1.0, 1.0] {
                let c = CGPoint(x: x + CGFloat(side) * ew * 0.58, y: h / 2)
                let rect = CGRect(x: c.x - ew / 2, y: c.y - eh * CGFloat(open) / 2, width: ew, height: max(1.5, eh * CGFloat(open)))
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
                ctx.stroke(Path(ellipseIn: rect), with: .color(.black.opacity(0.55)), lineWidth: 1)
                if open > 0.35 {
                    let pr = eh * 0.26
                    let pc = CGPoint(x: c.x + look * ew * 0.2, y: c.y + CGFloat(cos(t * 0.8 + Double(i))) * eh * 0.08)
                    ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr, y: pc.y - pr, width: pr * 2, height: pr * 2)),
                             with: .color(Color(red: 0.1, green: 0.1, blue: 0.2)))
                    ctx.fill(Path(ellipseIn: CGRect(x: pc.x - pr * 0.1, y: pc.y - pr * 0.75, width: pr * 0.6, height: pr * 0.6)),
                             with: .color(.white))
                }
            }
            x += 190 + CGFloat(rnd(i, 12)) * 90
            i += 1
        }
        ctx.opacity = 1
    }

    /// The menu bar becomes a spirit level that won't sit still.
    private func postureStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        tintBand(&ctx, w, h, .posture, a)
        var l = ctx
        l.opacity = a
        let tilt = sin(t * 1.4) * 1.1
        l.translateBy(x: w / 2, y: h / 2)
        l.rotate(by: .degrees(tilt))
        l.translateBy(x: -w / 2, y: -h / 2)
        let vial = CGRect(x: 8, y: 3, width: w - 16, height: h - 6)
        l.fill(Path(roundedRect: vial, cornerRadius: vial.height / 2),
               with: .linearGradient(Gradient(colors: [Color(red: 0.85, green: 1, blue: 0.45).opacity(0.5), Color(red: 0.55, green: 0.85, blue: 0.2).opacity(0.55)]),
                                     startPoint: CGPoint(x: 0, y: vial.minY), endPoint: CGPoint(x: 0, y: vial.maxY)))
        l.stroke(Path(roundedRect: vial, cornerRadius: vial.height / 2), with: .color(.black.opacity(0.35)), lineWidth: 1.5)
        for dx in [-34.0, 34.0] {
            var tick = Path()
            tick.move(to: CGPoint(x: w / 2 + dx, y: vial.minY + 3)); tick.addLine(to: CGPoint(x: w / 2 + dx, y: vial.maxY - 3))
            l.stroke(tick, with: .color(.black.opacity(0.45)), lineWidth: 1.5)
        }
        let bx = w / 2 - CGFloat(sin(t * 1.4)) * w * 0.32
        let bubble = CGRect(x: bx - 30, y: vial.minY + 3, width: 60, height: vial.height - 6)
        l.fill(Path(ellipseIn: bubble), with: .color(.white.opacity(0.92)))
        l.fill(Path(ellipseIn: bubble.insetBy(dx: 14, dy: bubble.height * 0.3).offsetBy(dx: -8, dy: -2)), with: .color(.white))
    }

    /// Elastic bands boinging across the bar, and a cartwheeler.
    private func stretchStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        tintBand(&ctx, w, h, .stretch, a)
        ctx.opacity = a
        let colors = [Color(red: 0.2, green: 0.85, blue: 0.5), Color(red: 1, green: 0.85, blue: 0.2), Color(red: 0.3, green: 0.8, blue: 1)]
        for k in 0..<3 {
            let amp = h * 0.36 * CGFloat(abs(sin(t * 2.3 + Double(k) * 0.5)))
            let wl = 110 + CGFloat(k) * 40
            var p = Path()
            var x: CGFloat = 0
            while x <= w {
                let y = h / 2 + CGFloat(sin(Double(x / wl) * 2 * .pi - t * 7 + Double(k))) * amp
                if x == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                x += 5
            }
            ctx.stroke(p, with: .color(colors[k].opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        let cx = CGFloat((t * 230).truncatingRemainder(dividingBy: Double(w + 120))) - 60
        var l = ctx
        l.translateBy(x: cx, y: h / 2)
        l.rotate(by: .radians(t * 7))
        l.draw(Text("🤸").font(.system(size: h * 0.8)), at: .zero)
        ctx.opacity = 1
    }

    /// The bar breathes: a lilac glow swells for 4s and ebbs for 6s.
    private func breatheStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        let cycle = t.truncatingRemainder(dividingBy: 10)
        let breath = cycle < 4 ? Fx.easeInOut(cycle / 4) : 1 - Fx.easeInOut((cycle - 4) / 6)
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)),
                 with: .color(Theme.lilac.opacity((0.15 + 0.45 * breath) * a)))
        let r = h * (0.2 + 0.25 * CGFloat(breath))
        for i in stride(from: 90.0, to: Double(w), by: 260) {
            ctx.stroke(Path(ellipseIn: CGRect(x: CGFloat(i) - r * 2, y: h / 2 - r, width: r * 4, height: r * 2)),
                       with: .color(.white.opacity(0.7 * a)), lineWidth: 1.5)
        }
    }

    /// Pop hops along the bar.
    private func standStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        tintBand(&ctx, w, h, .stand, a)
        let x = CGFloat((t * 150).truncatingRemainder(dividingBy: Double(w + 80))) - 40
        let hop = CGFloat(abs(sin(t * 6))) * h * 0.25
        ctx.opacity = a
        ctx.draw(Text("↑").font(.display(h * 0.7, .bold)).foregroundColor(Theme.orange), at: CGPoint(x: x - 30, y: h / 2))
        if let pop = ctx.resolveSymbol(id: SceneSymbol.mini(.stand)) { ctx.draw(pop, at: CGPoint(x: x, y: h * 0.5 - hop)) }
        ctx.opacity = 1
    }

    /// Tiny Stompy strolls across the menu bar, leaving footprints.
    private func walkStrip(_ ctx: inout GraphicsContext, _ w: CGFloat, _ h: CGFloat, _ a: Double) {
        tintBand(&ctx, w, h, .walk, a)
        ctx.opacity = a
        let lap = Double(w + 160)
        let speed = 120.0
        let x = CGFloat((t * speed).truncatingRemainder(dividingBy: lap)) - 80
        let step = 26.0
        for j in 1...16 {
            let px = x - CGFloat(j) * CGFloat(step) - CGFloat((t * speed).truncatingRemainder(dividingBy: step))
            guard px > 0 else { continue }
            let alpha = 1 - Double(j) / 16
            let y = h * 0.78 + (j % 2 == 0 ? -2.5 : 2.5)
            ctx.fill(Path(ellipseIn: CGRect(x: px - 5, y: y - 3, width: 10, height: 6)),
                     with: .color(Color(red: 0.6, green: 0.1, blue: 0.3).opacity(0.55 * alpha)))
        }
        if let walker = ctx.resolveSymbol(id: SceneSymbol.walker) {
            let bob = CGFloat(abs(sin(t * 10))) * 2.5
            ctx.draw(walker, at: CGPoint(x: x, y: h * 0.45 - bob))
        }
        ctx.opacity = 1
    }
}

// MARK: - Celebrations

extension SceneRenderer {
    func drawCelebration(_ ctx: inout GraphicsContext, _ size: CGSize, _ c: Celebration) {
        let e = date.timeIntervalSince(c.start)
        guard e >= 0, e <= c.duration else { return }
        let fade = 1 - Fx.easeIn((e - (c.duration - 0.7)) / 0.7)
        let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
        switch c.kind {
        case .water: glug(&ctx, size, c, e)
        case .eyes:
            Fx.rings(&ctx, center: center, elapsed: e, count: 3, color: .white, speed: 1300, fade: fade)
            for i in 0..<60 {
                let delay = rnd(i, 51) * 1.4
                let tt = e - delay
                guard tt > 0, tt < 1 else { continue }
                let r = CGFloat(sin(tt * .pi)) * CGFloat(10 + rnd(i, 52) * 22)
                let p = CGPoint(x: CGFloat(rnd(i, 53)) * size.width, y: CGFloat(rnd(i, 54)) * size.height)
                var l = ctx
                l.opacity = fade
                l.addFilter(.shadow(color: HabitKind.eyes.color, radius: 8))
                l.fill(Fx.starPath(center: p, radius: r, points: 4, inner: 0.25), with: .color(.white))
            }
            Fx.popText(&ctx, "👁️ 20/20 vision", at: center, size: 86, localTime: e - 0.15, fade: fade)
        case .posture:
            drawPosture(&ctx, size, straighten: min(1.15, Fx.spring(e * 1.2)))
            Fx.rain(&ctx, width: size.width, elapsed: e, count: 90, colors: Fx.gold, salt: 61, fade: fade, stars: true)
            let drop = Fx.spring(e * 1.3)
            var l = ctx
            l.opacity = fade
            l.draw(Text("👑").font(.system(size: 150)),
                   at: CGPoint(x: center.x, y: -120 + (center.y - 60 + 120) * CGFloat(drop)))
            Fx.popText(&ctx, "Royal posture", at: CGPoint(x: center.x, y: center.y + 90), size: 72, localTime: e - 0.35, fade: fade)
        case .stretch:
            let origin = CGPoint(x: size.width / 2, y: size.height - 150)
            Fx.confetti(&ctx, origin: origin, elapsed: e, count: 170, speed: 900...1700, spread: 1.7, colors: Fx.party, salt: 71, fade: fade)
            Fx.confetti(&ctx, origin: CGPoint(x: 60, y: size.height), elapsed: e - 0.15, count: 60, speed: 900...1500, spread: 0.5,
                        colors: Fx.party, salt: 81, fade: fade)
            Fx.confetti(&ctx, origin: CGPoint(x: size.width - 60, y: size.height), elapsed: e - 0.15, count: 60, speed: 900...1500,
                        spread: 0.5, colors: Fx.party, salt: 91, fade: fade)
            Fx.popText(&ctx, "💪 Limber legend!", at: center, size: 88, localTime: e - 0.1, fade: fade)
        case .breathe, .stand:
            Fx.rings(&ctx, center: center, elapsed: e, count: 3, color: c.kind.color, speed: 1000, fade: fade)
            Fx.confetti(&ctx, origin: CGPoint(x: size.width / 2, y: size.height - 150), elapsed: e, count: 120,
                        speed: 900...1500, spread: 1.6, colors: [c.kind.color, .white, Theme.sun], salt: 111, fade: fade)
            if let who = ctx.resolveSymbol(id: SceneSymbol.crew(c.kind)) {
                var l = ctx
                let s = Fx.spring(e * 1.3) * 1.5
                l.opacity = fade
                l.translateBy(x: center.x, y: center.y - 60)
                l.scaleBy(x: s, y: s)
                l.draw(who, at: .zero)
            }
            Fx.popText(&ctx, c.kind == .breathe ? "Zen unlocked 🌬️" : "Standing ovation! 🧍",
                       at: CGPoint(x: center.x, y: center.y + 120), size: 76, localTime: e - 0.3, fade: fade)
        case .walk:
            for i in 0..<10 {
                let arrive = Double(i) * 0.07
                let tt = e - arrive
                guard tt > 0 else { continue }
                let x = size.width + 40 - CGFloat(Fx.easeOut(tt / 0.5)) * (size.width / 2 + 40 - CGFloat(i) * 45)
                let y = size.height * 0.7 + (i % 2 == 0 ? -24 : 24)
                var l = ctx
                l.opacity = fade * 0.9
                l.translateBy(x: x, y: y)
                l.rotate(by: .degrees(-90))
                l.draw(Text("👣").font(.system(size: 40)), at: .zero)
            }
            let trophyT = e - 0.55
            if trophyT > 0 {
                let s = Fx.spring(trophyT * 1.4)
                var l = ctx
                l.opacity = fade
                l.translateBy(x: center.x, y: center.y - 30)
                l.scaleBy(x: s, y: s)
                l.rotate(by: .degrees(sin(e * 6) * 6))
                l.draw(Text("🏆").font(.system(size: 170)), at: .zero)
                Fx.confetti(&ctx, origin: CGPoint(x: center.x, y: center.y - 60), elapsed: trophyT, count: 120,
                            speed: 700...1400, spread: 2.6, colors: Fx.party, salt: 101, fade: fade)
            }
            Fx.popText(&ctx, "Steps acquired!", at: CGPoint(x: center.x, y: center.y + 120), size: 72, localTime: e - 0.7, fade: fade)
        }
    }

    /// "I drank": water surges up to fill the whole screen, Drip pops in, then it all fades away.
    private func glug(_ ctx: inout GraphicsContext, _ size: CGSize, _ c: Celebration, _ e: Double) {
        let w = size.width, h = size.height
        let startF = scene.water.value(at: c.start)
        let rise = 1.0, holdEnd = 1.8, dur = c.duration
        let f = startF + (1.1 - startF) * Fx.easeInOut(e / rise)
        let alpha = 1 - Fx.easeIn((e - holdEnd) / (dur - holdEnd))
        let surface = h * (1 - CGFloat(f))
        let center = CGPoint(x: w / 2, y: h * 0.45)

        var water = ctx
        water.opacity = alpha
        WaterPaint.body(&water, width: w, surface: surface, bottom: h + 40, t: t * 2, amplitude: 26, bubbles: 80)

        // Shine flash as the screen fills
        let flash = max(0, 1 - abs(e - rise) / 0.25) * 0.35
        if flash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash))) }

        // Splash droplets thrown off the rising crest
        for i in 0..<90 {
            let launch = 0.15 + rnd(i, 41) * 0.8
            let tt = e - launch
            guard tt > 0, tt < 1.3 else { continue }
            let y0 = h * (1 - CGFloat(startF + (1.1 - startF) * Fx.easeInOut(launch / rise)))
            let x = CGFloat(rnd(i, 42)) * w + CGFloat((rnd(i, 43) - 0.5) * 320 * tt)
            let y = y0 - CGFloat((600 + rnd(i, 44) * 800) * tt) + CGFloat(0.5 * 2200 * tt * tt)
            let r = CGFloat(6 + rnd(i, 45) * 10)
            let rect = CGRect(x: x - r / 2, y: y - r / 1.52, width: r, height: r / 0.76)
            ctx.fill(DropShape().path(in: rect), with: .color(waterLight.opacity(0.9 * (1 - tt / 1.3) * alpha)))
        }

        Fx.rings(&ctx, center: center, elapsed: e - rise, count: 4, color: .white, speed: 1100, fade: alpha)

        let heroT = e - 0.8
        if heroT > 0, let hero = ctx.resolveSymbol(id: SceneSymbol.hero) {
            let s = Fx.spring(heroT * 1.3) * (1 + 0.035 * sin(e * 9))
            var l = ctx
            l.opacity = alpha
            l.translateBy(x: center.x, y: center.y - 40)
            l.scaleBy(x: s, y: s)
            l.addFilter(.shadow(color: .black.opacity(0.3), radius: 24, y: 12))
            l.draw(hero, at: .zero)
            for k in 0..<8 {
                let a = Double(k) / 8 * 2 * .pi + e * 0.8
                let rr = 230 + 20 * sin(e * 4 + Double(k))
                let p = CGPoint(x: CGFloat(cos(a) * rr), y: CGFloat(sin(a) * rr * 0.8))
                l.fill(Fx.starPath(center: p, radius: CGFloat(12 + 8 * sin(e * 6 + Double(k))), points: 4, inner: 0.25),
                       with: .color(.white))
            }
        }
        Fx.popText(&ctx, "GLUG GLUG ✨", at: CGPoint(x: center.x, y: center.y + 190), size: 92, localTime: e - 1.0, fade: alpha)
    }
}

// MARK: - Flood extras

extension WaterPaint {
    /// Sunbeams slanting down through the water.
    static func lightRays(_ ctx: inout GraphicsContext, width: CGFloat, surface: CGFloat, bottom: CGFloat, t: Double) {
        for i in 0..<7 {
            let x0 = CGFloat(rnd(i, 120)) * width + CGFloat(sin(t * 0.4 + Double(i))) * 40
            var p = Path()
            p.move(to: CGPoint(x: x0 - 18, y: surface))
            p.addLine(to: CGPoint(x: x0 + 18, y: surface))
            p.addLine(to: CGPoint(x: x0 + 140, y: bottom))
            p.addLine(to: CGPoint(x: x0 + 20, y: bottom))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [.white.opacity(0.16), .white.opacity(0)]),
                                              startPoint: CGPoint(x: x0, y: surface), endPoint: CGPoint(x: x0, y: bottom)))
        }
    }

    static func seaweed(_ ctx: inout GraphicsContext, width: CGFloat, surface: CGFloat, bottom: CGFloat, t: Double) {
        let depth = bottom - surface
        guard depth > 60 else { return }
        var x: CGFloat = 40
        var i = 0
        while x < width {
            let tall = min(depth * 0.8, CGFloat(80 + rnd(i, 130) * 180))
            var p = Path()
            p.move(to: CGPoint(x: x, y: bottom))
            var y: CGFloat = 0
            while y <= tall {
                let sway = CGFloat(sin(t * 1.6 + Double(y) * 0.025 + Double(i))) * 14 * (y / tall)
                p.addLine(to: CGPoint(x: x + sway, y: bottom - y))
                y += 8
            }
            let green = Color(red: 0.15, green: 0.6 + rnd(i, 131) * 0.25, blue: 0.35)
            ctx.stroke(p, with: .color(green.opacity(0.75)), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            x += 90 + CGFloat(rnd(i, 132)) * 140
            i += 1
        }
    }

    static func crab(_ ctx: inout GraphicsContext, width: CGFloat, bottom: CGFloat, t: Double) {
        let x = CGFloat((t * 70).truncatingRemainder(dividingBy: Double(width + 200))) - 100
        let bob = CGFloat(abs(sin(t * 8))) * 4
        ctx.draw(Text("🦀").font(.system(size: 56)), at: CGPoint(x: x, y: bottom - 34 - bob))
    }
}
