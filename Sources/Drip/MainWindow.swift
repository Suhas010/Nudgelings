import SwiftUI
import ServiceManagement
import DripCore

// MARK: - Vocabulary

extension NudgeType {
    func subtitle(for kind: HabitKind, sound: SoundCue) -> String {
        switch self {
        case .menuWiggle: return "\(kind.character) wiggles in the menu bar"
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
        enabled ? "\(scheduleText) · \(style.title)\(playsSound ? " + sound" : "")" : "Off duty. Zzz."
    }
    /// "every 30 min after you last did it", "at 11:30 AM and 3:00 PM".
    var scheduleSentence: String {
        switch schedule {
        case let .every(minutes, anchor): "every \(durationText(minutes))" + (anchor == .lastDone ? " after you last did it" : " on the clock")
        case let .atTimes(times):
            "at " + ListFormatter.localizedString(byJoining: times.map { $0.date.formatted(date: .omitted, time: .shortened) })
        }
    }
    var windowSentence: String {
        "between \(window.start.date.formatted(date: .omitted, time: .shortened)) and \(window.end.date.formatted(date: .omitted, time: .shortened)) \(window.daysText)"
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
            item("Crew", icon: "person.3.fill", tint: Theme.leaf, selected: nav.page == .crew || isEditor) { go(.crew) }
            if isEditor || nav.page == .crew {
                ForEach(HabitKind.allCases) { kind in
                    Button { go(.editor(kind)) } label: {
                        HStack(spacing: 8) {
                            CharacterView(kind: kind, expression: .happy, size: 20, shadow: false)
                                .opacity(model.settings.config(kind).enabled ? 1 : 0.45)
                            Text("\(kind.character) · \(kind.noun)").font(.body(13, .bold))
                                .foregroundStyle(nav.page == .editor(kind) ? kind.accent : Theme.text.opacity(0.85))
                        }
                        .padding(.leading, 14).padding(.vertical, 5)
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
            item("Nudge styles", icon: "bell.badge.fill", tint: Theme.aqua, selected: nav.page == .styles) { go(.styles) }
            item("Schedule", icon: "calendar", tint: Theme.sun, selected: nav.page == .schedule) { go(.schedule) }
            item("Streaks", icon: "flame.fill", tint: Theme.coral, selected: nav.page == .streaks) { go(.streaks) }
            item("Share", icon: "square.and.arrow.up.fill", tint: Theme.lilac, selected: isShare) { go(.share(.today)) }
            item("Settings", icon: "gearshape.fill", tint: Theme.sprout, selected: nav.page == .settings) { go(.settings) }
            item("About", icon: "heart.fill", tint: Theme.orange, selected: nav.page == .about) { go(.about) }
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

    private func item(_ title: String, icon: String, tint: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                NavIcon(symbol: icon, tint: tint)
                Text(title).font(.display(14, .semibold))
            }
                .foregroundStyle(selected ? Theme.inverseText : Theme.text)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if selected { RoundedRectangle(cornerRadius: 10).fill(Theme.inverse).matchedGeometryEffect(id: "pill", in: pill) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .handCursor()
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
        case .gentle: "Retries twice. Never blocks your screen."
        case .nag: "Can block the screen after two ignores."
        case .max: "Can block the screen after one ignore. You asked for this."
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
        VStack(alignment: .leading, spacing: 18) {
            header
            if c.enabled {
                summary
                SectionTitle(number: 1, title: "When", tint: kind.color)
                whenCard
                SectionTitle(number: 2, title: "How should \(kind.character) get your attention?", tint: kind.color)
                howCard
                SectionTitle(number: 3, title: "If you ignore it", tint: kind.color)
                HStack(alignment: .top, spacing: 16) {
                    ignoredCard.frame(maxWidth: .infinity)
                    extrasCard.frame(maxWidth: 280)
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
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind.character).font(.display(34, .bold)).foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Text("\(kind.title) · goal \(c.goal) \(c.goalNoun) a day").font(.body(14)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { c.enabled }, set: { on in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { set { $0.enabled = on } }
                if on { cheer += 1 }
            }))
            .toggleStyle(ToySwitch())
            .accessibilityLabel("\(kind.character) on shift")
            if c.enabled {
                Button { model.previewNudges(kind) } label: { Label("Preview", systemImage: "play.fill") }
                    .buttonStyle(ToyButton(fill: kind.color, size: 14))
                    .help("Show \(kind.character)'s nudge right now. Your schedule stays the same.")
            }
        }
    }

    /// The whole setup, read back as one sentence, so nobody has to decode the controls.
    private var summary: some View {
        let strong = { (s: String) in Text(s).font(.body(14.5, .heavy)).foregroundColor(Theme.text) }
        let plain = { (s: String) in Text(s).font(.body(14.5, .semibold)).foregroundColor(Theme.text.opacity(0.8)) }
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: "text.bubble.fill").font(.system(size: 18, weight: .bold)).foregroundStyle(kind.accent)
                .accessibilityHidden(true)
            (plain("\(kind.character) will ") + strong(c.style.sentence(kind)) + plain(" ") + strong(c.scheduleSentence)
                + plain(", \(c.windowSentence)") + (c.playsSound ? plain(", with ") + strong(soundName(c.sound).lowercased()) : plain(""))
                + plain("."))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(kind.wash, radius: 14, shadow: 0)
        .accessibilityElement(children: .combine)
        .animation(.easeInOut(duration: 0.2), value: c)
    }

    private var level: NudgeLevel { c.style.level ?? .subtle }

    private func pick(_ style: NudgeType) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) { set { $0.style = style } }
        cheer += 1
    }

    private var howCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(NudgeLevel.allCases) { l in
                    LevelCard(level: l, kind: kind, selected: l == level) {
                        // Keep the current style if it's already on this level; else the character's own pick, else the first.
                        guard l != level else { return }
                        let own = HabitConfig.defaults(for: kind).style
                        pick(own.level == l ? own : l.styles[0])
                    }
                }
            }
            // The chosen level, in words, plus its styles.
            VStack(alignment: .leading, spacing: 10) {
                Text(level.blurb(kind)).font(.body(13.5)).foregroundStyle(Theme.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(level.styles.count > 1 ? "Style" : "Looks like").font(.body(12.5, .bold)).foregroundStyle(Theme.muted)
                    ForEach(level.styles) { st in
                        StyleChip(style: st, kind: kind, selected: st == c.style,
                                  pick: { pick(st) }, preview: { model.previewNudges(kind, types: [st]) })
                    }
                }
                Text(c.style.subtitle(for: kind, sound: c.sound))
                    .font(.body(12.5)).foregroundStyle(Theme.muted)
                    .contentTransition(.opacity)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.canvas))
            Divider()
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(get: { c.playsSound }, set: { on in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { set { $0.playsSound = on } }
                })).toggleStyle(ToySwitch(tint: kind.accent)).accessibilityLabel("Play a sound too")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Play a sound too").font(.display(14, .semibold)).foregroundStyle(Theme.text)
                    Text(c.playsSound ? "Every nudge starts with it." : "Silent nudges.").font(.body(12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Group {
                    if Motion.snapshot {
                        // Offscreen renders can't draw AppKit pop-ups; show what the picker displays.
                        HStack { Text(soundName(c.sound)); Spacer(); Image(systemName: "chevron.up.chevron.down") }
                            .font(.body(13, .bold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.raised))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line, lineWidth: 1.5))
                    } else {
                        Picker("Sound", selection: Binding(get: { c.sound }, set: { s in set { $0.sound = s } })) {
                            ForEach(SoundCue.allCases) { Text(soundName($0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                .frame(width: 160)
                .opacity(c.playsSound ? 1 : 0.55)
                Button { model.sound.play(c.sound, seconds: 6) } label: {
                    Image(systemName: "play.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                        .frame(width: 30, height: 30).background(Circle().fill(kind.color))
                        .overlay(Circle().strokeBorder(Theme.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .handCursor()
                .help("Hear \(soundName(c.sound).lowercased())")
                .accessibilityLabel("Play \(soundName(c.sound))")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(Theme.raised, radius: 16)
    }

    private var whenCard: some View {
        EditorCard {
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
                    StepButton("minus", label: "Nudge more often") { set { $0.schedule = .every(minutes: max(5, minutes - (minutes > 60 ? 15 : 5)), anchor: anchor) } }
                    Text(durationText(minutes)).font(.display(30, .bold)).foregroundStyle(Theme.text).monospacedDigit()
                        .contentTransition(.numericText(value: Double(minutes)))
                        .animation(.spring(response: 0.3), value: minutes)
                    StepButton("plus", label: "Nudge less often") { set { $0.schedule = .every(minutes: min(480, minutes + (minutes >= 60 ? 15 : 5)), anchor: anchor) } }
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

    private var ignoredCard: some View {
        EditorCard {
            HStack(spacing: 6) {
                Text("Try again in").font(.body(13.5))
                StepButton("minus", small: true, label: "Sooner") { set { $0.retryMinutes = max(2, $0.retryMinutes - 1) } }
                Text("\(c.retryMinutes) min").font(.display(14, .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(c.retryMinutes))).animation(.spring(response: 0.3), value: c.retryMinutes)
                    .accessibilityLabel("Retry every \(c.retryMinutes) minutes")
                StepButton("plus", small: true, label: "Later") { set { $0.retryMinutes = min(60, $0.retryMinutes + 1) } }
                Text("a little louder each time.").font(.body(13.5))
            }
            .foregroundStyle(Theme.text)
            IgnoreLadder(config: c, pushiness: model.settings.pushiness)
            Label("How far it goes depends on Pushiness (\(model.settings.pushiness.label)), at the bottom of the sidebar. No grudges either way.",
                  systemImage: "info.circle")
                .font(.body(12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var extrasCard: some View {
        EditorCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily goal").font(.display(13.5, .semibold)).foregroundStyle(Theme.text)
                HStack(spacing: 6) {
                    StepButton("minus", small: true, label: "Lower goal") { set { $0.goal = max(1, $0.goal - 1) } }
                    Text("\(c.goal) \(c.goalNoun)").font(.display(14, .semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        .contentTransition(.numericText(value: Double(c.goal))).animation(.spring(response: 0.3), value: c.goal)
                    StepButton("plus", small: true, label: "Raise goal") { set { $0.goal = min(30, $0.goal + 1) } }
                }
            }
            .accessibilityElement(children: .contain)
            Divider()
            if Motion.snapshot {
                Label("Also send a macOS notification", systemImage: c.notify ? "checkmark.square.fill" : "square")
                    .font(.body(13)).foregroundStyle(Theme.text)
            } else {
                Toggle(isOn: Binding(get: { c.notify }, set: { n in set { $0.notify = n } })) {
                    Text("Also send a macOS notification").font(.body(13)).foregroundStyle(Theme.text)
                }
                .toggleStyle(.checkbox)
            }
            if notifier.denied, c.notify {
                Text("Notifications are off for Nudgelings in System Settings.").font(.body(11.5)).foregroundStyle(HabitKind.stretch.accent)
            }
        }
    }
}

/// Numbered step heading for the editor's guided flow.
struct SectionTitle: View {
    let number: Int
    let title: String
    var tint: Color = Theme.leaf
    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.display(14, .bold)).foregroundStyle(Theme.ink)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint))
                .overlay(Circle().strokeBorder(Theme.outline, lineWidth: 2))
                .accessibilityHidden(true)
            Text(title).font(.display(18, .semibold)).foregroundStyle(Theme.text)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)")
        .accessibilityAddTraits(.isHeader)
    }
}

struct EditorCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.display(12.5, .semibold)).foregroundStyle(Theme.muted) }
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
    var label: String?
    var action: () -> Void
    init(_ icon: String, small: Bool = false, label: String? = nil, action: @escaping () -> Void) {
        self.icon = icon; self.small = small; self.label = label; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: small ? 11 : 13, weight: .heavy)).foregroundStyle(Theme.ink)
                .frame(width: small ? 28 : 34, height: small ? 28 : 34)
                .toyCard(.white, radius: 9, shadow: 2)
        }
        .buttonStyle(.plain)
        .handCursor()
        .accessibilityLabel(label ?? (icon == "minus" ? "Decrease" : "Increase"))
    }
}

struct HoursRow: View {
    @Binding var window: ActiveWindow
    let tint: Color
    private let days = [(2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S"), (1, "S")]
    private let names = [1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday", 5: "Thursday", 6: "Friday", 7: "Saturday"]
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
                        .accessibilityLabel(names[day] ?? label)
                        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
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
            Text("Nudge styles").font(.display(34, .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text("Four levels, quietest first. Each character uses one; ignore a nudge and it comes back a level louder.")
                .font(.body(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Preview with").font(.body(13)).foregroundStyle(Theme.muted)
                ForEach(HabitKind.allCases) { k in
                    Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { who = k } } label: {
                        CharacterView(kind: k, expression: .happy, size: 28, shadow: false)
                            .padding(4)
                            .background(Circle().fill(who == k ? k.color.opacity(0.35) : .clear))
                            .overlay(Circle().strokeBorder(who == k ? Theme.outline : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .handCursor()
                    .accessibilityLabel(k.character)
                    .accessibilityAddTraits(who == k ? [.isButton, .isSelected] : .isButton)
                }
            }
            ForEach(Array(NudgeLevel.allCases.enumerated()), id: \.element) { i, level in
                levelSection(level).entrance(i, step: 0.05, base: 0.08)
            }
        }
    }

    private func levelSection(_ level: NudgeLevel) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                LevelArt(level: level, kind: who, live: true).frame(width: 150)
                LoudnessMeter(level: level)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(level.title).font(.display(19, .bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Text(level.tagline).font(.body(13, .bold)).foregroundStyle(Theme.muted)
                }
                Text(level.blurb(who)).font(.body(13)).foregroundStyle(Theme.text.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
                ForEach(level.styles) { t in
                    HStack(spacing: 10) {
                        Image(systemName: t.symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.ink)
                            .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 7).fill(who.color))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.outline, lineWidth: 1.5))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(t.title).font(.display(14, .semibold)).foregroundStyle(Theme.text)
                            Text(t.subtitle(for: who, sound: model.settings.config(who).sound)).font(.body(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if t.blocksScreen {
                            Label("Blocks clicks", systemImage: "hand.raised.fill").font(.body(11.5, .heavy))
                                .foregroundStyle(HabitKind.stretch.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Capsule().fill(HabitKind.stretch.wash))
                        }
                        Button { model.previewNudges(who, types: [t]) } label: { Label("Try", systemImage: "play.fill") }
                            .buttonStyle(ToyButton(fill: who.color, size: 12))
                            .accessibilityLabel("Try \(t.title) with \(who.character)")
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toyCard(Theme.raised, radius: 16, shadow: 3)
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
