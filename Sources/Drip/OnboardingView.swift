import SwiftUI
import ServiceManagement
import DripCore

/// How the crew should get your attention (onboarding step 3).
enum AttentionStyle: CaseIterable {
    case shoulder, whisper, inPerson

    var title: String {
        switch self {
        case .shoulder: "Tap on the shoulder"
        case .whisper: "Whisper"
        case .inPerson: "Show up in person"
        }
    }
    var blurb: String {
        switch self {
        case .shoulder: "A sound and a corner toast. Recommended."
        case .whisper: "Just the menu bar wiggle. Silent and sneaky."
        case .inPerson: "Characters walk across your screen, and after a while it goes full-screen."
        }
    }
    /// Nudges for a hired habit; shoulder keeps each character's own recommended pick.
    func nudges(for kind: HabitKind) -> [NudgeType] {
        switch self {
        case .shoulder: HabitConfig.defaults(for: kind).nudges
        case .whisper: [.menuWiggle]
        case .inPerson: [.walkAcross, .gag]
        }
    }
}

/// Four steps, ~40 seconds; Enter accepts every sensible default.
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var finish: () -> Void

    @State private var step = 0
    @State private var hired: Set<HabitKind> = [.water, .eyes, .walk, .stretch]
    @State private var attention: AttentionStyle = .shoulder
    @State private var pushiness: Pushiness = .gentle
    @State private var start = ClockTime(hour: 9, minute: 30)
    @State private var end = ClockTime(hour: 18, minute: 30)
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]
    @State private var hush = true
    @State private var login = true
    @State private var forward = true
    @State private var hireBump: [HabitKind: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Group {
                    switch step {
                    case 0: meet
                    case 1: team
                    case 2: style
                    default: hours
                    }
                }
                .id(step)
                .transition(.asymmetric(
                    insertion: .offset(x: forward ? 70 : -70).combined(with: .opacity).combined(with: .scale(scale: 0.97)),
                    removal: .offset(x: forward ? -70 : 70).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule().fill(i == step ? Theme.inverse : Theme.muted.opacity(0.35)).frame(width: i == step ? 20 : 7, height: 7)
                            .onTapGesture { if i < step { go(to: i) } }
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: step)
                Spacer()
                if step == 2 {
                    Button("Preview") {
                        let k = HabitKind.allCases.first(where: hired.contains) ?? .water
                        model.previewNudges(k, types: attention.nudges(for: k))
                    }
                        .buttonStyle(ToyButton(fill: .white, size: 15))
                }
                Button { advance() } label: {
                    Text(primaryLabel).contentTransition(.numericText()).animation(.spring(response: 0.3), value: hired.count)
                }
                    .buttonStyle(ToyButton(fill: Theme.leaf, size: 15))
                    .keyboardShortcut(.defaultAction)
                    .disabled(step == 1 && hired.isEmpty)
            }
        }
        .padding(30)
        .frame(width: 580, height: 650)
        .background(Theme.paper)
    }

    private func go(to s: Int) {
        forward = s > step
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { step = s }
    }

    private var primaryLabel: String {
        switch step {
        case 0: "Meet the crew"
        case 1: "\(hired.count) hired"
        case 2: "Next"
        default: "Clock in"
        }
    }

    private func advance() {
        guard step == 3 else { go(to: step + 1); return }
        var s = model.settings
        for kind in HabitKind.allCases {
            var c = s.config(kind)
            c.enabled = hired.contains(kind)
            c.nudges = attention.nudges(for: kind)
            c.window = ActiveWindow(weekdays: days, start: start, end: end)
            s.habits[kind] = c
        }
        s.pushiness = attention == .inPerson && pushiness == .gentle ? .nag : pushiness
        s.autoHush = hush
        s.onboarded = true
        model.update(s)
        if login { try? SMAppService.mainApp.register() }
        finish()
        if let first = HabitKind.allCases.first(where: hired.contains) { model.previewNudges(first, types: [.menuShow, .toast]) }
    }

    // MARK: Steps

    private var meet: some View {
        VStack(spacing: 22) {
            Spacer()
            CrewRow(size: 70, parade: true)
            Text("Hi! We're the\nNudgelings.").font(.display(44, .bold)).multilineTextAlignment(.center).foregroundStyle(Theme.text)
                .entrance(0, base: 0.85, from: 24)
            Text("Seven tiny coworkers who keep your body happy while you do your actual job.")
                .font(.body(17)).foregroundStyle(Theme.muted).multilineTextAlignment(.center).frame(maxWidth: 380)
                .entrance(1, step: 0.1, base: 0.85, from: 24)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var team: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who's on your team?").font(.display(32, .bold)).foregroundStyle(Theme.text)
            Text("Pick as many as you like. You can swap later.").font(.body(15)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(HabitKind.allCases.enumerated()), id: \.element) { i, kind in
                    let on = hired.contains(kind)
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            if on { hired.remove(kind) } else { hired.insert(kind); hireBump[kind, default: 0] += 1 }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            CharacterView(kind: kind, expression: on ? .happy : .sleepy, size: 40, animated: true,
                                          bump: hireBump[kind] ?? 0)
                            Text("\(kind.character) · \(kind.noun)").font(.display(14, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 18, weight: .bold))
                                .foregroundStyle(on ? Theme.text : Theme.muted)
                        }
                        .padding(11)
                        .toyCard(on ? kind.wash : Theme.paper, radius: 14, shadow: on ? 3 : 0, dashed: !on)
                        .scaleEffect(on ? 1 : 0.97)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .entrance(i, step: 0.05, base: 0.12)
                }
            }
        }
    }

    private var style: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How should they get\nyour attention?").font(.display(30, .bold)).foregroundStyle(Theme.text)
            ForEach(Array(AttentionStyle.allCases.enumerated()), id: \.element) { i, a in
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { attention = a } } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(a.title).font(.display(16, .semibold)).foregroundStyle(Theme.text)
                            Text(a.blurb).font(.body(13)).foregroundStyle(Theme.text.opacity(0.75))
                        }
                        Spacer()
                        Image(systemName: attention == a ? "largecircle.fill.circle" : "circle").font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.text)
                    }
                    .padding(14)
                    .toyCard(attention == a ? Color(light: 0xe3f5df, dark: 0x234027) : Theme.raised, radius: 14, shadow: attention == a ? 3 : 0)
                    .offset(y: attention == a ? -1 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .handCursor()
                .entrance(i, step: 0.06, base: 0.12)
            }
            Text("HOW PUSHY IF YOU IGNORE THEM").font(.display(12, .semibold)).foregroundStyle(Theme.muted).padding(.top, 4)
            PushinessPicker(selection: $pushiness)
            .padding(.top, 6)
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("When are you at your desk?").font(.display(30, .bold)).foregroundStyle(Theme.text)
            Text("We'll clock out when you do.").font(.body(15)).foregroundStyle(Theme.muted)
            HStack(spacing: 12) {
                bigTime($start)
                Text("to").font(.body(15, .bold)).foregroundStyle(Theme.muted)
                bigTime($end)
            }
            HStack(spacing: 8) {
                ForEach([(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")], id: \.0) { d, l in
                    let on = days.contains(d)
                    Button(l) { if on { days.remove(d) } else { days.insert(d) } }
                        .buttonStyle(.plain)
                        .handCursor()
                        .font(.display(15, .semibold))
                        .frame(width: 42, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10).fill(on ? Theme.inverse : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(on ? Theme.inverse : Theme.muted.opacity(0.5), lineWidth: 2))
                        .foregroundStyle(on ? Theme.inverseText : Theme.muted)
                }
            }
            toggleRow("Hush during calls", "Stays quiet while your camera or mic is on", $hush)
            toggleRow("Open at login", "The crew clocks in with you", $login)
        }
    }

    private func bigTime(_ t: Binding<ClockTime>) -> some View {
        TimePickerChip(time: t, tint: Theme.leaf, big: true)
    }

    private func toggleRow(_ title: String, _ sub: String, _ on: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                Text(sub).font(.body(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: on).toggleStyle(ToySwitch(tint: Theme.leaf))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.canvas))
    }
}
