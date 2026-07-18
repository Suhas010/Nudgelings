import SwiftUI

/// Cheap deterministic pseudo-random in 0..<1, so particle layouts are stable frame to frame.
func rnd(_ i: Int, _ salt: Int = 0) -> Double {
    var x = UInt64(bitPattern: Int64(i &* 73_856_093 ^ salt &* 19_349_663 &+ 0x9E37))
    x ^= x >> 13; x = x &* 0x5bd1_e995_5bd1_e995; x ^= x >> 15
    return Double(x % 10_000) / 10_000
}

let waterLight = Color(red: 0.45, green: 0.85, blue: 1.0)
let waterDeep = Color(red: 0.05, green: 0.40, blue: 0.95)

/// All the water drawing lives here so every overlay shares one look.
enum WaterPaint {
    static func wave(width: CGFloat, surface: CGFloat, bottom: CGFloat, amplitude: CGFloat,
                     wavelength: CGFloat, phase: Double, crestX: CGFloat? = nil) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: bottom))
        var x: CGFloat = 0
        while x <= width + 8 {
            var a = amplitude
            if let cx = crestX { a += amplitude * 2.2 * exp(-pow((x - cx) / 140, 2)) }
            let y = surface + sin(Double(x / wavelength) * 2 * .pi + phase) * a
            p.addLine(to: CGPoint(x: x, y: y))
            x += 6
        }
        p.addLine(to: CGPoint(x: width, y: bottom))
        p.closeSubpath()
        return p
    }

    /// A body of water whose surface sits at `surface` (points from top) and fills to `bottom`.
    static func body(_ ctx: inout GraphicsContext, width: CGFloat, surface: CGFloat, bottom: CGFloat,
                     t: Double, amplitude: CGFloat = 12, bubbles: Int = 28) {
        guard bottom - surface > 1 else { return }
        let back = wave(width: width, surface: surface - amplitude * 0.4, bottom: bottom, amplitude: amplitude * 0.8,
                        wavelength: 380, phase: t * 1.3)
        ctx.fill(back, with: .color(waterDeep.opacity(0.35)))

        let front = wave(width: width, surface: surface, bottom: bottom, amplitude: amplitude,
                         wavelength: 560, phase: -t * 1.8 + 1)
        ctx.fill(front, with: .linearGradient(
            Gradient(colors: [waterLight.opacity(0.55), waterDeep.opacity(0.62)]),
            startPoint: CGPoint(x: 0, y: surface), endPoint: CGPoint(x: 0, y: bottom)))

        // Foam line along the crest
        var foam = Path()
        var x: CGFloat = 0
        while x <= width {
            let y = surface + sin(Double(x / 560) * 2 * .pi - t * 1.8 + 1) * amplitude
            if x == 0 { foam.move(to: CGPoint(x: x, y: y)) } else { foam.addLine(to: CGPoint(x: x, y: y)) }
            x += 6
        }
        ctx.stroke(foam, with: .color(.white.opacity(0.55)), lineWidth: 2.5)

        // Caustic shimmer
        for i in 0..<10 {
            let cx = CGFloat(rnd(i, 7)) * width + CGFloat(sin(t * 0.6 + Double(i))) * 30
            let cy = surface + (bottom - surface) * CGFloat(0.25 + rnd(i, 8) * 0.6)
            let rw = CGFloat(60 + rnd(i, 9) * 120)
            ctx.fill(Path(ellipseIn: CGRect(x: cx, y: cy, width: rw, height: rw * 0.18)),
                     with: .color(.white.opacity(0.06 + 0.04 * sin(t * 2 + Double(i)))))
        }

        drawBubbles(&ctx, count: bubbles, xRange: 0...width, top: surface + 10, bottom: bottom, t: t, salt: 1)
    }

    static func drawBubbles(_ ctx: inout GraphicsContext, count: Int, xRange: ClosedRange<CGFloat>,
                            top: CGFloat, bottom: CGFloat, t: Double, salt: Int, sizeScale: CGFloat = 1) {
        let height = bottom - top
        guard height > 4 else { return }
        for i in 0..<count {
            let speed = 30 + rnd(i, salt) * 70
            let travel = (t * speed + rnd(i, salt + 1) * Double(height)).truncatingRemainder(dividingBy: Double(height))
            let y = bottom - CGFloat(travel)
            let baseX = xRange.lowerBound + CGFloat(rnd(i, salt + 2)) * (xRange.upperBound - xRange.lowerBound)
            let x = baseX + CGFloat(sin(t * (1 + rnd(i, salt + 3)) + Double(i))) * 8
            let r = CGFloat(3 + rnd(i, salt + 4) * 9) * sizeScale
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.14)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.7)), lineWidth: 1.4)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.45, y: y - r * 0.55, width: r * 0.45, height: r * 0.45)),
                     with: .color(.white.opacity(0.8)))
        }
    }

    /// Water sloshing inside the menu bar strip, with a big crest rolling across.
    static func menuBarWaves(_ ctx: inout GraphicsContext, width: CGFloat, height: CGFloat, t: Double, intensity: Double = 1) {
        let crest = CGFloat((t * 320).truncatingRemainder(dividingBy: Double(width + 600))) - 300
        let back = wave(width: width, surface: height * 0.30, bottom: height, amplitude: height * 0.10,
                        wavelength: 140, phase: t * 3.2)
        ctx.fill(back, with: .color(waterDeep.opacity(0.35 * intensity)))
        let front = wave(width: width, surface: height * 0.42, bottom: height, amplitude: height * 0.11,
                         wavelength: 220, phase: -t * 4, crestX: crest)
        ctx.fill(front, with: .linearGradient(
            Gradient(colors: [waterLight.opacity(0.6 * intensity), waterDeep.opacity(0.7 * intensity)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: height)))
        drawBubbles(&ctx, count: Int(width / 45), xRange: 0...width, top: height * 0.4, bottom: height, t: t * 0.5,
                    salt: 40, sizeScale: 0.35)
    }

    /// Drops that bead up under the menu bar and fall off it.
    static func menuDrips(_ ctx: inout GraphicsContext, width: CGFloat, top: CGFloat, t: Double, intensity: Double = 1) {
        let cycle = 2.8
        for i in 0..<9 {
            let p = ((t + rnd(i, 30) * cycle) / cycle).truncatingRemainder(dividingBy: 1)
            let x = CGFloat(0.05 + rnd(i, 31) * 0.9) * width
            let w: CGFloat = 9 + CGFloat(rnd(i, 32)) * 5
            let y: CGFloat, scale: CGFloat, alpha: Double
            if p < 0.45 {
                scale = CGFloat(p / 0.45); y = top - 2; alpha = 1
            } else {
                let f = (p - 0.45) / 0.55
                scale = 1; y = top - 2 + CGFloat(f * f) * 260; alpha = 1 - f
            }
            let rect = CGRect(x: x - w * scale / 2, y: y, width: w * scale, height: w * scale / 0.76)
            ctx.fill(DropShape().path(in: rect), with: .linearGradient(
                Gradient(colors: [waterLight.opacity(0.9 * alpha * intensity), waterDeep.opacity(0.9 * alpha * intensity)]),
                startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        }
    }

    static func edgeBubbles(_ ctx: inout GraphicsContext, size: CGSize, top: CGFloat, t: Double) {
        drawBubbles(&ctx, count: 22, xRange: 6...80, top: top, bottom: size.height, t: t, salt: 20, sizeScale: 1.3)
        drawBubbles(&ctx, count: 22, xRange: (size.width - 80)...(size.width - 6), top: top, bottom: size.height, t: t, salt: 60, sizeScale: 1.3)
    }

    static func fish(_ ctx: inout GraphicsContext, size: CGSize, surface: CGFloat, t: Double) {
        let depth = size.height - surface
        guard depth > 60 else { return }
        let lap = Double(size.width + 400)
        for (i, emoji) in ["🐟", "🐠"].enumerated() {
            let speed = i == 0 ? 150.0 : 95.0
            let x = CGFloat(Double(size.width) + 200 - (t * speed + Double(i) * 600).truncatingRemainder(dividingBy: lap))
            let y = surface + depth * (i == 0 ? 0.45 : 0.7) + CGFloat(sin(t * 2 + Double(i))) * 14
            ctx.draw(Text(emoji).font(.system(size: i == 0 ? 76 : 54)), at: CGPoint(x: x, y: y))
            drawBubbles(&ctx, count: 3, xRange: (x - 50)...(x - 30), top: y - 90, bottom: y - 20, t: t, salt: 90 + i, sizeScale: 0.6)
        }
    }
}

/// Eased value moving from `from` to `to` over `duration` seconds.
struct Tween: Equatable {
    var from: Double = 0
    var to: Double = 0
    var start: Date = .distantPast
    var duration: Double = 3.5

    func value(at d: Date) -> Double {
        let p = min(1, max(0, d.timeIntervalSince(start) / duration))
        let e = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
        return from + (to - from) * e
    }

    func retargeted(_ target: Double, at d: Date) -> Tween {
        target == to ? self : Tween(from: value(at: d), to: target, start: d, duration: duration)
    }
}
