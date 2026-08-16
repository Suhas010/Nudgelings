import SwiftUI
import DripCore

/// "Start ⟨next⟩ now": says who will show up, and confirms on the button itself (no layout jump).
struct StartNextButton: View {
    @ObservedObject var model: AppModel
    var wide = true
    @State private var started: HabitKind?

    var body: some View {
        let next = model.nextUp
        Button {
            guard let k = model.startNextNow() else { return }
            withAnimation(.spring(response: 0.3)) { started = k }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation(.spring(response: 0.3)) { started = nil } }
        } label: {
            HStack(spacing: 6) {
                if let k = started ?? next?.kind { CharacterView(kind: k, expression: started != nil ? .cheer : .happy, size: 18, shadow: false) }
                Text(label(next)).contentTransition(.interpolate)
            }
            .frame(minWidth: wide ? nil : 170)
        }
        .buttonStyle(ToyButton(fill: Theme.leaf, size: 13.5, wide: wide))
        .disabled(started == nil && (next == nil || model.hasReminder))
        .help(next.map { "Show \($0.kind.character)'s \($0.kind.noun) nudge right away instead of waiting" } ?? "")
    }

    private func label(_ next: (kind: HabitKind, at: Date)?) -> String {
        if let k = started { return "✓ \(k.character)'s on the way" }
        return next.map { "Start \($0.kind.character) now" } ?? "Nobody on shift"
    }
}

/// One pause control everywhere: a short break for the whole crew (their settings stay as they are).
struct PauseMenu: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isPaused {
            Button("Resume now") { model.resume() }
                .buttonStyle(ToyButton(fill: .white, size: 13.5))
        } else {
            Menu {
                Button("Pause for 30 minutes") { model.pause(hours: 0.5) }
                Button("Pause for 1 hour") { model.pause(hours: 1) }
                Button("Pause until tomorrow") { model.pauseUntilTomorrow() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold))
                    Text("Pause")
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy))
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(ToyButton(fill: .white, size: 13.5))
            .fixedSize()
            .help("Give the whole crew a short break. Nobody is switched off.")
        }
    }
}

// MARK: - Time picker

/// Toy-style time field: shows the time; click for a quick hour grid + minutes.
struct TimePickerChip: View {
    @Binding var time: ClockTime
    var tint: Color = Theme.leaf
    var big = false
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: big ? 15 : 11, weight: .bold))
                Text(time.date.formatted(date: .omitted, time: .shortened)).monospacedDigit()
            }
            .fixedSize()
            .font(.display(big ? 22 : 13.5, .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, big ? 18 : 11).padding(.vertical, big ? 10 : 6)
            .frame(maxWidth: big ? .infinity : nil)
            .toyCard(.white, radius: big ? 14 : 10, shadow: big ? 3 : 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .popover(isPresented: $open, arrowEdge: .bottom) {
            TimeGrid(time: $time, tint: tint) { open = false }
        }
    }
}

struct TimeGrid: View {
    @Binding var time: ClockTime
    var tint: Color
    var done: () -> Void
    @State private var pm: Bool

    init(time: Binding<ClockTime>, tint: Color, done: @escaping () -> Void) {
        _time = time; self.tint = tint; self.done = done
        _pm = State(initialValue: time.wrappedValue.hour >= 12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(time.date.formatted(date: .omitted, time: .shortened)).font(.display(22, .bold)).monospacedDigit()
                    .contentTransition(.numericText()).animation(.spring(response: 0.3), value: time)
                Spacer()
                HStack(spacing: 4) {
                    Button("AM") { setPM(false) }.buttonStyle(ChipStyle(selected: !pm, tint: tint))
                    Button("PM") { setPM(true) }.buttonStyle(ChipStyle(selected: pm, tint: tint))
                }
            }
            Text("HOUR").font(.display(11, .semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(38), spacing: 6), count: 6), spacing: 6) {
                ForEach(1...12, id: \.self) { h in
                    let hour24 = (h % 12) + (pm ? 12 : 0)
                    Button("\(h)") { time = ClockTime(hour: hour24, minute: time.minute) }
                        .buttonStyle(ChipStyle(selected: time.hour == hour24, tint: tint))
                }
            }
            Text("MINUTE").font(.display(11, .semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Button(String(format: ":%02d", m)) { time = ClockTime(hour: time.hour, minute: m) }
                        .buttonStyle(ChipStyle(selected: time.minute == m, tint: tint))
                }
                Spacer()
                Button("Done", action: done).buttonStyle(ToyButton(fill: tint, size: 12.5)).fixedSize()
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.paper)
    }

    private func setPM(_ on: Bool) {
        pm = on
        let h = time.hour % 12 + (on ? 12 : 0)
        time = ClockTime(hour: h, minute: time.minute)
    }
}

// MARK: - Pushiness

extension Pushiness {
    var onboardingTitle: String {
        switch self {
        case .gentle: "Gentle"
        case .nag: "Nagging"
        case .max: "Relentless"
        }
    }
    var face: Expression {
        switch self {
        case .gentle: .happy
        case .nag: .worried
        case .max: .cheer
        }
    }
    var level: Int { Pushiness.allCases.firstIndex(of: self)! + 1 }

    /// Longer explanation for the onboarding tiles.
    var onboardingBlurb: String {
        switch self {
        case .gentle: "Retries twice, never takes over."
        case .nag: "Retries sooner; takes over after two ignores."
        case .max: "Climbs two rungs at a time; takes over after one ignore."
        }
    }
}

/// Three tappable tiles instead of a slider: a face, an intensity meter and what it actually means.
struct PushinessPicker: View {
    @Binding var selection: Pushiness
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Pushiness.allCases) { p in
                let on = selection == p
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { selection = p } } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .bottom) {
                            CharacterView(kind: .water, expression: p.face, size: compact ? 30 : 38, animated: true,
                                          bump: on ? 1 : 0)
                            Spacer()
                            Meter(level: p.level, on: on)
                        }
                        Text(p.onboardingTitle).font(.display(compact ? 13.5 : 15, .semibold)).foregroundStyle(Theme.text)
                        if !compact {
                            Text(p.onboardingBlurb).font(.body(11.5)).foregroundStyle(Theme.text.opacity(0.72))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .toyCard(on ? Color(light: 0xe3f5df, dark: 0x234027) : Theme.raised, radius: 14, shadow: on ? 4 : 0)
                    .offset(y: on ? -2 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
            }
        }
    }
}

/// 1–3 rising bars.
private struct Meter: View {
    let level: Int
    let on: Bool
    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(i <= level ? (on ? Theme.leaf : Theme.muted.opacity(0.6)) : Theme.muted.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Theme.outline.opacity(i <= level && on ? 1 : 0), lineWidth: 1))
                    .frame(width: 6, height: CGFloat(6 + i * 5))
            }
        }
    }
}
