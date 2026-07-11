import SwiftUI
import DripCore

/// Where the main window should open (popover rows jump straight into a character's editor).
@MainActor
final class Navigation: ObservableObject {
    static let shared = Navigation()
    enum Page: Hashable { case crew, editor(HabitKind), styles, schedule, streaks, share(ShareKind), settings, about }
    @Published var page: Page = .crew
}

/// Menu-bar popover: design 1a (crew list) with 1b's day tank as the header.
struct MenuPopover: View {
    @ObservedObject var model: AppModel
    var openMain: (Navigation.Page) -> Void
    var share: () -> Void
    /// Tallest the popover may be on the current screen; the crew list scrolls beyond it.
    var maxHeight: CGFloat = .infinity
    /// New on every open, so the entrance choreography replays.
    var openID = UUID()
    @ObservedObject private var motion = Motion.shared

    static let rowHeight: CGFloat = 60, rowSpacing: CGFloat = 8, chrome: CGFloat = 370

    private var listHeight: CGFloat {
        let off = HabitKind.allCases.contains { !model.settings.config($0).enabled }
        let n = CGFloat(model.settings.enabledKinds.count)
        let content = n * (Self.rowHeight + Self.rowSpacing) + (off ? 46 : 0)
        return min(content, max(Self.rowHeight * 2, maxHeight - Self.chrome))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header.entrance(0)
            DayTank(model: model).entrance(1)
            if let reason = model.hushReason, reason != .paused {
                Text(reason.message).font(.body(12.5, .bold)).foregroundStyle(Theme.muted).entrance(2)
            }
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: Self.rowSpacing) {
                    ForEach(Array(model.settings.enabledKinds.enumerated()), id: \.element) { i, kind in
                        CrewRowCard(model: model, kind: kind) { openMain(.editor(kind)) }.entrance(i + 2)
                    }
                    offDuty.entrance(model.settings.enabledKinds.count + 2)
                }
                .padding(.bottom, 5)   // room for the cards' hard shadows
                .padding(.top, 3)
            }
            .frame(height: listHeight)
            footer.entrance(model.settings.enabledKinds.count + 3)
        }
        .padding(16)
        .frame(width: 360)
        .background(Theme.paper)
        .environment(\.motionPaused, !motion.popoverOpen)
        .id(openID)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<12: "Morning, legend"
        case ..<17: "Afternoon, legend"
        default: "Evening, legend"
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.display(21, .bold)).foregroundStyle(Theme.text)
                let done = DayProgress.done(settings: model.settings, stats: model.state.stats)
                let goal = model.settings.enabledKinds.reduce(0) { $0 + model.settings.config($1).goal }
                // Status lives on this one line (no banners sliding in): progress, or the pause.
                Text(model.pausedUntilText.map { "☕ Paused until \($0)" } ?? "\(done) of \(goal) nudges done today")
                    .font(.body(12.5, model.isPaused ? .bold : .semibold))
                    .foregroundStyle(model.isPaused ? HabitKind.eyes.accent : Theme.muted)
                    .contentTransition(.opacity)
            }
            Spacer()
            Button { openMain(.crew) } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.ink)
                    .frame(width: 34, height: 34).toyCard(.white, radius: 10, shadow: 3)
            }
            .buttonStyle(.plain)
            .handCursor()
            .help("Crew & settings")
        }
    }

    @ViewBuilder
    private var offDuty: some View {
        let off = HabitKind.allCases.filter { !model.settings.config($0).enabled }
        if !off.isEmpty {
            Button { openMain(.crew) } label: {
                HStack(spacing: -6) {
                    ForEach(off) { CharacterView(kind: $0, expression: .sleepy, size: 26, shadow: false).opacity(0.6) }
                    Text(off.count == HabitKind.allCases.count ? "Hire your crew" : "\(off.map(\.character).joined(separator: ", ")) off duty")
                        .font(.body(12, .bold)).foregroundStyle(Theme.muted).padding(.leading, 14).lineLimit(1)
                    Spacer()
                    Text("Manage").font(.display(12, .semibold)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .toyCard(.clear, radius: 14, dashed: true)
            }
            .buttonStyle(.plain)
            .handCursor()
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Rectangle().fill(Theme.line).frame(height: 1.5).padding(.vertical, 2)
            HStack(spacing: 10) {
                if model.isPaused {
                    Button("Resume now") { model.resume() }.buttonStyle(ToyButton(fill: Theme.leaf, size: 13.5, wide: true))
                } else {
                    StartNextButton(model: model)
                    PauseMenu(model: model)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: model.isPaused)
            HStack(spacing: 14) {
                Button("Share today") { openMain(.share(.today)) }.buttonStyle(.plain).handCursor()
                Button("Streak \(model.streak.current)🔥") { openMain(.streaks) }.buttonStyle(.plain).handCursor()
                Button("About") { openMain(.about) }.buttonStyle(.plain).handCursor()
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.plain).handCursor()
            }
            .font(.body(12, .bold))
            .foregroundStyle(Theme.muted)
        }
    }
}

/// 1b's tank: your day as water filling up, with Drip floating on it.
/// On open it fills from empty and the percentage counts up; every completion sloshes it.
struct DayTank: View {
    @ObservedObject var model: AppModel
    var fixedDate: Date?
    @Environment(\.motionPaused) private var paused
    @State private var fill = Tween(from: 0, to: 0, start: .distantPast, duration: 1.4)
    @State private var sloshAt = Date.distantPast

    var body: some View {
        Group {
            if let fixedDate { tank(fixedDate, target: model.dayProgress) } else {
                TimelineView(.animation(minimumInterval: 1 / 40, paused: paused)) { tl in tank(tl.date, target: nil) }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .toyCard(Color(hex: 0xeafaff), radius: 16)   // fixed light: the tank's ink text sits on it and on the aqua water
        .onAppear {
            let start = Motion.shared.reduced || Motion.snapshot ? model.dayProgress : 0
            fill = Tween(from: start, to: model.dayProgress, start: Date(), duration: 1.4)
            sloshAt = Date()
        }
        .onChange(of: model.dayProgress) { _, new in
            fill = fill.retargeted(new, at: Date())
            sloshAt = Date()
        }
    }

    private func tank(_ date: Date, target: Double?) -> some View {
        let f = target ?? fill.value(at: date)
        let t = date.timeIntervalSinceReferenceDate
        let since = date.timeIntervalSince(sloshAt)
        let slosh = Motion.shared.reduced ? 0 : 10 * exp(-since * 1.8) * (0.6 + 0.4 * sin(since * 9))
        return GeometryReader { geo in
            let size = geo.size
            let surface = size.height * (1 - CGFloat(0.08 + 0.84 * f))
            ZStack(alignment: .topLeading) {
                Canvas { ctx, size in
                    let back = WaterPaint.wave(width: size.width, surface: surface - 3, bottom: size.height,
                                               amplitude: 4 + CGFloat(slosh) * 0.6, wavelength: 90, phase: t * 1.6)
                    ctx.fill(back, with: .color(Theme.aquaDeep.opacity(0.45)))
                    let front = WaterPaint.wave(width: size.width, surface: surface, bottom: size.height,
                                                amplitude: 5 + CGFloat(slosh), wavelength: 130, phase: -t * 2.2)
                    ctx.fill(front, with: .color(Theme.aqua))
                    WaterPaint.drawBubbles(&ctx, count: 7, xRange: 10...(size.width * 0.7), top: surface + 8, bottom: size.height,
                                           t: t * 0.5, salt: 9, sizeScale: 0.8)
                }
                CharacterView(kind: .water, expression: model.isPaused ? .sleepy : model.mood.expression, size: 56, animated: fixedDate == nil,
                              bump: model.state.stats.done[.water] ?? 0)
                    .rotationEffect(.degrees(sin(t * 1.7) * 5 + slosh * 0.6 * sin(since * 7)), anchor: .bottom)
                    .position(x: size.width - 48, y: surface + 4 + CGFloat(sin(t * 2)) * 3)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int((f * 100).rounded()))%").font(.display(34, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    Text("of a very healthy day").font(.body(12.5, .bold)).foregroundStyle(Theme.ink.opacity(0.75))
                    Spacer()
                    Text(summary).font(.body(12, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                .padding(14)
            }
        }
    }

    private var summary: String {
        let d = model.state.stats.done
        let parts: [(HabitKind, String, String)] = [(.water, "sip", "sips"), (.eyes, "eye break", "eye breaks"),
                                                    (.walk, "walk", "walks"), (.stretch, "stretch", "stretches"),
                                                    (.posture, "sit-up", "sit-ups"), (.breathe, "breath", "breaths"),
                                                    (.stand, "stand", "stands")]
        let shown = parts.filter { model.settings.config($0.0).enabled }.prefix(3).map { k, one, many in
            let n = d[k] ?? 0
            return "\(n) \(n == 1 ? one : many)"
        }
        return shown.isEmpty ? "Hire the crew to start filling the tank" : shown.joined(separator: " · ")
    }
}

/// One crew member in the popover list. Lifts on hover; bursts when its habit gets done.
struct CrewRowCard: View {
    @ObservedObject var model: AppModel
    let kind: HabitKind
    var open: () -> Void
    @State private var hovering = false
    @State private var hoverBump = 0

    var body: some View {
        let c = model.settings.config(kind)
        let due = model.activeKind == kind
        let done = model.state.stats.done[kind] ?? 0
        HStack(spacing: 12) {
            CharacterView(kind: kind, expression: model.isPaused ? .sleepy : due ? .worried : (kind == .water ? model.mood.expression : .happy),
                          size: 38, animated: true, bump: done + hoverBump)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.title).font(.display(14.5, .semibold)).foregroundStyle(Theme.text)
                GoalDots(kind: kind, done: done, goal: c.goal)
            }
            Spacer(minLength: 4)
            if due {
                Button(kind.actionLabel) { model.done() }.buttonStyle(ToyButton(fill: kind.color, size: 12))
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text(timeText(c)).font(.display(13, .semibold)).foregroundStyle(Theme.text.opacity(0.8)).monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .toyCard(kind.wash, radius: 14, shadow: hovering ? 5 : (due ? 4 : 3))
        .overlay(Burst(trigger: done, colors: [kind.color, .white, Theme.sun], power: 120).allowsHitTesting(false))
        .offset(y: hovering ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hovering)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: due)
        .contentShape(Rectangle())
        .onHover { h in hovering = h; if h { hoverBump += 1 } }
        .handCursor()
        .onTapGesture(perform: open)
        .contextMenu {
            Button("I just did it") { model.logDone(kind) }
            Button("Preview nudge") { model.previewNudges(kind) }
        }
    }

    private func timeText(_ c: HabitConfig) -> String {
        if model.isPaused { return "paused" }
        if model.state.queued.contains(kind) { return "waiting…" }
        guard let d = model.state.nextDue[kind] else { return "—" }
        if case .atTimes = c.schedule { return d.formatted(date: .omitted, time: .shortened) }
        if !Calendar.current.isDateInToday(d) { return d.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        let m = Int(max(0, d.timeIntervalSinceNow) / 60)
        return m < 1 ? "now" : m < 60 ? "in \(m)m" : "in \(m / 60)h \(m % 60)m"
    }
}

/// Today's progress toward a habit's goal as little segments; the newest one pops in.
struct GoalDots: View {
    let kind: HabitKind
    let done: Int
    let goal: Int
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<min(goal, 12), id: \.self) { i in
                let filled = i < done
                Capsule().fill(filled ? kind.color : Theme.text.opacity(0.16))
                    .overlay(Capsule().strokeBorder(Theme.ink.opacity(filled ? 0.6 : 0), lineWidth: 1))
                    .frame(width: goal > 8 ? 9 : 13, height: 5)
                    .keyframeAnimator(initialValue: 1.0, trigger: i == done - 1 ? done : 0) { v, scale in
                        v.scaleEffect(scale)
                    } keyframes: { _ in
                        KeyframeTrack {
                            SpringKeyframe(1.9, duration: 0.14)
                            SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: filled)
            }
            if goal > 12 { Text("\(done)/\(goal)").font(.body(10, .bold)).foregroundStyle(Theme.muted).contentTransition(.numericText()) }
        }
    }
}
