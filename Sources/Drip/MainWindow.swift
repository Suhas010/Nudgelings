import SwiftUI
import ServiceManagement
import DripCore

// MARK: - Vocabulary

extension NudgeType {
    var title: String {
        switch self {
        case .menuWiggle: "Menu wiggle"
        case .sound: "Sound cue"
        case .toast: "Corner toast"
        case .menuShow: "Menu-bar show"
        case .walkAcross: "Walk-across"
        case .cursorTrail: "Cursor trail"
        case .dim: "Dim & blur"
        case .gag: "Screen gag"
        case .takeover: "Takeover"
        case .miniGame: "Mini-game"
        }
    }

    func subtitle(for kind: HabitKind, sound: SoundCue) -> String {
        switch self {
        case .menuWiggle: return "Barely there"
        case .sound: return "Plays \(soundName(sound).lowercased())"
        case .toast: return "Top-right card"
        case .menuShow:
            switch kind {
            case .water: return "Waves across the bar"
            case .eyes: return "Eyes peek from the bar"
            case .walk: return "Stompy struts the bar"
            case .stretch: return "Elastic bands boing"
            case .posture: return "The bar turns into a level"
            case .breathe: return "The bar breathes"
            case .stand: return "Pop hops along the bar"
            }
        case .walkAcross: return "\(kind.character) strolls by"
        case .cursorTrail:
            switch kind {
            case .water: return "Tiny droplet trail"
            case .eyes: return "Sparkles follow you"
            case .walk: return "Footprints follow you"
            case .stretch: return "Confetti crumbs"
            case .posture: return "Falling leaves"
            case .breathe: return "Calm ripples"
            case .stand: return "Little up arrows"
            }
        case .dim: return kind == .eyes ? "Dims, blurs, counts 20s" : "Screen goes soft"
        case .gag:
            switch kind {
            case .water: return "The screen floods (with fish)"
            case .eyes: return "Fog, then a wiper"
            case .walk: return "Footprints walk off"
            case .stretch: return "Jelly wobble"
            case .posture: return "The screen tilts"
            case .breathe: return "The screen breathes"
            case .stand: return "Pop pops up"
            }
        case .takeover:
            switch kind {
            case .water: return "Full-screen brook"
            case .eyes: return "Spotlight countdown"
            default: return "Full-screen \(kind.character)"
            }
        case .miniGame:
            switch kind {
            case .water: return "Pop bubbles to close"
            case .stretch: return "Hold-to-stretch"
            default: return "Hold to finish"
            }
        }
    }

    /// Short label for summaries ("toast + brook sound").
    var short: String {
        switch self {
        case .menuWiggle: "menu wiggle"
        case .sound: "sound"
        case .toast: "toast"
        case .menuShow: "menu-bar show"
        case .walkAcross: "walks across screen"
        case .cursorTrail: "cursor trail"
        case .dim: "dim + countdown"
        case .gag: "screen gag"
        case .takeover: "takeover"
        case .miniGame: "mini-game"
        }
    }
}

func durationText(_ minutes: Int) -> String {
    switch (minutes / 60, minutes % 60) {
    case (0, let m): "\(m) min"
    case (let h, 0): "\(h) h"
    case (let h, let m): "\(h) h \(m) min"
    }
}

extension HabitConfig {
    var scheduleText: String {
        switch schedule {
        case let .every(minutes, _): "Every \(durationText(minutes))"
        case let .atTimes(times): "At " + times.map { $0.date.formatted(date: .omitted, time: .shortened) }.joined(separator: ", ")
        }
    }
    var summary: String {
        enabled ? "\(scheduleText) · \(nudges.map(\.short).joined(separator: " + "))" : "Off duty. Zzz."
    }
    var goalNoun: String {
        switch kind {
        case .water: "glasses"
        case .eyes: "eye breaks"
        case .walk: "walks"
        case .stretch: "stretches"
        case .posture: "posture checks"
        case .breathe: "breathers"
        case .stand: "stand-ups"
        }
    }
}

extension ClockTime {
    init(_ date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
    var date: Date { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() }
}

// MARK: - Window

struct MainWindow: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav = Navigation.shared

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, nav: nav)
            Rectangle().fill(Theme.outline).frame(width: Theme.stroke)
            ScrollView {
                ZStack(alignment: .topLeading) {
                    Group {
                    switch nav.page {
                    case .crew: CrewPage(model: model, nav: nav)
                    case let .editor(kind): HabitEditor(model: model, notifier: model.notifier, kind: kind).id(kind)
                    case .styles: StylesPage(model: model)
                    case .schedule: SchedulePage(model: model)
                    case .streaks: StreaksPage(model: model, nav: nav)
                    case let .share(kind): ShareStudio(model: model, kind: kind).id(kind)
                    case .settings: SettingsPage(model: model)
                    case .about: AboutPage()
                    }
                    }
                    .id(nav.page)
                    .transition(.asymmetric(insertion: .offset(y: 14).combined(with: .opacity),
                                            removal: .opacity))
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: nav.page)
                .padding(28)
                .frame(maxWidth: 880, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Theme.paper)
        }
        .frame(minWidth: 900, minHeight: 640)
        .background(Theme.paper)
        // Run under the transparent title bar so the sidebar and its divider reach the top edge.
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigation
    @Namespace private var pill

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer().frame(height: 44)   // clears the window's traffic lights
            item("Crew", selected: nav.page == .crew || isEditor) { go(.crew) }
            if isEditor || nav.page == .crew {
                ForEach(HabitKind.allCases) { kind in
                    Button { go(.editor(kind)) } label: {
                        HStack(spacing: 8) {
                            CharacterView(kind: kind, expression: .happy, size: 20, shadow: false)
                                .opacity(model.settings.config(kind).enabled ? 1 : 0.45)
                            Text("\(kind.character) · \(kind.noun)").font(.body(13, .bold))
                                .foregroundStyle(nav.page == .editor(kind) ? kind.accent : Theme.text.opacity(0.85))
                        }
                        .padding(.leading, 12).padding(.vertical, 4)
                        .padding(.trailing, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(nav.page == .editor(kind) ? kind.wash : .clear))
                        .padding(.leading, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                }
            }
            item("Nudge styles", selected: nav.page == .styles) { go(.styles) }
            item("Schedule", selected: nav.page == .schedule) { go(.schedule) }
            item("Streaks", selected: nav.page == .streaks) { go(.streaks) }
            item("Share", selected: isShare) { go(.share(.today)) }
            item("Settings", selected: nav.page == .settings) { go(.settings) }
            item("About", selected: nav.page == .about) { go(.about) }
            Spacer()
            PushinessBox(model: model)
        }
        .padding(12)
        .frame(width: 220)
        .background(Theme.canvas)
    }

    private var isEditor: Bool { if case .editor = nav.page { true } else { false } }
    private var isShare: Bool { if case .share = nav.page { true } else { false } }

    private func go(_ p: Navigation.Page) {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { nav.page = p }
    }

    private func item(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.display(14, .semibold))
                .foregroundStyle(selected ? Theme.inverseText : Theme.text)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 10).fill(Theme.inverse).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

struct PushinessBox: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pushiness").font(.display(13, .semibold)).foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                ForEach(Pushiness.allCases) { p in
                    Button(p.label) {
                        var s = model.settings
                        s.pushiness = p
                        model.update(s)
                    }
                    .buttonStyle(ChipStyle(selected: model.settings.pushiness == p))
                }
            }
            Text(model.settings.pushiness.blurb).font(.body(11)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(Theme.raised, radius: 14, shadow: 3)
    }
}

extension Pushiness {
    var label: String {
        switch self {
        case .gentle: "Gentle"
        case .nag: "Nag"
        case .max: "Max"
        }
    }
    var blurb: String {
        switch self {
        case .gentle: "Retries twice, never takes over."
        case .nag: "Retries sooner; takes over after two ignores."
        case .max: "Relentless. You asked for this."
        }
    }
}

// MARK: - 1j · Crew

struct CrewPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var nav: Navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your crew").font(.display(34, .bold)).foregroundStyle(Theme.text)
                    Text(subtitle).font(.body(14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if !model.isPaused { StartNextButton(model: model, wide: false) }
                PauseMenu(model: model)
            }
            Label("Switch a character off to take them off duty. Pause gives the whole crew a short break and brings everyone back on its own.",
                  systemImage: "info.circle")
                .font(.body(12.5)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(Array(HabitKind.allCases.enumerated()), id: \.element) { i, kind in
                    CrewCard(model: model, kind: kind) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) { nav.page = .editor(kind) }
                    }
                    .entrance(i, step: 0.05, base: 0.06)
                }
            }
        }
    }

    private var subtitle: String {
        let on = model.settings.enabledKinds
        let next = on.compactMap { k in model.state.nextDue[k].map { (k, $0) } }.min { $0.1 < $1.1 }
        var s = "\(on.count) on shift"
        if let until = model.pausedUntilText { return s + " · ☕ paused until \(until)" }
        if let (k, d) = next {
            let m = Int(max(0, d.timeIntervalSinceNow) / 60)
            s += " · next up: \(k.character) " + (m < 1 ? "now" : m < 60 ? "in \(m) min" : "at \(d.formatted(date: .omitted, time: .shortened))")
        }
        return s
    }
}

struct CrewCard: View {
    @ObservedObject var model: AppModel
    let kind: HabitKind
    var open: () -> Void
    @State private var hovering = false
    @State private var bump = 0

    var body: some View {
        let c = model.settings.config(kind)
        HStack(spacing: 14) {
            CharacterView(kind: kind, expression: c.enabled ? .happy : .sleepy, size: 52, animated: true, bump: bump)
                .opacity(c.enabled ? 1 : 0.6)
                .animation(.easeInOut(duration: 0.3), value: c.enabled)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(kind.character) · \(kind.title)").font(.display(16, .semibold)).foregroundStyle(c.enabled ? Theme.text : Theme.muted)
                Text(c.summary).font(.body(12.5)).foregroundStyle(c.enabled ? Theme.text.opacity(0.78) : Theme.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { c.enabled }, set: { on in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { model.updateHabit(kind) { $0.enabled = on } }
                if on { bump += 1 }
            }))
                .toggleStyle(ToySwitch())
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .toyCard(c.enabled ? kind.wash : Theme.canvas, radius: 16, shadow: c.enabled ? (hovering ? 6 : 4) : 0, dashed: !c.enabled)
        .offset(y: hovering ? -2 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .handCursor()
        .onTapGesture(perform: open)
    }
}

// MARK: - 1k · Habit editor

struct HabitEditor: View {
    @ObservedObject var model: AppModel
    @ObservedObject var notifier: Notifier
    let kind: HabitKind
    @State private var cheer = 0

    private var c: HabitConfig { model.settings.config(kind) }
    private func set(_ change: (inout HabitConfig) -> Void) { model.updateHabit(kind, change) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            if c.enabled {
                nudgePicker
                HStack(alignment: .top, spacing: 16) {
                    whenCard.frame(maxWidth: .infinity)
                    VStack(spacing: 16) { soundCard; ignoredCard }.frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 10) {
                    Text("\(kind.character) is off duty. Zzz.").font(.display(20, .semibold)).foregroundStyle(Theme.text)
                    Button("Put \(kind.character) on shift") { set { $0.enabled = true } }
                        .buttonStyle(ToyButton(fill: kind.color, size: 14))
                }
                .frame(maxWidth: .infinity).padding(40)
                .toyCard(Theme.canvas, radius: 18, dashed: true)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            CharacterView(kind: kind, expression: c.enabled ? .happy : .sleepy, size: 76, animated: true, bump: cheer)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.character).font(.display(34, .bold)).foregroundStyle(Theme.text)
                Text("\(kind.title) · goal \(c.goal) \(c.goalNoun) a day").font(.body(14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { c.enabled }, set: { on in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { set { $0.enabled = on } }
                if on { cheer += 1 }
            })).toggleStyle(ToySwitch())
            if c.enabled {
                Button("Preview nudge") { model.previewNudges(kind) }.buttonStyle(ToyButton(fill: kind.color, size: 14))
            }
        }
    }

    private var nudgePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW \(kind.character.uppercased()) NUDGES YOU (PICK UP TO 2)").font(.display(13, .semibold)).foregroundStyle(Theme.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(NudgeType.allCases) { t in
                    let on = c.nudges.contains(t)
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { set { $0.toggle(t) } }
                        cheer += 1
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(t.title).font(.display(13.5, .semibold))
                                if on {
                                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .foregroundStyle(on ? Theme.ink : Theme.text)
                            Text(t.subtitle(for: kind, sound: c.sound)).font(.body(11.5)).foregroundStyle(on ? Theme.ink.opacity(0.75) : Theme.muted)
                                .lineLimit(2, reservesSpace: true)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .toyCard(on ? kind.color.opacity(0.9) : Theme.raised, radius: 12, shadow: on ? 3 : 0)
                        .offset(y: on ? -2 : 0)
                        .keyframeAnimator(initialValue: 1.0, trigger: on) { v, sc in v.scaleEffect(sc) } keyframes: { _ in
                            KeyframeTrack {
                                SpringKeyframe(1.06, duration: 0.12)
                                SpringKeyframe(1.0, duration: 0.35, spring: .bouncy)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .contextMenu { Button("Preview \(t.title)") { model.previewNudges(kind, types: [t]) } }
                }
            }
            Text("Tip: right-click any style to preview it on its own.").font(.body(11.5)).foregroundStyle(Theme.muted)
        }
    }

    private var whenCard: some View {
        EditorCard(title: "WHEN") {
            HStack(spacing: 6) {
                let every = { if case .every = c.schedule { true } else { false } }()
                Button("Every…") { if !every { set { $0.schedule = .every(minutes: 45, anchor: .lastDone) } } }
                    .buttonStyle(ChipStyle(selected: every, tint: kind.color))
                Button("At set times") {
                    if every { set { $0.schedule = .atTimes([ClockTime(hour: 11, minute: 30), ClockTime(hour: 15, minute: 0)]) } }
                }
                .buttonStyle(ChipStyle(selected: !every, tint: kind.color))
            }
            switch c.schedule {
            case let .every(minutes, anchor):
                HStack(spacing: 12) {
                    StepButton("minus") { set { $0.schedule = .every(minutes: max(5, minutes - (minutes > 60 ? 15 : 5)), anchor: anchor) } }
                    Text(durationText(minutes)).font(.display(30, .bold)).foregroundStyle(Theme.text).monospacedDigit()
                        .contentTransition(.numericText(value: Double(minutes)))
                        .animation(.spring(response: 0.3), value: minutes)
                    StepButton("plus") { set { $0.schedule = .every(minutes: min(480, minutes + (minutes >= 60 ? 15 : 5)), anchor: anchor) } }
                    Text("About \(perDay(minutes)) nudges a day").font(.body(12.5)).foregroundStyle(Theme.muted)
                }
                HStack(spacing: 6) {
                    Text("Count from").font(.body(12.5)).foregroundStyle(Theme.muted)
                    Button("Last time I did it") { set { $0.schedule = .every(minutes: minutes, anchor: .lastDone) } }
                        .buttonStyle(ChipStyle(selected: anchor == .lastDone, tint: kind.color))
                    Button("The clock") { set { $0.schedule = .every(minutes: minutes, anchor: .clock) } }
                        .buttonStyle(ChipStyle(selected: anchor == .clock, tint: kind.color))
                }
            case let .atTimes(times):
                FlowLayout(spacing: 6) {
                    ForEach(Array(times.enumerated()), id: \.offset) { i, time in
                        TimeChip(time: time, tint: kind.color,
                                 onChange: { new in set { var t = times; t[i] = new; $0.schedule = .atTimes(t.sorted()) } },
                                 onRemove: { set { var t = times; t.remove(at: i); $0.schedule = .atTimes(t) } })
                    }
                    Button { set { let last = times.max() ?? ClockTime(hour: 9, minute: 0)
                        $0.schedule = .atTimes((times + [ClockTime(hour: min(23, last.hour + 2), minute: last.minute)]).sorted()) } } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(ChipStyle(selected: false))
                }
            }
            HoursRow(window: Binding(get: { c.window }, set: { w in set { $0.window = w } }), tint: kind.color)
        }
    }

    private func perDay(_ minutes: Int) -> Int {
        let span = c.window.end.minutesSinceMidnight - c.window.start.minutesSinceMidnight
        return max(1, span / max(1, minutes))
    }

    private var soundCard: some View {
        EditorCard(title: "SOUND") {
            HStack(spacing: 10) {
                Button { model.sound.play(c.sound, seconds: 6) } label: {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30).background(Circle().fill(kind.color))
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .handCursor()
                Picker("", selection: Binding(get: { c.sound }, set: { s in set { $0.sound = s } })) {
                    ForEach(SoundCue.allCases) { Text(soundName($0)).tag($0) }
                }
                .labelsHidden()
            }
            Text(c.nudges.contains(.sound) ? "Plays when \(kind.character) nudges you." : "Add “Sound cue” above to hear it on each nudge.")
                .font(.body(11.5)).foregroundStyle(Theme.muted)
        }
    }

    private var ignoredCard: some View {
        EditorCard(title: "IF IGNORED") {
            HStack(spacing: 6) {
                Text("Try again in").font(.body(13.5))
                StepButton("minus", small: true) { set { $0.retryMinutes = max(2, $0.retryMinutes - 1) } }
                Text("\(c.retryMinutes) min").font(.display(14, .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(c.retryMinutes))).animation(.spring(response: 0.3), value: c.retryMinutes)
                StepButton("plus", small: true) { set { $0.retryMinutes = min(60, $0.retryMinutes + 1) } }
            }
            .foregroundStyle(Theme.text)
            Text("then step up one rung. \(kind.character) gives up after \(model.settings.pushiness == .gentle ? 2 : model.settings.pushiness == .nag ? 3 : 4) tries and doesn't hold grudges.")
                .font(.body(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 6) {
                Text("Daily goal").font(.body(13.5))
                StepButton("minus", small: true) { set { $0.goal = max(1, $0.goal - 1) } }
                Text("\(c.goal) \(c.goalNoun)").font(.display(14, .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(c.goal))).animation(.spring(response: 0.3), value: c.goal)
                StepButton("plus", small: true) { set { $0.goal = min(30, $0.goal + 1) } }
            }
            .foregroundStyle(Theme.text)
            Toggle(isOn: Binding(get: { c.notify }, set: { n in set { $0.notify = n } })) {
                Text("Also send a macOS notification").font(.body(13))
            }
            .toggleStyle(.checkbox)
            if notifier.denied, c.notify {
                Text("Notifications are off for Nudgelings in System Settings.").font(.body(11.5)).foregroundStyle(HabitKind.stretch.accent)
            }
        }
    }
}

struct EditorCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.display(12.5, .semibold)).foregroundStyle(Theme.muted)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(Theme.raised, radius: 16)
    }
}

struct StepButton: View {
    let icon: String
    var small = false
    var action: () -> Void
    init(_ icon: String, small: Bool = false, action: @escaping () -> Void) { self.icon = icon; self.small = small; self.action = action }
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: small ? 10 : 13, weight: .heavy)).foregroundStyle(Theme.ink)
                .frame(width: small ? 24 : 34, height: small ? 24 : 34)
                .toyCard(.white, radius: 9, shadow: 2)
        }
        .buttonStyle(.plain)
        .handCursor()
    }
}

struct HoursRow: View {
    @Binding var window: ActiveWindow
    let tint: Color
    private let days = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Between").font(.body(12.5)).foregroundStyle(Theme.muted)
                TimePickerChip(time: $window.start, tint: tint)
                Text("and").font(.body(12.5)).foregroundStyle(Theme.muted)
                TimePickerChip(time: $window.end, tint: tint)
            }
            HStack(spacing: 5) {
                ForEach(days, id: \.0) { day, label in
                    let on = window.weekdays.contains(day)
                    Button(label) { if on { window.weekdays.remove(day) } else { window.weekdays.insert(day) } }
                        .buttonStyle(.plain)
                        .handCursor()
                        .font(.display(12.5, .semibold))
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Theme.inverse : Color.clear))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Theme.inverse : Theme.muted.opacity(0.5), lineWidth: 1.5))
                        .foregroundStyle(on ? Theme.inverseText : Theme.muted)
                }
            }
        }
    }
}

struct TimeChip: View {
    let time: ClockTime
    let tint: Color
    var onChange: (ClockTime) -> Void
    var onRemove: () -> Void
    @State private var editing = false

    var body: some View {
        HStack(spacing: 6) {
            Button(time.date.formatted(date: .omitted, time: .shortened)) { editing = true }.buttonStyle(.plain).handCursor()
            Button(action: onRemove) { Image(systemName: "xmark.circle.fill").opacity(0.7) }.buttonStyle(.plain).handCursor()
        }
        .font(.display(12.5, .semibold))
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 11).padding(.vertical, 6)
        .background(Capsule().fill(tint))
        .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 2))
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            TimeGrid(time: Binding(get: { time }, set: { onChange($0) }), tint: tint) { editing = false }
        }
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0,
                      height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + s.width > width { rows.append(Row()) }
            var r = rows[rows.count - 1]
            r.width += (r.indices.isEmpty ? 0 : spacing) + s.width
            r.height = max(r.height, s.height)
            r.indices.append(i)
            rows[rows.count - 1] = r
        }
        return rows
    }
}

// MARK: - Nudge styles, schedule, settings

struct StylesPage: View {
    @ObservedObject var model: AppModel
    @State private var who: HabitKind = .water

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nudge styles").font(.display(34, .bold)).foregroundStyle(Theme.text)
            Text("The ladder, quietest first. Ignored nudges come back one rung louder.").font(.body(14)).foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                Text("Try with").font(.body(13)).foregroundStyle(Theme.muted)
                ForEach(HabitKind.allCases) { k in
                    Button { who = k } label: { CharacterView(kind: k, expression: .happy, size: 30, shadow: false) }
                        .buttonStyle(.plain)
                        .handCursor()
                        .padding(3)
                        .background(Circle().fill(who == k ? k.color.opacity(0.35) : .clear))
                }
            }
            ForEach(Array(NudgeType.allCases.enumerated()), id: \.element) { i, t in
                HStack(spacing: 14) {
                    Text("\(i + 1)").font(.display(15, .bold)).foregroundStyle(Theme.inverseText)
                        .frame(width: 30, height: 30).background(Circle().fill(Theme.inverse))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t.title).font(.display(15, .semibold)).foregroundStyle(Theme.text)
                        Text(t.subtitle(for: who, sound: model.settings.config(who).sound)).font(.body(12.5)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if t.blocksScreen { Text("Blocks screen").font(.body(11, .bold)).foregroundStyle(HabitKind.stretch.accent) }
                    Button("Try") { model.previewNudges(who, types: [t]) }.buttonStyle(ToyButton(fill: who.color, size: 12.5))
                }
                .padding(12)
                .toyCard(Theme.raised, radius: 14, shadow: 2)
                .entrance(i, step: 0.035, base: 0.08)
            }
        }
    }
}

struct SchedulePage: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Schedule").font(.display(34, .bold)).foregroundStyle(Theme.text)
            Text("Who's coming up next, and how today is going.").font(.body(14)).foregroundStyle(Theme.muted)
            let on = model.settings.enabledKinds.sorted {
                (model.state.nextDue[$0] ?? .distantFuture) < (model.state.nextDue[$1] ?? .distantFuture)
            }
            if on.isEmpty { Text("Nobody's on shift yet.").font(.body(14)).foregroundStyle(Theme.muted) }
            ForEach(on) { k in
                let c = model.settings.config(k)
                HStack(spacing: 14) {
                    CharacterView(kind: k, expression: .happy, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(k.character) · \(k.title)").font(.display(15, .semibold)).foregroundStyle(Theme.text)
                        GoalDots(kind: k, done: model.state.stats.done[k] ?? 0, goal: c.goal)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(model.state.nextDue[k].map { $0.formatted(date: .omitted, time: .shortened) } ?? "—")
                            .font(.display(18, .bold)).foregroundStyle(Theme.text).monospacedDigit()
                        Text(c.scheduleText).font(.body(11.5)).foregroundStyle(Theme.text.opacity(0.72))
                    }
                }
                .padding(14)
                .toyCard(k.wash, radius: 16, shadow: 3)
            }
        }
    }
}

// MARK: - About

struct AboutPage: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "Version \(v)"
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer().frame(height: 30)
            CrewRow(size: 64, parade: true)
            Text("Nudgelings").font(.display(40, .bold)).foregroundStyle(Theme.text).entrance(0, base: 0.8)
            Text("A tiny crew that lives in your menu bar and gently bullies you into being healthy.")
                .font(.body(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420)
            Text(version).font(.body(12, .bold)).foregroundStyle(Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Theme.canvas))
            VStack(spacing: 6) {
                Text("Everything stays on your Mac. No accounts, no tracking, no network.")
                Text("Fonts: Fredoka and Nunito, under the SIL Open Font License.")
            }
            .font(.body(12.5)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            .padding(.top, 8)
            Spacer().frame(height: 12)
            HStack(spacing: 8) {
                CharacterView(kind: .water, expression: .happy, size: 22, shadow: false)
                Text("Made with care (and plenty of water) by Suhas More")
                    .font(.body(13, .semibold)).foregroundStyle(Theme.text.opacity(0.7))
            }
            SocialLinks().padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }
}
