import SwiftUI
import AppKit
import DripCore

enum ShareKind: String, CaseIterable, Hashable, Identifiable {
    case today, week, caught
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .week: "This week"
        case .caught: "Caught by…"
        }
    }
}

/// Everything a share card shows, computed once from the model.
struct ShareFacts {
    var name: String?
    var date: Date
    var streak: Int
    var today: DayStats
    var weekDone: [HabitKind: Int]
    var enabled: [HabitKind]
    var mood: Mood
    var weekNumber: Int
    /// Mon…Sun for the week grid.
    var week: [DayStats?]

    /// A friendly default for "Name on card": the account short name's first part ("suhas.more" → "Suhas").
    static var defaultName: String {
        let short = NSUserName().split(whereSeparator: { ".-_ ".contains($0) }).first.map(String.init) ?? NSUserName()
        return short.prefix(1).uppercased() + short.dropFirst()
    }

    @MainActor init(model: AppModel, name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces)
        self.name = (trimmed?.isEmpty ?? true) ? nil : trimmed
        date = Date()
        streak = model.streak.current
        today = model.state.stats
        enabled = model.settings.enabledKinds
        weekDone = Dictionary(uniqueKeysWithValues: HabitKind.allCases.map { ($0, model.weekTotal($0)) })
        mood = model.mood
        weekNumber = AppModel.calendar.component(.weekOfYear, from: Date())
        week = model.week.map(\.stats)
    }

    static func noun(_ k: HabitKind, _ n: Int) -> String {
        let (one, many): (String, String) = switch k {
        case .water: ("glass", "glasses")
        case .eyes: ("eye break", "eye breaks")
        case .walk: ("walk", "walks")
        case .stretch: ("stretch", "stretches")
        case .posture: ("sit-up", "sit-ups")
        case .breathe: ("breather", "breathers")
        case .stand: ("stand-up", "stand-ups")
        }
        return n == 1 ? one : many
    }

    /// The day's headline brag: water if on shift, else whatever was done most.
    func headline(_ counts: [HabitKind: Int], period: String) -> (HabitKind, String) {
        let kind = enabled.contains(.water) ? .water : enabled.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? .water
        let n = counts[kind] ?? 0
        let text: String = switch kind {
        case .water: "I drank \(n) glass\(n == 1 ? "" : "es") of water \(period)."
        case .eyes: "I rested my eyes \(n) time\(n == 1 ? "" : "s") \(period)."
        case .walk: "I went for \(n) walk\(n == 1 ? "" : "s") \(period)."
        case .stretch: "I stretched \(n) time\(n == 1 ? "" : "s") \(period)."
        case .posture: "I fixed my posture \(n) time\(n == 1 ? "" : "s") \(period)."
        case .breathe: "I took \(n) deep breather\(n == 1 ? "" : "s") \(period)."
        case .stand: "I stood up \(n) time\(n == 1 ? "" : "s") \(period)."
        }
        return (kind, text)
    }

    var caught: (HabitKind, String, String) {
        let kind = today.longestWaitKind ?? enabled.first ?? .eyes
        guard today.longestWait >= 60 else {
            return (kind, "0 min", "\(kind.character) hasn't caught me slacking today. Yet.")
        }
        let mins = Int(today.longestWait / 60)
        let wait = "\(mins) minute\(mins == 1 ? "" : "s")"
        let what: String = switch kind {
        case .water: "for me to drink some water"
        case .eyes: "for me to look away from my screen"
        case .walk: "for me to go for a walk"
        case .stretch: "for me to stretch"
        case .posture: "for me to sit up straight"
        case .breathe: "for me to take one breath"
        case .stand: "for me to stand up"
        }
        return (kind, wait, "\(kind.character) waited \(wait) \(what).")
    }

    func caption(_ k: ShareKind) -> String {
        switch k {
        case .today:
            let (_, h) = headline(today.done, period: "today")
            return "\(h) My menu-bar crew keeps me honest 💧 #Nudgelings"
        case .week:
            let (_, h) = headline(weekDone, period: "this week")
            return "\(h)" + (streak > 1 ? " \(streak)-day streak 🔥" : "") + " #Nudgelings"
        case .caught:
            return "\(caught.2) Busted. 👀 #Nudgelings"
        }
    }
}

// MARK: - Cards (1080×1350)

struct ShareCard: View {
    let kind: ShareKind
    let facts: ShareFacts
    var body: some View {
        Group {
            switch kind {
            case .today: TodayCard(f: facts)
            case .week: WeekCard(f: facts)
            case .caught: CaughtCard(f: facts)
            }
        }
        .frame(width: 1080, height: 1350)
        .clipped()
    }
}

private struct CardFooter: View {
    let f: ShareFacts
    var dark = false
    var body: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .bottom, spacing: -14) {
                ForEach(f.enabled.isEmpty ? [HabitKind.water, .eyes, .walk] : Array(f.enabled.prefix(5))) {
                    CharacterView(kind: $0, expression: .happy, size: 120)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Nudgelings").font(.display(40, .bold))
                if f.streak > 1 { Text("\(f.streak)-day streak 🔥").font(.body(28, .bold)) }
            }
            .foregroundStyle(dark ? Color.white : Theme.ink)
        }
    }
}

private struct Hills: View {
    var color: Color
    var body: some View {
        Canvas { ctx, size in
            for (i, r) in [(0, 300.0), (1, 380.0), (2, 330.0)] {
                let cx = CGFloat(i) * size.width / 2
                ctx.fill(Path(ellipseIn: CGRect(x: cx - r, y: size.height - r * 0.9, width: r * 2, height: r * 2)), with: .color(color))
            }
        }
    }
}

struct TodayCard: View {
    let f: ShareFacts
    var body: some View {
        let (kind, headline) = f.headline(f.today.done, period: "today")
        ZStack(alignment: .topLeading) {
            kind.color
            Hills(color: .white.opacity(0.18))
            VStack(alignment: .leading, spacing: 28) {
                Text(([f.name].compactMap { $0 } + ["TODAY", f.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased()])
                        .joined(separator: " · "))
                    .font(.display(30, .semibold)).tracking(3)
                Text(headline).font(.display(104, .bold)).lineSpacing(-10).fixedSize(horizontal: false, vertical: true)
                FlowStats(f: f, counts: f.today.done)
                Spacer()
                HStack(alignment: .top, spacing: 24) {
                    CharacterView(kind: kind, expression: .cheer, size: 300)
                    Text(kind == .water ? Lines.all(.mood(f.mood))[0] : Lines.all(.done(kind))[0])
                        .font(.display(40, .bold)).foregroundStyle(Theme.ink)
                        .padding(28).frame(maxWidth: 520, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 28).fill(.white))
                        .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(Theme.ink, lineWidth: 6))
                        .background(RoundedRectangle(cornerRadius: 28).fill(Theme.ink).offset(y: 10))
                        .padding(.top, 20)
                }
                .frame(maxWidth: .infinity)
                Spacer()
                CardFooter(f: f)
            }
            .foregroundStyle(Theme.ink)
            .padding(70)
        }
    }
}

struct WeekCard: View {
    let f: ShareFacts
    var body: some View {
        let (_, headline) = f.headline(f.weekDone, period: "this week")
        let eyes = f.weekDone[.eyes] ?? 0
        ZStack(alignment: .topLeading) {
            Theme.aqua
            Hills(color: Theme.aquaDeep.opacity(0.5))
            VStack(alignment: .leading, spacing: 30) {
                Text(([ "WEEK \(f.weekNumber)", f.name?.uppercased()].compactMap { $0 }).joined(separator: " · "))
                    .font(.display(30, .semibold)).tracking(3)
                Text(headline).font(.display(112, .bold)).fixedSize(horizontal: false, vertical: true)
                if f.enabled.contains(.eyes), eyes > 0 {
                    Text("and looked away from my screen \(eyes) times. My eyes say thanks.")
                        .font(.body(40, .bold)).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                MiniWeek(f: f)
                Spacer()
                CardFooter(f: f)
            }
            .foregroundStyle(Theme.ink)
            .padding(70)
        }
    }
}

struct CaughtCard: View {
    let f: ShareFacts
    var body: some View {
        let (kind, wait, line) = f.caught
        ZStack {
            Theme.sun
            VStack(spacing: 44) {
                // The polaroid
                VStack(spacing: 30) {
                    ZStack {
                        Theme.ink
                        HStack(spacing: 40) {
                            CharacterView(kind: kind, expression: .worried, size: 260)
                            Text(wait.replacingOccurrences(of: " minutes", with: " min").replacingOccurrences(of: " minute", with: " min"))
                                .font(.display(120, .bold)).foregroundStyle(Theme.sun).minimumScaleFactor(0.5).lineLimit(1)
                        }
                        .padding(40)
                    }
                    .frame(height: 440)
                    Text(line).font(.display(54, .bold)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 20)
                }
                .padding(34)
                .background(.white)
                .overlay(Rectangle().strokeBorder(Theme.ink, lineWidth: 8))
                .background(Rectangle().fill(Theme.ink).offset(x: 10, y: 14))
                .rotationEffect(.degrees(-3))
                .padding(.horizontal, 50)
                .padding(.top, 150)
                Text("\(f.date.formatted(.dateTime.weekday(.wide).hour().minute())) · caught in the act")
                    .font(.body(32, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                HStack {
                    Text("Nudgelings").font(.display(40, .bold))
                    Spacer()
                    Text("Get your own crew").font(.display(30, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 14).background(Capsule().fill(Theme.ink))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 70).padding(.bottom, 60)
            }
        }
    }
}

private struct FlowStats: View {
    let f: ShareFacts
    let counts: [HabitKind: Int]
    var body: some View {
        let kinds = f.enabled.filter { (counts[$0] ?? 0) > 0 }
        FlowLayout(spacing: 16) {
            ForEach(kinds) { k in
                HStack(spacing: 12) {
                    CharacterView(kind: k, expression: .happy, size: 56, shadow: false)
                    Text("\(counts[k] ?? 0) \(ShareFacts.noun(k, counts[k] ?? 0))")
                        .font(.display(36, .semibold))
                }
                .padding(.horizontal, 22).padding(.vertical, 12)
                .background(Capsule().fill(.white.opacity(0.85)))
                .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 4))
            }
        }
    }
}

/// The week as rows of squares (like the Streaks page), sized for a share card.
private struct MiniWeek: View {
    let f: ShareFacts
    var body: some View {
        let kinds = Array(f.enabled.prefix(5))
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Color.clear.frame(width: 80, height: 1)
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, l in
                    Text(l).font(.display(28, .semibold)).frame(width: 96)
                }
            }
            ForEach(kinds) { k in
                HStack(spacing: 14) {
                    CharacterView(kind: k, expression: .happy, size: 70, shadow: false).frame(width: 80)
                    ForEach(0..<7, id: \.self) { i in
                        let d = f.week[i]
                        let done = d?.done[k] ?? 0
                        let goal = d?.goals[k] ?? 1
                        RoundedRectangle(cornerRadius: 14)
                            .fill(done >= goal && done > 0 ? k.color : done > 0 ? Color.white.opacity(0.6) : Color.white.opacity(0.22))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.ink, lineWidth: done >= goal && done > 0 ? 5 : 0))
                            .frame(width: 96, height: 58)
                    }
                }
            }
        }
        .foregroundStyle(Theme.ink)
    }
}

// MARK: - Studio

/// Pick a card, then share it: system share sheet, a pre-filled post, copy, or save.
struct ShareStudio: View {
    @ObservedObject var model: AppModel
    @State var kind: ShareKind
    @AppStorage("shareShowName") private var showName = true
    @AppStorage("shareName") private var nameText = ShareFacts.defaultName
    private var cardName: String? { showName ? nameText : nil }
    @State private var done: String?
    @State private var fileURL: URL?

    var body: some View {
        let facts = ShareFacts(model: model, name: cardName)
        VStack(alignment: .leading, spacing: 18) {
            Text("Share").font(.display(34, .bold)).foregroundStyle(Theme.text)
            Text("Pick a card. Everything is made on your Mac; nothing is posted unless you post it.")
                .font(.body(14)).foregroundStyle(Theme.muted)
            HStack(alignment: .top, spacing: 26) {
                VStack(spacing: 12) {
                    ShareCard(kind: kind, facts: facts)
                        .scaleEffect(0.3, anchor: .topLeading)
                        .frame(width: 324, height: 405, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .toyCard(.clear, radius: 14, shadow: 5)
                        .id(kind)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                    HStack(spacing: 6) {
                        ForEach(ShareKind.allCases) { k in
                            Button(k.title) { withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { kind = k } }
                                .buttonStyle(ChipStyle(selected: kind == k))
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("CAPTION").font(.display(12, .semibold)).foregroundStyle(Theme.muted)
                    Text(facts.caption(kind)).font(.body(14)).foregroundStyle(Theme.text)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .toyCard(Theme.raised, radius: 12, shadow: 2)
                        .textSelection(.enabled)
                    HStack(spacing: 8) {
                        Toggle(isOn: $showName) { Text("Name on card").font(.body(13)) }.toggleStyle(.checkbox)
                        TextField("Your name", text: $nameText)
                            .textFieldStyle(.plain).font(.display(13, .semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .toyCard(.white, radius: 9, shadow: 0)
                            .foregroundStyle(Theme.ink)
                            .disabled(!showName).opacity(showName ? 1 : 0.5)
                    }

                    Text("POST IT").font(.display(12, .semibold)).foregroundStyle(Theme.muted).padding(.top, 6)
                    if let url = fileURL {
                        ShareLink(item: url, subject: Text("Nudgelings"), message: Text(facts.caption(kind))) {
                            Label("Share…", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(ToyButton(fill: Theme.leaf, size: 14, wide: true))
                    }
                    HStack(spacing: 10) {
                        post("LinkedIn", "https://www.linkedin.com/feed/?shareActive=true&text=", facts)
                        post("X", "https://x.com/intent/post?text=", facts)
                    }
                    Text("LinkedIn and X don't let apps attach images, so we copy the card for you — just paste it (⌘V) into the post.")
                        .font(.body(11.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        Button(done == "copy" ? "✓ Copied" : "Copy image") { copy(facts); confirm("copy") }
                            .buttonStyle(ToyButton(fill: .white, size: 13, wide: true))
                        Button(done == "save" ? "✓ Saved" : "Save PNG") { save(facts); confirm("save") }
                            .buttonStyle(ToyButton(fill: .white, size: 13, wide: true))
                    }
                }
                .frame(maxWidth: 360)
            }
        }
        // Render the PNG only when the card changes (the model publishes every second).
        .task(id: "\(kind.rawValue)-\(showName)-\(nameText)") { fileURL = render(ShareFacts(model: model, name: cardName)) }
    }

    private func post(_ name: String, _ base: String, _ facts: ShareFacts) -> some View {
        Button(done == name ? "✓ Paste the image" : "Post on \(name)") {
            copy(facts)
            let text = facts.caption(kind).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: base + text) { NSWorkspace.shared.open(url) }
            confirm(name)
        }
        .buttonStyle(ToyButton(fill: name == "X" ? .white : Theme.aqua, size: 13, wide: true))
    }

    private func confirm(_ what: String) {
        withAnimation(.spring(response: 0.3)) { done = what }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { withAnimation { if done == what { done = nil } } }
    }

    private func png(_ facts: ShareFacts) -> Data? { pngData(of: ShareCard(kind: kind, facts: facts)) }

    /// Renders the current card to a temp file for the share sheet.
    private func render(_ facts: ShareFacts) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Nudgelings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Nudgelings-\(kind.rawValue).png")
        guard let data = png(facts), (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

    private func copy(_ facts: ShareFacts) {
        guard let data = png(facts), let img = NSImage(data: data) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
    }

    private func save(_ facts: ShareFacts) {
        guard let data = png(facts) else { return }
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let url = downloads.appendingPathComponent("Nudgelings-\(kind.rawValue)-\(model.state.stats.day).png")
        if (try? data.write(to: url, options: .atomic)) != nil { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
