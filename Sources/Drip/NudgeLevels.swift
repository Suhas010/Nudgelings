import SwiftUI
import DripCore

// MARK: - Vocabulary
//
// People choose how much a reminder interrupts them (a level); the exact style inside a level
// is a secondary pick. Sound is a separate switch that rides along with any style.

extension NudgeLevel {
    var title: String {
        switch self {
        case .subtle: "Subtle"
        case .polite: "Polite"
        case .playful: "Playful"
        case .unmissable: "Unmissable"
        }
    }

    var tagline: String {
        switch self {
        case .subtle: "Barely there"
        case .polite: "A tap on the shoulder"
        case .playful: "Hard to miss"
        case .unmissable: "Can't be ignored"
        }
    }

    func blurb(_ kind: HabitKind) -> String {
        switch self {
        case .subtle: "Only the menu-bar icon wiggles. Easy to miss, on purpose."
        case .polite: "A small card slides in. Click Done or Later."
        case .playful: "\(kind.character) shows up on your screen. Clicks go right through."
        case .unmissable: "Takes over the screen for a moment. Hard to ignore, quick to finish."
        }
    }

    /// 1…4, for the noticeability meter.
    var loudness: Int { (NudgeLevel.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// Meter colour: calm green to alarm coral.
    var heat: Color {
        switch self {
        case .subtle: Theme.leaf
        case .polite: Theme.aqua
        case .playful: Theme.orange
        case .unmissable: Theme.coral
        }
    }
}

extension NudgeType {
    var title: String {
        switch self {
        case .menuWiggle: "Icon wiggle"
        case .sound: "Sound"
        case .toast: "Corner card"
        case .menuShow: "Menu-bar show"
        case .walkAcross: "Walks across"
        case .cursorTrail: "Cursor trail"
        case .dim: "Dim the screen"
        case .gag: "Screen prank"
        case .takeover: "Full-screen break"
        case .miniGame: "Mini-game"
        }
    }

    var symbol: String {
        switch self {
        case .menuWiggle: "menubar.rectangle"
        case .sound: "speaker.wave.2.fill"
        case .toast: "rectangle.inset.topright.filled"
        case .menuShow: "sparkles"
        case .walkAcross: "figure.walk"
        case .cursorTrail: "cursorarrow.motionlines"
        case .dim: "moon.fill"
        case .gag: "theatermasks.fill"
        case .takeover: "rectangle.fill"
        case .miniGame: "gamecontroller.fill"
        }
    }

    /// Finishes "Drip will …".
    func sentence(_ kind: HabitKind) -> String {
        switch self {
        case .menuWiggle: "wiggle in your menu bar"
        case .sound: "play a sound"
        case .toast: "slide a card into the corner"
        case .menuShow: "put on a little show in your menu bar"
        case .walkAcross: "stroll across your screen"
        case .cursorTrail: "leave a trail behind your cursor"
        case .dim: kind == .eyes ? "dim your screen for a 20-second break" : "dim your screen"
        case .gag: "pull a screen prank"
        case .takeover: "take over your screen"
        case .miniGame: "start a quick mini-game"
        }
    }
}

extension ActiveWindow {
    /// "on weekdays", "every day", "on Mon, Wed and Fri".
    var daysText: String {
        let order = [2, 3, 4, 5, 6, 7, 1]
        let names = [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        switch weekdays {
        case Set(1...7): return "every day"
        case [2, 3, 4, 5, 6]: return "on weekdays"
        case [1, 7]: return "on weekends"
        case []: return "on no days yet"
        default:
            let list = order.filter(weekdays.contains).compactMap { names[$0] }
            return "on " + (list.count > 1 ? list.dropLast().joined(separator: ", ") + " and " + list.last! : list[0])
        }
    }
}

// MARK: - Noticeability meter

struct LoudnessMeter: View {
    let level: NudgeLevel
    var height: CGFloat = 8
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...4, id: \.self) { i in
                Capsule()
                    .fill(i <= level.loudness ? level.heat : Theme.line.opacity(0.7))
                    .overlay(Capsule().strokeBorder(Theme.outline.opacity(i <= level.loudness ? 1 : 0.25), lineWidth: 1.5))
                    .frame(width: height * 2.2, height: height)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Noticeability")
        .accessibilityValue("\(level.loudness) of 4")
    }
}

// MARK: - Mini Mac screen illustrating a level

struct LevelArt: View {
    let level: NudgeLevel
    let kind: HabitKind
    /// Plays the level's little loop (hover or selected). Reduce Motion keeps it still.
    var live = false
    @ObservedObject private var motion = Motion.shared

    var body: some View {
        let animate = live && !motion.reduced && !Motion.snapshot
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, bar = h * 0.14
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0xd8ecea), Color(hex: 0xb5d6d9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                // a window to make it read as a desktop
                RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.9))
                    .frame(width: w * 0.46, height: h * 0.5).offset(x: w * 0.08, y: bar + h * 0.14)
                Rectangle().fill(.white).frame(height: bar)
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.outline).frame(height: 1.5) }
                HStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(Theme.line).frame(width: w * 0.07, height: 3) } }
                    .frame(height: bar).padding(.leading, 6)
                content(w: w, h: h, bar: bar, animate: animate)
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.outline, lineWidth: 2))
        }
        .aspectRatio(1.6, contentMode: .fit)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func content(w: CGFloat, h: CGFloat, bar: CGFloat, animate: Bool) -> some View {
        switch level {
        case .subtle:
            Wiggle(animate: animate) { CharacterView(kind: kind, expression: .happy, size: bar * 0.95, shadow: false) }
                .position(x: w - bar * 1.1, y: bar / 2)
        case .polite:
            Slide(animate: animate, from: CGSize(width: w * 0.5, height: 0)) {
                HStack(spacing: 3) {
                    CharacterView(kind: kind, expression: .happy, size: h * 0.13, shadow: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Capsule().fill(Theme.ink).frame(width: w * 0.14, height: 2.5)
                        Capsule().fill(Theme.line).frame(width: w * 0.1, height: 2.5)
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.outline, lineWidth: 1.5))
            }
            .position(x: w * 0.76, y: bar + h * 0.15)
        case .playful:
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle().fill(Theme.outline.opacity(0.25)).frame(width: 4, height: 4)
                        .offset(x: -CGFloat(i + 1) * w * 0.07, y: CGFloat(i % 2) * 3 + h * 0.12)
                }
                Slide(animate: animate, from: CGSize(width: -w * 0.25, height: 0)) {
                    CharacterView(kind: kind, expression: .cheer, size: h * 0.36, shadow: false)
                }
            }
            .position(x: w * 0.66, y: h * 0.6)
        case .unmissable:
            Pulse(animate: animate) {
                ZStack {
                    kind.color.opacity(0.92)
                    CharacterView(kind: kind, expression: .happy, size: h * 0.42, shadow: false)
                }
            }
            .frame(width: w, height: h)
        }
    }
}

/// Tiny looping motions for the art (phase animators only run while `animate`).
private struct Wiggle<C: View>: View {
    let animate: Bool
    @ViewBuilder var content: C
    var body: some View {
        content.phaseAnimator([0.0, -14, 14, 0], trigger: animate) { v, a in v.rotationEffect(.degrees(animate ? a : 0)) }
            animation: { _ in .easeInOut(duration: 0.12) }
    }
}

private struct Slide<C: View>: View {
    let animate: Bool
    let from: CGSize
    @ViewBuilder var content: C
    var body: some View {
        content.phaseAnimator([false, true], trigger: animate) { v, on in v.offset(animate && !on ? from : .zero).opacity(animate && !on ? 0 : 1) }
            animation: { on in on ? .spring(response: 0.45, dampingFraction: 0.7) : nil }
    }
}

private struct Pulse<C: View>: View {
    let animate: Bool
    @ViewBuilder var content: C
    var body: some View {
        content.phaseAnimator([false, true], trigger: animate) { v, on in v.opacity(animate && !on ? 0 : 1).scaleEffect(animate && !on ? 1.15 : 1) }
            animation: { on in on ? .easeOut(duration: 0.35) : nil }
    }
}

// MARK: - Level card (picker tile)

struct LevelCard: View {
    let level: NudgeLevel
    let kind: HabitKind
    let selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                LevelArt(level: level, kind: kind, live: hovering || selected)
                    .overlay(alignment: .topTrailing) {
                        ZStack {
                            Circle().fill(selected ? Theme.inverse : Theme.raised)
                            Circle().strokeBorder(selected ? Theme.inverse : Theme.muted.opacity(0.6), lineWidth: 2)
                            if selected {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundStyle(Theme.inverseText)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .frame(width: 22, height: 22)
                        .offset(x: 6, y: -6)
                    }
                Text(level.title).font(.display(15.5, .semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(level.tagline).font(.body(12.5, .bold)).foregroundStyle(Theme.text.opacity(0.8))
                    .lineLimit(2, reservesSpace: true)
                LoudnessMeter(level: level, height: 7)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toyCard(selected ? kind.wash : Theme.raised, radius: 14, shadow: selected ? 4 : (hovering ? 2 : 0))
            .offset(y: selected ? -2 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(level.title), \(level.tagline)")
        .accessibilityHint(level.blurb(kind))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Style chip (secondary pick inside a level)

struct StyleChip: View {
    let style: NudgeType
    let kind: HabitKind
    let selected: Bool
    var pick: () -> Void
    var preview: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: pick) {
                HStack(spacing: 7) {
                    Image(systemName: style.symbol).font(.system(size: 12, weight: .bold)).frame(width: 16)
                    Text(style.title).font(.display(13, .semibold))
                }
                .foregroundStyle(selected ? Theme.ink : Theme.text)
                .padding(.leading, 12).padding(.trailing, 8).frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .accessibilityLabel(style.title)
            .accessibilityHint(style.subtitle(for: kind, sound: .pop))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            Rectangle().fill(selected ? Theme.outline.opacity(0.35) : Theme.line).frame(width: 1.5, height: 18)
            Button(action: preview) {
                Image(systemName: "play.fill").font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(selected ? Theme.ink : Theme.muted)
                    .frame(width: 30, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .handCursor()
            .help("Preview \(style.title)")
            .accessibilityLabel("Preview \(style.title)")
        }
        .background(Capsule().fill(selected ? kind.color : Theme.raised))
        .overlay(Capsule().strokeBorder(selected ? Theme.outline : Theme.muted.opacity(0.45), lineWidth: selected ? 2 : 1.5))
    }
}

// MARK: - The ignore ladder, drawn

/// What happens each time a nudge is ignored, as a row of steps.
struct IgnoreLadder: View {
    let config: HabitConfig
    let pushiness: Pushiness

    private struct Step: Identifiable { let id: Int; let level: NudgeLevel; let minutes: Int }

    private var steps: [Step] {
        let retry = Nudging.retrySeconds(retryMinutes: config.retryMinutes, pushiness: pushiness)
        var out: [Step] = []
        for attempt in 0..<12 {
            let plan = Nudging.plan(nudges: config.nudges, retryMinutes: config.retryMinutes, pushiness: pushiness,
                                    elapsed: Double(attempt) * retry + 1)
            if plan.gaveUp { break }
            let loudest = plan.types.compactMap(\.level).max { $0.loudness < $1.loudness } ?? .subtle
            out.append(Step(id: attempt, level: loudest, minutes: Int((Double(attempt) * retry / 60).rounded())))
        }
        return out
    }

    var body: some View {
        let s = steps
        FlowLayout(spacing: 6) {
                ForEach(s) { step in
                    HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.id == 0 ? "First" : "+\(durationText(step.minutes))").font(.body(11, .heavy)).foregroundStyle(Theme.muted)
                        Text(step.level.title).font(.display(12.5, .semibold)).foregroundStyle(Theme.text)
                        LoudnessMeter(level: step.level, height: 5)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .fixedSize()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.canvas))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line, lineWidth: 1.5))
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.muted)
                    }
                }
                Label("Lets it go", systemImage: "hand.wave.fill").font(.display(12, .semibold))
                    .foregroundStyle(Theme.muted).frame(height: 52)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("If ignored: " + s.map { ($0.id == 0 ? "first " : "after \(durationText($0.minutes)) ") + $0.level.title }
            .joined(separator: ", ") + ", then it lets it go.")
    }
}

// MARK: - Sidebar icon tile

struct NavIcon: View {
    let symbol: String
    let tint: Color
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.outline, lineWidth: 1.5))
            .accessibilityHidden(true)
    }
}
