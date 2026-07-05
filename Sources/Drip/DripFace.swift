import SwiftUI
import DripCore

/// Classic teardrop. Width should be ~0.76 × height so the bottom arc closes neatly.
struct DropShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height
        let center = CGPoint(x: r.midX, y: r.maxY - w / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addCurve(to: CGPoint(x: r.maxX, y: center.y),
                   control1: CGPoint(x: r.midX + w * 0.10, y: r.minY + h * 0.20),
                   control2: CGPoint(x: r.maxX, y: r.minY + h * 0.40))
        p.addArc(center: center, radius: w / 2, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        p.addCurve(to: CGPoint(x: r.midX, y: r.minY),
                   control1: CGPoint(x: r.minX, y: r.minY + h * 0.40),
                   control2: CGPoint(x: r.midX - w * 0.10, y: r.minY + h * 0.20))
        p.closeSubpath()
        return p
    }
}
