import SwiftUI
import DripCore

/// Shared "is the hold button (or Space) down?" state for hold-to-finish mini-games.
@MainActor
final class HoldState: ObservableObject {
    static let shared = HoldState()
    @Published var holding = false
}

/// The top rung: full-screen, clickable. Built to trigger the habit through the senses, not to scold.
///
/// Motion: the scene pours out of the menu bar as a growing liquid circle, content drops in,
/// and on the way out it drains back up into the menu bar.
struct TakeoverView: View {
    @ObservedObject var model: AppModel
    @State private var shown: Presentation?
    @State private var reveal: Double = 0
    @ObservedObject private var motion = Motion.shared

    var body: some View {
        GeometryReader { geo in
            if let p = shown {
                scene(p)
                    .id(p.attemptStartedAt)
                    .mask(RevealMask(progress: motion.reduced ? 1 : reveal, origin: CGPoint(x: geo.size.width - 150, y: -10)))
                    .opacity(motion.reduced ? reveal : 1)
            }
        }
        .onAppear { sync(model.presentation) }
        .onChange(of: model.presentation) { _, p in sync(p) }
    }

    private func sync(_ p: Presentation?) {
        if let p, p.blocksScreen {
            let fresh = shown?.attemptStartedAt != p.attemptStartedAt
            shown = p
            if fresh {
                reveal = Motion.snapshot ? 1 : 0
                DispatchQueue.main.async { withAnimation(.spring(response: 0.95, dampingFraction: 0.86)) { reveal = 1 } }
            }
        } else if shown != nil {
            withAnimation(.easeIn(duration: 0.42)) { reveal = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { if model.presentation?.blocksScreen != true { shown = nil } }
        }
    }

    @ViewBuilder
    private func scene(_ p: Presentation) -> some View {
        if p.types.contains(.miniGame) {
            switch p.kind {
            case .water: BubblePopGame(model: model)
            default: HoldGame(model: model, kind: p.kind)
            }
        } else {
            switch p.kind {
            case .water: BrookTakeover(model: model)
            case .eyes: SpotlightTakeover(model: model, startedAt: p.attemptStartedAt)
            default: CharacterTakeover(model: model, kind: p.kind)
            }
        }
    }
}

/// A circle that grows from `origin` until it covers the whole rect, with a wobbly liquid edge.
struct RevealMask: View {
    var progress: Double
    var origin: CGPoint
    var body: some View {
        GeometryReader { geo in
            let far = hypot(max(origin.x, geo.size.width - origin.x), geo.size.height - origin.y) * 1.08
            Canvas { ctx, _ in
                let r = CGFloat(progress) * far
                guard r > 0.5 else { return }
                var p = Path()
                let n = 72
                for i in 0...n {
                    let a = Double(i) / Double(n) * 2 * .pi
                    let wobble = 1 + 0.035 * sin(a * 7 + progress * 9) * (1 - progress)
                    let pt = CGPoint(x: origin.x + CGFloat(cos(a) * wobble) * r, y: origin.y + CGFloat(sin(a) * wobble) * r)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                ctx.fill(p, with: .color(.black))
            }
        }
    }
}

// MARK: 1d · Immersive brook

struct BrookTakeover: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let c = model.settings.config(.water)
        let glass = (model.state.stats.done[.water] ?? 0) + 1
        ZStack {
            Theme.aqua
            TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                Canvas { ctx, size in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    WaterPaint.drawBubbles(&ctx, count: 26, xRange: 0...size.width, top: 0, bottom: size.height, t: t * 0.6,
                                           salt: 3, sizeScale: 2.2)
                    // Rolling hills of water at the bottom
                    for i in 0..<5 {
                        let r = size.width * 0.16
                        let cx = CGFloat(i) * size.width / 4 + CGFloat(sin(t * 0.8 + Double(i))) * 10
                        ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: size.height - r * 0.9, width: r * 2, height: r * 2)),
                                 with: .color(Theme.aquaDeep.opacity(0.7)))
                    }
                }
            }
            VStack(spacing: 18) {
                CharacterView(kind: .water, expression: .happy, size: 200, animated: true, tint: .white)
                    .entrance(0, base: 0.3, from: -120)
                Text(model.settings.pushiness == .max ? "Drink. Water. Now." : "Psst… hear that?")
                    .font(.display(64, .bold)).foregroundStyle(Theme.ink).entrance(1, step: 0.08, base: 0.35, from: 30)
                Text("Take a little sip. Your brain is 75% water and it's asking nicely.")
                    .font(.body(22, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center).frame(maxWidth: 560)
                    .entrance(2, step: 0.08, base: 0.35, from: 30)
                HStack(spacing: 14) {
                    Button("Sipped!") { model.done() }.buttonStyle(ToyButton(fill: .white, size: 20))
                    Button("In 5 min") { model.snooze() }.buttonStyle(ToyButton(fill: Theme.aqua, size: 20))
                }
                .padding(.top, 6)
            }
            VStack {
                HStack {
                    Label(soundName(c.sound), systemImage: "waveform").font(.display(15, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(Theme.ink, in: Capsule())
                    Spacer()
                    Text("Glass \(glass) of \(c.goal)").font(.display(15, .semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8).toyCard(.white, radius: 20, shadow: 3)
                }
                Spacer()
            }
            .padding(28)
        }
    }
}

func soundName(_ cue: SoundCue) -> String {
    switch cue {
    case .brook: "Babbling brook"
    case .rain: "Soft rain"
    case .chime: "Little chime"
    case .birds: "Morning birds"
    case .pop: "Bubble pops"
    case .breeze: "Slow breeze"
    }
}

// MARK: 1e · Spotlight

struct SpotlightTakeover: View {
    @ObservedObject var model: AppModel
    let startedAt: Date

    var body: some View {
        ZStack {
            BehindWindowBlur().overlay(Theme.ink.opacity(0.78))
            TimelineView(.periodic(from: .now, by: 0.1)) { tl in
                let total = HabitKind.eyes.gagSeconds ?? 20
                let left = max(0, total - tl.date.timeIntervalSince(startedAt))
                HStack(spacing: 60) {
                    ZStack {
                        Circle().stroke(Color(hex: 0x2a3d35), lineWidth: 28)
                        Circle().trim(from: 0, to: left / total).rotation(.degrees(-90))
                            .stroke(Theme.sun, style: StrokeStyle(lineWidth: 28, lineCap: .round))
                        CharacterView(kind: .eyes, size: 170, animated: true)
                    }
                    .frame(width: 280, height: 280)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(String(format: "0:%02d", Int(left.rounded(.up)))).font(.display(110, .bold)).foregroundStyle(Theme.sun).monospacedDigit()
                        Text("Look at something\n20 feet away.").font(.display(44, .bold)).foregroundStyle(.white)
                        Text("A window, a plant, a coworker's suspiciously nice chair.\nPeep is looking with you.")
                            .font(.body(19)).foregroundStyle(.white.opacity(0.75))
                        HStack(spacing: 20) {
                            Text("Closes by itself").font(.body(15, .bold)).foregroundStyle(.white.opacity(0.7))
                            Button("Skip this one") { model.skip() }.buttonStyle(.plain).handCursor()
                                .font(.body(15, .bold)).foregroundStyle(.white).underline()
                        }
                        .padding(.top, 6)
                    }
                }
            }
        }
    }
}

// MARK: Character takeover (walk, posture, breathe, stand, stretch)

struct CharacterTakeover: View {
    @ObservedObject var model: AppModel
    let kind: HabitKind

    var body: some View {
        ZStack {
            kind.wash
            VStack(spacing: 20) {
                CharacterView(kind: kind, expression: .happy, size: 220, animated: true)
                    .entrance(0, base: 0.3, from: -140)
                Text(kind.toastTitle).font(.display(62, .bold)).foregroundStyle(Theme.text).entrance(1, step: 0.08, base: 0.35, from: 30)
                Text(model.line).font(.body(22, .semibold)).foregroundStyle(Theme.text.opacity(0.8))
                    .multilineTextAlignment(.center).frame(maxWidth: 620)
                HStack(spacing: 14) {
                    Button(kind.doneLabel) { model.done() }.buttonStyle(ToyButton(fill: kind.color, size: 20))
                    Button("In 5 min") { model.snooze() }.buttonStyle(ToyButton(fill: .white, size: 20))
                }
                .padding(.top, 6)
                Text("Esc skips").font(.body(14)).foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: 1f · Hold to stretch (and hold-to-finish for the rest)

struct HoldGame: View {
    @ObservedObject var model: AppModel
    let kind: HabitKind
    @ObservedObject private var hold = HoldState.shared
    @State private var step = 0
    @State private var held: Double = 0
    @State private var last = Date()
    static let secondsPerStep = 5.0

    private var steps: [(chip: String, title: String, sub: String)] {
        switch kind {
        case .stretch: [
            ("Arms up", "Reach for the ceiling.", "Hold the button with one hand and stretch the other up. Noodle does the counting."),
            ("Lean left", "Lean to the left.", "Keep holding. Feel that side stretch. Noodle's leaning too."),
            ("Lean right", "Now lean right.", "Last one. Hold it… Noodle believes in you."),
        ]
        case .breathe: [("In", "Breathe in slowly.", "Hold the button while you breathe in for four."),
                        ("Out", "And out…", "Keep holding while you breathe out for six.")]
        default: [(kind.noun.capitalized, kind.toastTitle, "Hold the button while you do it. \(kind.character) counts.")]
        }
    }

    var body: some View {
        let s = steps[min(step, steps.count - 1)]
        ZStack {
            kind.wash
            VStack(alignment: .leading, spacing: 34) {
                HStack(spacing: 8) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { i, st in
                        Text("\(i + 1) · \(st.chip)").font(.display(14, .semibold))
                            .foregroundStyle(i == step ? Color.white : Theme.ink)
                            .padding(.horizontal, 14).padding(.vertical, 7)
                            .background(Capsule().fill(i == step ? Theme.ink : Color.white))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
                    }
                }
                HStack(alignment: .center, spacing: 60) {
                    CharacterView(kind: kind, expression: hold.holding ? .cheer : .calm, size: 260, animated: true)
                        .rotationEffect(.degrees(step == 1 ? -12 : step == 2 ? 12 : 0), anchor: .bottom)
                        .animation(.spring(response: 0.5, dampingFraction: 0.6), value: step)
                    VStack(alignment: .leading, spacing: 14) {
                        Text(s.title).font(.display(54, .bold)).foregroundStyle(Theme.text)
                        Text(s.sub).font(.body(20, .semibold)).foregroundStyle(Theme.text.opacity(0.8)).frame(maxWidth: 460, alignment: .leading)
                        holdBar.padding(.top, 10)
                        Text("Or press Space · Esc skips").font(.body(15, .bold)).foregroundStyle(kind.accent)
                    }
                }
            }
            .padding(60)
        }
        .onReceive(Timer.publish(every: 1 / 30, on: .main, in: .common).autoconnect()) { now in
            let dt = now.timeIntervalSince(last)
            last = now
            guard hold.holding else { return }
            held += dt
            if held >= Self.secondsPerStep {
                held = 0
                if step + 1 >= steps.count { model.done() } else { step += 1 }
            }
        }
    }

    private var holdBar: some View {
        let progress = held / Self.secondsPerStep
        return ZStack(alignment: .leading) {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 14).fill(kind.color).frame(width: geo.size.width * progress)
            }
            HStack {
                Text(hold.holding ? "Holding…" : "Hold me").font(.display(20, .bold))
                Spacer()
                Text("\(Int((Self.secondsPerStep - held).rounded(.up)))s").font(.display(20, .bold)).monospacedDigit()
            }
            .padding(.horizontal, 20)
            .foregroundStyle(Theme.ink)
        }
        .frame(width: 400, height: 64)
        .toyCard(.white, radius: 16)
        .handCursor()
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !hold.holding { hold.holding = true } }
            .onEnded { _ in hold.holding = false })
    }
}

// MARK: Drip's mini-game: pop the bubbles

struct BubblePopGame: View {
    @ObservedObject var model: AppModel
    @State private var popped: Set<Int> = []
    @State private var pops: [(CGPoint, Date)] = []
    private let count = 8

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.aqua
                TimelineView(.animation(minimumInterval: 1 / 30)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    ZStack {
                        ForEach(0..<count, id: \.self) { i in
                            if !popped.contains(i) {
                                let x = geo.size.width * (0.12 + 0.76 * rnd(i, 7)) + sin(t * 0.9 + Double(i)) * 30
                                let y = geo.size.height * (0.2 + 0.6 * rnd(i, 8)) + cos(t * 0.7 + Double(i)) * 24
                                Button {
                                    pops.append((CGPoint(x: x, y: y), Date()))
                                    withAnimation(.spring(response: 0.25)) { _ = popped.insert(i) }
                                    if popped.count == count { DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.done() } }
                                } label: {
                                    Circle().fill(.white.opacity(0.25))
                                        .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                                        .overlay(Circle().fill(.white).frame(width: 18, height: 18).offset(x: -18, y: -20))
                                        .frame(width: 110, height: 110)
                                }
                                .buttonStyle(.plain)
                                .handCursor()
                                .position(x: x, y: y)
                                .transition(.scale(scale: 1.6).combined(with: .opacity))
                            }
                        }
                        // Pop! A ring and a spray of droplets where each bubble burst.
                        Canvas { ctx, _ in
                            for (p, when) in pops {
                                let e = tl.date.timeIntervalSince(when)
                                guard e < 0.6 else { continue }
                                let r = 55 + CGFloat(e) * 160
                                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                                           with: .color(.white.opacity(1 - e / 0.6)), lineWidth: 4 * CGFloat(1 - e / 0.6))
                                for k in 0..<10 {
                                    let a = Double(k) / 10 * 2 * .pi
                                    let d = CGFloat(e) * 260
                                    let q = CGPoint(x: p.x + CGFloat(cos(a)) * d, y: p.y + CGFloat(sin(a)) * d + CGFloat(e * e) * 300)
                                    let rect = CGRect(x: q.x - 5, y: q.y - 6, width: 10, height: 13)
                                    ctx.fill(DropShape().path(in: rect), with: .color(.white.opacity(1 - e / 0.6)))
                                }
                            }
                        }
                        .allowsHitTesting(false)
                    }
                }
                VStack(spacing: 8) {
                    CharacterView(kind: .water, expression: .happy, size: 120, animated: true, tint: .white)
                    Text("Pop \(count - popped.count) bubbles, then sip.").font(.display(40, .bold)).foregroundStyle(Theme.ink)
                    Text("Drip will wait. Drip is very patient. (Esc skips.)").font(.body(18)).foregroundStyle(Theme.ink.opacity(0.75))
                }
                .allowsHitTesting(false)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.88)
            }
        }
    }
}
