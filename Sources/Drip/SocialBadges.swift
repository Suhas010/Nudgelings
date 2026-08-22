import SwiftUI
import AppKit

/// The author's links, as little toy characters that match the crew.
struct SocialLinks: View {
    struct Link: Identifiable {
        let id: String
        let label: String
        let handle: String
        let url: String
        let fill: Color
        let glyph: Glyph
    }
    enum Glyph { case planet, x, linkedIn }

    static let links: [Link] = [
        Link(id: "web", label: "Website", handle: "suhasmore.me", url: "https://suhasmore.me", fill: Theme.leaf, glyph: .planet),
        Link(id: "x", label: "X", handle: "@suhas_more_", url: "https://x.com/suhas_more_", fill: Theme.sun, glyph: .x),
        Link(id: "in", label: "LinkedIn", handle: "in/suhas-more", url: "https://www.linkedin.com/in/suhas-more", fill: Theme.aqua, glyph: .linkedIn),
    ]

    var body: some View {
        VStack(spacing: 12) {
            Text("SAY HI").font(.display(12, .semibold)).foregroundStyle(Theme.muted).tracking(1.5)
            HStack(spacing: 22) {
                ForEach(Array(Self.links.enumerated()), id: \.element.id) { i, link in
                    SocialBadge(link: link, seed: Double(i) * 1.9).entrance(i, step: 0.08, base: 0.9)
                }
            }
        }
    }
}

struct SocialBadge: View {
    let link: SocialLinks.Link
    var seed: Double = 0
    @State private var hoverAt: Date?
    @State private var hovering = false
    @ObservedObject private var motion = Motion.shared

    var body: some View {
        Button {
            if let url = URL(string: link.url) { NSWorkspace.shared.open(url) }
        } label: {
            VStack(spacing: 8) {
                TimelineView(.animation(minimumInterval: 1 / 30, paused: motion.reduced)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate + seed
                    let e = hoverAt.map { tl.date.timeIntervalSince($0) } ?? 9
                    let hop = e < 0.42 ? Ease.bump(e / 0.42) : 0
                    let wobble = e < 0.8 ? sin(e * 18) * (1 - e / 0.8) * 7 : 0
                    Canvas { ctx, size in draw(&ctx, size, t: t, grin: e < 0.9 || hovering) }
                        .frame(width: 62, height: 62)
                        .rotationEffect(.degrees(wobble), anchor: .bottom)
                        .offset(y: -CGFloat(hop) * 12)
                }
                .frame(width: 62, height: 74, alignment: .bottom)
                VStack(spacing: 1) {
                    Text(link.label).font(.display(13, .semibold)).foregroundStyle(Theme.text)
                    Text(link.handle).font(.body(11)).foregroundStyle(Theme.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .help(link.url.replacingOccurrences(of: "https://", with: ""))
        .onHover { h in
            hovering = h
            if h, !motion.reduced { hoverAt = Date() }
        }
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, grin: Bool) {
        let s = size.width
        let ink = GraphicsContext.Shading.color(Theme.ink)
        let body = Path(roundedRect: CGRect(x: 3, y: 3, width: s - 6, height: s - 10), cornerRadius: s * 0.28)
        ctx.fill(body.offsetBy(dx: 0, dy: 4), with: ink)
        ctx.fill(body, with: .color(link.fill))
        ctx.fill(Path(ellipseIn: CGRect(x: s * 0.2, y: s * 0.12, width: s * 0.2, height: s * 0.1)), with: .color(.white.opacity(0.45)))
        ctx.stroke(body, with: ink, lineWidth: 2.5)

        // Eyes: blink on their own rhythm, glance side to side
        let blinkPhase = t.truncatingRemainder(dividingBy: 3.9)
        let open = blinkPhase < 0.14 ? abs(blinkPhase / 0.07 - 1) : 1
        let look = CGFloat(sin(t * 0.7)) * 1.6
        for dx in [-0.13, 0.13] {
            let c = CGPoint(x: s / 2 + s * CGFloat(dx) + look, y: s * 0.3)
            if grin {
                var arc = Path()
                arc.move(to: CGPoint(x: c.x - 3.2, y: c.y + 1.4))
                arc.addQuadCurve(to: CGPoint(x: c.x + 3.2, y: c.y + 1.4), control: CGPoint(x: c.x, y: c.y - 3.4))
                ctx.stroke(arc, with: ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            } else {
                let h = max(1.2, 6.5 * open)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.6, y: c.y - h / 2, width: 5.2, height: h)), with: ink)
            }
        }

        // The glyph, in the lower half
        let g = CGRect(x: s * 0.28, y: s * 0.44, width: s * 0.44, height: s * 0.38)
        switch link.glyph {
        case .planet:
            let r = min(g.width, g.height) / 2
            let c = CGPoint(x: g.midX, y: g.midY)
            let globe = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            ctx.fill(globe, with: .color(.white))
            ctx.stroke(globe, with: ink, lineWidth: 2)
            var lines = Path()
            lines.move(to: CGPoint(x: c.x - r, y: c.y)); lines.addLine(to: CGPoint(x: c.x + r, y: c.y))
            lines.addEllipse(in: CGRect(x: c.x - r * 0.45, y: c.y - r, width: r * 0.9, height: r * 2))
            ctx.stroke(lines, with: ink, lineWidth: 1.6)
        case .x:
            var x = Path()
            x.move(to: CGPoint(x: g.minX + 3, y: g.minY + 2)); x.addLine(to: CGPoint(x: g.maxX - 3, y: g.maxY - 2))
            x.move(to: CGPoint(x: g.maxX - 3, y: g.minY + 2)); x.addLine(to: CGPoint(x: g.minX + 3, y: g.maxY - 2))
            ctx.stroke(x, with: ink, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        case .linkedIn:
            ctx.draw(Text("in").font(.display(22, .bold)).foregroundColor(Theme.ink), at: CGPoint(x: g.midX, y: g.midY + 1))
        }
    }
}
